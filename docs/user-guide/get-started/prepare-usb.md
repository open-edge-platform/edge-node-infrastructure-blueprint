<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Prepare USB and Validate

This guide covers Phase 2 and Phase 3 of the provisioning workflow: preparing the bootable USB on the developer system, installing the OS on the target system, and validating bring-up.

Before starting, ensure you have `usb-installation-files.tar.gz` produced by [Build from Source](./build-from-source.md).

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

#### Installation Mode Details

Installation mode is optional and defaults to the **Unattended Mode**, which means a fully automated installation
without user interaction. If you require interactive debugging, set `installation_mode=true` in the `config-file`
to enable the **Attended Mode** with prompts for user input during the boot process.

If installation fails or you need to troubleshoot, run the installer in interactive debug mode on the Alpine OS terminal:

```bash
/usr/local/bin/os-install.sh -i
```

This launches the installer in interactive debug mode for troubleshooting and manual configuration.

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

For the Kubernetes cluster:

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

For containers:

```bash
docker info
docker ps
```

For details on exposing Intel® GPU or NPU to containers via CDI, see the
[Intel CDI Usage Guide](../how-to/container-device-interface-guide.md).
