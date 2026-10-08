# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:

INTEL_ECI_URL := https://eci.intel.com/repos/noble
INTEL_ECI_KEY_URL := https://eci.intel.com/repos/gpg-keys/GPG-PUB-KEY-INTEL-ECI.gpg
INTEL_ECI_KEY_FINGERPRINT := B1CDAB5E8EE9205CBD8A7500EF16D1B6C97E2FC9
LIBREALSENSE_KEY_ID := FB0B24895113F120
LIBREALSENSE_KEY_ID_LC := fb0b24895113f120

.PHONY: realsense cdi-sriov

realsense:
	if [[ $$EUID -ne 0 ]]; then
		echo "ERROR: the realsense target must be run as root (e.g. sudo make realsense)." >&2
		exit 1
	fi
	mkdir -p /etc/apt/keyrings

	curl -sSf "$(INTEL_ECI_KEY_URL)" -o /tmp/intel-eci.gpg
	ACTUAL_ECI_FPR=$$(gpg --show-keys --with-colons /tmp/intel-eci.gpg | awk -F: '/^fpr:/ {print $$10; exit}')
	if [[ "$${ACTUAL_ECI_FPR}" != "$(INTEL_ECI_KEY_FINGERPRINT)" ]]; then
		echo "ERROR: Intel ECI GPG key fingerprint mismatch: expected $(INTEL_ECI_KEY_FINGERPRINT), got $${ACTUAL_ECI_FPR}" >&2
		rm -f /tmp/intel-eci.gpg
		exit 1
	fi
	gpg --dearmor -o /tmp/intel-eci-keyring.gpg /tmp/intel-eci.gpg
	install -m 644 /tmp/intel-eci-keyring.gpg /etc/apt/keyrings/intel-eci.gpg
	rm -f /tmp/intel-eci.gpg /tmp/intel-eci-keyring.gpg
	echo "deb [signed-by=/etc/apt/keyrings/intel-eci.gpg] $(INTEL_ECI_URL) isar main" \
		| tee /etc/apt/sources.list.d/intel-eci.list > /dev/null

	curl -sSf "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$(LIBREALSENSE_KEY_ID)" -o /tmp/librealsense.gpg
	ACTUAL_RS_FPR=$$(gpg --show-keys --with-colons /tmp/librealsense.gpg | awk -F: '/^fpr:/ {print $$10; exit}')
	if [[ "$${ACTUAL_RS_FPR,,}" != *"$(LIBREALSENSE_KEY_ID_LC)" ]]; then
		echo "ERROR: librealsense GPG key ID mismatch: expected $(LIBREALSENSE_KEY_ID), got fingerprint $${ACTUAL_RS_FPR}" >&2
		rm -f /tmp/librealsense.gpg
		exit 1
	fi
	gpg --dearmor -o /tmp/librealsense-keyring.gpg /tmp/librealsense.gpg
	install -m 644 /tmp/librealsense-keyring.gpg /etc/apt/keyrings/librealsense.gpg
	rm -f /tmp/librealsense.gpg /tmp/librealsense-keyring.gpg
	echo "deb [signed-by=/etc/apt/keyrings/librealsense.gpg] https://librealsense.intel.com/Debian/apt-repo $$(lsb_release -cs) main" \
		| tee /etc/apt/sources.list.d/librealsense.list > /dev/null

	apt-get update
	apt-get install -y \
		librealsense2 librealsense2-dkms librealsense2-utils librealsense2-dev librealsense2-gl
	echo "Intel RealSense packages installed from the Intel ECI and librealsense repositories."

cdi-sriov:
	if [[ $$EUID -ne 0 ]]; then
		echo "ERROR: the cdi-sriov target must be run as root (e.g. sudo make cdi-sriov)." >&2
		exit 1
	fi
	apt update && apt install -y golang
	mkdir -p /opt/edge/scripts/cdi
	install -m 755 container_setup_sriov.sh /opt/edge/scripts/container_setup_sriov.sh
	install -m 644 systemd/intel-sriov-vf.service /etc/systemd/system/intel-sriov-vf.service
	systemctl daemon-reload
	systemctl enable intel-sriov-vf.service
	bash /opt/edge/scripts/container_setup_sriov.sh
	if [[ ! -x cdi/intel-cdi-specs-generator-gpu ]]; then
		echo "Building Intel CDI GPU spec generator..."
		cdi/build-gpu-generator.sh	
	fi
	install -m 755 cdi/intel-cdi-specs-generator-gpu /opt/edge/scripts/cdi/intel-cdi-specs-generator-gpu
	install -m 755 cdi/intel-cdi-npu-generator.sh /opt/edge/scripts/cdi/intel-cdi-npu-generator.sh
	cdi/systemd/install-systemd.sh
	echo "CDI and SR-IOV services installed."
