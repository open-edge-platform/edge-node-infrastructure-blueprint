<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

<!--hide_directive
```{eval-rst}
:orphan:
```
hide_directive-->

# Set Up a Developer Build System with Windows Subsystem for Linux 2 (WSL2)

This guide explains how to prepare a Windows machine using Windows Subsystem for Linux 2 (WSL2) with Ubuntu 24.04.

## Prerequisites

- Windows 11
- Administrator access on the Windows machine

---

## Step 1: Install WSL2 with Ubuntu 24.04

Open **PowerShell as Administrator** and run:

```powershell
wsl.exe --install Ubuntu-24.04
```

This installs WSL2 and Ubuntu 24.04 in one step. Reboot if prompted.

For full WSL command reference, see the [WSL Basic commands guide](https://learn.microsoft.com/en-us/windows/wsl/basic-commands).

---

## Step 2: Launch Ubuntu 24.04

```powershell
wsl.exe -d Ubuntu-24.04
```

This opens a Ubuntu 24.04 terminal. All subsequent steps run inside this terminal.

---

## Step 3: Configure Networking

Configure network settings based on your connection type.

### Option A: Proxy-based lab network (no VPN)

Configure proxy environment variables:

> **Note:** If no proxy is required on your network, leave all values empty.

```bash
# Append the proxy environment variables to /etc/environment
http_proxy="http://proxy-server-ip:port"
https_proxy="http://proxy-server-ip:port"
no_proxy=".internal,127.0.0.1,::1,localhost"
HTTP_PROXY="http://proxy-server-ip:port"
HTTPS_PROXY="http://proxy-server-ip:port"
NO_PROXY=".internal,127.0.0.1,::1,localhost"

# Append the following lines to ~/.bashrc
export PATH=$PATH:/usr/local/go/bin
export http_proxy="http://proxy-server-ip:port"
export https_proxy="http://proxy-server-ip:port"
export no_proxy=".internal,127.0.0.1,::1,localhost"
export HTTP_PROXY="http://proxy-server-ip:port"
export HTTPS_PROXY="http://proxy-server-ip:port"
export NO_PROXY=".internal,127.0.0.1,::1,localhost"

# Configure apt proxy in /etc/apt/apt.conf.d/apt.conf
Acquire::http::proxy "http://proxy-server-ip:port";
Acquire::https::proxy "http://proxy-server-ip:port";
```

### Option B: VPN with mirrored networking

If you are on VPN and WSL2 cannot connect to the internet (for example, `apt update` fails or the proxy is unreachable), enable **mirrored networking mode**. This makes WSL2 share the Windows network stack directly, so VPN routing applies to WSL2 too.

Open `.wslconfig` in Notepad from **Windows PowerShell** (not inside WSL):

```powershell
notepad "$env:USERPROFILE\.wslconfig"
```

Add the following configuration and save the file:

```ini
[wsl2]
networkingMode=mirrored
```

### Restart WSL

```powershell
wsl --shutdown
wsl -d Ubuntu-24.04
```

### Verify Connectivity

Inside the Ubuntu 24.04 terminal:

```bash
curl -I http://archive.ubuntu.com
sudo apt update
sudo apt upgrade -y

# Install go lang and tools required for build
wget https://go.dev/dl/go1.24.2.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.24.2.linux-amd64.tar.gz
sudo apt install -y make
```

---

## Step 4: Clone the Repository and Build Artifacts

The build steps are the same on WSL2 as on a native Linux developer system. From inside the Ubuntu 24.04 terminal, follow **Phase 1 — Build Artifacts on the Developer System** in the [Build from Source](../get-started/build-from-source.md) guide to clone the repository and run `make build MODE=image-from-iso ...`.

Once the build completes and you have `usb-installation-files.tar.gz`, continue with Step 5 below to attach your USB drive to WSL2.

---

## Step 5: Attach USB Drive to WSL2

To run `bootable-usb-prepare.sh` inside WSL2, the USB drive must be explicitly attached
using **usbipd-win**.

### 5a. Install usbipd-win on Windows

In **Windows PowerShell as Administrator**:

```powershell
winget install usbipd
```

Alternatively, download the installer from [USBIPD-WIN Releases](https://github.com/dorssel/usbipd-win/releases).

### 5b. List available USB devices

In **Windows PowerShell as Administrator**:

```powershell
usbipd list
```

Example output:

```
BUSID  VID:PID    DEVICE                                                        STATE
1-13   2174:2100  USB Attached SCSI (UAS) Mass Storage Device                   Not shared
```

### 5c. Bind the USB device (one-time setup per device)

```powershell
usbipd bind -f -b 1-13
```

Replace `1-13` with the BUSID of your USB drive from the list above.

### 5d. Attach the USB device to WSL2

```powershell
usbipd attach -w -b 1-13
```

The device state will change to `Attached`:

```
BUSID  VID:PID    DEVICE                                                        STATE
1-13   2174:2100  USB Attached SCSI (UAS) Mass Storage Device                   Attached
```

### 5e. Verify the device is visible in WSL2

Inside the Ubuntu 24.04 terminal:

```bash
lsblk
```

The USB drive will appear as `/dev/sdb` (or similar). Now run the USB preparation script:

```bash
cd infrastructure/build-artifacts
sudo ./bootable-usb-prepare.sh /dev/sdb usb-bootable-files.tar.gz config-file
```

### 5f. Detach when done

```powershell
usbipd detach -b 1-13
```

---

## Troubleshooting

| Issue | Fix |
|---|---|
| `apt update` fails — proxy not resolving | Follow Step 3 (mirrored networking) |
| Docker daemon not starting | Run `sudo service docker start` inside WSL2 |
| `make` not found | `sudo apt install -y make` |
| Build fails with KVM error | WSL2 does not support KVM by default; ensure you are on a machine where nested virtualization is enabled in Windows settings |
| USB drive not visible in WSL2 (`lsblk`) | Ensure `usbipd attach -w -b <BUSID>` was run in PowerShell as Administrator |
| `usbipd bind` fails | Run PowerShell as Administrator |
| `usbipd attach` fails | Unplug and plug the USB drive and retry the steps list/bind/attach |
