<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Building an Ubuntu 24.04 Image with OS Image Composer

This document describes how to build a bootable Ubuntu 24.04 raw image for
Intel Panther Lake (PTL) platforms using
[image-composer-tool](https://github.com/open-edge-platform/image-composer-tool)
and the provided template
[`ubuntu24-x86_64-minimal-ptl.yml`](./ubuntu24-x86_64-minimal-ptl.yml).

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Clone the Repository](#clone-the-repository)
3. [Install the Tool](#install-the-tool)
4. [Install Image Composition Prerequisites](#install-image-composition-prerequisites)
5. [Configure the Template](#configure-the-template)
6. [(Optional) Generate Secure Boot Keys](#optional-generate-secure-boot-keys)
7. [Validate the Template](#validate-the-template)
8. [Build the Image](#build-the-image)
9. [Build Output](#build-output)

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

Follow instructions at [Image Composition Prerequisites](https://github.com/open-edge-platform/image-composer-tool/blob/main/docs/tutorial/installation.md#image-composition-prerequisites) if you face issues installing packages using apt.

> **Note:** `mmdebstrap` version 0.8.x (shipped with Ubuntu 22.04) has known
> issues. Ensure you have version 1.4.3 or later. On Ubuntu 23.04+, the
> repository version is sufficient.

---

## Configure the Template

Copy the upstream template to a working location and edit it for your
environment:

```bash
cp <ENIB-HOME>/infrastructure/host-os/ict/ubuntu24-x86_64-minimal-ptl.yml my-ubuntu24-ptl.yml
```

Here `ENIB-HOME` is the root directory of this project not the image-composer-tool.

Key fields to review and update before building:

### User Credentials

Replace the default `user` user `password` hash with your own
SHA-512 hashed password, and update the SSH `authorized_keys` entries:

```yaml
users:
  - name: user
    password: "<SHA-512-hashed-password>"
```

---

## (Optional) Generate Secure Boot Keys

If you want Secure Boot enforcement in the image, generate the required
keys **before** building. Skip this section if Secure Boot is not required.

```bash
# Create a directory for Secure Boot keys
mkdir -p /data/secureboot/keys
cd /data/secureboot/keys

# Generate RSA 3072-bit private key and self-signed certificate (SHA-384)
openssl req -new -x509 -newkey rsa:3072 -sha384 \
  -keyout DB.key -out DB.crt \
  -days 3650 -nodes \
  -subj "/CN=ICT Secure Boot Key/"

# Convert certificate to DER format (required by UEFI)
openssl x509 -outform DER -in DB.crt -out DB.cer
```

> **Key strength note:** `RSA3072SHA384` is recommended. Validate your
> firmware supports it before using `RSA2048SHA256`.

Generated files:

| File | Purpose |
|------|---------|
| `DB.key` | Private signing key — keep secure, never commit |
| `DB.crt` | Certificate in PEM format |
| `DB.cer` | Certificate in DER format (for UEFI enrollment) |

Then add the following section to your template (use absolute paths):

```yaml
immutability:
  enabled: true
  secureBootDBKey: "/data/secureboot/keys/DB.key"
  secureBootDBCrt: "/data/secureboot/keys/DB.crt"
  secureBootDBCer: "/data/secureboot/keys/DB.cer"
```

> **Note:** The template ships with `immutability.enabled: false`. Set it
> to `true` only when adding Secure Boot keys as shown above.

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
2026-04-09T15:10:22.705+0530    INFO    display/display.go:21   Checking for image artifacts in: /home/intel/rranjan3/ict/workspace/ubuntu-ubuntu24-x86_64/imagebuild/minimal
2026-04-09T15:10:22.705+0530    INFO    display/display.go:30   Found 2 total entries in directory
2026-04-09T15:10:22.705+0530    INFO    display/display.go:36   Checking file: minimal-desktop-ubuntu-ptl-24.04.raw.gz (isDir=false)
2026-04-09T15:10:22.705+0530    INFO    display/display.go:36   Checking file: spdx_manifest_deb_minimal-desktop-ubuntu-ptl_20260409_150520.json (isDir=false)
2026-04-09T15:10:22.706+0530    INFO    display/display.go:44   Found 2 artifacts after filtering
2026-04-09T15:10:22.706+0530    INFO    display/display.go:52
2026-04-09T15:10:22.706+0530    INFO    display/display.go:53   ╔════════════════════════════════════════════════════════════════════════════╗
2026-04-09T15:10:22.706+0530    INFO    display/display.go:54   ║                    ✓ IMAGE CREATED SUCCESSFULLY                            ║
2026-04-09T15:10:22.706+0530    INFO    display/display.go:55   ╚════════════════════════════════════════════════════════════════════════════╝
2026-04-09T15:10:22.706+0530    INFO    display/display.go:56
2026-04-09T15:10:22.706+0530    INFO    display/display.go:59     Image Type:   RAW
2026-04-09T15:10:22.706+0530    INFO    display/display.go:60
2026-04-09T15:10:22.706+0530    INFO    display/display.go:61     Generated Artifacts (including SBOM):
2026-04-09T15:10:22.706+0530    INFO    display/display.go:79       • minimal-desktop-ubuntu-ptl-24.04.raw.gz (2.62 GB)
2026-04-09T15:10:22.706+0530    INFO    display/display.go:80         /home/intel/rranjan3/ict/workspace/ubuntu-ubuntu24-x86_64/imagebuild/minimal/minimal-desktop-ubuntu-ptl-24.04.raw.gz
2026-04-09T15:10:22.706+0530    INFO    display/display.go:81
2026-04-09T15:10:22.706+0530    INFO    display/display.go:79       • spdx_manifest_deb_minimal-desktop-ubuntu-ptl_20260409_150520.json (1.37 MB)
2026-04-09T15:10:22.706+0530    INFO    display/display.go:80         /home/intel/rranjan3/ict/workspace/ubuntu-ubuntu24-x86_64/imagebuild/minimal/spdx_manifest_deb_minimal-desktop-ubuntu-ptl_20260409_150520.json
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

| File | Description |
|------|-------------|
| `minimal-desktop-ubuntu-ptl.raw.gz` | Compressed raw disk image (ready to flash) |
| `DB.cer` | Secure Boot certificate, if keys were configured |

To flash the image to a target device (confirm device path before running):

```bash
gunzip -c minimal-desktop-ubuntu-ptl.raw.gz | sudo dd of=/dev/sdX bs=4M status=progress && sync
```

## Troubleshoot

1. Following error is seen when image build is triggered:

  ```text
  Error: pre-processing failed: failed to generate apt sources from repositories: failed to download and add GPG keys: failed to download GPG key from https://af01p-png.devtools.intel.com/artifactory/hspe-edge-png-local/ubuntu/keys/adl-hirsute-public.gpg: failed to fetch GPG key from https://af01p-png.devtools.intel.com/artifactory/hspe-edge-png-local/ubuntu/keys/adl-hirsute-public.gpg: Get "https://af01p-png.devtools.intel.com/artifactory/hspe-edge-png-local/ubuntu/keys/adl-hirsute-public.gpg": tls: failed to verify certificate: x509: certificate signed by unknown authority
  ```

  Solution: Ideally these repositories are not expected to be used. However, if this is a development environment, add `.devtools.intel.com` to `no_proxy` and rerun.
