#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit(f"usage: {sys.argv[0]} ODM_ROOT")

root = Path(sys.argv[1])
policy = root / "etc/audio/audio_policy_configuration.xml"
if not policy.is_file():
    raise SystemExit(f"missing {policy}")

text = policy.read_text(encoding="utf-8")
start_tag = "<!-- #ifdef OPLUS_FEATURE_BTAUDIO_BINAURAL_RECORD -->"
end_tag = "<!-- #endif OPLUS_FEATURE_BTAUDIO_BINAURAL_RECORD -->"
start = text.find(start_tag)
end = text.find(end_tag)
if start < 0 or end < start:
    raise SystemExit("binaural_record block not found")

end += len(end_tag)
new = text[:start] + (
    "<!-- gaokun3 v23: binaural_record provider is not registered on this device; "
    "do not make audio policy wait for it at boot -->"
) + text[end:]
if "<module name=\"binaural_record\"" in new:
    raise SystemExit("binaural_record still referenced after patch")
policy.write_text(new, encoding="utf-8")
print("PATCHED", policy, len(text), "->", len(new))

