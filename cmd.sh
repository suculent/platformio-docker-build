#!/usr/bin/env bash

set -e

# Config options you may pass via Docker like so 'docker run -e "<option>=<value>"':
# - KEY=<value>

if [ -z "$WORKDIR" ]; then
  cd $WORKDIR
else
  echo "No working directory given."
  true
fi

cd /opt/platformio-builder

platformio run
