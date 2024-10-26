# IDF v5.3; ESP8266@; ESP32@

FROM debian:bookworm-20240926-slim

LABEL version="1.8.95"

ENV DEBIAN_FRONTEND=noninteractive
ENV ESP_IDF_VERSION="v5.3"

RUN mkdir /opt/workspace
WORKDIR /opt/workspace
COPY cmd.sh /opt/

COPY dummy-esp8266 /opt/dummy-esp8266
COPY dummy-esp32 /opt/dummy-esp32
COPY dummy-esp32-idf /opt/dummy-esp32-idf

RUN apt update -qq && \
apt install -y -qq --no-install-recommends software-properties-common gpgv2 && \
apt install -qq -y --no-install-recommends \
bc \
bison \
build-essential \
curl \
flex \
gcc \
git \
gperf \
jq \
libncurses-dev \
libusb-1.0-0-dev \
make \
python3-dev \
python3-pip \
python3.11-venv \
srecord \
unzip \
wget \
xz-utils \
&& apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#
# Install Python icomponents
#

RUN python3 -m pip install --break-system-packages pipx setuptools platformio virtualenv
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
 && cat /root/.platformio/platforms/espressif32/platform.py

#
# ESP-IDF for projects containing `sdkconfig` or `*platform*espidf*` in platformio.ini
#

# https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/linux-macos-setup.html#get-started-get-esp-idf

RUN mkdir -p ~/esp \
 && cd ~/esp \
 && git clone -b ${ESP_IDF_VERSION} --recursive https://github.com/espressif/esp-idf.git \
 && cd ./esp-idf \
 && ./install.sh all

WORKDIR /opt/dummy-esp32
RUN pio --version && pio run

WORKDIR /opt/dummy-esp8266
RUN pio --version && pio run

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