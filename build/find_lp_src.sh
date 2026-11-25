#!/bin/bash
# 找 AOSP 源码（liblp / fs_mgr）或任何可用的 lp 写入实现
set -u
echo "== liblp source trees"
find /home/cenmin /opt /usr/local -maxdepth 7 -type d -name liblp 2>/dev/null | head -10
echo "== liblp.cpp"
find /home/cenmin -maxdepth 8 -type f -name 'liblp.cpp' 2>/dev/null | head -5
echo "== fs_mgr dirs"
find /home/cenmin -maxdepth 6 -type d -name 'fs_mgr' 2>/dev/null | head -5
echo "== any aosp/manifest"
ls -d /home/cenmin/*/build/make 2>/dev/null | head -5
echo "== pip pkgs that may ship lp tools"
/home/cenmin/coloros-build/venv/bin/python3 -c "import importlib.util as u; print([m for m in ['liblp','lpunpack','lp'] if u.find_spec(m)])" 2>&1
echo "== apt candidates"
apt-cache policy android-sdk-libsparse-utils 2>/dev/null | head -3
