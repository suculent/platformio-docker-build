FROM debian:11-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV ESP_IDF_VERSION="v4.4"

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
make \
python3-dev \
python3-pip \
srecord \
unzip \
wget \
xz-utils \
&& apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN python3 -m pip install --upgrade pip setuptools
RUN python3 -m pip install -U platformio
RUN python3 -V

# ESP32 & ESP8266 Arduino Frameworks for Platformio

# https://docs.platformio.org/en/latest/core/installation.html#piocore-install-shell-commands

RUN pio platform install espressif8266 \
 && pio platform install espressif32 \
 && cat /root/.platformio/platforms/espressif32/platform.py \
 && chmod 777 /root/.platformio/platforms/espressif32/platform.py \
 && sed -i 's/~2/>=1/g' /root/.platformio/platforms/espressif32/platform.py \
 && cat /root/.platformio/platforms/espressif32/platform.py

# ESP-IDF for projects containing `sdkconfig` or `*platform*espidf*` in platformio.ini

# https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started-legacy/linux-setup.html

RUN mkdir -p /root/esp \
 && cd /root/esp \
 && git clone -b ${ESP_IDF_VERSION} --recursive https://github.com/espressif/esp-idf.git \
 && cd ./esp-idf \
 && ./install.sh esp32

# Build tests for ESP-IDF

#RUN export PATH=$PATH:/root/esp/xtensa-esp32-elf/bin \
# && export IDF_PATH=/root/esp/esp-idf \
# && cd /root/esp/esp-idf/examples/get-started/hello_world \
# && cp -v /opt/dummy-esp32-idf/sdkconfig . \
# && ls -la \
# && ln -s $(which python3) /usr/bin/python \
# && make

WORKDIR /opt/dummy-esp32
RUN pio --version && pio run

WORKDIR /opt/dummy-esp8266
RUN pio --version && pio run

CMD /opt/cmd.sh
