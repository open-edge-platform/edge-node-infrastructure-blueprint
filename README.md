# Edge Node Infrastructure software

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/open-edge-platform/edge-node-infrastructure-blueprint/badge)](https://scorecard.dev/viewer/?uri=github.com/open-edge-platform/edge-node-infrastructure-blueprint)

## Documentation

Full documentation is available at [Federal And Aerospace AI Suite](https://docs.openedgeplatform.intel.com/2026.2/ai-suite-fed-aero.html).

## Introduction

The Edge Node Infrastructure software creates a comprehensive edge computing platform that enables hardware acceleration capabilities including GPU, NPU, SR-IOV, and other features for modern applications, allowing containerized and cloud-native applications to be deployed seamlessly on edge nodes.

This repository helps you:
- Build bootable installation artifacts.
- Prepare USB media for target node provisioning.
- Bring up core software components after first boot.
- Validate platform readiness for cloud-native edge workloads.

The solution bridges the gap between edge hardware capabilities and application requirements, providing a standardized platform for deploying latency-sensitive workloads, AI and machine learning inference, IoT processing, and real-time applications at the network edge.

## Scope

- Developer system: The host machine used to generate installation artifacts.
- Target system: The edge machine used for application deployment.

## Phase 1: Build Artifacts on the Developer System

### 1. Prerequisites

#### System Requirements

The developer system is used to build installation artifacts and prepare the bootable USB.

| Component | Minimum                                                          |
| --------- | ---------------------------------------------------------------- |
| OS        | Ubuntu 24.04/22.04 or WSL environment                            |
| CPU       | Any modern x86-64 processor with virtualisation support          |
| Memory    | 16 GiB RAM                                                       |
| Storage   | 100 GiB free disk space (for image build workspace)              |
| USB       | 32 GiB USB drive (for bootable installation media)               |
| Network   | Internet access to fetch packages and images                     |

The target system is the Intel edge node on which the provisioned OS and workloads will run. The infrastructure software has been validated on the following hardware configurations:

| CPU                         | Memory      | Storage      |
| --------------------------- | ----------- | ------------ |
| Intel® Core Ultra™ X7 358HR | 16 GiB DDR5 | 512 GiB NVMe |
| Intel® Core Ultra™ X7 358H  | 32 GiB DDR5 | 512 GiB NVMe |
| Intel® Core Ultra™ 5 338H   | 32 GiB DDR5 | 512 GiB NVMe |

#### Docker Setup on Developer System

Docker Engine is required because the build workflow uses Docker images and containers. Install Docker Engine for your Ubuntu system using the official Docker documentation for [Ubuntu](https://docs.docker.com/engine/install/ubuntu/). For Windows Subsystem for Linux (WSL), follow the steps in the [windows-wsl-guide](docs/user-guide/how-to/set-up-windows-wsl.md).

Configure Docker for non-root usage and service startup after installation: https://docs.docker.com/engine/install/linux-postinstall/

If you are behind a proxy, configure Docker daemon proxy settings: https://docs.docker.com/config/daemon/systemd/

#### Install Make and other tools on the Development System

Install GNU Make and other utilities on your development system:

```bash
sudo apt update
sudo apt-get install -y make gdisk openssl whois
```

#### Important Notes

- Keep `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` consistent across all proxy configuration files.
- Build flow has been verified on Ubuntu 22.04 and 24.04.

### 2. Clone the Repository

```bash
git clone https://github.com/open-edge-platform/edge-node-infrastructure-blueprint.git -b release-2026.2.0
cd edge-node-infrastructure-blueprint
```

### 3. Build Bootable USB Artifacts

> Note:If your development environment is behind a firewall, add proxy configuration to the `proxy.env` file in the `edge-node-infrastructure-blueprint` directory. To skip the proxy settings, pass `skip-proxy=true` to the make command.

#### Option 1: Build from a Standard Ubuntu 24.04 image

Before building, export the `USERNAME` and `PASSWORD` environment variables with your own credentials. These are required and must not be null or empty; the build exits before starting if either variable is unset or empty.

```bash
export USERNAME='<your-username>'
# Generate the SHA-512 password hash with one of the following methods.
# Using openssl (requires `openssl` to be installed)
export PASSWORD="$(openssl passwd -6 '<your-password>')"

# Or using mkpasswd (requires `whois` to be installed)
export PASSWORD="$(mkpasswd --method=sha-512 '<your-password>')"
```

> **Note:** The output changes on every invocation because the salt is randomly generated. All outputs verify against the same password.


Now, build the Ubuntu image, which includes the required tools and packages.

```bash
# Use MODE=server-image for uncrewed aerial vehicle(UAV) image
make build MODE=standard-image
```

Use the additional flag `HOST_OS_REBUILD=true` to force no cache usage for subsequent builds. Or, run `make clean-all` to restart from scratch.

#### Option 2: Build with Image Composer Tool Image

This path is intended for advanced users who need fine-grained control over disk layout, installed packages, and package repositories. Most users can start with Option 1. See [`infrastructure/host-os/ict/README.md`](infrastructure/host-os/ict/README.md) to generate an image using Image Composer Tool.

Use the `image-from-tool` mode when you already have an image generated by Image Composer Tool. This mode skips host image creation and packages the provided Image Composer Tool image into the USB artifacts:

```bash
make build MODE=image-from-tool ICT_IMG=/absolute/path/to/minimal-desktop-ubuntu-24.04.raw.gz
```

`ICT_IMG` may point to any readable file on the host (absolute or relative to `$PWD`); it does not have to live inside the repository. `make` resolves the path, bind-mounts the containing directory read-only into the build container, and stages the image into `infrastructure/build-artifacts/` for packaging.

The following are the supported Image Composer Tool image extensions:
- `.raw.gz`
- `.raw.img.gz`

Examples:

```bash
# Absolute path anywhere on the host
make build MODE=image-from-tool ICT_IMG=/home/user/images/minimal-desktop-ubuntu-24.04.raw.gz

# Path relative to the repository root
make build MODE=image-from-tool ICT_IMG=./minimal-desktop-ubuntu-24.04.raw.gz
```

Build output:
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
- USB Device Path (usb): The target USB device identifier (for example, `/dev/sdX`). Use the `lsblk` command to locate the correct device.
- Bootable Package (`usb-bootable-files.tar.gz`): The compressed archive containing bootable system files.
- Configuration File (`config-file`): User-customizable settings that include the following:
   - Proxy configurations
   - SSH public key (`id_rsa.pub`)
   - Workload orchestration preference (host_type)
   - Single Root I/O Virtualization (SRIOV) toggle
   - Additional system parameters
   - Debug Mode (`false`)

Run the following command:

```bash
sudo ./bootable-usb-prepare.sh /dev/sdX usb-bootable-files.tar.gz config-file
```

After the USB preparation completes:
1. Safely disconnect the USB from the developer system.
2. Connect it to the target system.
3. Enter the BIOS boot menu and boot from the USB.

### 3. Access the Edge Node

After installation, log in using the credentials specified during image build.

## Phase 3: Post-Boot Bring-Up and Validation on Target System

After the target system boots from the USB and completes first-boot provisioning via cloud-init, verify that services are running correctly. The orchestration mode depends on the `host_type` value set in the `config-file` during USB preparation (`container` is the default).

For container mode (`host_type=container`):

```bash
docker info
docker ps
```

For details on exposing Intel® GPU or NPU to containers via CDI, see the
[Intel CDI Usage Guide](docs/user-guide/how-to/configure-cdi.md).

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
- GPU or NPU not detected: Re-run the Best-Known Configuration (BKC) installation and inspect `dmesg` for driver load failures.
- OS installation fails: Set `debug_mode=true` in the `config-file`, rebuild the USB, and reboot to enable **Debug Mode** with interactive prompts. Optionally, run `/usr/local/bin/os-install.sh -i` on the Alpine OS terminal to launch the installer in interactive debug mode.
