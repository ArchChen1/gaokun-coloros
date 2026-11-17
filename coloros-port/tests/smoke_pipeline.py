#!/usr/bin/env python3
"""Run the complete offline pipeline on synthetic fixtures.

This is a repeatable smoke test for the toolchain itself, not for a real ROM.
It verifies:
  OTA inspection -> preflight -> payload extraction -> scan -> super repack
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "tests"
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(TESTS))

import test_images  # noqa: E402
import test_ota  # noqa: E402


def run(args: list[str]) -> subprocess.CompletedProcess:
    result = subprocess.run([sys.executable] + args, capture_output=True, text=True)
    print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)
    return result


def main() -> int:
    with tempfile.TemporaryDirectory() as temp_raw:
        temp = Path(temp_raw)
        ota = temp / "OPD2413_test.zip"
        test_ota.build_ota(ota)

        report = temp / "donor.json"
        result = run([str(SCRIPTS / "ota_inspect.py"), str(ota), "--report", str(report)])
        if result.returncode:
            return result.returncode

        result = run([str(SCRIPTS / "preflight.py"), "--donor", str(report), "--allow-incomplete"])
        if result.returncode:
            return result.returncode

        parts = temp / "parts"
        result = run([str(SCRIPTS / "payload_extract.py"), str(ota), "--output", str(parts),
                      "--report", str(temp / "extract.json")])
        if result.returncode:
            return result.returncode

        scan = temp / "scan.json"
        result = run([str(SCRIPTS / "scan_oppo_deps.py"), str(parts), "--json", str(scan)])
        if result.returncode:
            return result.returncode

        template = temp / "super.img"
        test_images.make_super(template)
        output = temp / "super.raw.img"
        layout = temp / "layout.json"
        result = run([str(SCRIPTS / "super_repack.py"), "--template", str(template),
                      "--images", str(parts), "--partition", "system",
                      "--output", str(output), "--report", str(layout)])
        if result.returncode:
            return result.returncode

        inspected = temp / "inspect.json"
        result = run([str(SCRIPTS / "partition_inspect.py"), str(output), "--partitions", "--json", str(inspected)])
        if result.returncode:
            return result.returncode

        data = json.loads(inspected.read_text())
        if not data.get("lp"):
            raise SystemExit("final image is not liblp")
        print("SMOKE OK")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
