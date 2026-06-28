# Debian trixie Upgrade + Parallel CI Build-Chain Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the PlatformIO build image from `debian:bookworm` to `debian:13.5-slim`, modernize the ESP-IDF dummy for IDF 5.3, and make the embedded build-chain testable via three parallel CircleCI jobs after a single shared base-image build.

**Architecture:** A baseline install log is captured on the untouched bookworm image first (for diffing). The production `Dockerfile` is bumped to trixie. Two platform-pinned clones (`Dockerfile.test.amd64`, `Dockerfile.test.arm64`) drop the inline warm-builds and instead expose `/opt/tests/build-*.sh` scripts. CircleCI builds the test image once, shares it across jobs by digest, and runs the three dummy-project builds (esp32 Arduino, esp8266 Arduino, esp32 IDF) in parallel.

**Tech Stack:** Docker / buildx, Debian 13 (trixie), PlatformIO, ESP-IDF v5.3 (idf.py/CMake), CircleCI `circleci/docker@2.8.0` orb.

## Global Constraints

- Base image: `debian:13.5-slim` (verified to exist on Docker Hub, multi-arch).
- ESP-IDF version: `v5.3` (already pinned via `ENV ESP_IDF_VERSION="v5.3"`).
- Docker image name: `suculent/platformio-docker-build` (unchanged).
- CircleCI orb: `circleci/docker@2.8.0`; executor `docker/docker`; credentials via `dockerhub` context.
- Baseline log is gitignored, never committed.
- Production `Dockerfile` keeps its inline esp32/esp8266 warm-builds; only the `.test.*` clones drop them.
- Image is shared across CI jobs **by digest** (persist the digest file, not the image).
- The three test jobs MUST run in parallel, each `requires: [build-base]`.

---

### Task 0: Baseline install log (IN PROGRESS — running in background)

**Files:**
- Create: `baseline-install-bookworm-arm64.log` (gitignored artifact)

**Interfaces:**
- Produces: a full install log of the **unmodified bookworm** Dockerfile, for later diffing against the trixie build.

- [ ] **Step 1: Confirm the background build was launched on the untouched Dockerfile**

