<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Building an Ubuntu OS Version 24.04 Image with Image Composer Tool

This section shows how to build a bootable Ubuntu OS version 24.04 raw image for
 Intel® Core™ Ultra processor platforms using
[Image Composer Tool](https://github.com/open-edge-platform/image-composer-tool/tree/2026.1-Release)
and the provided templates:

- **Desktop:** [`generic-handheld-os-template.yml`](./generic-handheld-os-template.yml)
- **Server (headless):** [`generic-companion-os-server-template.yml`](./generic-companion-os-server-template.yml)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Clone the Repository](#clone-the-repository)
3. [Install the Tool](#install-the-tool)
4. [Install Image Composition Prerequisites](#install-image-composition-prerequisites)
5. [Configure the Template](#configure-the-template)
6. [Validate the Template](#validate-the-template)
7. [Build the Image](#build-the-image)
8. [Build Output](#build-output)

---

## Prerequisites

| Requirement | Version and/or Notes |
|-------------|----------------|
| Build host OS | Ubuntu OS version 24.04 (recommended) |
| Go toolchain | Version 1.24.0 or later — [installation guide](https://go.dev/doc/manage-install) |

---

## Clone the Repository

```bash
git clone https://github.com/open-edge-platform/image-composer-tool.git -b 2026.1-Release
cd image-composer-tool
```

---

## Install the Tool

Produces `./image-composer-tool` in the repo root:

```bash
go build -buildmode=pie -ldflags "-s -w" ./cmd/image-composer-tool
```

---

## Install Image Composition Prerequisites

These packages are required before composing any image:

```bash
sudo apt install systemd-ukify mmdebstrap
```

Follow the instructions at [Image Composition Prerequisites](https://github.com/open-edge-platform/image-composer-tool/blob/2026.1-Release/docs/tutorial/installation.md#image-composition-prerequisites)
if you face issues installing packages using apt.

> **Note:** `mmdebstrap` version 0.8.x (shipped with Ubuntu OS version 22.04) has known
> issues. Ensure you have version 1.4.3 or later. On Ubuntu OS version 23.04 or later, the
> repository version is sufficient.

---

## Configure the Template

Create a copy of the template file before you edit anything.

```bash
# Desktop image
cp <ENIB-HOME>/infrastructure/host-os/ict/generic-handheld-os-template.yml my-ubuntu24.yml

# Server (headless) image
cp <ENIB-HOME>/infrastructure/host-os/ict/generic-companion-os-server-template.yml my-ubuntu24-server.yml
```

Here, `ENIB-HOME` is the root directory of this project, not the Image Composer Tool.

Key fields to review and update before building:

### User Credentials

> **Important:** You **must** update the `<username>` and `<password>` placeholders
> in the template before building the image. The build will fail or produce an
> unusable image if these placeholders are left unchanged.

Replace `<username>` with your desired login name and `<password>` with a
SHA-512 hashed password:

```yaml
users:
  - name: <username>
    password: <password>
```

The password must contain a SHA-512 hash generated using the following tools:

```bash
# Using openssl (requires `openssl` to be installed)
openssl passwd -6 'your-password-here'

# Using mkpasswd (requires `whois` to be installed)
mkpasswd --method=sha-512 'your-password-here'
```
Now, you can adapt this template to suit your use case. The advanced customization options are discussed
below in the [Package curation and template customization](#package-curation-and-template-customization) section.

## Validate the Template

Check the template for syntax and schema errors before starting a full
build (fast, no root required):

```bash
./image-composer-tool validate my-ubuntu24.yml
```

---

## Build the Image

Run the build with elevated privileges so that the tool can manage loop devices
and chroot environments. Pass `-E` to preserve your proxy and environment
variables:

```bash
sudo -E ./image-composer-tool build my-ubuntu24.yml
```

---

## Build Output

When the build completes, expect the following output on the console with build timings:

```bash
2026-04-09T15:10:22.705+0530    INFO    display/display.go:21   Checking for image artifacts in: /home/user/ict/workspace/ubuntu-ubuntu24-x86_64/imagebuild/minimal
2026-04-09T15:10:22.705+0530    INFO    display/display.go:30   Found 2 total entries in directory
2026-04-09T15:10:22.705+0530    INFO    display/display.go:36   Checking file: minimal-desktop-ubuntu-24.04.raw.gz (isDir=false)
2026-04-09T15:10:22.705+0530    INFO    display/display.go:36   Checking file: spdx_manifest_deb_minimal-desktop-ubuntu_20260409_150520.json (isDir=false)
2026-04-09T15:10:22.706+0530    INFO    display/display.go:44   Found 2 artifacts after filtering
2026-04-09T15:10:22.706+0530    INFO    display/display.go:52
2026-04-09T15:10:22.706+0530    INFO    display/display.go:53   ╔════════════════════════════════════════════════════════════════════════════╗
2026-04-09T15:10:22.706+0530    INFO    display/display.go:54   ║                    ✓ IMAGE CREATED SUCCESSFULLY                            ║
2026-04-09T15:10:22.706+0530    INFO    display/display.go:55   ╚════════════════════════════════════════════════════════════════════════════╝
2026-04-09T15:10:22.706+0530    INFO    display/display.go:56
2026-04-09T15:10:22.706+0530    INFO    display/display.go:59     Image Type:   RAW
2026-04-09T15:10:22.706+0530    INFO    display/display.go:60
2026-04-09T15:10:22.706+0530    INFO    display/display.go:61     Generated Artifacts (including SBOM):
2026-04-09T15:10:22.706+0530    INFO    display/display.go:79       • minimal-desktop-ubuntu-24.04.raw.gz (2.62 GB)
2026-04-09T15:10:22.706+0530    INFO    display/display.go:80         /home/user/ict/workspace/ubuntu-ubuntu24-x86_64/imagebuild/minimal/minimal-desktop-ubuntu-24.04.raw.gz
2026-04-09T15:10:22.706+0530    INFO    display/display.go:81
2026-04-09T15:10:22.706+0530    INFO    display/display.go:79       • spdx_manifest_deb_minimal-desktop-ubuntu_20260409_150520.json (1.37 MB)
2026-04-09T15:10:22.706+0530    INFO    display/display.go:80         /home/user/ict/workspace/ubuntu-ubuntu24-x86_64/imagebuild/minimal/spdx_manifest_deb_minimal-desktop-ubuntu_20260409_150520.json
2026-04-09T15:10:22.706+0530    INFO    display/display.go:81
2026-04-09T15:10:22.706+0530    INFO    display/display.go:84   ════════════════════════════════════════════════════════════════════════════
2026-04-09T15:10:22.706+0530    INFO    display/display.go:85
2026-04-09T15:10:22.877+0530    INFO    image-composer-tool/build.go:137  image build completed successfully
2026-04-09T15:10:22.877+0530    INFO    display/display.go:154    Build Timings:
2026-04-09T15:10:22.877+0530    INFO    display/display.go:155    +----------------------------------+----------------+
2026-04-09T15:10:22.877+0530    INFO    display/display.go:156    | Stage                            | Duration       |
2026-04-09T15:10:22.877+0530    INFO    display/display.go:157    +----------------------------------+----------------+
2026-04-09T15:10:22.877+0530    INFO    display/display.go:159    | Initialization and Configuration | 16.499s        |
2026-04-09T15:10:22.877+0530    INFO    display/display.go:159    | Package Download                 | 3m20.339s      |
2026-04-09T15:10:22.877+0530    INFO    display/display.go:159    | Chroot Env Initialization        | 52.647s        |
2026-04-09T15:10:22.877+0530    INFO    display/display.go:159    | Image Build                      | 8m54.777s      |
2026-04-09T15:10:22.877+0530    INFO    display/display.go:159    | Image Conversion                 | 4m58.711s      |
2026-04-09T15:10:22.877+0530    INFO    display/display.go:159    | Finalization and Clean Up        | 1.264s         |
2026-04-09T15:10:22.877+0530    INFO    display/display.go:161    +----------------------------------+----------------+
2026-04-09T15:10:22.877+0530    INFO    display/display.go:162    | Total Time                       | 18m24.237s     |
2026-04-09T15:10:22.877+0530    INFO    display/display.go:163    +----------------------------------+----------------+

```

The output artefacts are written to:

```
./workspace/ubuntu-ubuntu24-x86_64/imagebuild/<config-name>/
```

Expected artefacts:

Expected artifact (one of the following, based on the template you choose):

| File                                  | Description                                |
| ------------------------------------- | ------------------------------------------ |
| `minimal-desktop-ubuntu-24.04.raw.gz` | Compressed raw disk image (ready to flash) |
| `minimal-ubuntu-server-24.04.raw.gz` | Compressed raw disk image (ready to flash) |

## Troubleshoot

### Package Not Found or Conflicting Versions

If the build fails with errors like `failed: bad status: 404 Not Found` or conflicting versions, the package may not exist in the configured repositories or may have been renamed in Ubuntu 24.04.

1. Confirm the package name is correct:

   ```bash
   apt-cache search <name>
   apt-cache show <name>
   ```

2. Clean the ICT cache and temporary files, then rebuild:

   ```bash
   sudo ./image-composer-tool cache clean
   sudo rm -rf tmp/
   ```

### Mirror Issues

Standard Ubuntu mirrors may occasionally be unreliable or return stale metadata.
If you encounter intermittent download failures or hash-sum mismatches during the
build, update the `packageRepositories` section in your template to use other
open-source mirrors. For example, using the Kernel.org mirror:

```yaml
packageRepositories:
   - codename: "noble"
      url: "http://mirrors.edge.kernel.org/ubuntu/"
      component: "main restricted universe multiverse"
      priority: 500
```

To find the fastest mirror for your region, you can optionally use `mirrorselect`:

```bash
sudo snap install mirrorselect
mirrorselect --country us
```

Replace `us` with your country code (for example, `de`, `in`, `sg`) and use the
returned URL in `packageRepositories`.

After updating the mirror, clean and rebuild:

```bash
sudo ./image-composer-tool cache clean
sudo rm -rf tmp/
```
