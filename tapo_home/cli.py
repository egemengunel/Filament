"""Command line control: `uv run tapo on|off|toggle|status|brightness N|color H S|temp K`."""

from __future__ import annotations

import argparse
import asyncio
import sys

from kasa import Module

from .connection import MissingCredentials, connect


def describe(device) -> str:
    light = device.modules[Module.Light]
    parts = [f"{device.alias} ({device.model}) is {'on' if device.is_on else 'off'}"]
    parts.append(f"brightness {light.brightness}%")
    if light.color_temp:
        parts.append(f"white {light.color_temp}K")
    else:
        h, s, _ = light.hsv
        parts.append(f"color hue {h} sat {s}%")
    return ", ".join(parts)


async def run(args: argparse.Namespace) -> None:
    device = await connect(args.host)
    light = device.modules[Module.Light]
    try:
        match args.command:
            case "on":
                await device.turn_on()
            case "off":
                await device.turn_off()
            case "toggle":
                await (device.turn_off() if device.is_on else device.turn_on())
            case "brightness":
                await light.set_brightness(args.value)
            case "color":
                await light.set_hsv(args.hue, args.saturation)
            case "temp":
                await light.set_color_temp(args.kelvin)
        await device.update()
        print(describe(device))
    finally:
        await device.disconnect()


def main() -> None:
    parser = argparse.ArgumentParser(prog="tapo")
    parser.add_argument("--host", help="bulb IP (default: config.json)")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("status", "on", "off", "toggle"):
        sub.add_parser(name)
    sub.add_parser("brightness").add_argument("value", type=int)
    color = sub.add_parser("color")
    color.add_argument("hue", type=int, help="0-360")
    color.add_argument("saturation", type=int, help="0-100")
    sub.add_parser("temp").add_argument("kelvin", type=int, help="2500-6500")
    try:
        asyncio.run(run(parser.parse_args()))
    except MissingCredentials as err:
        sys.exit(str(err))


if __name__ == "__main__":
    main()
