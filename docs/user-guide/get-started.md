<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Edge Node Infrastructure Blueprint — Get Started

This guide walks you through provisioning an Intel edge node end-to-end: building installation artifacts on a developer system, writing them to a bootable USB, installing the OS on the target system, and validating the bring-up.

![Setup overview](./_assets/setup.svg)

The workflow involves two types of systems:

| System                   | Role                                                           |
| ------------------------ | -------------------------------------------------------------- |
| **Developer system**     | Builds the OS image and USB installation artifacts             |
| **Target (host) system** | The Intel edge node that will be provisioned and run workloads |

The process is divided into three phases:

1. **Phase 1** — Build bootable USB artifacts on the developer system
2. **Phase 2** — Prepare and boot from the USB on the target system
3. **Phase 3** — Validate bring-up and confirm services are running

## Prerequisites

### Developer System

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

### Target (Host) System

The target system is the Intel edge node on which the provisioned OS and workloads will run. The blueprint has been validated on the following hardware configurations:

| CPU                       | Memory      | Storage      |
| ------------------------- | ----------- | ------------ |
| Intel Core Ultra X7 358HR | 16 GiB DDR5 | 512 GiB NVMe |
| Intel Core Ultra X7 358H  | 32 GiB DDR5 | 512 GiB NVMe |
| Intel Core Ultra 5 338H   | 32 GiB DDR5 | 512 GiB NVMe |

All target configurations run **Ubuntu 24.04.4 LTS** with the Intel mainline-tracking 6.18 kernel from the Intel Linux overlay.

### Go Toolchain

You will need Go programming language version 1.22 or later to build the Intel CDI GPU specification generator, which is compiled and embedded into the HookOS image before the OS build starts.

```bash
# Install Go programming language version 1.22 or later, for example, version 1.24.2
wget https://go.dev/dl/go1.24.2.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.24.2.linux-amd64.tar.gz
export PATH=/usr/local/go/bin:$PATH  # add to ~/.bashrc to persist
go version  # should report Go programming language version 1.22 or later
```

> **Notes**:
>
> - Keep the `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` values consistent across all proxy configuration files.
> - The build flow has been verified on Ubuntu OS versions 22.04 and 24.04.

## Phase 1: Build Artifacts on the Developer System

For the developer system, we recommend using Ubuntu 24.04 or Ubuntu 22.04 LTS. The developer host OS can be either a baremetal Ubuntu installation or Windows Subsystem for Linux (WSL) to build the artifacts.

For Windows Subsystem for Linux (WSL), follow the steps in the [windows-wsl-guide](./windows-wsl-guide.md).

### 1. Clone the Repository

```bash
git clone --branch v2026.1.0 https://github.com/open-edge-platform/edge-node-infrastructure-blueprint.git
cd edge-node-infrastructure-blueprint
```

### 2. Build Bootable USB Artifacts

From the repository root, run one of the following build modes.

> **Note**: If your development environment is behind a firewall, add proxy configuration to the
> `proxy.env` file in the `edge-node-infrastructure-blueprint` directory. To skip the proxy settings,
> pass `skip-proxy=true` to the make command.

#### Option 1 (Recommended): Build from ISO

