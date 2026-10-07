SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
INTEL_LPMD_COMMIT ?= 956df747e56aca1739b39bff8cff77e81758af9a

.PHONY: power-tuning system-info lpmd

power-tuning: lpmd
	sudo apt-get update
	sudo apt-get install -y turbostat msr-tools "linux-tools-$$(uname -r)" stress-ng # docker/k3s/openvino
	sudo mkdir -p /opt/edge/developer/tools/
	sudo cp -r power-tuning /opt/edge/developer/tools/power-tuning

system-info:
	sudo mkdir -p /opt/edge/developer/tools/
	sudo cp -r system-info /opt/edge/developer/tools/system-info

lpmd:
	if [[ $$EUID -ne 0 ]]; then
		echo "ERROR: the lpmd target must be run as root (e.g. sudo make lpmd)." >&2
		exit 1
	fi
	apt-get update
	apt-get install -y autoconf autoconf-archive gcc libglib2.0-dev libdbus-1-dev libxml2-dev libnl-3-dev \
		libnl-genl-3-dev libsystemd-dev gtk-doc-tools libupower-glib-dev automake
	cd /tmp
	rm -rf lpmd
	git clone https://github.com/intel/intel-lpmd.git lpmd
	cd lpmd
	git checkout "$(INTEL_LPMD_COMMIT)" || { echo "ERROR: Failed to checkout intel-lpmd commit $(INTEL_LPMD_COMMIT)"; exit 1; }
	ACTUAL_COMMIT=$$(git rev-parse HEAD)
	if [[ "$$ACTUAL_COMMIT" != "$(INTEL_LPMD_COMMIT)" ]]; then
		echo "ERROR: intel-lpmd commit verification failed: expected $(INTEL_LPMD_COMMIT), got $$ACTUAL_COMMIT"
		exit 1
	fi
	./autogen.sh
	make
	make install
	# Remove restrictive hardware conditions so the service attempts to start
	# on all platforms. The daemon itself will exit gracefully if unsupported.
	mkdir -p /etc/systemd/system/intel_lpmd.service.d
	tee /etc/systemd/system/intel_lpmd.service.d/override.conf > /dev/null <<-EOF
		[Unit]
		# Clear all Condition* directives from the upstream unit
		ConditionPathExists=
		ConditionVirtualization=
	EOF
	# NOTE: Not purging build dependencies — they are shared with dkms,
	# build-essential, intel-mipi-gmsl-dkms, and librealsense2-dkms.
	apt-get clean
	# Enable service
	systemctl --root=/ enable intel_lpmd.service
	cd /tmp
	rm -rf lpmd
	echo "Installed intel-lpmd"