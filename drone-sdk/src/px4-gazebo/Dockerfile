# syntax=docker/dockerfile:1
# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

FROM ubuntu:24.04

# Build-time proxy args — declared as both ARG and ENV so that:
#   - apt (via apt.conf.d/00proxy) uses the proxy
#   - wget/curl inside ubuntu.sh inherit https_proxy from the environment
#   - git inherits http.proxy from the environment
ARG http_proxy
ARG https_proxy
ARG no_proxy
ENV http_proxy=${http_proxy} \
    https_proxy=${https_proxy} \
    no_proxy=${no_proxy} \
    DEBIAN_FRONTEND=noninteractive

# Explicit apt proxy config — ubuntu:24.04 does not pick up http_proxy automatically.
RUN if [ -n "${http_proxy}" ]; then \
      echo "Acquire::http::Proxy \"${http_proxy}\";"   > /etc/apt/apt.conf.d/00proxy; \
      echo "Acquire::https::Proxy \"${https_proxy}\";" >> /etc/apt/apt.conf.d/00proxy; \
      echo "http_proxy=${http_proxy}"   >> /etc/environment; \
      echo "https_proxy=${https_proxy}" >> /etc/environment; \
      echo "no_proxy=${no_proxy}"       >> /etc/environment; \
    fi

# ── Ensure video and render groups exist for GPU device access ───────────────
# The render group is not created by default in Ubuntu 24.04; Docker's
# group_add: [render] will fail unless the group exists inside the image.
RUN groupadd -f render && groupadd -f video

# ── Intel GPU stack — Noble (Mesa 25.x + Xe3/Panther Lake 0xb08f support) ───
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      wget gpg ca-certificates \
    && if [ -n "${https_proxy}" ]; then \
         echo "https_proxy=${https_proxy}" >> /etc/wgetrc; \
         echo "http_proxy=${http_proxy}"   >> /etc/wgetrc; \
         echo "use_proxy=on"               >> /etc/wgetrc; \
       fi \
    && wget -qO - https://repositories.intel.com/gpu/intel-graphics.key \
       | gpg --dearmor -o /usr/share/keyrings/intel-graphics.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/intel-graphics.gpg] \
       https://repositories.intel.com/gpu/ubuntu noble unified" \
       > /etc/apt/sources.list.d/intel-gpu.list \
    && apt-get update && apt-get install -y --no-install-recommends \
       libgl1-mesa-dri \
       libglx-mesa0 \
       libegl-mesa0 \
       mesa-vulkan-drivers \
       libgbm1 \
       libxatracker2 \
       libigdgmm12

# ── PX4 build toolchain via PX4's own ubuntu.sh ──────────────────────────────
# ubuntu.sh fetches the OSRF GPG key and repo via wget — https_proxy must be
# set in the environment for this RUN layer (re-declare ARG to ensure it is).
ARG http_proxy
ARG https_proxy
ARG no_proxy
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      git curl sudo lsb-release \
    && if [ -n "${http_proxy}" ]; then \
         git config --system http.proxy  "${http_proxy}"; \
         git config --system https.proxy "${https_proxy}"; \
       fi \
    && git clone --depth 1 --branch v1.17.0 \
         https://github.com/PX4/PX4-Autopilot.git /tmp/px4-setup \
    && bash /tmp/px4-setup/Tools/setup/ubuntu.sh --no-nuttx \
    && rm -rf /tmp/px4-setup

# ── Gazebo Harmonic dev libs ─────────────────────────────────────────────────
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
       libgz-sim8-dev \
       libgz-transport13-dev \
       libgz-sensors8-dev \
       gz-harmonic

# ── PX4 v1.17.0 source + submodules ─────────────────────────────────────────
ARG http_proxy
ARG https_proxy
ARG no_proxy
RUN git clone --depth 1 --branch v1.17.0 \
      https://github.com/PX4/PX4-Autopilot.git /px4 \
    && cd /px4 \
    && git submodule update --init --recursive --depth 1 --jobs "$(nproc)"

# ── Compile SITL binaries ────────────────────────────────────────────────────
RUN cd /px4 && make px4_sitl_default

# Clear proxy so it is not present at runtime
ENV http_proxy= \
    https_proxy= \
    no_proxy=

WORKDIR /px4

# HEADLESS and PX4_HOME_* are injected at runtime via docker-compose.yml.
CMD ["bash", "-c", "make px4_sitl gz_x500_lidar_down"]
