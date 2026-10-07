SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:

.PHONY: realsense cdi-sriov

# Installs the Intel RealSense SDK from librealsense.intel.com (librealsense2,
# librealsense2-dkms, librealsense2-utils, librealsense2-dev, librealsense2-gl).
realsense:
	if [[ $$EUID -ne 0 ]]; then
		echo "ERROR: the realsense target must be run as root (e.g. sudo make realsense)." >&2
		exit 1
	fi
	mkdir -p /etc/apt/keyrings
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
	install -m 644 /tmp/librealsense-keyring.gpg /etc/apt/keyrings/librealsense.gpg
	rm -f /tmp/librealsense.gpg /tmp/librealsense-keyring.gpg
	echo "deb [signed-by=/etc/apt/keyrings/librealsense.gpg] https://librealsense.intel.com/Debian/apt-repo $$(lsb_release -cs) main" \
		| tee /etc/apt/sources.list.d/librealsense.list > /dev/null
	apt-get update
	apt-get install -y \
		librealsense2 librealsense2-dkms librealsense2-utils librealsense2-dev librealsense2-gl
	echo "Intel RealSense packages installed."

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