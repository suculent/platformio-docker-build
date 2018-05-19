FROM ubuntu
MAINTAINER suculent

RUN mkdir /opt/workspace
WORKDIR /opt/workspace
ADD dummy-esp8266 /opt/dummy-esp8266
ADD dummy-esp32 /opt/dummy-esp32
COPY cmd.sh /opt/

RUN apt-get update && apt-get install -y wget unzip git make \
 srecord bc xz-utils gcc python curl python-pip python-dev build-essential \
 && python -m pip install --upgrade pip

RUN pip install -U platformio

RUN pio platform install espressif8266 --with-package framework-arduinoespressif8266 \
 && pio platform install espressif32 \
 && cat /root/.platformio/platforms/espressif32/platform.py \
 && chmod 777 /root/.platformio/platforms/espressif32/platform.py \
 && sed -i 's/~2/>=1/g' /root/.platformio/platforms/espressif32/platform.py \
 && cat /root/.platformio/platforms/espressif32/platform.py

RUN cd /opt/dummy-esp32 && pio --version && pio run

RUN cd /opt/dummy-esp8266 && pio --version && pio run

RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

CMD /opt/cmd.sh
