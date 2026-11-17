#!/usr/bin/env python3
"""Unit tests for preflight and dependency scanning."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "coloros-port" / "scripts"


class PreflightTests(unittest.TestCase):
    def test_complete_donor(self):
        with tempfile.TemporaryDirectory() as temp:
            report = Path(temp) / "donor.json"
            report.write_text(json.dumps({
                "path": "/inputs/OPD2413_16.0.0.210.zip",
                "bytes": 123,
                "sha256": "abc",
                "payload": {
                    "block_size": 4096,
                    "partitions": [
                        {"name": name, "bytes": 1, "operations": 1}
                        for name in ["system", "system_ext", "product", "my_product", "my_manifest"]
                    ],
                },
                "ota_metadata": {"post-build": "OPD2413_16.0.0.210(CN01)"},
            }), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPTS / "preflight.py"), "--donor", str(report)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("PREFLIGHT OK", result.stdout)

    def test_missing_partition(self):
        with tempfile.TemporaryDirectory() as temp:
            report = Path(temp) / "donor.json"
            report.write_text(json.dumps({
                "path": "/inputs/bad.zip",
                "payload": {"block_size": 4096, "partitions": [{"name": "system"}]},
            }), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPTS / "preflight.py"), "--donor", str(report)],
                capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing required partition", result.stderr)


class ScannerTests(unittest.TestCase):
    def test_scan_oppo_strings(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "system"
            root.mkdir()
            (root / "surfaceflinger").write_bytes(b"waitForService IDisplayColorFeature vendor.oplus.display\0")
            report = Path(temp) / "scan.json"
            result = subprocess.run(
                [sys.executable, str(SCRIPTS / "scan_oppo_deps.py"), str(root), "--json", str(report)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(report.read_text())
            self.assertIn("IDisplayColorFeature", data["interfaces"])
            self.assertEqual(len(data["wait_files"]), 1)


if __name__ == "__main__":
    unittest.main()
