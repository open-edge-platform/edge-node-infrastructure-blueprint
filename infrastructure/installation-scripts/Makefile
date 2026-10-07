SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:

.PHONY: realsense cdi-sriov

# Installs the Intel RealSense SDK from librealsense.intel.com (librealsense2,
# librealsense2-dkms, librealsense2-utils, librealsense2-dev, librealsense2-gl).
realsense:
	sudo mkdir -p /etc/apt/keyrings
	# gpg --verify is expected to fail here (no pubkey yet); disable pipefail
	# so that expected failure doesn't short-circuit the NO_PUBKEY parse below.
	set +o pipefail
	KEY_ID=$$(curl -sSf "https://librealsense.intel.com/Debian/apt-repo/dists/$$(lsb_release -cs)/InRelease" \
		| gpg --status-fd 1 --verify 2>/dev/null | grep "NO_PUBKEY" | awk '{print $$3}')
	set -o pipefail
	if [ -z "$${KEY_ID}" ]; then
		echo "ERROR: Unable to determine the Intel RealSense GPG key ID." >&2
		exit 1
	fi
	curl -sSf "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$${KEY_ID}" -o /tmp/librealsense.gpg
	ACTUAL_FPR=$$(gpg --show-keys --with-colons /tmp/librealsense.gpg | awk -F: '/^fpr:/ {print $$10; exit}')
	if [[ "$${ACTUAL_FPR,,}" != *"$${KEY_ID,,}" ]]; then
		echo "ERROR: GPG key ID mismatch: expected $${KEY_ID}, got fingerprint $${ACTUAL_FPR}" >&2
		rm -f /tmp/librealsense.gpg
		exit 1
	fi
	gpg --dearmor -o /tmp/librealsense-keyring.gpg /tmp/librealsense.gpg
	sudo install -m 644 /tmp/librealsense-keyring.gpg /etc/apt/keyrings/librealsense.gpg
	rm -f /tmp/librealsense.gpg /tmp/librealsense-keyring.gpg
	echo "deb [signed-by=/etc/apt/keyrings/librealsense.gpg] https://librealsense.intel.com/Debian/apt-repo $$(lsb_release -cs) main" \
		| sudo tee /etc/apt/sources.list.d/librealsense.list > /dev/null
	sudo apt-get update
	sudo apt-get install -y \
		librealsense2 librealsense2-dkms librealsense2-utils librealsense2-dev librealsense2-gl
	echo "Intel RealSense packages installed."

cdi-sriov:
	sudo apt update && sudo apt install -y golang
	sudo mkdir -p /opt/edge/scripts/cdi
	sudo install -m 755 container_setup_sriov.sh /opt/edge/scripts/container_setup_sriov.sh
	sudo install -m 644 systemd/intel-sriov-vf.service /etc/systemd/system/intel-sriov-vf.service
	sudo systemctl daemon-reload
	sudo systemctl enable intel-sriov-vf.service
	sudo bash /opt/edge/scripts/container_setup_sriov.sh
	if [[ ! -x cdi/intel-cdi-specs-generator-gpu ]]; then
		echo "Building Intel CDI GPU spec generator..."
		cdi/build-gpu-generator.sh	
	fi
	sudo install -m 755 cdi/intel-cdi-specs-generator-gpu /opt/edge/scripts/cdi/intel-cdi-specs-generator-gpu
	sudo install -m 755 cdi/intel-cdi-npu-generator.sh /opt/edge/scripts/cdi/intel-cdi-npu-generator.sh
	sudo cdi/systemd/install-systemd.sh
	echo "CDI and SR-IOV services installed."