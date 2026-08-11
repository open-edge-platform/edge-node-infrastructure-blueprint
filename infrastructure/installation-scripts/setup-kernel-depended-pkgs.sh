#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0


# Find Intel kernel version Installed on the system.
# Uses a plain glob rather than `find -printf` / `ls`: this script is also staged
# into the busybox-based hook OS, where `find` has no -printf.
INTEL_KERNEL_VERSION=$(
    for moddir in /lib/modules/*-intel; do
        [ -d "$moddir" ] && printf '%s\n' "${moddir##*/}"
    done | sort -V | tail -1
)
export INTEL_KERNEL_VERSION
