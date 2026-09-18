# IDF v5.3; ESP8266@; ESP32@

# Docker Hardened Image base (CIS-compliant, DHI-maintained Debian 13 "trixie").
# The `-dev` variant is required, not the bare `:trixie` runtime variant: this
# image *is* a build toolchain, so it needs apt at build time and gcc/python3/
# git/ninja at run time. The runtime variant ships neither a package manager
# nor a compiler, so it cannot host (or be produced from) this Dockerfile.
FROM dhi.io/debian-base:trixie-dev

LABEL version="1.8.98"

ENV DEBIAN_FRONTEND=noninteractive
ENV ESP_IDF_VERSION="v5.3"

RUN mkdir /opt/workspace
WORKDIR /opt/workspace
COPY cmd.sh /opt/

COPY dummy-esp8266 /opt/dummy-esp8266
COPY dummy-esp32 /opt/dummy-esp32
COPY dummy-esp32-idf /opt/dummy-esp32-idf
COPY tests /opt/tests
RUN chmod +x /opt/tests/*.sh

RUN apt update -qq && \
apt install -y -qq --no-install-recommends gpgv && \
apt install -qq -y --no-install-recommends \
bc \
bison \
build-essential \
ca-certificates \
ccache \
cmake \
curl \
dfu-util \
flex \
gcc \
git \
gperf \
jq \
libffi-dev \
libncurses-dev \
libssl-dev \
libusb-1.0-0 \
make \
ninja-build \
python3 \
python3-dev \
python3-pip \
python3-venv \
srecord \
unzip \
wget \
xz-utils \
&& apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#
# Install Python icomponents
#

# `cryptography` is pinned rather than left to transitive resolution so the
# system Python gets a known version on every rebuild. This pin covers the
# system interpreter only; the ESP-IDF virtualenv created by `install.sh`
# below is governed by Espressif's own constraints file, which caps
# cryptography at <43 for IDF v5.3 and cannot take this version.
#
# `msgpack` is deliberately NOT pinned here. The only copy in this image is
# the one vendored inside pip itself (pip/_vendor/msgpack, 1.1.2 as of pip
# 26.2.1), present in both the system and the ESP-IDF interpreters and not
# registered as an installed distribution. Installing a top-level `msgpack`
# would not change what pip imports, so it would clear nothing and leave an
# unused package behind. GHSA-6v7p-g79w-8964 (availability-only OOB read on
# Unpacker reuse, fixed upstream in 1.2.1) is therefore accepted risk: it is
# reachable only through pip's own build-time HTTP cache, over entries pip
# wrote itself from a trusted index. No released pip vendors the fix yet
# (main is at 1.2.1); revisit by bumping pip once that ships.
RUN python3 -m pip install --no-cache-dir --break-system-packages \
 cryptography==50.0.1 \
 pipx setuptools platformio virtualenv intelhex
RUN python3 -m pipx ensurepath
RUN python3 -V

#
# ESP32 & ESP8266 Arduino Frameworks for Platformio
#

# https://docs.platformio.org/en/latest/core/installation.html#piocore-install-shell-commands

RUN pio platform install espressif8266 \
 && pio platform install espressif32 \
 && cat /root/.platformio/platforms/espressif32/platform.py \
 && chmod 777 /root/.platformio/platforms/espressif32/platform.py \
 && sed -i 's/~2/>=1/g' /root/.platformio/platforms/espressif32/platform.py \
 && cat /root/.platformio/platforms/espressif32/platform.py \
 && rm -rf /root/.platformio/.cache

#
# ESP-IDF for projects containing `sdkconfig` or `*platform*espidf*` in platformio.ini
#

# https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/linux-macos-setup.html#get-started-get-esp-idf

RUN mkdir -p ~/esp \
 && cd ~/esp \
 && git clone -b ${ESP_IDF_VERSION} --depth 1 --shallow-submodules --recursive https://github.com/espressif/esp-idf.git
RUN cd ~/esp/esp-idf \
 && ./install.sh all \
 && rm -rf /root/.espressif/dist /root/.cache/pip

 # Build tests for ESP32 and ESP8266 (may take up to 20 minutes!)

WORKDIR /opt/dummy-esp32
RUN pio --version && pio run

WORKDIR /opt/dummy-esp8266
RUN pio --version && pio run \
 && rm -rf /root/.platformio/.cache

CMD /opt/cmd.sh

# Build tests for ESP-IDF (make fails with: No targets specified and no makefile found.)

#RUN export PATH=$PATH:/root/esp/xtensa-esp32-elf/bin \
# && export IDF_PATH=/root/esp/esp-idf \
# && cd /root/esp/esp-idf/examples/get-started/hello_world \
# && ls -la \
# && cp -v /opt/dummy-esp32-idf/sdkconfig . \
# && ln -s $(which python3) /usr/bin/python \
# && make

# Build tests for ESP32 and ESP8266 (may take up to 20 minutes!)