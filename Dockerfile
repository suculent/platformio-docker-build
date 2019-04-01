FROM ubuntu
MAINTAINER suculent@me.com

RUN mkdir /opt/workspace
WORKDIR /opt/workspace
COPY cmd.sh /opt/

COPY dummy-esp8266 /opt/dummy-esp8266
COPY dummy-esp32 /opt/dummy-esp32
COPY dummy-esp32-idf /opt/dummy-esp32-idf

RUN apt-get update && apt-get install -y --no-install-recommends wget unzip git make \
 srecord bc xz-utils gcc python curl python-pip python-dev build-essential \
 && python -m pip install --upgrade pip setuptools

RUN pip install -U platformio

# ESP32 & ESP8266 Arduino Frameworks for Platformio

RUN pio platform install espressif8266 --with-package framework-arduinoespressif8266 \
 && pio platform install espressif32 \
 && cat /root/.platformio/platforms/espressif32/platform.py \
 && chmod 777 /root/.platformio/platforms/espressif32/platform.py \
 && sed -i 's/~2/>=1/g' /root/.platformio/platforms/espressif32/platform.py \
 && cat /root/.platformio/platforms/espressif32/platform.py

# ESP-IDF for projects containing `sdkconfig` or `*platform*espidf*` in platformio.ini

RUN mkdir -p /root/esp \
 && apt-get install -y --no-install-recommends  gcc libncurses-dev flex bison gperf python python-serial \
 && cd /root/esp \
 && wget https://dl.espressif.com/dl/xtensa-esp32-elf-linux64-1.22.0-80-g6c4433a-5.2.0.tar.gz \
 && tar -xzf ./xtensa-*.tar.gz \
 && echo "export PATH=$PATH:/root/esp/xtensa-esp32-elf/bin" > .profile \
 && echo "export IDF_PATH=/root/esp/esp-idf" > .profile \
 && git clone https://github.com/espressif/esp-idf.git --recurse-submodules

# Build tests

RUN export PATH=$PATH:/root/esp/xtensa-esp32-elf/bin \
 && export IDF_PATH=/root/esp/esp-idf \
 && /usr/bin/python -m pip install --user -r /root/esp/esp-idf/requirements.txt \
 && cd /root/esp/esp-idf/examples/get-started/hello_world \
 && cp -v /opt/dummy-esp32-idf/sdkconfig . \
 && make

WORKDIR /opt/dummy-esp32
RUN pio --version && pio run

WORKDIR /opt/dummy-esp8266
RUN pio --version && pio run

RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

CMD /opt/cmd.sh
