#!/usr/bin/env python3
"""Collect Android boot diagnostics from a gaokun3 over ADB.

The device may be partially booted: adb shell, root and logcat must work.
All output stays inside a local directory. No data is uploaded.

Examples:
    python scripts/collect_boot_diag.py --serial SERIAL --output reports/diag-001
    python scripts/collect_boot_diag.py --serial SERIAL --output reports/diag-002 --root
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

COMMANDS = {
    "getprop.txt": ["getprop"],
    "boot_completed.txt": ["getprop", "sys.boot_completed"],
    "bootanim.txt": ["getprop", "init.svc.bootanim"],
    "surfaceflinger.txt": ["getprop", "init.svc.surfaceflinger"],
    "system_server.txt": ["getprop", "init.svc.zygote"],
    "mounts.txt": ["cat", "/proc/mounts"],
    "cmdline.txt": ["cat", "/proc/cmdline"],
    "version.txt": ["cat", "/proc/version"],
    "services.txt": ["service", "list"],
    "display.txt": ["dumpsys", "display"],
    "window.txt": ["dumpsys", "window"],
    "power.txt": ["dumpsys", "power"],
    "battery.txt": ["dumpsys", "battery"],
    "audio.txt": ["dumpsys", "audio"],
    "selinux.txt": ["getenforce"],
    "pstore.txt": ["ls", "-la", "/sys/fs/pstore"],
}

LOG_COMMANDS = {
    "logcat-main.txt": ["logcat", "-b", "main", "-d", "-v", "threadtime"],
    "logcat-system.txt": ["logcat", "-b", "system", "-d", "-v", "threadtime"],
    "logcat-crash.txt": ["logcat", "-b", "crash", "-d", "-v", "threadtime"],
}

ROOT_COMMANDS = {
    "anr-list.txt": ["ls", "-la", "/data/anr"],
    "tombstones.txt": ["ls", "-la", "/data/tombstones"],
    "dropbox.txt": ["ls", "-la", "/data/system/dropbox"],
}


def adb(serial: str, args: list[str], timeout: int = 25) -> dict:
    command = ["adb", "-s", serial] + args
    started = time.time()
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        return {
            "command": command,
            "returncode": result.returncode,
            "seconds": round(time.time() - started, 2),
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {
            "command": command,
            "returncode": None,
            "seconds": round(time.time() - started, 2),
            "stdout": "",
            "stderr": str(exc),
        }


def write_result(path: Path, result: dict) -> None:
    payload = result["stdout"]
    if result["stderr"]:
        payload += "\n--- STDERR ---\n" + result["stderr"]
    path.write_text(payload, encoding="utf-8", errors="replace")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--root", action="store_true", help="also list protected Android state directories")
    args = parser.parse_args(argv)
    args.output.mkdir(parents=True, exist_ok=True)
    index = []

    for filename, command in COMMANDS.items():
        result = adb(args.serial, ["shell"] + command)
        write_result(args.output / filename, result)
        index.append({"file": filename, "returncode": result["returncode"]})

    for filename, command in LOG_COMMANDS.items():
        result = adb(args.serial, ["shell"] + command, timeout=45)
        write_result(args.output / filename, result)
        index.append({"file": filename, "returncode": result["returncode"]})

    if args.root:
        for filename, command in ROOT_COMMANDS.items():
            result = adb(args.serial, ["shell", "su", "-c", " ".join(command)])
            write_result(args.output / filename, result)
            index.append({"file": filename, "returncode": result["returncode"]})

    (args.output / "index.json").write_text(json.dumps(index, indent=2), encoding="utf-8")
    print(f"WROTE {args.output}")
    missing = [item["file"] for item in index if item["returncode"] not in (0, None)]
    if missing:
        print("WARN  commands with non-zero exit: " + ", ".join(missing), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
