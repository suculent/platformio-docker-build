#!/usr/bin/env bash
set -euo pipefail
echo "[test] esp32 (Arduino) build starting"
cd /opt/dummy-esp32
pio run
echo "[test] esp32 (Arduino) build OK"
