#!/usr/bin/env python3
"""Validate a donor and the target contract before any image work starts."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def donor_from_report(report: dict) -> dict:
    payload = report.get("payload")
    if not payload:
        raise SystemExit("donor report has no payload section; run ota_inspect.py first")
    names = [part["name"] for part in payload.get("partitions", [])]
    return {
        "path": report.get("path"),
        "partitions": names,
        "bytes": report.get("bytes"),
        "sha256": report.get("sha256"),
        "block_size": payload.get("block_size"),
        "version": payload.get("version"),
        "metadata": report.get("ota_metadata") or {},
    }


def check(donor: dict, contract: dict) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    spec = contract["donor"]
    parts = set(donor["partitions"])
    for required in spec["required_partitions"]:
        if required not in parts:
            errors.append(f"missing required partition: {required}")
    for preferred in spec["preferred_partitions"]:
        if preferred not in parts:
            warnings.append(f"preferred partition absent: {preferred}")
    if not any(name.startswith("my_") for name in parts):
        errors.append("no my_* partitions found; this does not look like a ColorOS donor")
    if "system" not in parts:
        errors.append("no system partition found")
    if donor.get("block_size") not in (None, 4096):
        warnings.append(f"donor block size is {donor['block_size']}, expected 4096")
    basename = Path(donor.get("path") or "").name.upper()
    for marker in spec.get("forbidden_markers", []):
        if marker.upper() in basename:
            errors.append(f"filename contains forbidden marker {marker!r}")
    metadata = donor.get("metadata") or {}
    fingerprint = " ".join(str(value) for value in metadata.values())
    if not fingerprint.strip():
        warnings.append("OTA metadata is empty; verify the donor device and build manually")
    return errors, warnings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--donor", type=Path, required=True, help="report from ota_inspect.py")
    parser.add_argument("--contract", type=Path, default=ROOT / "config/port.json")
    parser.add_argument("--allow-incomplete", action="store_true")
    args = parser.parse_args(argv)
    contract = load_json(args.contract)
    donor = donor_from_report(load_json(args.donor))
    errors, warnings = check(donor, contract)
    print(f"DONOR   {donor['path']}")
    print(f"PARTS   {', '.join(donor['partitions'])}")
    for warning in warnings:
        print(f"WARN    {warning}")
    for error in errors:
        print(f"ERROR   {error}", file=sys.stderr)
    if errors and not args.allow_incomplete:
        return 1
    print("PREFLIGHT OK" if not errors else "PREFLIGHT INCOMPLETE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