Build the Ubuntu image, including the required tools and packages, from an Ubuntu ISO image
file. For additional image customization, see the
[Ubuntu Desktop Raw Image Generation guide](https://github.com/open-edge-platform/edge-node-infrastructure-blueprint/blob/v2026.1.0/infrastructure/host-os/readme.md).

```bash
make build MODE=image-from-iso ISO_URL=https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-desktop-amd64.iso
```

#### Option 2 (Advanced): Build with Image Composer Tool Image

This path is intended for advanced users who need fine-grained control over disk
layout, installed packages, and package repositories. Most users can start with
Option 1.

To generate an image using Image Composer Tool, refer to:

- [Advanced Image Customization (Using Image Composer Tool)](./advance-package-curation.md).

#### Build output

With any of the above build options, expect the following output:

- `usb-installation-files.tar.gz` in `infrastructure/build-artifacts/out`

## Phase 2: Prepare Bootable USB

### 1. Extract Installation Files on the Developer System

```bash
sudo tar -xzf usb-installation-files.tar.gz
```

The extracted files include:

- `usb-bootable-files.tar.gz`
- `config-file`
- `bootable-usb-prepare.sh`
- `ven-deployment.sh`

### 2. Configure and Prepare the USB Device

Required inputs:

- USB Device Path (`usb`): The target USB device identifier (for example, `/dev/sdX`). Use the `lsblk` command to locate the correct device.
- Bootable Package (`usb-bootable-files.tar.gz`): The compressed archive containing bootable system files.
- Configuration File (`config-file`): User-customizable settings that include the following:
  - Proxy configurations
  - SSH public key (`id_rsa.pub`)
  - Workload orchestration preference (host_type)
  - Single Root I/O Virtualization (SRIOV) toggle
  - Additional system parameters
  - Installation Mode (Attended or Unattended)

> **Note:** Proxy configuration is optional in unrestricted network environments.

Run the following command:

```bash
sudo ./bootable-usb-prepare.sh /dev/sdX usb-bootable-files.tar.gz config-file
```

To reuse a prebuilt image:

```bash
sudo ./bootable-usb-prepare.sh /dev/sdX usb-bootable-files.tar.gz config-file image.raw.gz
```

After USB preparation completes:

1. Safely disconnect the USB from the developer system.
2. Connect it to the target system.
3. Enter the BIOS boot menu and boot from the USB.

### Access the Edge Node

After installation, log in using the credentials specified in the `config-file` during the Ubuntu desktop image preparation.

## Phase 3: Post-Boot Bring-Up and Validation on Target System

After the target system boots from the USB and completes first-boot provisioning via cloud-init, verify that services are running correctly. The orchestration mode depends on the `host_type` value set in the `config-file` during USB preparation (`container` is the default).

For container mode (`host_type=container`):

```bash
docker info
docker ps
```

For details on exposing Intel® GPU or NPU to containers via CDI, see the
[Intel CDI Usage Guide](./container-device-interface-guide.md).

For Kubernetes mode (`host_type=kubernetes`):

```bash
# Kubernetes nodes and plugin pods
sudo kubectl get nodes
sudo kubectl get pods -A
```

Expected healthy output includes the running Intel and Node Feature Discovery components, for example:

```text
intel-device-plugins     intel-gpu-plugin-xxxxx                  1/1   Running
intel-device-plugins     intel-npu-plugin-xxxxx                  1/1   Running
node-feature-discovery   nfd-master-xxxxx                        1/1   Running
node-feature-discovery   nfd-worker-xxxxx                        1/1   Running
kube-system              coredns-xxxxx                           1/1   Running
kube-system              metrics-server-xxxxx                    1/1   Running
```

Verify SR-IOV status:

```bash
sudo cat /sys/kernel/debug/dri/0000:00:02.1/sriov_info
```

Expected indicators:

```text
supported: yes
enabled: yes
mode: SR-IOV VF
```

Verify GPU and NPU driver bring-up:

```bash
sudo dmesg | grep xe
sudo dmesg | grep vpu
```

## Troubleshooting Checklist

- Docker build fails: Recheck the Docker daemon and CLI proxy settings, then restart the Docker daemon.
- USB preparation fails: Verify the device path and available USB capacity.
- `kubectl` issues: Confirm that the Kubernetes installation has completed and the node status is `Ready`.
- GPU or NPU not detected: Inspect `dmesg` for driver load failures.
- OS installation fails: Set `installation_mode=true` in the `config-file`, rebuild the USB, and reboot to enable **Attended Mode** with interactive prompts. Optionally, run `/usr/local/bin/os-install.sh -i` on the Alpine OS terminal to launch the installer in interactive debug mode.

## Next Steps

- Use [Advanced Image Customization](./advance-package-curation.md) if you want to build a custom image flavor.
- Run repeatable workflows through natural language using the agent skills described in the
  [AI Agent-Driven Development Strategy](https://github.com/open-edge-platform/edge-node-infrastructure-blueprint/blob/v2026.1.0/infrastructure/docs/agent-skills-guide.md)
  section.
- Expose Intel® accelerators to containerized workloads using the
  [Intel CDI Usage Guide](./container-device-interface-guide.md).
