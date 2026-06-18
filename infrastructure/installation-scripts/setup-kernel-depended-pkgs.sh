#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -e

# Find Intel kernel version Installed on the system
INTEL_KERNEL_VERSION=$(ls -1d /lib/modules/*-intel 2>/dev/null | sort -V | tail -1 | sed 's|.*/||')
export INTEL_KERNEL_VERSION

echo "Detected Intel kernel version: ${INTEL_KERNEL_VERSION}"

if [ -z "${INTEL_KERNEL_VERSION}" ]; then
    echo "ERROR: No Intel kernel found in /lib/modules/"
    exit 1
fi

# Create symbolic links for kernel-dependent packages
# This resolves DKMS module build dependencies with the custom Intel kernel

KERNEL_MODULE_DIR="/lib/modules/${INTEL_KERNEL_VERSION}"

# Ensure kernel headers and build directories exist
if [ ! -d "${KERNEL_MODULE_DIR}/build" ]; then
    echo "Creating symbolic link for kernel build directory..."
    INTEL_HEADERS_DIR="/usr/src/linux-headers-${INTEL_KERNEL_VERSION}"

    if [ -d "${INTEL_HEADERS_DIR}" ]; then
        ln -sf "${INTEL_HEADERS_DIR}" "${KERNEL_MODULE_DIR}/build"
        echo "Linked ${KERNEL_MODULE_DIR}/build -> ${INTEL_HEADERS_DIR}"
    else
        echo "WARNING: Intel kernel headers not found at ${INTEL_HEADERS_DIR}"
    fi
fi

# Rebuild DKMS modules against the Intel kernel
echo "Rebuilding DKMS modules for Intel kernel ${INTEL_KERNEL_VERSION}..."

# List of DKMS modules that need Intel kernel support
DKMS_MODULES=(
    "intel-ipu6"           # IPU6 MIPI camera driver
    "intel-usbio"          # USB I/O bridge for MIPI
    "librealsense2"        # RealSense camera support
)

for module in "${DKMS_MODULES[@]}"; do
    # Check if DKMS module is installed
    if dkms status "${module}" >/dev/null 2>&1; then
        echo "Processing DKMS module: ${module}"

        # Get module version
        MODULE_VERSION=$(dkms status "${module}" | head -1 | awk -F', ' '{print $1}' | awk -F'/' '{print $2}')

        if [ -n "${MODULE_VERSION}" ]; then
            echo "  Building ${module}/${MODULE_VERSION} for ${INTEL_KERNEL_VERSION}..."

            # Remove existing build if present
            dkms remove "${module}/${MODULE_VERSION}" -k "${INTEL_KERNEL_VERSION}" 2>/dev/null || true

            # Build and install for Intel kernel
            if dkms build "${module}/${MODULE_VERSION}" -k "${INTEL_KERNEL_VERSION}"; then
                dkms install "${module}/${MODULE_VERSION}" -k "${INTEL_KERNEL_VERSION}"
                echo "  ✓ ${module} built and installed successfully"
            else
                echo "  ✗ WARNING: Failed to build ${module} for ${INTEL_KERNEL_VERSION}"
            fi
        fi
    else
        echo "DKMS module ${module} not found, skipping..."
    fi
done

# Update module dependencies
echo "Updating module dependencies..."
depmod -a "${INTEL_KERNEL_VERSION}"

# Verify MIPI/IPU6 modules
echo "Verifying MIPI camera modules..."
for mod in intel-ipu6 intel-ipu6-isys intel-usbio; do
    if modinfo "${mod}" -k "${INTEL_KERNEL_VERSION}" >/dev/null 2>&1; then
        echo "  ✓ Module ${mod} is available"
    else
        echo "  ✗ WARNING: Module ${mod} not found for ${INTEL_KERNEL_VERSION}"
    fi
done

echo "Kernel-dependent package setup completed successfully"
