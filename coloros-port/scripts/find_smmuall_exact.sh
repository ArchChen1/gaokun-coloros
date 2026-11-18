#!/bin/bash
set -euo pipefail
echo '===== policy string occurrences ====='
grep -RIn 'gaokun3_smmuall' /tmp/vendor-current/root/etc/selinux /home/cenmin/coloros-build/policy-src 2>/dev/null | head -80 || true
grep -RIn 'smmu-notali' /tmp/vendor-current/root/etc/selinux /home/cenmin/coloros-build/policy-src 2>/dev/null | head -80 || true
echo '===== all file_context entries smmu ====='
grep -RIn -E 'smmu' /tmp/vendor-current/root/etc/selinux /tmp/odm-v2/root/etc/selinux 2>/dev/null | head -120 || true
echo '===== init service blocks smmu ====='
grep -RIn -A15 -B3 -E 'service .*smmu|smmu-notali' /tmp/vendor-current/root/etc/init /tmp/odm-v2/root/etc/init 2>/dev/null | head -160 || true