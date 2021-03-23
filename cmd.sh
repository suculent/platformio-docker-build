#!/usr/bin/env bash

set -e

echo "platformio-docker-build-1.6.48"
echo $GIT_TAG

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

export IDF_PATH=/root/esp/esp-idf
export PATH=$PATH:/root/esp/xtensa-esp32-elf/bin

echo "export PATH=$PATH:/root/esp/xtensa-esp32-elf/bin" > ~/.profile
echo "export IDF_PATH=/root/esp/esp-idf" > ~/.profile

if [[ -z "$WORKDIR" ]]; then
  cd $WORKDIR
else
  echo "No working directory given."
  true
fi

cd /opt/workspace

#
# Build
#

# Parse thinx.yml config

YMLFILE=$(find /opt/workspace -name "thinx.yml" | head -n 1)

if [[ ! -f $YMLFILE ]]; then
  echo "No thinx.yml found"
  exit 1
else
  eval $(parse_yaml "$YMLFILE" "")
  # output filename for the per-device environment file
  if [[ ! -z "${environment_target}" ]]; then
    ENVOUT="${WORKDIR}/${environment_target}" # e.g. src/env.h
  fi
fi

# Parse environment.json

ENVFILE=$(find /opt/workspace -name "environment.json" | head -n 1)
ENVOUT=$(find /opt/workspace -name "environment.h" | head -n 1)

# echo "Will write to ENVOUT ${ENVOUT}"

if [[ ! -f $ENVFILE ]]; then
  echo "No environment.json found"
else
  echo "Generating per-device environment headers to: ${ENVOUT}"
  # Generate C-header from key-value JSON object
  arr=()
  # Print out header, will clear previous contents.
  # echo "Touching file at ${ENVOUT}"
  touch ${ENVOUT}
  echo "/* This file is auto-generated. */" > ${ENVOUT}
  while IFS='' read -r keyname; do
    # SKIP CPASS and CSSID, those will end up in thinx.yml to be encrypted using DevSec instead
    if [[ $keyname == "CPASS"]]; then 
      continue
    fi
    if [[ $keyname == "CSSID"]]; then
      continue
    fi
    arr+=("$keyname")
    VAL=$(jq '.'$keyname $ENVFILE)
    NAME=$(echo "environment_${keyname}" | tr '[:lower:]' '[:upper:]')
    echo "#define ${NAME}" "$VAL" >> ${ENVOUT}
  done < <(jq -r 'keys[]' $ENVFILE)
fi

BUILD_TYPE='platformio'

if [[ -f "./sdkconfig" ]]; then
  echo "Found `sdkconfig` in workspace root, switching to ESP-IDF build."
  BUILD_TYPE='espidf'
fi

if [[ $BUILD_TYPE == "platformio" ]]; then
  if [[ ! -f "./platformio.ini" ]]; then
    echo "Incorrect workdir $(pwd)"
  else
    if [[ ! -z $(cat ./platformio.ini | grep -v "^;" | grep "framework" | grep "espidf") ]]; then
      echo "Found `framework = espidf` in platformio.ini, switching to ESP-IDF build."
      BUILD_TYPE='espidf'
    fi
  fi
fi

if [[ $BUILD_TYPE != "platformio" ]]; then

  make

  rm -rf build/partitions_singleapp.bin

  cp -vf build/*.bin /opt/workspace/build/firmware.bin
  cp -vf build/*.elf /opt/workspace/build/firmware.elf

else

  platformio run # --silent # suppressed progress reporting

  if [[ -d build ]]; then
    rm -rf build
  fi

  mkdir build

  cd ./.pio/build/

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
        chmod 775 /opt/workspace/build/firmware.*
      fi
      popd
    fi
  done

fi

RESULT=$?

echo ""

# Report build status using logfile
if [[ $RESULT == 0 ]]; then
  echo "THiNX BUILD SUCCESSFUL."
else
  echo "THiNX BUILD FAILED: $?"
fi
