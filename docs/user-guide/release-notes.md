# Release Notes: Edge Node Infrastructure Blueprint

## Version 2026.2.0

**Release Date**: September 9, 2026

**New**:

- Added server-image enablement through ICT and script-based build flows.
- Added IPU6/IPU7 camera HAL packages.
- Added power and thermal management capabilities, including combined profiles and analysis tools.
- Optimized the build process, package selection, and base-image footprint.
- Updated Alpine OS to version 3.21.
- Added branch-aligned source archive support for target-system tooling.
- Updated PCM tooling to the latest supported version.
- Additional skills for power and thermal tuning.

**Bug Fixes**:

- Resolved image-build failures related to kernel configuration and unintended kernel upgrades during installation.
- Corrected ICT image-build behavior with pinned base kernels.
- Resolved a race condition between GDM and virtual-function creation.
- Hardened the build for permissions, proxy configuration, and credential-handling.

**Known issues and limitations**:

- First-run image build can take approximately 30 minutes.
- CPU package and GPU power metrics may intermittently report 0 W or unrealistically high values. This occurs when the underlying RAPL energy counter wraps during sampling, resulting in an incorrect power calculation.
