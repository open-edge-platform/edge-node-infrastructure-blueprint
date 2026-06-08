#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0


# Find Intel kernel version Installed on the system
INTEL_KERNEL_VERSION=$(ls -1d /lib/modules/*-intel 2>/dev/null | sort -V | tail -1 | sed 's|.*/||')

