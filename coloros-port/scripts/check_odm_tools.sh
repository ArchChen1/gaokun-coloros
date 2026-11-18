#!/bin/bash
set -euo pipefail
df -h /home /tmp | tail -5
for c in simg2img img2simg fsck.erofs dump.erofs fsck.erofs lpunpack; do printf '%-12s ' "$c"; command -v "$c" || true; done