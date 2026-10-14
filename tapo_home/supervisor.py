"""Run the HomeKit bridge only while this Mac is on the home network.

"Home" is recognised by the default gateway's MAC address (config.json:
home_gateway_mac). Unlike the Wi-Fi name, it is readable without Location
Services permission. The bridge is restarted when the Mac's IP address
changes so HomeKit advertises the right address.
"""

from __future__ import annotations

import logging
import re
import signal
import subprocess
import sys
import time

from .connection import load_config

log = logging.getLogger("tapo_home.supervisor")
CHECK_SECONDS = 15


def normalize_mac(mac: str) -> str:
    # arp prints 12:34:5:6:78:9a for 12:34:05:06:78:9a
    return ":".join(f"{int(part, 16):02x}" for part in mac.split(":"))


def run(*args: str) -> str:
    return subprocess.run(args, capture_output=True, text=True).stdout


def current_network() -> tuple[str | None, str | None]:
    """Return (gateway MAC, local IP) for the default route, or Nones if offline."""
    route = run("route", "-n", "get", "default")
    gateway = re.search(r"gateway: (\S+)", route)
    interface = re.search(r"interface: (\S+)", route)
    if not gateway or not interface:
        return None, None
    mac = re.search(r" at ([0-9a-f:]+) ", run("arp", "-n", gateway.group(1)))
    ip = run("ipconfig", "getifaddr", interface.group(1)).strip() or None
    return (normalize_mac(mac.group(1)) if mac else None), ip


class Supervisor:
    def __init__(self, home_mac: str) -> None:
        self.home_mac = normalize_mac(home_mac)
        self.bridge: subprocess.Popen | None = None
        self.bridge_ip: str | None = None

    def start_bridge(self, ip: str) -> None:
        log.info("On home network (%s), starting HomeKit bridge", ip)
        self.bridge = subprocess.Popen([sys.executable, "-m", "tapo_home.bridge"])
        self.bridge_ip = ip

    def stop_bridge(self, reason: str) -> None:
        if self.bridge is None:
            return
        log.info("Stopping HomeKit bridge: %s", reason)
        self.bridge.terminate()
        try:
            self.bridge.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.bridge.kill()
        self.bridge = None

    def check(self) -> None:
        mac, ip = current_network()
        at_home = mac == self.home_mac and ip is not None
        if self.bridge is not None and self.bridge.poll() is not None:
            log.warning("Bridge exited with %s", self.bridge.returncode)
            self.bridge = None
        if not at_home:
            self.stop_bridge("not on home network")
        elif self.bridge is not None and ip != self.bridge_ip:
            self.stop_bridge(f"IP changed {self.bridge_ip} -> {ip}")
            self.start_bridge(ip)
        elif self.bridge is None:
            self.start_bridge(ip)

    def loop(self) -> None:
        while True:
            self.check()
            time.sleep(CHECK_SECONDS)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    config = load_config()
    if "home_gateway_mac" not in config:
        sys.exit("config.json needs home_gateway_mac (your router's MAC address)")
    supervisor = Supervisor(config["home_gateway_mac"])

    def shutdown(*_: object) -> None:
        supervisor.stop_bridge("shutting down")
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    supervisor.loop()


if __name__ == "__main__":
    main()
