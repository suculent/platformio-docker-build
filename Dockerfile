FROM ubuntu
MAINTAINER suculent

RUN mkdir /opt/workspace
WORKDIR /opt/workspace
ADD dummy-esp8266 /opt/workspace/dummy-esp8266
ADD dummy-esp32 /opt/workspace/dummy-esp32
COPY cmd.sh /opt/

RUN apt-get update && apt-get install -y wget unzip git make \
 srecord bc xz-utils gcc python curl python-pip python-dev build-essential \
 && python -m pip install --upgrade pip

RUN pip install -U platformio

RUN platformio platform install espressif8266 --with-package framework-arduinoespressif8266 \
 && platformio platform install espressif32 \
 && cd /opt/workspace/dummy-esp8266 \
 && platformio run \
 && rm -rf /opt/workspace/dummy-esp8266 \
 && cd /opt/workspace/dummy-esp32 \
 && platformio run \
 && rm -rf /opt/workspace/dummy-esp32 \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN sed 's/~/>=/g' /root/.platformio/platforms/espressif32/platform.py > /root/.platformio/platforms/espressif32/platform.py; cat test.py

CMD /opt/cmd.sh
