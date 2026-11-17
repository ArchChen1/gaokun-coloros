#!/usr/bin/env python3
"""Summarise a collect_boot_diag.py output directory.

Prints boot state, blocked services, SELinux denials, watchdog and common
ColorOS/OPPO HAL failure markers.  The summary is intentionally short enough
to paste into an issue.
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

PATTERNS = {
    "SELinux denial": re.compile(r"avc:\s+denied", re.I),
    "watchdog": re.compile(r"Watchdog|WATCHDOG|system_server.*WDT", re.I),
    "SurfaceFlinger block": re.compile(r"surfaceflinger.*(wait|block|timeout)|waitForService", re.I),
    "OPPO missing HAL": re.compile(r"could not find|service not found|No service|waitForService", re.I),
    "system_server crash": re.compile(r"FATAL EXCEPTION IN SYSTEM PROCESS|SystemServer.*crash|system_server.*died", re.I),
    "bootloop": re.compile(r"BootReceiver|rescue party|bootloop|Reboot requested", re.I),
}


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args(argv)
    if not args.directory.is_dir():
        parser.error(f"not a directory: {args.directory}")
    print("== BOOT STATE ==")
    for name in ("boot_completed.txt", "bootanim.txt", "surfaceflinger.txt", "system_server.txt"):
        value = read(args.directory / name).strip()
        print(f"{name:<22} {value or '(empty)'}")

    print("\n== SERVICES ==")
    services = read(args.directory / "services.txt")
    for token in ("SurfaceFlinger", "package", "activity", "audio", "display", "camera", "thermal", "power"):
        found = any(token.lower() in line.lower() for line in services.splitlines())
        print(f"{token:<14} {'present' if found else 'MISSING'}")

    print("\n== SIGNALS ==")
    corpus = "\n".join(read(path) for path in args.directory.glob("*.txt"))
    for label, pattern in PATTERNS.items():
        count = len(pattern.findall(corpus))
        print(f"{label:<24} {count}")

    print("\n== LAST CRASH LINES ==")
    for path in (args.directory / "logcat-crash.txt", args.directory / "logcat-system.txt"):
        lines = [line for line in read(path).splitlines() if line.strip()]
        for line in lines[-12:]:
            print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
