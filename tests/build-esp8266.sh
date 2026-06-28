#!/usr/bin/env bash
set -euo pipefail
echo "[test] esp8266 (Arduino) build starting"
cd /opt/dummy-esp8266
pio run
echo "[test] esp8266 (Arduino) build OK"
