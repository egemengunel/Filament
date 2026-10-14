"""Connect to the Tapo bulb using credentials stored in the macOS Keychain."""

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path

from kasa import Credentials, Device, Discover

KEYCHAIN_SERVICE = "tapo-home"
PROJECT_DIR = Path(__file__).resolve().parent.parent
CONFIG_FILE = PROJECT_DIR / "config.json"
DEFAULT_CONFIG = {"host": "192.168.1.172", "name": "Tapo Bulb"}


class MissingCredentials(RuntimeError):
    pass


def load_config() -> dict:
    config = dict(DEFAULT_CONFIG)
    if CONFIG_FILE.exists():
        config.update(json.loads(CONFIG_FILE.read_text()))
    if host := os.environ.get("TAPO_HOST"):
        config["host"] = host
    return config


def load_credentials() -> Credentials:
    """Read the TP-Link account email + password saved under KEYCHAIN_SERVICE."""
    item = subprocess.run(
        ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE],
        capture_output=True,
        text=True,
    )
    password = subprocess.run(
        ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
        capture_output=True,
        text=True,
    )
    # Non-ASCII account names are printed as hex: "acct"<blob>=0xE280A8...
    match = re.search(r'"acct"<blob>=(?:0x([0-9A-F]+)|"([^"]*)")', item.stdout)
    if item.returncode != 0 or password.returncode != 0 or not match:
        raise MissingCredentials(
            "No Tapo credentials in the Keychain. Run: bash save-credentials.sh"
        )
    hex_account, plain_account = match.groups()
    account = bytes.fromhex(hex_account).decode() if hex_account else plain_account
    # str.strip() also removes invisible separators that sneak in when pasting
    return Credentials(account.strip(), password.stdout.rstrip("\n"))


async def connect(host: str | None = None) -> Device:
    host = host or load_config()["host"]
    device = await Discover.discover_single(
        host, credentials=load_credentials(), discovery_timeout=5, timeout=10
    )
    if device is None:
        raise ConnectionError(f"No Tapo device answered at {host}")
    await device.update()
    return device