The build was started with:
```bash
docker buildx build --platform=linux/arm64 --progress=plain -t pio-baseline:bookworm . \
  > baseline-install-bookworm-arm64.log 2>&1
```
It MUST run before any edit to `Dockerfile` (buildx reads the Dockerfile at launch, so later edits don't affect this in-flight build — but do not edit `Dockerfile` until this build has at least started, which it has).

- [ ] **Step 2: When it finishes, confirm exit status**

Run: `grep BASELINE_BUILD_EXIT baseline-install-bookworm-arm64.log`
Expected: `BASELINE_BUILD_EXIT=0` (a non-zero exit on bookworm is itself a useful baseline data point — record it, don't block on it).

This task does not gate Tasks 2–4/6/7; it only gates the **final verification** of Task 5 (so the trixie build can be compared against it). Proceed with other tasks while it runs.

---

### Task 1: Update `.gitignore`

**Files:**
- Modify: `.gitignore`

**Interfaces:**
- Produces: ignore rules so baseline logs and IDF/PIO build artifacts never get committed.

- [ ] **Step 1: Append ignore rules**

Current `.gitignore` contains:
```
.pioenvs
.piolibdeps
```
Append:
```
.pio/
baseline-install-*.log
dummy-esp32-idf/build/
dummy-esp32-idf/sdkconfig
```

- [ ] **Step 2: Verify nothing already-tracked is now ignored unexpectedly**

Run: `git status --porcelain dummy-esp32-idf/sdkconfig`
Expected: empty output after the next task removes it from tracking (sdkconfig is deleted in Task 2). For now it may still show as tracked — that's fine.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: ignore baseline logs and IDF/PIO build artifacts"
```

---

### Task 2: Modernize `dummy-esp32-idf` for ESP-IDF 5.3 (idf.py/CMake)

**Files:**
- Create: `dummy-esp32-idf/CMakeLists.txt`
- Create: `dummy-esp32-idf/main/CMakeLists.txt`
- Modify: `dummy-esp32-idf/main/hello_world_main.c`
- Delete: `dummy-esp32-idf/Makefile`, `dummy-esp32-idf/main/component.mk`, `dummy-esp32-idf/sdkconfig`

**Interfaces:**
- Produces: an IDF project buildable with `idf.py set-target esp32 && idf.py build` under IDF 5.3. Consumed by `tests/build-esp32-idf.sh` (Task 3).

- [ ] **Step 1: Create the top-level `CMakeLists.txt`**

```cmake
cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(hello-world)
```

- [ ] **Step 2: Create `main/CMakeLists.txt`**

```cmake
idf_component_register(SRCS "hello_world_main.c" INCLUDE_DIRS "")
```

- [ ] **Step 3: Rewrite `main/hello_world_main.c` for IDF 5.3 APIs**

Replace the removed `esp_spi_flash.h` / `spi_flash_get_chip_size()` with `esp_flash.h` / `esp_flash_get_size()`:

```c
/* Hello World Example — ESP-IDF 5.3 (idf.py/CMake) */
#include <stdio.h>
#include <inttypes.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_system.h"
#include "esp_chip_info.h"
#include "esp_flash.h"

void app_main(void)
{
    printf("Hello world!\n");

    esp_chip_info_t chip_info;
    esp_chip_info(&chip_info);
    printf("This is %s chip with %d CPU core(s), WiFi%s%s, ",
           CONFIG_IDF_TARGET,
           chip_info.cores,
           (chip_info.features & CHIP_FEATURE_BT) ? "/BT" : "",
           (chip_info.features & CHIP_FEATURE_BLE) ? "/BLE" : "");
    printf("silicon revision %d, ", chip_info.revision);

    uint32_t flash_size = 0;
    if (esp_flash_get_size(NULL, &flash_size) == ESP_OK) {
        printf("%" PRIu32 "MB %s flash\n", flash_size / (1024 * 1024),
               (chip_info.features & CHIP_FEATURE_EMB_FLASH) ? "embedded" : "external");
    }

    for (int i = 10; i >= 0; i--) {
        printf("Restarting in %d seconds...\n", i);
        vTaskDelay(1000 / portTICK_PERIOD_MS);
    }
    printf("Restarting now.\n");
    fflush(stdout);
    esp_restart();
}
```

- [ ] **Step 4: Delete the legacy build files**

```bash
git rm dummy-esp32-idf/Makefile dummy-esp32-idf/main/component.mk dummy-esp32-idf/sdkconfig
```

- [ ] **Step 5: Commit**

```bash
git add dummy-esp32-idf/CMakeLists.txt dummy-esp32-idf/main/CMakeLists.txt dummy-esp32-idf/main/hello_world_main.c
git commit -m "refactor(idf): migrate dummy-esp32-idf to idf.py/CMake for ESP-IDF 5.3"
```

> Verification of an actual `idf.py build` happens in Task 5 (needs the built image / IDF toolchain).

---

### Task 3: Add `tests/` build scripts

**Files:**
- Create: `tests/build-esp32.sh`
- Create: `tests/build-esp8266.sh`
- Create: `tests/build-esp32-idf.sh`
- Create: `tests/run-all-local.sh`

**Interfaces:**
- Consumes: dummy projects copied to `/opt/dummy-*` inside the image; `IDF_PATH=/root/esp/esp-idf`.
- Produces: executable scripts at `/opt/tests/*.sh`, invoked by `docker run <image> /opt/tests/build-<target>.sh`.

- [ ] **Step 1: Create `tests/build-esp32.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "[test] esp32 (Arduino) build starting"
cd /opt/dummy-esp32
pio run
echo "[test] esp32 (Arduino) build OK"
```

- [ ] **Step 2: Create `tests/build-esp8266.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "[test] esp8266 (Arduino) build starting"
cd /opt/dummy-esp8266
pio run
echo "[test] esp8266 (Arduino) build OK"
```

- [ ] **Step 3: Create `tests/build-esp32-idf.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "[test] esp32-idf build starting"
export IDF_PATH="${IDF_PATH:-/root/esp/esp-idf}"
# shellcheck disable=SC1091
. "$IDF_PATH/export.sh"
cd /opt/dummy-esp32-idf
idf.py set-target esp32
idf.py build
echo "[test] esp32-idf build OK"
```

- [ ] **Step 4: Create `tests/run-all-local.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
# Convenience runner for local arm64 testing against a built image.
# Usage: docker run --rm <image> /opt/tests/run-all-local.sh
/opt/tests/build-esp32.sh
/opt/tests/build-esp8266.sh
/opt/tests/build-esp32-idf.sh
echo "[test] ALL build-chain tests passed"
```

- [ ] **Step 5: Make them executable and commit**

```bash
chmod +x tests/*.sh
git add tests/
git commit -m "test: add per-target build-chain test scripts for /opt/tests"
```

---

### Task 4: Add `Dockerfile.test.amd64` and `Dockerfile.test.arm64`

**Files:**
- Create: `Dockerfile.test.amd64`
- Create: `Dockerfile.test.arm64`

**Interfaces:**
- Consumes: `cmd.sh`, `dummy-*` projects, `tests/` scripts.
- Produces: test images that contain the full toolchain + `/opt/tests/*.sh`, WITHOUT the inline esp32/esp8266 warm-builds (those become CI jobs).

- [ ] **Step 1: Create `Dockerfile.test.amd64`**

Identical to the (trixie) production `Dockerfile` EXCEPT: (a) platform-pinned `FROM`, (b) add `COPY tests /opt/tests` + `chmod +x`, (c) remove the inline `pio run` warm-build steps (the `WORKDIR /opt/dummy-esp32 … pio run` / `WORKDIR /opt/dummy-esp8266 … pio run` blocks).

```dockerfile
# IDF v5.3; ESP8266@; ESP32@  — CI test image (amd64)
FROM --platform=linux/amd64 debian:13.5-slim

LABEL version="1.8.96"

ENV DEBIAN_FRONTEND=noninteractive
ENV ESP_IDF_VERSION="v5.3"

RUN mkdir /opt/workspace
WORKDIR /opt/workspace
COPY cmd.sh /opt/

COPY dummy-esp8266 /opt/dummy-esp8266
COPY dummy-esp32 /opt/dummy-esp32
COPY dummy-esp32-idf /opt/dummy-esp32-idf
COPY tests /opt/tests
RUN chmod +x /opt/tests/*.sh

RUN apt update -qq && \
apt install -y -qq --no-install-recommends software-properties-common gpgv2 && \
apt install -qq -y --no-install-recommends \
bc \
bison \
build-essential \
ccache \
cmake \
curl \
dfu-util \
flex \
gcc \
git \
gperf \
jq \
libffi-dev \
libncurses-dev \
libssl-dev \
libusb-1.0-0 \
make \
ninja-build \
python3 \
python3-dev \
python3-pip \
python3-venv \
srecord \
unzip \
wget \
xz-utils \
&& apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN python3 -m pip install --break-system-packages pipx setuptools platformio virtualenv intelhex
RUN python3 -m pipx ensurepath
RUN python3 -V

RUN pio platform install espressif8266 \
 && pio platform install espressif32 \
 && chmod 777 /root/.platformio/platforms/espressif32/platform.py \
 && sed -i 's/~2/>=1/g' /root/.platformio/platforms/espressif32/platform.py

RUN mkdir -p ~/esp \
 && cd ~/esp \
 && git clone -b ${ESP_IDF_VERSION} --recursive https://github.com/espressif/esp-idf.git
RUN cd ~/esp/esp-idf \
 && ./install.sh all

CMD /opt/cmd.sh
```

- [ ] **Step 2: Create `Dockerfile.test.arm64`**

Byte-identical to `Dockerfile.test.amd64` except the first non-comment line:
```dockerfile
# IDF v5.3; ESP8266@; ESP32@  — local test image (arm64)
FROM --platform=linux/arm64 debian:13.5-slim
```
(Everything else identical.)

- [ ] **Step 3: Verify both parse**

Run: `docker buildx build --platform=linux/arm64 -f Dockerfile.test.arm64 --target=__nonexistent__ . 2>&1 | head -5 || true`
Expected: an error about the missing target/stage (proves the Dockerfile parsed) rather than a syntax error. (A full build happens in Task 5.)

- [ ] **Step 4: Commit**

```bash
git add Dockerfile.test.amd64 Dockerfile.test.arm64
git commit -m "build: add platform-pinned test Dockerfiles (amd64 CI / arm64 local) on debian:13.5-slim"
```

---

### Task 5: Bump production `Dockerfile` to `debian:13.5-slim` + verify the build-chain

**Files:**
- Modify: `Dockerfile:3` (FROM), `Dockerfile:5` (LABEL)

**Interfaces:**
- Consumes: baseline log from Task 0 (for comparison).
- Produces: a trixie-based production image that still warm-builds esp32/esp8266 and copies `/opt/tests`.

- [ ] **Step 1: Wait for the Task 0 baseline build to finish**

Run: `grep -q BASELINE_BUILD_EXIT baseline-install-bookworm-arm64.log && echo DONE || echo WAIT`
If `WAIT`, poll until `DONE`.

- [ ] **Step 2: Update `FROM` and `LABEL`**

In `Dockerfile`:
- Line 3: `FROM debian:bookworm-20250929-slim` → `FROM debian:13.5-slim`
- Line 5: `LABEL version="1.8.95"` → `LABEL version="1.8.96"`
- Add after the `COPY dummy-esp32-idf …` line: `COPY tests /opt/tests` and `RUN chmod +x /opt/tests/*.sh` (so the production image also carries the test scripts).

- [ ] **Step 3: Build the production image on arm64 and capture the trixie log**

```bash
docker buildx build --platform=linux/arm64 --progress=plain --load \
  -t pio-trixie:local . 2>&1 | tee trixie-install-arm64.log
```
Expected: build succeeds. If apt fails on a renamed/removed trixie package (e.g. `gpgv2`), diff against the baseline log, fix the offending package name in BOTH the production `Dockerfile` and the two `.test.*` clones, and rebuild. Record any package changes in the commit message.

- [ ] **Step 4: Run the three build-chain tests against the trixie test image (arm64)**

```bash
docker buildx build --platform=linux/arm64 --load -f Dockerfile.test.arm64 -t pio-test:arm64 .
docker run --rm pio-test:arm64 /opt/tests/run-all-local.sh
```
Expected final line: `[test] ALL build-chain tests passed`. If the IDF step fails, fix `dummy-esp32-idf` (Task 2) and/or `tests/build-esp32-idf.sh` (Task 3) and rerun.

- [ ] **Step 5: Commit**

```bash
git add Dockerfile
git commit -m "build: upgrade base image to debian:13.5-slim (trixie); carry /opt/tests"
```

---

### Task 6: Rewire `.circleci/config.yml` for parallel build-chain tests

**Files:**
- Modify: `.circleci/config.yml` (full rewrite)

**Interfaces:**
- Consumes: `Dockerfile.test.amd64`, `/opt/tests/build-*.sh`, `dockerhub` context.
- Produces: `build-base` (build+push by digest, persist digest) → 3 parallel test jobs (pull by digest, run one script each) → `deploy-docker-build` (master only).

- [ ] **Step 1: Replace the config with the digest-shared, parallel-test workflow**

```yaml
version: 2.1
orbs:
  docker: circleci/docker@2.8.0

jobs:

  build-base:
    executor: docker/docker
    steps:
      - setup_remote_docker
      - checkout
      - docker/check
      - docker/build:
          image: suculent/platformio-docker-build
          dockerfile: ./Dockerfile.test.amd64
          tag: ci
      - docker/push:
          digest-path: /tmp/digest.txt
          image: suculent/platformio-docker-build
          tag: ci
      - run:
          name: Persist image digest for downstream test jobs
          command: |
            mkdir -p /tmp/workspace
            cp /tmp/digest.txt /tmp/workspace/digest.txt
            echo "Built digest: $(cat /tmp/workspace/digest.txt)"
      - persist_to_workspace:
          root: /tmp/workspace
          paths:
            - digest.txt

  test-esp32:
    executor: docker/docker
    steps:
      - setup_remote_docker
      - attach_workspace:
          at: /tmp/workspace
      - docker/check
      - run:
          name: Build esp32 (Arduino) in shared image
          command: |
            DIGEST=$(cat /tmp/workspace/digest.txt)
            docker pull "suculent/platformio-docker-build@${DIGEST}"
            docker run --rm "suculent/platformio-docker-build@${DIGEST}" /opt/tests/build-esp32.sh

  test-esp8266:
    executor: docker/docker
    steps:
      - setup_remote_docker
      - attach_workspace:
          at: /tmp/workspace
      - docker/check
      - run:
          name: Build esp8266 (Arduino) in shared image
          command: |
            DIGEST=$(cat /tmp/workspace/digest.txt)
            docker pull "suculent/platformio-docker-build@${DIGEST}"
            docker run --rm "suculent/platformio-docker-build@${DIGEST}" /opt/tests/build-esp8266.sh

  test-esp32-idf:
    executor: docker/docker
    steps:
      - setup_remote_docker
      - attach_workspace:
          at: /tmp/workspace
      - docker/check
      - run:
          name: Build esp32-idf (ESP-IDF) in shared image
          command: |
            DIGEST=$(cat /tmp/workspace/digest.txt)
            docker pull "suculent/platformio-docker-build@${DIGEST}"
            docker run --rm "suculent/platformio-docker-build@${DIGEST}" /opt/tests/build-esp32-idf.sh

  deploy-docker-build:
    executor: docker/docker
    steps:
      - setup_remote_docker
      - checkout
      - docker/check
      - docker/build:
          image: suculent/platformio-docker-build
          tag: latest
      - docker/push:
          digest-path: /tmp/digest.txt
          image: suculent/platformio-docker-build
          tag: latest
      - run:
          command: |
            echo "Digest is: $(</tmp/digest.txt)"
            docker tag $(</tmp/digest.txt) suculent/platformio-docker-build:latest

#
# WORKFLOWS
#

workflows:
  version: 2
  build:
    jobs:
      - build-base:
          context:
            - dockerhub
      - test-esp32:
          context:
            - dockerhub
          requires:
            - build-base
      - test-esp8266:
          context:
            - dockerhub
          requires:
            - build-base
      - test-esp32-idf:
          context:
            - dockerhub
          requires:
            - build-base
      - deploy-docker-build:
          context:
            - dockerhub
          requires:
            - test-esp32
            - test-esp8266
            - test-esp32-idf
          filters:
            branches:
              only: master
```

- [ ] **Step 2: Validate the config**

Run: `circleci config validate .circleci/config.yml 2>/dev/null || docker run --rm -v "$PWD/.circleci":/cfg circleci/circleci-cli:latest config validate /cfg/config.yml`
Expected: `Config file at .circleci/config.yml is valid.` (If neither validator is available locally, visually confirm the three test jobs each `requires: [build-base]` and `deploy-docker-build` requires all three.)

- [ ] **Step 3: Commit**

```bash
git add .circleci/config.yml
git commit -m "ci: build base image once, run esp32/esp8266/idf build-chain tests in parallel by digest"
```

---

### Task 7: Final verification + README note

**Files:**
- Modify: `README.md` (add a short "Testing" section)

**Interfaces:**
- Produces: documentation for how the three build-chain tests run locally and in CI.

- [ ] **Step 1: Add a "Testing the build-chain" section to `README.md`**

```markdown
## Testing the build-chain

The image is verified against three dummy projects:

- `dummy-esp32`  — ESP32 (Arduino framework, PlatformIO)
- `dummy-esp8266` — ESP8266 (Arduino framework, PlatformIO)
- `dummy-esp32-idf` — ESP32 (ESP-IDF 5.3, `idf.py`)

**Locally (arm64):**

    docker buildx build --platform=linux/arm64 --load -f Dockerfile.test.arm64 -t pio-test:arm64 .
    docker run --rm pio-test:arm64 /opt/tests/run-all-local.sh

**CircleCI (amd64):** `build-base` builds `Dockerfile.test.amd64` once and shares it
by digest; `test-esp32`, `test-esp8266`, and `test-esp32-idf` then run in parallel.
```

- [ ] **Step 2: Final consistency check**

Run:
```bash
grep -n "debian:13.5-slim" Dockerfile Dockerfile.test.amd64 Dockerfile.test.arm64
grep -n "platform=linux/amd64" Dockerfile.test.amd64
grep -n "platform=linux/arm64" Dockerfile.test.arm64
ls -l tests/*.sh
```
Expected: all three Dockerfiles on `debian:13.5-slim`; correct platform pins; four executable test scripts.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document the three-target build-chain test harness"
```

---

## Known issues (out of scope, flagged)

- `cmd.sh`'s runtime ESP-IDF path still calls legacy `make` (line 128), now inconsistent with the modernized idf.py dummy. Track as a follow-up.
- Three near-identical Dockerfiles (`Dockerfile`, `.test.amd64`, `.test.arm64`) must be kept in sync by hand; any package-list fix must land in all three.
