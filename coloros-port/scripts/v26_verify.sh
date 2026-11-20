#!/bin/bash
set -euo pipefail
I=/home/cenmin/v5/parts/odm_v26_a.img
M=/mnt/v26check
mkdir -p "$M"
cleanup(){ umount "$M" 2>/dev/null || true; }
trap cleanup EXIT
mount -t erofs -o loop,ro "$I" "$M"
test ! -e "$M/etc/vintf/manifest/android.hardware.contexthub-service.qmi.xml"
test ! -e "$M/etc/init/android.hardware.contexthub-service.qmi.rc"
test -f "$M/etc/audio/audio_policy_configuration.xml"
python3 -c "import xml.etree.ElementTree as E; E.parse('$M/etc/audio/audio_policy_configuration.xml'); print('POLICY_XML_OK')"
echo ODM_V26_CHECK_OK
sha256sum "$I"