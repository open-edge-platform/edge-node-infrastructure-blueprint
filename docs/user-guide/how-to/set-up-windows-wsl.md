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
sudo apt install -y make
```

---

## Step 4: Install Docker

Inside the Ubuntu 24.04 terminal, install Docker Engine:

```bash
sudo apt-get install -y ca-certificates curl gnupg lsb-release

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
```

Configure Docker proxy settings when operating behind a proxy:

```bash
mkdir ~/.docker

vi  ~/.docker/config.json
{
        "proxies": {
                "default": {
                        "httpProxy": "http://proxy-server-ip:port",
                        "httpsProxy": "http://proxy-server-ip:port",
                        "noProxy": "localhost,127.0.0.0/8,/var/run/docker.sock"
                }
        }
}
```

Allow your user to run Docker without `sudo`, then activate the change:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

Reload daemon and restart the service:

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker.service
```


Verify Docker is working:

```bash
docker run --rm hello-world
```

---

## Step 5: Clone the Repository and Build Artifacts

The build steps are the same on WSL2 as on a native Linux developer system. From inside the Ubuntu 24.04 terminal, follow **Phase 1 — Build Artifacts on the Developer System** in the [Build from Source](../get-started/build-from-source.md) guide to clone the repository

Before building standard-image, export the `USERNAME` and `PASSWORD` environment variables with your own credentials.
These are required and must not be null or empty; the build exits before starting if either variable is unset or empty.

```bash
export USERNAME='<your-username>'
# Generate the SHA-512 password hash with one of the following methods.
# Using openssl (requires `openssl` to be installed)
export PASSWORD="$(openssl passwd -6 '<your-password>')"

# Or using mkpasswd (requires `whois` to be installed)
export PASSWORD="$(mkpasswd --method=sha-512 '<your-password>')"

# Build the standard image
make build MODE=standard-image
```

Once the build completes and you have `usb-installation-files.tar.gz`, continue with Step 6 below to attach your USB drive to WSL2.

---

## Step 6: Attach USB Drive to WSL2

To run `bootable-usb-prepare.sh` inside WSL2, the USB drive must be explicitly attached
using **usbipd-win**.

### 6a. Install usbipd-win on Windows

In **Windows PowerShell as Administrator**:

```powershell
winget install usbipd
```

Alternatively, download the installer from [USBIPD-WIN Releases](https://github.com/dorssel/usbipd-win/releases).

### 6b. List available USB devices

In **Windows PowerShell as Administrator**:

```powershell
usbipd list
```

Example output:

```
BUSID  VID:PID    DEVICE                                                        STATE
1-13   2174:2100  USB Attached SCSI (UAS) Mass Storage Device                   Not shared
```

### 6c. Bind the USB device (one-time setup per device)

```powershell
usbipd bind -f -b 1-13
```

Replace `1-13` with the BUSID of your USB drive from the list above.

### 6d. Attach the USB device to WSL2

```powershell
usbipd attach -w -b 1-13
```

The device state will change to `Attached`:

```
BUSID  VID:PID    DEVICE                                                        STATE
1-13   2174:2100  USB Attached SCSI (UAS) Mass Storage Device                   Attached
```

### 6e. Verify the device is visible in WSL2

Inside the Ubuntu 24.04 terminal:

```bash
lsblk
```

The USB drive will appear as `/dev/sdb` (or similar). Now run the USB preparation script:

```bash
cd infrastructure/build-artifacts
sudo ./bootable-usb-prepare.sh /dev/sdb usb-bootable-files.tar.gz config-file
```

### 6f. Detach when done

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
