#!/usr/bin/env python3
"""Stream-decompress a .zst file without loading it into memory."""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

try:
    import zstandard as zstd
except ImportError as exc:
    raise SystemExit("zstandard is required: python -m pip install zstandard") from exc


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path)
    args = parser.parse_args(argv)
    if not args.source.is_file():
        parser.error(f"not a file: {args.source}")
    args.target.parent.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    total = 0
    with args.source.open("rb") as src, args.target.open("wb") as dst:
        reader = zstd.ZstdDecompressor().stream_reader(src, read_across_frames=True)
        while block := reader.read(8 * 1024 * 1024):
            dst.write(block)
            digest.update(block)
            total += len(block)
    print(f"WROTE {args.target} ({total:,} bytes)")
    print(f"SHA256 {digest.hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
