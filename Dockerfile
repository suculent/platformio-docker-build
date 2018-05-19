FROM ubuntu
MAINTAINER suculent

RUN mkdir /opt/workspace
WORKDIR /opt/workspace
ADD dummy /opt/workspace/dummy
COPY cmd.sh /opt/

RUN apt-get update && apt-get install -y wget unzip git make \
 srecord bc xz-utils gcc python curl python-pip python-dev build-essential \
 && python -m pip install --upgrade pip \
 && pip install -U platformio \
 && platformio platform install espressif8266 --with-package framework-arduinoespressif8266 \
 && platformio platform install espressif32 \
 && cd /opt/workspace/dummy-esp8266 \
 && platformio run \
 && rm -rf /opt/workspace/dummy-esp8266 \
 && cd /opt/workspace/dummy-esp32 \
 && platformio run \
 && rm -rf /opt/workspace/dummy-esp32 \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

CMD /opt/cmd.sh
