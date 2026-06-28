#!/usr/bin/env bash
set -euo pipefail
echo "[test] esp32-idf build starting"
export IDF_PATH="${IDF_PATH:-/root/esp/esp-idf}"
# shellcheck disable=SC1091
. "$IDF_PATH/export.sh"
cd /opt/dummy-esp32-idf
idf.py set-target esp32
idf.py build
echo "[test] esp32-idf build OK"
