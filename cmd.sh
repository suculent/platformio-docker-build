#!/usr/bin/env bash

set -e

parse_yaml() {
    local prefix=$2
    local s
    local w
    local fs
    s='[[:space:]]*'
    w='[a-zA-Z0-9_]*'
    fs="$(echo @|tr @ '\034')"
    sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" "$1" |
    awk -F"$fs" '{
    indent = length($1)/2;
    vname[indent] = $2;
    for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
            printf("%s%s%s=(\"%s\")\n", "'"$prefix"'",vn, $2, $3);
        }
    }' | sed 's/_=/+=/g'
}

# Config options you may pass via Docker like so 'docker run -e "<option>=<value>"':
# - KEY=<value>

if [ -z "$WORKDIR" ]; then
  cd $WORKDIR
else
  echo "No working directory given."
  true
fi

cd /opt/workspace

#
# Build
#

if [[ ! -f "./platformio.ini" ]]; then
  echo "Incorrect workdir $(pwd)"
fi

platformio run # --silent # suppressed progress reporting

#
# Export artefacts
#

if [[ -d build ]]; then
  rm -rf build
fi

mkdir build

cd ./.pioenvs

# WARNING! Currently supports only one simultaneous
# build-environment and overwrites OUTFILE(s) with recents.

for dir in $(ls -d */); do
  if [[ -d $dir ]]; then
    pushd $dir
    if [[ -f firmware.bin ]]; then
      if [[ ! -d /opt/workspace/build ]]; then
        mkdir -p /opt/workspace/build
      fi
      cp -vf firmware.bin /opt/workspace/build/firmware.bin
      if [[ -f firmware.elf ]]; then
        cp -vf firmware.elf /opt/workspace/build/firmware.elf
      fi
    fi
    popd
  fi
done
