#!/usr/bin/env bash
set -euo pipefail
cd /tmp
curl -fL --retry 3 -o secilc.deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/pool/universe/s/secilc/secilc_3.5-1_amd64.deb
sha256sum secilc.deb
dpkg -i secilc.deb
secilc --help | head -30
