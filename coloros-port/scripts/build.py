#!/usr/bin/env python3
"""Build orchestration for the first ColorOS diagnostic super image.

Stages are explicit and never flash:

  preflight  validate donor report and target contract
  unpack     extract payload partitions to work/parts
  stage      copy ColorOS system partitions into a working tree
  image      create ext4 images and copy the staged trees into them
  super      repack the gaokun3 liblp template
  verify     inspect the produced super

The image stage needs Linux with root, loop devices, mount and mkfs.ext4.
A later phase will add EROFS. Without root, run only preflight/unpack/stage.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
REQUIRED = ["system", "system_ext", "product", "vendor"]
SIZES_MB = {"system": 2048, "system_ext": 1024, "product": 4096, "vendor": 512}


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def run(command: list[str]) -> None:
    print("+", " ".join(map(str, command)))
    subprocess.run([str(item) for item in command], check=True)


def stage_donor(parts: Path, stage: Path) -> None:
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    for name in REQUIRED:
        source = parts / f"{name}.img"
        if not source.is_file():
            raise SystemExit(f"missing extracted partition image: {source}")
        shutil.copy2(source, stage / f"{name}.img")
    print(f"staged {', '.join(REQUIRED)}")


def make_ext4_from_dir(source: Path, target: Path, size_mb: int) -> None:
    if os.name != "posix" or os.geteuid() != 0:
        raise SystemExit("image creation needs Linux root (loop mounts)")
    if target.exists():
        target.unlink()
    with target.open("wb") as handle:
        handle.truncate(size_mb * 1024 * 1024)
    run(["mkfs.ext4", "-q", "-F", "-b", "4096", "-I", "256", "-m", "0", "-L", target.stem, target])
    mountpoint = ROOT / "work" / f"mount-{target.stem}"
    mountpoint.mkdir(parents=True, exist_ok=True)
    try:
        run(["mount", "-o", "loop", target, mountpoint])
        subprocess.run(["cp", "-a", f"{source}/.", str(mountpoint)], check=True)
        run(["sync"])
    finally:
        subprocess.run(["umount", mountpoint], check=False)
        mountpoint.rmdir()
    print(f"created {target} ({size_mb} MiB)")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--donor-report", type=Path, required=True)
    parser.add_argument("--ota", type=Path, help="ColorOS OTA zip; required unless --skip-unpack")
    parser.add_argument("--parts", type=Path, default=ROOT / "work/parts")
    parser.add_argument("--template", type=Path, required=True, help="gaokun3 super.img or metadata MiB")
    parser.add_argument("--out", type=Path, default=ROOT / "out")
    parser.add_argument("--stage", type=Path, default=ROOT / "work/stage")
    parser.add_argument("--skip-unpack", action="store_true")
    parser.add_argument("--only", choices=["preflight", "unpack", "stage", "image", "super", "verify"], action="append")
    args = parser.parse_args(argv)
    only = set(args.only or ["preflight", "unpack", "stage", "image", "super", "verify"])
    args.out.mkdir(parents=True, exist_ok=True)
    reports = ROOT / "reports"

    if "preflight" in only:
        run([sys.executable, SCRIPTS / "preflight.py", "--donor", args.donor_report])
    if "unpack" in only:
        if args.skip_unpack:
            pass
        elif args.ota:
            run([sys.executable, SCRIPTS / "payload_extract.py", args.ota, "--output", args.parts])
        else:
            raise SystemExit("--ota is required for unpack")
    if "stage" in only:
        stage_donor(args.parts, args.stage)
    if "image" in only:
        for name in REQUIRED:
            make_ext4_from_dir(args.stage / name, args.out / f"{name}.img", SIZES_MB[name])
    if "super" in only:
        run([sys.executable, SCRIPTS / "super_repack.py", "--template", args.template,
             "--images", args.out, "--output", args.out / "super.raw.img",
             "--report", reports / "super-layout.json"])
    if "verify" in only:
        run([sys.executable, SCRIPTS / "partition_inspect.py", args.out / "super.raw.img", "--partitions"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
