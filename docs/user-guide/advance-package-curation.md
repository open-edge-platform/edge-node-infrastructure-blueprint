<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->
# Advanced Image Customization (Using Image Composer Tool)

The [Image Composer Tool (ICT)](https://github.com/open-edge-platform/image-composer-tool/tree/2026.1-Release)
is a command-line tool for building custom Linux images from pre-built packages.
To get a bootable RAW or ISO image, you define the target OS, packages, kernel, and disk layout.
ICT supports multiple distributions including Ubuntu, Azure Linux, and Red Hat compatible
distros on x86_64.

> Note that this path is intended for advanced users who need fine-grained control over disk
> layout, installed packages, and package repositories. Most users can start with the simpler
> path, [using a pre-built ISO image](./get-started.md#option-1-recommended-build-from-iso).

This article will show you how to:

- [Build and verify the default template](#build-and-verify-the-default-template)
- [Package the image into artifacts](#package-the-image-into-artifacts)
- [Package curation and template customization](#package-curation-and-template-customization)
- [Troubleshoot the process](#troubleshoot)

## Build and verify the default template

Refer to the detailed [ICT QuickStart](https://github.com/open-edge-platform/image-composer-tool/tree/2026.1-Release#quick-start)
to build the `image-composer-tool` binary.

### Configure the template

Copy the upstream template to the Image Composer Tool home directory where you must have the `image-composer-tool` binary.

```bash
cd image-composer-tool/
cp <ENIB-HOME>/infrastructure/host-os/ict/generic-handheld-os-template.yml my-ubuntu24.yml
```

Here, `ENIB-HOME` is the root directory of this project, not the Image Composer Tool.

Now, you can adapt this template to suit your use case. The advanced customization options are discussed below in the [Package curation and template customization](#package-curation-and-template-customization) section.

For a quick trial, you only need to update the user credentials for the target system before building. Replace the default `user` user `password` hash with your own SHA-512 hashed password:

```yaml
users:
  - name: user
    password: "<SHA-512-hashed-password>"
```

Generate the password hash using one of the following methods:

```bash
# Using openssl (requires `openssl` to be installed)
openssl passwd -6 'your-password-here'

# Using mkpasswd (requires `whois` to be installed)
mkpasswd --method=sha-512 'your-password-here'
```

> **Note:** The output changes on every invocation because the salt is randomly generated. All outputs verify against the same password.

### Validate the template

Check the template for syntax and schema errors before starting a full
build (fast, no root required):

```bash
./image-composer-tool validate my-ubuntu24.yml
```

### Build the image

Run the build with elevated privileges so that the tool can manage loop devices
and chroot environments. Pass `-E` to preserve your proxy and environment
variables:

```bash
sudo -E ./image-composer-tool build my-ubuntu24.yml
```

### Build output

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

```text
./workspace/ubuntu-ubuntu24-x86_64/imagebuild/<config-name>/
```

Expected artefacts:

| File | Description |
|------|-------------|
| `minimal-desktop-ubuntu-24.04.raw.gz` | Compressed raw disk image (ready to flash) |

## Package the image into artifacts

Use the `image-from-tool` mode when you already have an image generated by Image Composer Tool.
This mode packages the provided Image Composer Tool image into
the USB artifacts:

```bash
make build MODE=image-from-tool ICT_IMG=/absolute/path/to/minimal-desktop-ubuntu-24.04.raw.gz
```

The following are the supported Image Composer Tool image extensions:

- `.raw.gz`
- `.raw.img.gz`

Example:

```bash
make build MODE=image-from-tool ICT_IMG=/home/user/images/minimal-desktop-ubuntu-24.04.raw.gz
```

Build output:

- `usb-installation-files.tar.gz` in `infrastructure/build-artifacts/out`

Once `usb-installation-files.tar.gz` is ready, continue with
[Phase 2: Prepare Bootable USB](./get-started.md#phase-2-prepare-bootable-usb) in the Get Started guide
for the remaining steps: configuring the USB device, writing the artifacts, and booting the target system.

## Package curation and template customization

This section explains how to curate package lists with the `update-install-packages` skill and produce a new Image Composer Tool (ICT) image variant on top of the default template.

Use this flow when you want to build a custom image flavor (for example, debug, media-heavy, or minimal runtime) without editing the baseline files manually each time.

### What you are modifying

The package curation flow can update one or both of the following files:

- `infrastructure/host-os/auto-install-pkgs.yaml`
- `infrastructure/host-os/ict/generic-handheld-os-template.yml`

The ICT-based template is the preferred advanced image build method. For consistency, if not explicitly specified, the method updates package intent for both ISO-based (`auto-install-pkgs.yaml`) and ICT-based (`generic-handheld-os-template.yml`) images.

### End-to-end flow

1. Start from the repository root and define your package delta (add or delete).
2. Run the `update-install-packages` skill to apply package curation safely.
3. Validate YAML and backups created by the skill.
4. Copy the default ICT template into a working template for your variant.
5. Validate and build the image using ICT.
6. Record artifact path and package delta for reproducibility.

### Run the skill

If you are using Copilot Chat in agent mode, invoke the skill with a natural language prompt describing your intent. For example:

```text
Add htop, jq, and iperf3 to the ict-template in /home/user/edge-node-infrastructure-blueprint
```

```text
Delete mosquitto and mosquitto-clients from both auto-install-pkgs and the ict-template.
```

```text
Add sysbench and stress-ng to auto-install-pkgs only for a debug image variant.
```

The skill is expected to:

- validate package name format
- verify package availability in Ubuntu 24.04 repositories
- optionally search repositories for packages matching hardware details (device name, model, or vendor) and confirm matches before adding
- create backups before file changes
- return per-file package change results (`added`, `deleted`, `already-present`, `not-found`)
- validate YAML syntax after updates

### Build an ICT variant from the curated baseline

After package curation succeeds, create a variant template from the default template:

```bash
cp infrastructure/host-os/ict/generic-handheld-os-template.yml \
   infrastructure/host-os/ict/my-variant-template.yml
```

For detailed validation and build instructions, refer to [Building an Ubuntu OS Version 24.04 Image with Image Composer Tool](https://github.com/open-edge-platform/edge-node-infrastructure-blueprint/blob/v2026.1.0/infrastructure/host-os/ict/README.md). That guide covers:

- template validation
- image build process
- troubleshooting and build output artifacts

Expected output artifact type:

- compressed raw image (`.raw.gz`)

### Safety and rollback

Follow these rules for reliable curation:

- do not edit the only source copy without backup
- stop on any precondition or YAML validation failure
- restore from backup if update or validation fails
- do not request or store secrets in prompts or scripts

If rollback is needed, restore backup files produced by the skill for each modified target file and re-run validation.

## Troubleshoot

### Package not found or conflicting versions

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

### Mirror issues

Standard Ubuntu mirrors may occasionally be unreliable or return stale metadata. If you encounter intermittent download failures or hash-sum mismatches during the build, update the `packageRepositories` section in your template to use other open-source mirrors. For example, using the Kernel.org mirror:

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

Replace `us` with your country code (for example, `de`, `in`, `sg`) and use the returned URL in `packageRepositories`.

After updating the mirror, clean and rebuild:

```bash
sudo ./image-composer-tool cache clean
sudo rm -rf tmp/
```
