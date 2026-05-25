<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Building Live ISO installer using Image Composer Tool(ICT)

This document describes how to build a Live ISO installer for
Intel Panther Lake (PTL) platforms using
[image-composer-tool](https://github.com/open-edge-platform/image-composer-tool)
and the provided template
[`ubuntu24-x86_64-minimal-unattended-iso.yml`](./ubuntu24-x86_64-minimal-unattended-iso.yml).

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Clone the Repository](#clone-the-repository)
3. [Build the Tools](#build-the-tools)
4. [Install Image Composition Prerequisites](#install-image-composition-prerequisites)
5. [Configure the Template](#configure-the-template)
6. [Validate the Template](#validate-the-template)
7. [Build the Image](#build-the-image)
8. [Build Output](#build-output)

---

## Prerequisites

| Requirement | Version / Notes |
|-------------|----------------|
| Build host OS | Ubuntu 24.04 (recommended) |
| Go toolchain | 1.24.0 or later — [installation guide](https://go.dev/doc/manage-install) |
| OpenSSL | Required only if generating Secure Boot keys |

---

## Clone the Repository

```bash
git clone https://github.com/open-edge-platform/image-composer-tool.git
cd image-composer-tool
```

---

## Install Image Composition Prerequisites

These packages are required before composing any image:

```bash
sudo apt install systemd-ukify mmdebstrap
```

Follow instructions at [Image Composition Prerequisites](https://github.com/open-edge-platform/image-composer-tool/blob/main/docs/tutorial/installation.md#image-composition-prerequisites) if you face issues installing packages using apt.

> **Note:** `mmdebstrap` version 0.8.x (shipped with Ubuntu 22.04) has known
> issues. Ensure you have version 1.4.3 or later. On Ubuntu 23.04+, the
> repository version is sufficient.

---

## Build the Tools

Produces `./build/live-installer` in the repo root:

```bash
go build -buildmode=pie -o ./build/live-installer ./cmd/live-installer
```

Produces `./image-composer-tool` in the repo root:

```bash
go build -buildmode=pie -ldflags "-s -w" ./cmd/image-composer-tool
```

---

## Configure the Template

Copy the upstream template to a working location and edit it for your
environment:

```bash
cp <ENIB-HOME>/infrastructure/live-iso/ubuntu24-x86_64-minimal-unattended.yml my-ubuntu24-ptl.yml
```

Here `ENIB-HOME` is the root directory of this project not the image-composer-tool.

Key fields to review and update before building:

### Kernel Options

The template targets Intel Xe GPU; it includes alternative `cmdline` and
`enableExtraModules` options for i915 or legacy GPUs. Uncomment the block
that matches your hardware and optionally augment it like additional 
parameters to cmdline for Xe GPU `intel_iommu=on iommu=pt`.

```yaml
kernel:
  # For Xe GPU (default):
  cmdline: "console=ttyS0,115200 console=tty0 loglevel=7 xe.force_probe=* modprobe.blacklist=i915 udmabuf.list_limit=8192 intel_iommu=on iommu=pt"
  enableExtraModules: "intel_vpu uas"

  # For i915 GPU (uncomment instead):
  # cmdline: "console=ttyS0,115200 console=tty0 loglevel=7 i915.force_probe=*"
  # enableExtraModules: "intel_vpu uas"
```

---

## Validate the Template

Check the template for syntax and schema errors before starting a full
build (fast, no root required):

```bash
./image-composer-tool validate my-ubuntu24-ptl.yml
```

---

## Build the Image

Run the build with elevated privileges so the tool can manage loop devices
and chroot environments. Pass `-E` to preserve your proxy and environment
variables:

```bash
sudo -E ./image-composer-tool build my-ubuntu24-ptl.yml
```

---

## Build Output

Upon completion of the build process expect such an output on the console with build timings:

```bash
2026-05-13T11:33:12.751+0530    INFO    isomaker/isomaker.go:454        ISO creation completed successfully
2026-05-13T11:33:12.752+0530    INFO    manifest/manifest.go:246        Copying SBOM to image build directory: /media/disk_sdb/fedaero/ict/workspace/ubuntu-ubuntu24-x86_64/imagebuild/Default_ISO
2026-05-13T11:33:12.752+0530    WARN    manifest/manifest.go:256        SBOM file not found at tmp/spdx_manifest.json, skipping copy
2026-05-13T11:33:12.752+0530    INFO    isomaker/isomaker.go:118        Pure ISO image build time: 3m32.318s
2026-05-13T11:33:12.752+0530    INFO    isomaker/isomaker.go:121        ISO image build completed successfully: /media/disk_sdb/fedaero/ict/workspace/ubuntu-ubuntu24-x86_64/imagebuild/Default_ISO/minimal-os-image-ubuntu-unattended-24.04.iso
2026-05-13T11:33:12.752+0530    INFO    initrdmaker/initrdmaker.go:261  Cleaning up initrd rootfs: /media/disk_sdb/fedaero/ict/workspace/ubuntu-ubuntu24-x86_64/chrootenv/workspace/imagebuild/Default_Initrd_Unattended
2026-05-13T11:33:13.601+0530    INFO    display/display.go:21   Checking for image artifacts in: /media/disk_sdb/fedaero/ict/workspace/ubuntu-ubuntu24-x86_64/imagebuild/Default_ISO
2026-05-13T11:33:13.602+0530    INFO    display/display.go:30   Found 2 total entries in directory
2026-05-13T11:33:13.602+0530    INFO    display/display.go:36   Checking file: minimal-os-image-ubuntu-unattended-24.04.iso (isDir=false)
2026-05-13T11:33:13.602+0530    INFO    display/display.go:36   Checking file: template-dump.yaml (isDir=false)
2026-05-13T11:33:13.602+0530    INFO    display/display.go:44   Found 2 artifacts after filtering
2026-05-13T11:33:13.602+0530    INFO    display/display.go:52
2026-05-13T11:33:13.602+0530    INFO    display/display.go:53   ╔════════════════════════════════════════════════════════════════════════════╗
2026-05-13T11:33:13.602+0530    INFO    display/display.go:54   ║                    ✓ IMAGE CREATED SUCCESSFULLY                            ║
2026-05-13T11:33:13.602+0530    INFO    display/display.go:55   ╚════════════════════════════════════════════════════════════════════════════╝
2026-05-13T11:33:13.602+0530    INFO    display/display.go:56
2026-05-13T11:33:13.602+0530    INFO    display/display.go:59     Image Type:   ISO
2026-05-13T11:33:13.602+0530    INFO    display/display.go:60
2026-05-13T11:33:13.602+0530    INFO    display/display.go:61     Generated Artifacts (including SBOM):
2026-05-13T11:33:13.602+0530    INFO    display/display.go:79       • minimal-os-image-ubuntu-unattended-24.04.iso (1.68 GB)
2026-05-13T11:33:13.602+0530    INFO    display/display.go:80         /media/disk_sdb/fedaero/ict/workspace/ubuntu-ubuntu24-x86_64/imagebuild/Default_ISO/minimal-os-image-ubuntu-unattended-24.04.iso
2026-05-13T11:33:13.602+0530    INFO    display/display.go:81
2026-05-13T11:33:13.602+0530    INFO    display/display.go:79       • template-dump.yaml (0.00 MB)
2026-05-13T11:33:13.602+0530    INFO    display/display.go:80         /media/disk_sdb/fedaero/ict/workspace/ubuntu-ubuntu24-x86_64/imagebuild/Default_ISO/template-dump.yaml
2026-05-13T11:33:13.602+0530    INFO    display/display.go:81
2026-05-13T11:33:13.602+0530    INFO    display/display.go:84   ════════════════════════════════════════════════════════════════════════════
2026-05-13T11:33:13.602+0530    INFO    display/display.go:85
2026-05-13T11:33:13.673+0530    INFO    image-composer-tool/build.go:147        image build completed successfully
2026-05-13T11:33:13.674+0530    INFO    display/display.go:154    Build Timings:
2026-05-13T11:33:13.674+0530    INFO    display/display.go:155    +----------------------------------+----------------+
2026-05-13T11:33:13.674+0530    INFO    display/display.go:156    | Stage                            | Duration       |
2026-05-13T11:33:13.674+0530    INFO    display/display.go:157    +----------------------------------+----------------+
2026-05-13T11:33:13.674+0530    INFO    display/display.go:159    | Initialization and Configuration | 19.633s        |
2026-05-13T11:33:13.674+0530    INFO    display/display.go:159    | Package Download                 | 19.67s         |
2026-05-13T11:33:13.674+0530    INFO    display/display.go:159    | Chroot Package Download          | 0s             |
2026-05-13T11:33:13.674+0530    INFO    display/display.go:159    | Chroot Env Initialization        | 1m10.426s      |
2026-05-13T11:33:13.674+0530    INFO    display/display.go:159    | Image Build                      | 3m32.318s      |
2026-05-13T11:33:13.674+0530    INFO    display/display.go:159    | Image Conversion                 | 0s             |
2026-05-13T11:33:13.674+0530    INFO    display/display.go:159    | Finalization and Clean Up        | 0s             |
2026-05-13T11:33:13.674+0530    INFO    display/display.go:161    +----------------------------------+----------------+
2026-05-13T11:33:13.674+0530    INFO    display/display.go:162    | Total Time                       | 5m22.048s      |
2026-05-13T11:33:13.675+0530    INFO    display/display.go:163    +----------------------------------+----------------+

```

The output artefacts are written to:

```
./workspace/ubuntu-ubuntu24-x86_64/imagebuild/Default_ISO/minimal-os-image-ubuntu-unattended-24.04.iso
```

Expected artefacts:

| File | Description |
|------|-------------|
| `minimal-os-image-ubuntu-unattended-24.04.iso` | Live image (ready to flash) |
| `DB.cer` | Secure Boot certificate, if keys were configured |

To flash the image to a target device (confirm device path before running):

```bash
sudo dd if=<PATH>/minimal-os-image-ubuntu-unattended-24.04.iso of=/dev/sdX bs=4M status=progress && sync
```

Boot the Edge Node with created USB drive.

## Troubleshoot

1. TBD
