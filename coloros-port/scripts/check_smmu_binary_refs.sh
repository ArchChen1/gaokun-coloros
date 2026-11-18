#!/bin/bash
set -euo pipefail
echo '===== super-check contents ====='
ls -lh /tmp/super-vintffix-check/super.raw /tmp/super-vintffix-check/odm_a.img 2>/dev/null || true
echo '===== binary search for smmu-notali in extracted trees ====='
grep -aRIl 'smmu-notali' /tmp/vendor-current/root /tmp/odm-v2/root 2>/dev/null | head -40 || true