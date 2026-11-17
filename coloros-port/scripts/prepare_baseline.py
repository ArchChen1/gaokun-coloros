#!/usr/bin/env python3
"""Prepare the gaokun3 release super.img.zst for repacking.

The upstream release is:
    super.img.zst  (zstd-compressed Android sparse image)
    -> zstd -d       super.img (sparse, not 12 GiB on disk)
    -> simg2img      super.raw.img (12 GiB raw)

This tool performs the second step with the pure-Python sparse expander. It
requires the zstd command line tool for the first step, or an already expanded
super.img. It never flashes anything.

Usage:
    python scripts/prepare_baseline.py inputs/super.img.zst --output work/baseline-super.raw.img
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib_android import is_sparse, unsparse


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="super.img.zst or an expanded super.img")
    parser.add_argument("--output", type=Path, default=Path("work/baseline-super.raw.img"))
    parser.add_argument("--keep-sparse", action="store_true")
    args = parser.parse_args(argv)
    if not args.image.is_file():
        parser.error(f"not a file: {args.image}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    sparse = args.image
    if args.image.suffix == ".zst":
        if shutil.which("zstd") is None:
            raise SystemExit("zstd is required to expand super.img.zst")
        sparse = args.output.with_suffix(".sparse.img")
        result = subprocess.run(["zstd", "-d", "-f", str(args.image), "-o", str(sparse)])
        if result.returncode:
            raise SystemExit("zstd decompression failed")
    if not is_sparse(sparse):
        # Already a raw image; copy it to the requested output.
        if sparse != args.output:
            shutil.copyfile(sparse, args.output)
        print(f"RAW    {args.output} ({args.output.stat().st_size:,} bytes)")
        return 0
    info = unsparse(sparse, args.output)
    if not args.keep_sparse and sparse != args.image:
        sparse.unlink()
    print(f"RAW    {args.output} ({info['raw_bytes']:,} bytes)")
    print("NOTE   expect exactly 12,884,901,888 bytes and 3 metadata slots")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
