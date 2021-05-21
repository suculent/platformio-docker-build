FROM ubuntu:groovy-20210416

ENV DEBIAN_FRONTEND=noninteractive

RUN mkdir /opt/workspace
WORKDIR /opt/workspace
COPY cmd.sh /opt/

COPY dummy-esp8266 /opt/dummy-esp8266
COPY dummy-esp32 /opt/dummy-esp32
COPY dummy-esp32-idf /opt/dummy-esp32-idf

RUN apt-get update -qq && \
apt-get install -y -qq software-properties-common && \
apt-add-repository universe && \
apt-get update -qq && \
apt-get install -qq -y --no-install-recommends \
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
xz-utils

RUN python3 -m pip install --upgrade pip setuptools
RUN python3 -m pip install -U platformio

RUN python3 -V

# ESP32 & ESP8266 Arduino Frameworks for Platformio

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
 && wget https://dl.espressif.com/dl/xtensa-esp32-elf-gcc8_4_0-esp-2020r3-linux-amd64.tar.gz \
 && tar -xzf ./xtensa-*.tar.gz \
 && echo "export PATH=$PATH:/root/esp/xtensa-esp32-elf/bin" > .profile \
 && echo "export IDF_PATH=/root/esp/esp-idf" > .profile \
 && git clone https://github.com/espressif/esp-idf.git --recurse-submodules

# Build tests

RUN export PATH=$PATH:/root/esp/xtensa-esp32-elf/bin \
 && export IDF_PATH=/root/esp/esp-idf \
 && python3 -m pip install --user -r /root/esp/esp-idf/requirements.txt

RUN export PATH=$PATH:/root/esp/xtensa-esp32-elf/bin \
 && export IDF_PATH=/root/esp/esp-idf \
 && cd /root/esp/esp-idf/examples/get-started/hello_world \
 && cp -v /opt/dummy-esp32-idf/sdkconfig . \
 && ls -la \
 && ln -s $(which python3) /usr/bin/python \
 && make

WORKDIR /opt/dummy-esp32
RUN pio --version && pio run

WORKDIR /opt/dummy-esp8266
RUN pio --version && pio run

RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

CMD /opt/cmd.sh
