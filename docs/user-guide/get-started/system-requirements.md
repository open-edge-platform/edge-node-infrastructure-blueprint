<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# System Requirements

## Developer System

The developer system is used to build installation artifacts and prepare the bootable USB. The build flow has been verified on:

| Component | Minimum                                                          |
| --------- | ---------------------------------------------------------------- |
| OS        | Linux distribution or WSL environment                            |
| CPU       | Any modern x86-64 processor with virtualisation support          |
| Memory    | 16 GiB RAM                                                       |
| Storage   | 100 GiB free disk space (for image build workspace)              |
| USB       | 32 GiB USB drive (for bootable installation media)               |
| Network   | Internet access (or configured proxy) to fetch packages and ISOs |

## Prerequisites

### Docker Setup

For Windows Subsystem for Linux (WSL), follow the steps in the [Windows WSL Guide](../how-to/set-up-windows-wsl.md).

Docker Engine is required because the build workflow uses Docker images and containers.

Install Docker Engine for your Linux distribution using the official Docker documentation:

- [Linux install overview](https://docs.docker.com/engine/install/)
- [Debian](https://docs.docker.com/engine/install/debian/)
- [Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [RHEL](https://docs.docker.com/engine/install/rhel/)
- [Fedora](https://docs.docker.com/engine/install/fedora/)

Configure Docker for [non-root usage and service startup after installation](https://docs.docker.com/engine/install/linux-postinstall/).

If you are behind a proxy, configure [Docker daemon proxy settings](https://docs.docker.com/config/daemon/systemd/).

### Install Make on the Development System

```bash
sudo apt-get install -y make
```

### Password Hash Tools

The build requires a SHA-512 password hash for the image credentials. Install at least one of the following:

```bash
# Option 1: openssl
sudo apt-get install -y openssl

# Option 2: mkpasswd (whois package)
sudo apt-get install -y whois
```

## Target (Host) System

The target system is the Intel edge node on which the provisioned OS and workloads will run. The blueprint has been validated on the following hardware configurations:

| CPU                       | Memory      | Storage      |
| ------------------------- | ----------- | ------------ |
| Intel Core Ultra X7 358HR | 16 GiB DDR5 | 512 GiB NVMe |
| Intel Core Ultra X7 358H  | 32 GiB DDR5 | 512 GiB NVMe |
| Intel Core Ultra 5 338H   | 32 GiB DDR5 | 512 GiB NVMe |

All target configurations run **Ubuntu 24.04.4 LTS** with the Intel mainline-tracking 6.18 kernel from the Intel Linux overlay.

> **Notes:**
>
> - Keep the `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` values consistent across all proxy configuration files.
> - The build flow has been verified on Ubuntu OS versions 22.04 and 24.04.
