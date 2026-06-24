<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Build Artifacts on macOS (Apple Silicon)

This guide walks you through running the Phase 1 build on a **macOS Apple Silicon (ARM)** machine
using a Ubuntu 24.04 ARM virtual machine in UTM.

> The build scripts require Linux. macOS is not directly supported.
> This guide uses UTM (free) with Ubuntu 24.04 Desktop ARM as the build environment.

---

## Prerequisites

| What | Where |
|------|-------|
| MacBook with Apple Silicon chip | — |
| macOS Ventura or Sonoma | — |
| UTM (free VM app) | https://mac.getutm.app |
| Ubuntu 24.04 Desktop ARM ISO | https://cdimage.ubuntu.com/releases/24.04/release/ |
| 30 GB free disk space | For VM + build output |
| 8 GB RAM free | 4 GB assigned to VM minimum |

---

## Step 1 — Install UTM

1. Go to **https://mac.getutm.app** and click **Download**.
2. Open the downloaded `.dmg` and drag **UTM** to your Applications folder.
3. Open UTM. If macOS blocks it: right-click → **Open** → **Open** again.

---

## Step 2 — Download Ubuntu 24.04 Desktop ARM

Download the **ARM desktop ISO** from the Ubuntu releases page:

```
https://cdimage.ubuntu.com/releases/24.04/release/
```

File: `ubuntu-24.04.x-desktop-arm64.iso` (~5 GB)

> **Important:** Do not use the AMD64 desktop — it will not run
> natively on Apple Silicon.

---

## Step 3 — Create the Ubuntu VM in UTM

1. Open UTM → click **Create a New Virtual Machine**.
2. Select **Virtualize** (not Emulate).
3. Select **Linux**.
4. Under **Boot ISO Image** → Browse → select the ARM ISO you downloaded.
5. Set:
   - **RAM**: 4096 MB (8192 recommended for faster builds)
   - **CPU cores**: 4
   - **Storage**: 30 GB
6. Click **Save**.

---

## Step 4 — Install Ubuntu in the VM

1. Click **▶ Play** in UTM to start the VM.
2. Select **Try or Install Ubuntu**.
3. Follow the graphical installer — accept defaults for everything except:
   - Set a username and password you will remember.
4. Let the install complete (~15 min) and reboot into the VM.
5. Log in with your username and password.

---

## Step 5 — Install Prerequisites Inside the VM

### Docker

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Allow your user to run docker without sudo
sudo usermod -aG docker $USER
newgrp docker
```

### Go 1.22+ (ARM64)

```bash
wget https://go.dev/dl/go1.24.2.linux-arm64.tar.gz
sudo tar -C /usr/local -xzf go1.24.2.linux-arm64.tar.gz
echo 'export PATH=/usr/local/go/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
go version   # should show go1.24.2 linux/arm64
```

### Other required tools

```bash
sudo apt install -y make git curl xorriso squashfs-tools dosfstools \
  parted gdisk wget python3 python3-yaml qemu-system-x86
```

> `qemu-system-x86` is needed because the build script runs an x86 QEMU VM
> to install Ubuntu packages into the image — even though your build machine
> is ARM.

---

## Step 6 — Clone the Repository

```bash
git clone https://github.com/open-edge-platform/edge-node-infrastructure-blueprint.git
cd edge-node-infrastructure-blueprint
```

---

## Step 7 — Configure Proxy (corporate networks only)

If your network requires a proxy, edit `proxy.env` in the repo root:

```bash
nano proxy.env
```

Fill in:

```bash
HTTP_PROXY="http://proxy.mycompany.com:8080"
HTTPS_PROXY="http://proxy.mycompany.com:8080"
NO_PROXY="localhost,127.0.0.0/8"
http_proxy="http://proxy.mycompany.com:8080"
https_proxy="http://proxy.mycompany.com:8080"
no_proxy="localhost,127.0.0.0/8"
```

On a home or open network, leave all values empty — the build will prompt and
you can confirm to proceed without a proxy.

---

## Step 8 — Build the USB Artifacts

Run from the repository root inside the VM:

```bash
make build MODE=image-from-iso \
  ISO_URL=https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-desktop-amd64.iso
```

> **Important:** Always use the **amd64** (x86_64) ISO, even though your build
> machine is ARM. The build script runs `qemu-system-x86_64` to create an OS
> image for **Intel edge nodes**. Passing an ARM64 ISO to `qemu-system-x86_64`
> will fail at boot — the extracted kernel is ARM64 and cannot execute on an
> x86_64 QEMU machine.

The first build downloads the ISO, installs packages, and compiles the CDI
GPU spec generator. This takes **20–40 minutes** depending on your network and
VM resources.

Build output appears at:

```
infrastructure/build-artifacts/out/usb-installation-files.tar.gz
```

---

## Step 9 — Prepare the Bootable USB

Plug your USB drive into the MacBook. In UTM, connect it to the VM:

1. With the VM running, click the **USB icon** in the UTM toolbar.
2. Select your USB drive from the list to pass it through to the VM.

Inside the VM, identify the USB device:

```bash
lsblk
```

Look for a device like `/dev/sda` or `/dev/sdb` with the USB's capacity.

Extract the build output and run the USB preparation script:

```bash
cd infrastructure/build-artifacts/out

