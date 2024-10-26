#!/bin/bash

docker buildx build --platform=linux/arm64 -t suculent/platformio-docker-build:arm64 .

docker buildx build --platform=linux/amd64 -t suculent/platformio-docker-build:latest .

