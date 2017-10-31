FROM ubuntu
MAINTAINER suculent

RUN apt-get update && apt-get install -y wget unzip git make python-serial \
 srecord bc xz-utils gcc python curl python-pip python-dev build-essential \
 && python -m pip install --upgrade pip \
 && pip install -U platformio \
 && platformio platform install espressif8266 --with-package framework-arduinoespressif8266 \
 && platformio platform install espressif32

RUN mkdir /opt/workspace
WORKDIR /opt/workspace
COPY cmd.sh /opt/
CMD /opt/cmd.sh