sudo tar -xzf usb-installation-files.tar.gz

# Replace /dev/sdX with your actual USB device from lsblk
sudo ./bootable-usb-prepare.sh /dev/sdX usb-bootable-files.tar.gz config-file
```

> **Double-check the device path** — this will erase the target device.

After the script completes:

1. In UTM, click the USB icon and disconnect the drive from the VM.
2. Safely eject it from macOS.
3. Connect the USB to the target edge node.
4. Enter the BIOS/UEFI boot menu and boot from the USB.

---

## Known Issues on macOS ARM (Ubuntu UTM VM)

Running the build inside an Ubuntu ARM VM on Apple Silicon has several
**fundamental incompatibilities**. The table below explains why the build
fails out of the box on this platform, and what would be needed to address
each issue.

| # | Issue | Severity | Error Seen | Why It Happens on ARM | Possible Fix |
|---|-------|----------|-----------|----------------------|--------------|
| 1 | **KVM not available** | Fatal | `Could not access KVM kernel module: No such file or directory` | UTM on Apple Silicon virtualises the ARM architecture. There is no x86 hardware to accelerate, so `/dev/kvm` does not exist in the VM | Replace `-enable-kvm -cpu host` with `-machine accel=tcg -cpu qemu64` (software emulation, 3–5× slower) |
| 2 | **`-aio=native` requires KVM** | Fatal | `aio=native requires cache.direct=on` | Native AIO is a Linux kernel feature tied to direct I/O, which only works reliably under KVM acceleration. TCG mode does not support it | Remove `-aio=native` from the drive string on the TCG path |
| 3 | **OVMF firmware not found** | Fatal | `Can't open file /usr/share/qemu/OVMF.fd: No such file or directory` | The `ovmf` package was not listed as a dependency and the hardcoded path does not match where Ubuntu 24.04 actually installs the firmware (`/usr/share/OVMF/OVMF_CODE.fd`) | Install the `ovmf` package; probe the actual path at runtime instead of hardcoding it |
| 4 | **Alpine chroot fails with Exec format error** | Fatal | `chroot: failed to run command '/bin/sh': Exec format error` | The Alpine rootfs downloaded is x86_64. On an ARM host those binaries cannot execute natively — the kernel has no way to run them without a userspace QEMU translator | Install `qemu-user-static` and `binfmt-support`; copy `/usr/bin/qemu-x86_64-static` into the rootfs before entering chroot |
| 5 | **`grub-mkrescue` produces ARM ISO (not x86_64)** | Fatal (silent) | Build succeeds but ISO does not boot on Intel edge node | On an ARM host, `grub-mkrescue` only has ARM grub modules available. Without x86_64-specific EFI and BIOS modules the resulting ISO is not bootable on x86_64 hardware | Install `grub-efi-amd64-bin` and `grub-pc-bin` to provide the x86_64 grub modules |
| 6 | **Wrong Ubuntu ISO architecture** | Fatal | `qemu-system-x86_64` extracts `casper/vmlinuz` from the ISO and uses it as the QEMU boot kernel — an ARM64 kernel cannot start under x86_64 emulation; even if it could, the installed system would contain ARM64 packages unrunnable on Intel edge nodes | Using `arm64` ISO URL with this build script. The build machine is ARM but the **target** is always an Intel x86_64 edge node | Always supply the `amd64` (x86_64) Ubuntu Desktop ISO URL regardless of your build machine architecture |
| 7 | **CDI GPU generator build fails (CGO cross-compilation)** | Fatal | `gcc: error: unrecognized command-line option '--target=x86_64'` or `exec: "x86_64-linux-gnu-gcc": executable file not found` | `build-gpu-generator.sh` sets `CGO_ENABLED=1 GOARCH=amd64` — on an ARM host Go needs a C cross-compiler targeting x86_64, which is not installed by default | Install `gcc-x86-64-linux-gnu` (`sudo apt install gcc-x86-64-linux-gnu`) and set `CC=x86_64-linux-gnu-gcc` before the build, or set `CGO_ENABLED=0` if no C code is actually used |

> **Why not use an x86_64 VM instead?**  UTM can emulate x86_64 via QEMU TCG
> (Emulate mode, not Virtualize), but this adds another layer of software
> emulation on top of the one the build script itself runs — making builds
> prohibitively slow (many hours) and potentially unstable.  The recommended
> path for ARM Mac users is to use a native x86_64 Linux machine or CI for
> the build.

---

## Troubleshooting

**`go: command not found` when running `sudo make build`**

The `sudo` environment does not inherit your PATH. Fix:

```bash
sudo ln -s /usr/local/go/bin/go /usr/local/bin/go
sudo go version   # verify
```

**Docker permission denied**

```bash
sudo usermod -aG docker $USER
newgrp docker
```

**Build hangs downloading packages**

Set proxy in `proxy.env` (see Step 8).

**USB device not visible in VM**

The USB must be physically plugged in before clicking the UTM USB icon.
If it still does not appear, try a different USB port on the MacBook.
