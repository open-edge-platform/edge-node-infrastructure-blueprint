#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0


# Find Intel kernel version Installed on the system
INTEL_KERNEL_VERSION=$(ls -1d /lib/modules/*-intel 2>/dev/null | sort -V | tail -1 | sed 's|.*/||')

# Check if Intel kernel exists
if [ -n "${INTEL_KERNEL_VERSION}" ]; then
    
    # Find generic tools directory
    GENERIC_TOOLS_DIR=$(ls -1d /usr/lib/linux-tools/*-generic 2>/dev/null | sort -V | tail -1)
    
    #  Create symlinks if tools exist
    if [ -n "${GENERIC_TOOLS_DIR}" ] && [ -d "${GENERIC_TOOLS_DIR}" ]; then
        mkdir -p "/usr/lib/linux-tools/${INTEL_KERNEL_VERSION}"
        ln -sf "${GENERIC_TOOLS_DIR}"/* "/usr/lib/linux-tools/${INTEL_KERNEL_VERSION}/" 2>/dev/null || true
    fi
    
    #  Setup perf alternative
    if [ -f "/usr/lib/linux-tools/${INTEL_KERNEL_VERSION}/perf" ]; then
        update-alternatives --install /usr/bin/perf perf "/usr/lib/linux-tools/${INTEL_KERNEL_VERSION}/perf" 100 2>/dev/null || true
    fi
fi
