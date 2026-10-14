"""Expose the Tapo bulb to Apple Home as a HomeKit accessory (HAP-python)."""

from __future__ import annotations

import asyncio
import logging
import signal

from aiohttp import web
from kasa import Device, Module
from pyhap.accessory import Accessory
from pyhap.accessory_driver import AccessoryDriver
from pyhap.const import CATEGORY_LIGHTBULB

from .connection import PROJECT_DIR, connect, load_config

log = logging.getLogger("tapo_home")
POLL_SECONDS = 5
LOCAL_API_PORT = 51828  # 127.0.0.1 only; used by the macOS widget
SETUP_FILE = PROJECT_DIR / "homekit-setup.txt"


def kelvin_to_mired(kelvin: int) -> int:
    return round(1_000_000 / kelvin)


class TapoLight(Accessory):
    category = CATEGORY_LIGHTBULB

    def __init__(self, driver: AccessoryDriver, config: dict) -> None:
        super().__init__(driver, config["name"])
        self.host = config["host"]
        self.room = config.get("room", "Bedroom")
        self.tile_name = config.get("tile_name", "Bulb")
        self.device: Device | None = None
        self.lock = asyncio.Lock()
        self.api_runner: web.AppRunner | None = None

        self.set_info_service(manufacturer="TP-Link", model="Tapo", serial_number=self.host)
        service = self.add_preload_service(
            "Lightbulb", chars=["On", "Brightness", "Hue", "Saturation", "ColorTemperature"]
        )
        self.char_on = service.configure_char("On")
        self.char_brightness = service.configure_char("Brightness")
        self.char_hue = service.configure_char("Hue")
        self.char_saturation = service.configure_char("Saturation")
        self.char_temp = service.configure_char(
            "ColorTemperature",
            # L530 range is 2500K-6500K
            properties={"minValue": kelvin_to_mired(6500), "maxValue": kelvin_to_mired(2500)},
        )
        service.setter_callback = self._on_homekit_set

    async def _device(self) -> Device:
        if self.device is None:
            self.device = await connect(self.host)
            log.info("Connected to %s (%s)", self.device.alias, self.device.model)
        return self.device

    def _on_homekit_set(self, values: dict) -> None:
        self.driver.add_job(self._apply, values)

    async def _apply(self, values: dict) -> None:
        log.info("HomeKit set %s", values)
        async with self.lock:
            try:
                device = await self._device()
                light = device.modules[Module.Light]
                if values.get("On") is False:
                    await device.turn_off()
                    return
                if "Hue" in values or "Saturation" in values:
                    await light.set_hsv(
                        int(values.get("Hue", self.char_hue.value)),
                        int(values.get("Saturation", self.char_saturation.value)),
                    )
                elif "ColorTemperature" in values:
                    await light.set_color_temp(round(1_000_000 / values["ColorTemperature"]))
                if "Brightness" in values:
                    await light.set_brightness(max(1, int(values["Brightness"])))
                if values.get("On") is True:
                    await device.turn_on()
            except Exception:
                log.exception("Failed to control bulb; will reconnect")
                self.device = None

    @Accessory.run_at_interval(POLL_SECONDS)
    async def run(self) -> None:
        """Mirror bulb state into HomeKit so changes from the Tapo app show up too."""
        if self.api_runner is None:
            self.api_runner = await start_local_api(self)
        await self.refresh()

    async def refresh(self) -> None:
        async with self.lock:
            try:
                device = await self._device()
                await device.update()
            except Exception as err:
                log.warning("Bulb unreachable: %s", err)
                self.device = None
                return
        light = device.modules[Module.Light]
        self.char_on.set_value(bool(device.is_on))
        self.char_brightness.set_value(light.brightness)
        if light.color_temp:
            self.char_temp.set_value(kelvin_to_mired(light.color_temp))
        else:
            hue, saturation, _ = light.hsv
            self.char_hue.set_value(hue)
            self.char_saturation.set_value(saturation)

    def snapshot(self) -> dict:
        state = {
            "room": self.room,
            "name": self.tile_name,
            "reachable": self.device is not None,
            "on": bool(self.char_on.value),
            "brightness": int(self.char_brightness.value),
            "hue": 0,
            "saturation": 0,
            "color_temp": 0,
        }
        if self.device is not None:
            light = self.device.modules[Module.Light]
            state["color_temp"] = light.color_temp
            state["hue"], state["saturation"], _ = light.hsv
        return state

    async def apply_command(self, command: dict) -> None:
        """Apply a widget command: on, brightness/delta, and hue+saturation or color_temp."""
        async with self.lock:
            try:
                device = await self._device()
                light = device.modules[Module.Light]
                if command.get("on") is False:
                    await device.turn_off()
                    return
                level = command.get("brightness")
                if level is None and "delta" in command:
                    level = light.brightness + int(command["delta"])
                if level is not None:
                    level = min(100, max(1, int(level)))
                if not device.is_on or command.get("on") is True:
                    await device.turn_on()
                if "hue" in command:
                    await light.set_hsv(int(command["hue"]), int(command["saturation"]), level)
                elif "color_temp" in command:
                    await light.set_color_temp(int(command["color_temp"]), brightness=level)
                elif level is not None:
                    await light.set_brightness(level)
            except Exception:
                log.exception("Failed to apply widget command; will reconnect")
                self.device = None

    async def stop(self) -> None:
        if self.api_runner is not None:
            await self.api_runner.cleanup()
        if self.device is not None:
            await self.device.disconnect()


async def start_local_api(light: TapoLight) -> web.AppRunner:
    """GET /state, POST /set {"on", "brightness", "delta", "hue"+"saturation", "color_temp"}."""

    async def state(_: web.Request) -> web.Response:
        return web.json_response(light.snapshot())

    async def set_state(request: web.Request) -> web.Response:
        await light.apply_command(await request.json())
        await light.refresh()
        return web.json_response(light.snapshot())

    app = web.Application()
    app.add_routes([web.get("/state", state), web.post("/set", set_state)])
    runner = web.AppRunner(app, access_log=None)
    await runner.setup()
    await web.TCPSite(runner, "127.0.0.1", LOCAL_API_PORT).start()
    log.info("Local API on http://127.0.0.1:%d", LOCAL_API_PORT)
    return runner


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    config = load_config()
    driver = AccessoryDriver(port=51826, persist_file=str(PROJECT_DIR / "homekit.state"))
    accessory = TapoLight(driver, config)
    driver.add_accessory(accessory)

    if driver.state.paired:
        log.info("Already paired with Apple Home")
    else:
        SETUP_FILE.write_text(
            f"HomeKit setup code: {driver.state.pincode.decode()}\n"
            f"Setup URI (QR payload): {accessory.xhm_uri()}\n"
        )
        log.info("HomeKit setup code: %s", driver.state.pincode.decode())
    signal.signal(signal.SIGTERM, driver.signal_handler)
    driver.start()


if __name__ == "__main__":
    main()
