<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->
# Advanced Image Customization (Using Image composer tool)


## Package Curation and ICT Variants

This guide explains how to curate package lists with the `update-install-packages` skill and produce a new Image Composer Tool (ICT) image variant on top of the default template.

Use this flow when you want to build a custom image flavor (for example, debug, media-heavy, or minimal runtime) without editing the baseline files manually each time.

### What You Are Modifying

The package curation flow can update one or both of the following files:

- `infrastructure/host-os/auto-install-pkgs.yaml`
- `infrastructure/host-os/ict/generic-handheld-os-template.yml`

The ICT-based template is the preferred advanced image build. For consistency, if not explicitly specified, the method updates package intent for both ISO-based (`auto-install-pkgs.yaml`) and ICT-based (`generic-handheld-os-template.yml`) images.

### End-to-End Flow

1. Start from the repository root and define your package delta (add or delete).
2. Run the `update-install-packages` skill to apply package curation safely.
3. Validate YAML and backups created by the skill.
4. Copy the default ICT template into a working template for your variant.
5. Validate and build the image using ICT.
6. Record artifact path and package delta for reproducibility.

### Run the Skill

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
- verify package availability for Ubuntu 24.04
- create backups before file changes
- return per-file change results (`added`, `deleted`, `already-present`, `not-found`)
- validate YAML after updates

### Build an ICT Variant from the Curated Baseline

After package curation succeeds, create a variant template from the default template:

```bash
cp infrastructure/host-os/ict/generic-handheld-os-template.yml \
   infrastructure/host-os/ict/my-variant-template.yml
```

For detailed validation and build instructions, refer to [Building an Ubuntu OS Version 24.04 Image with Image Composer Tool](https://github.com/open-edge-platform/edge-node-infrastructure-blueprint/blob/main/infrastructure/host-os/ict/README.md). That guide covers:

- template validation
- image build process
- troubleshooting and build output artifacts

Expected output artifact type:

- compressed raw image (`.raw.gz`)

### Safety and Rollback

Follow these rules for reliable curation:

- do not edit the only source copy without backup
- stop on any precondition or YAML validation failure
- restore from backup if update or validation fails
- do not request or store secrets in prompts or scripts

If rollback is needed, restore backup files produced by the skill for each modified target file and re-run validation.
