<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Build from Source

This guide covers Phase 1 of the provisioning workflow: building bootable USB artifacts on the developer system.

Before starting, confirm your system meets all [System Requirements](./system-requirements.md).

For Windows Subsystem for Linux (WSL), follow the steps in the [Windows WSL Guide](../how-to/set-up-windows-wsl.md).

## Phase 1: Build Artifacts on the Developer System

### 1. Clone the Repository

```bash
git clone https://github.com/open-edge-platform/edge-node-infrastructure-blueprint.git -b main
cd edge-node-infrastructure-blueprint
```

### 2. Build Bootable USB Artifacts

From the repository root, run one of the following build modes.

> **Note:** If your development environment is behind a firewall, add proxy configuration to the
> `proxy.env` file in the `edge-node-infrastructure-blueprint` directory. To skip the proxy settings,
> pass `skip-proxy=true` to the make command.

#### Option 1: Build from a Standard Ubuntu 24.04 image

Build the Ubuntu image, including the required tools and packages, from the standard Ubuntu image flow:

Before building, export the `USERNAME` and `PASSWORD` environment variables with your own credentials. These are required and must not be null or empty; the build exits before starting if either variable is unset or empty:

```bash
export USERNAME='<your-username>'
# Generate the SHA-512 password hash with one of the following methods.
# Using openssl (requires `openssl` to be installed)
export PASSWORD="$(openssl passwd -6 '<your-password>')"

# Or using mkpasswd (requires `whois` to be installed)
export PASSWORD="$(mkpasswd --method=sha-512 '<your-password>')"
```

> **Note:** The output changes on every invocation because the salt is randomly generated. All outputs verify against the same password.

```bash
make build
```

Or explicitly specify the standard mode:

```bash
make build MODE=standard-image
```

#### Option 2 (Advanced): Build with Image Composer Tool Image

This path is intended for advanced users who need fine-grained control over disk
layout, installed packages, and package repositories. Most users can start with
Option 1.

To generate an image using Image Composer Tool, refer to:

- [Advanced Image Customization (Using Image Composer Tool)](../how-to/advanced-image-customization.md).

### Build Output

With any of the above build options, expect the following output:

- `usb-installation-files.tar.gz` in `infrastructure/build-artifacts/out`

Once the build completes, continue to [Prepare USB and Validate](./prepare-usb.md).
