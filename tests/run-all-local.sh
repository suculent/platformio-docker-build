#!/usr/bin/env bash
set -euo pipefail
# Convenience runner for local arm64 testing against a built image.
# Usage: docker run --rm <image> /opt/tests/run-all-local.sh
/opt/tests/build-esp32.sh
/opt/tests/build-esp8266.sh
/opt/tests/build-esp32-idf.sh
echo "[test] ALL build-chain tests passed"
