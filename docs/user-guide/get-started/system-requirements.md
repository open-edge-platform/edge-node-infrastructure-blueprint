<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# System Requirements

## Developer System

The developer system is used to build installation artifacts and prepare the bootable USB. The build flow has been verified on:

| Component | Minimum                                                          |
| --------- | ---------------------------------------------------------------- |
| OS        | Ubuntu 22.04 LTS or Ubuntu 24.04 LTS (x86-64)                    |
| CPU       | Any modern x86-64 processor with virtualisation support          |
| Memory    | 16 GiB RAM                                                       |
| Storage   | 100 GiB free disk space (for image build workspace)              |
| Network   | Internet access (or configured proxy) to fetch packages and ISOs |

> **BIOS requirement:** The image build uses QEMU to run the Ubuntu installer inside a virtual machine.
> Hardware virtualisation (**Intel VT-x**) must be enabled in the developer system BIOS before running the build.
> To verify it is enabled, run `grep -m1 -c 'vmx' /proc/cpuinfo` — a value of `1` or higher confirms VT-x is active.

## Target (Host) System

The target system is the Intel edge node on which the provisioned OS and workloads will run. The blueprint has been validated on the following hardware configurations:

| CPU                       | Memory      | Storage      |
| ------------------------- | ----------- | ------------ |
| Intel Core Ultra X7 358HR | 16 GiB DDR5 | 512 GiB NVMe |
| Intel Core Ultra X7 358H  | 32 GiB DDR5 | 512 GiB NVMe |
| Intel Core Ultra 5 338H   | 32 GiB DDR5 | 512 GiB NVMe |

All target configurations run **Ubuntu 24.04.4 LTS** with the Intel mainline-tracking 6.18 kernel from the Intel Linux overlay.

## Go Toolchain

You will need Go programming language version 1.22 or later to build the Intel CDI GPU specification generator, which is compiled and embedded into the HookOS image before the OS build starts.

```bash
# Install Go programming language version 1.22 or later, for example, version 1.24.2
wget https://go.dev/dl/go1.24.2.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.24.2.linux-amd64.tar.gz
export PATH=/usr/local/go/bin:$PATH  # add to ~/.bashrc to persist
go version  # should report Go programming language version 1.22 or later
```

> **Notes:**
>
> - Keep the `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` values consistent across all proxy configuration files.
> - The build flow has been verified on Ubuntu OS versions 22.04 and 24.04.
