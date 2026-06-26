<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Build from Source

This guide covers Phase 1 of the provisioning workflow: building bootable USB artifacts on the developer system.

Before starting, confirm your system meets all [System Requirements](./system-requirements.md).

For Windows Subsystem for Linux (WSL), follow the steps in the [Windows WSL Guide](../how-to/windows-wsl-guide.md).

## 1. Clone the Repository

```bash
git clone https://github.com/open-edge-platform/edge-node-infrastructure-blueprint.git
cd edge-node-infrastructure-blueprint
```

## 2. Build Bootable USB Artifacts

From the repository root, run one of the following build modes.

> **Note**: If your development environment is behind a firewall, add proxy configuration to the
> `proxy.env` file in the `edge-node-infrastructure-blueprint` directory. To skip the proxy settings,
> pass `skip-proxy=true` to the make command.

### Option 1 (Recommended): Build from ISO

Build the Ubuntu image, including the required tools and packages, from an Ubuntu ISO image
file. For additional image customization, see the
[Ubuntu Desktop Raw Image Generation guide](https://github.com/open-edge-platform/edge-node-infrastructure-blueprint/blob/main/infrastructure/host-os/readme.md).

```bash
make build MODE=image-from-iso ISO_URL=https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-desktop-amd64.iso
```

### Option 2 (Advanced): Build with Image Composer Tool Image

This path is intended for advanced users who need fine-grained control over disk
layout, installed packages, and package repositories. Most users can start with
Option 1.

To generate an image using Image Composer Tool, refer to:

- [Building an Ubuntu OS Version 24.04 Image](https://github.com/open-edge-platform/edge-node-infrastructure-blueprint/blob/main/infrastructure/host-os/ict/README.md).

### Developer Incremental Build

Use the `reuse-image` mode to use a prebuilt image, skipping base image regeneration and reducing build time.
For reusable ICT images, use `MODE=image-from-tool` with `ICT_IMG` instead of `MODE=reuse-image`.

```bash
make build MODE=reuse-image
```

You can also manually copy an existing image to USB partition 5 when required by your process.

## Build Output

With any of the above build options, expect the following output:

- `usb-installation-files.tar.gz` in `infrastructure/build-artifacts/out`

Once the build completes, continue to [Prepare USB and Validate](./prepare-usb.md).
