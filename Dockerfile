FROM ubuntu
MAINTAINER suculent

RUN mkdir /opt/workspace
WORKDIR /opt/workspace
COPY cmd.sh /opt/

ADD dummy-esp8266 /opt/dummy-esp8266
ADD dummy-esp32 /opt/dummy-esp32
ADD dummy-esp32-idf /opt/dummy-esp32-idf

RUN apt-get update && apt-get install -y wget unzip git make \
 srecord bc xz-utils gcc python curl python-pip python-dev build-essential \
 && python -m pip install --upgrade pip

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
 && apt-get install -y gcc libncurses-dev flex bison gperf python python-serial \
 && cd /root/esp \
 && wget https://dl.espressif.com/dl/xtensa-esp32-elf-linux64-1.22.0-80-g6c4433a-5.2.0.tar.gz \
 && tar -xzf ./xtensa-*.tar.gz \
 && echo "export PATH=$PATH:/root/esp/xtensa-esp32-elf/bin" > .profile \
 && echo "export IDF_PATH=/root/esp/esp-idf" > .profile \
 && git clone https://github.com/espressif/esp-idf.git --recurse-submodules

# Build tests

RUN export PATH=$PATH:/root/esp/xtensa-esp32-elf/bin \
 && export IDF_PATH=/root/esp/esp-idf \
 && cd /root/esp/esp-idf/examples/get-started/hello_world \
 && cp -v /opt/dummy-esp32-idf/sdkconfig . \
 && make

RUN cd /opt/dummy-esp32 && pio --version && pio run

RUN cd /opt/dummy-esp8266 && pio --version && pio run

RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

CMD /opt/cmd.sh
