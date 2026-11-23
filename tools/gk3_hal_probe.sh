#!/system/bin/sh
# 在设备上用 /data/local/tmp 当临时库目录，迭代找出 charger HAL 缺的 system 库
D=/data/local/tmp/hl
rm -rf "$D"; mkdir -p "$D"
i=0
while [ $i -lt 15 ]; do
  i=$((i+1))
  out=$(LD_LIBRARY_PATH=$D:/system_ext/lib64 timeout 4 /odm/bin/hw/vendor.oplus.hardware.charger-V12-service 2>&1)
  lib=$(printf '%s\n' "$out" | sed -n 's/.*library "\([^"]*\)" not found.*/\1/p' | head -1)
  if [ -z "$lib" ]; then
    printf 'LINK_OK after %d iters\n%s\n' "$i" "$(printf '%s\n' "$out" | head -2)"
    break
  fi
  printf 'need: %s\n' "$lib"
  cp "/system/lib64/$lib" "$D/" 2>/dev/null || { printf 'not in system/lib64: %s\n' "$lib"; break; }
done
printf '== collected ==\n'
ls -l "$D"
