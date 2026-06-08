#!/bin/bash
########################################################################
## This script will Setup the Intel Proxies, setup the apt 
## configuration & install all the Platform Software Packages
## with platform POR kernel
########################################################################
## source: Configurable BKC Script Template
## Primary Author: Patel, Tejas
## Contributors : jyong2, rgeddyse
## Passing arguments 1: <Program Name> 
##     possible values for ARL Family ==> ARL,ARL-H,ARL-P,ARL-U, ARL-S, MTL-S
##     possible values for ASL Family ==> ASL, ADL-N, TWL
##     possible values for RPL Family ==> RPL, RPL-P, RPL-PS
##     possible values for MTL Family ==> MTL, MTL-P, MTL-PS
##     possible values for PTL Family ==> PTL, PTL-H, PTL-U
##     possible values for WCL Family ==> WCL, WCL-H, WCL-U
##     possible values for NVL Family ==> NVL, NVL-S, NVL-H, NVL-U
##     possible values for BTL Family ==> BTL, BTL-S
##     possible values for ADL Family ==> ADL, ADL-S, ADL-P, ADL-PS
## Passing arguments 2: <Kernel Type>
##     possible values for Kernel Type ==> default , rt
##     this argument is optional if not passed then consider as default.
## Output File Name: installer.sh
## How to run installer.sh: sudo ./installer.sh MTL default
##
########################################################################

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# This Scripts updated with panther-lake/20260512-1624/instaler.sh
set -x 

function usage ()
{
  echo 'Usage : Script <Program Name> <Kernel Type>'
  echo 'Program Name can be as follows 
        ARL Family ==> ARL,ARL-H,ARL-P,ARL-U, MTL-S, ARL-S
	ASL Family ==> ASL, ADL-N, TWL
  	RPL Family ==> RPL, RPL-P, RPL-PS
	MTL Family ==> MTL, MTL-P, MTL-PS
	PTL Family ==> PTL, PTL-H, PTL-U
	WCL Family ==> WCL, WCL-H, WCL-U
	NVL Family ==> NVL, NVL-S, NVL-H, NVL-U
    BTL Family ==> BTL, BTL-S
	ADL Family ==> ADL, ADL-S, ADL-P, ADL-PS
	ACM Family ==> ACM
	BMG Family ==> BMG'
  echo 'Kernel Type can be as follows
        default 
	rt'
  exit 1
}

if [ $USER != "root" ]; then
	echo "ERROR: This script must be run with sudo!"
	usage
fi

#Validate passing arguments
if [ $# -le 0 ]; then
    echo "ERROR: Illegal number of parameters"
	usage
fi

producName=""
#Check 1st parameter as product name
if [ "$1" == "ARL" ] || [ "$1" == "arl" ] || [ "$1" == "ARL-P" ] || [ "$1" == "arl-p" ] \
	|| [ "$1" == "ARL-H" ] || [ "$1" == "arl-h" ] || [ "$1" == "ARL-U" ] || [ "$1" == "arl-u" ] \
	|| [ "$1" == "ARL-S" ] || [ "$1" == "arl-s" ] || [ "$1" == "MTL-S" ] || [ "$1" == "mtl-s" ]
then
	producName="ARL"
elif [ "$1" == "MTL" ] || [ "$1" == "mtl" ] || [ "$1" == "MTL-P" ] || [ "$1" == "mtl-p" ] \
	|| [ "$1" == "MTL-H" ] || [ "$1" == "mtl-h" ] || [ "$1" == "MTL-U" ] || [ "$1" == "mtl-u" ] \
	|| [ "$1" == "MTL-PS" ] || [ "$1" == "mtl-ps" ]
then
	producName="MTL"
elif [ "$1" == "ASL" ] || [ "$1" == "asl" ] || [ "$1" == "ADL-N" ] || [ "$1" == "adl-n" ] \
	|| [ "$1" == "TWL" ] || [ "$1" == "twl" ] ||   [ "$1" == "ASL-FUSA" ] ||  [ "$1" == "asl-fusa" ]
then
	producName="ASL"
elif [ "$1" == "ADL" ] || [ "$1" == "adl" ] || [ "$1" == "ADL-S" ] || [ "$1" == "adl-s" ] \
	|| [ "$1" == "ADL-P" ] || [ "$1" == "adl-p" ] || [ "$1" == "ADL-PS" ] || [ "$1" == "adl-ps" ]
then
	producName="ADL"
elif [ "$1" == "RPL" ] || [ "$1" == "rpl" ] || [ "$1" == "RPL-P" ] || [ "$1" == "rpl-p" ] \
	|| [ "$1" == "RPL-PS" ] || [ "$1" == "rpl-ps" ] 
then
	producName="RPL"
elif [ "$1" == "ACM" ] || [ "$1" == "acm" ] || [ "$1" == "ACM-E" ] || [ "$1" == "acm-e" ]
then
	producName="ACM"
elif [ "$1" == "BTL" ] || [ "$1" == "btl" ] || [ "$1" == "BTL-S" ] || [ "$1" == "btl-s" ] 
then
        producName="BTL"
elif [ "$1" == "PTL" ] || [ "$1" == "ptl" ] || [ "$1" == "PTL-H" ] || [ "$1" == "ptl-h" ] \
	|| [ "$1" == "PTL-U" ] || [ "$1" == "ptl-u" ]
then
        producName="PTL"
elif [ "$1" == "BMG" ] || [ "$1" == "bmg" ] || [ "$1" == "BMG-E" ] || [ "$1" == "bmg-e" ] 
then
        producName="BMG"
elif [ "$1" == "WCL" ] || [ "$1" == "wcl" ] || [ "$1" == "WCL-H" ] || [ "$1" == "wcl-h" ] \
	|| [ "$1" == "WCL-U" ] || [ "$1" == "wcl-u" ]
then
        producName="WCL"
elif [ "$1" == "NVL" ] || [ "$1" == "nvl" ] || [ "$1" == "NVL-S" ] || [ "$1" == "nvl-s" ] || [ "$1" == "NVL-H" ] || [ "$1" == "nvl-h" ] \
	|| [ "$1" == "NVL-U" ] || [ "$1" == "nvl-u" ]
then
        producName="NVL"
else
	echo "ERROR: Incorrect first Parameter value"
	usage
fi

kernelType="default"
if [ "$producName" == "ASL" ] || [ "$producName" == "ADL" ] \
	|| [ "$producName" == "RPL" ] || [ "$producName" == "BTL" ] || [ "$producName" == "WCL" ] || [ "$producName" == "PTL" ] || [ "$producName" == "ACM" ] || [ "$producName" == "NVL" ]
then
	if [ "$2" != "" ] && [ "$2" == "rt" ]; then
		kernelType="rt"
	elif [ "$2" != "" ] && [ "$2" != "default" ]; then
		echo "ERROR: Incorrect 2nd Parameter value"
		usage
	fi
fi


current_workspace="$PWD"
exceptionFailString=("NOCHANGE: partition" 
		    "'rbfadmin' already exists"
		    "E: Sub-process /usr/bin/dpkg returned an error code (1)")
current_workspace="$PWD"

# Load configuration from config file
CONFIG_FILE="/etc/environment"
if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        set +a
        export http_proxy
        export https_proxy
        export no_proxy="devtools.intel.com,jf.intel.com,teamcity-or.intel.com,caas.intel.com,inn.intel.com,isscorp.intel.com,gfx-assets.fm.intel.com"
        export ftp_proxy=$http_proxy
        export socks_server
else
        # Default values if config file not found
        PROXY_HTTP="$http_proxy"
        PROXY_HTTPS="$https_proxy"
        PROXY_SOCKS="$socks_server"
fi



function die() 
{
	outPutOfLastCmd=$( tail -n 1 cbkc_output.log )
	isException=0
	for i in "${exceptionFailString[@]}"
	do
		if [[ $outPutOfLastCmd = *$i* ]]; then
			isException=1.
			break
		fi
	done
	
	if [ "$isException" == "0" ]; then
		echo >&2 -e "\nERROR: $@\n"; 
		exit 1; 
	fi
}

function run() 
{ 
	eval $*
	code=$?; [ $code -ne 0 ] && die "command [$*] failed with error code $code"; 
}

function is_client_os() {
    echo "Checking system is using server image or client image..."

    dpkg -l | grep -E "ubuntu-desktop(-minimal)?"

    # Safe check to avoid SIGPIPE, preserve exit code
    dpkg -l | grep -E "ubuntu-desktop(-minimal)?" | head -n1 > /dev/null
    process=$?

   if [ "$process" -eq 0 ]; then
        echo "Detected client OS. Ending is_client_os."
        return 0
    else
        echo "Detected server OS. Installing ubuntu-desktop package."
        run "apt-get update"
        run "DEBIAN_FRONTEND=noninteractive apt-get install ubuntu-desktop -y"
        return 1
    fi
}

function parition_extention() {
	if is_client_os; then
		echo "Detected client OS. Executing partition logic."
		echo ".......Removing the swapfile and adding the SWAP partition of 8GB..........."
		
		drive=$(lsblk -no pkname $(findmnt -n / | awk '{ print $2 }'))
		new_partition=$(lsblk -npo name /dev/$drive | tail -n1)
		trimmed_partition=${new_partition#*/}
		partition_number=$(echo $trimmed_partition | rev | cut -c 1)

		if test $partition_number -ge 3; then
			echo "Already swap partition added. No change needed"
		else
			drive_memory=$(lsblk | grep $drive | grep disk | awk -F' ' '{ print $4 }')
			echo "Total Drive Memory : $drive_memory"
			if [[ $drive_memory == "30G" ]]; then
				echo "ERROR: You are running installer script on VM"
				echo "Please increase the raw image size to run installer.sh on VM"
				echo "Command to increase the additional image size is below"
				echo "sudo qemu-img resize -f raw <image-file> +20G"
				exit 1
			fi

			memory_type=$(echo $drive_memory | rev | cut -c 1)
			if [[ $memory_type == "T" ]]; then
				memory=$(echo $drive_memory | rev | cut -c2- | rev)
				drive_memory=$(echo "$memory*1000" | bc -l)
			fi

			if [[ $drive_memory == *"."* ]]; then
				disk_memory=${drive_memory%.*}
			else
				disk_memory=${drive_memory::-1}
			fi

			actual_memory=$((disk_memory - 10))
			percentage=$((actual_memory * 100 / disk_memory))
			free_percentage=$((100 - percentage))
			run "sudo swapoff -a"
			run "rm /swap.img"
			run "sudo growpart --free-percent $free_percentage /dev/$drive 2"
			run "sudo resize2fs /$trimmed_partition"

			echo "Creating Swap Partition"
			device=/dev/$drive
			while read x ; do sleep 1 ; echo $x ; done <<! | fdisk $device
n


+8G
w
q
!
			echo "Successfully Swap Partition Created \n"
			latest_partition=$(lsblk -npo name /dev/$drive | tail -n1)
			latest_trimmed_parition=${latest_partition#*/}
			run "sudo mkswap /$latest_trimmed_parition -U 6443e3b1-12bc-41d0-83d8-e5c25477b5a0"
			run "sudo swapon /$latest_trimmed_parition"
			echo "Update /etc/fstab for the new partition line"
			run "sudo sed -i '$ d' /etc/fstab"
			run "sudo chmod 766 /etc/fstab"
			echo "/dev/disk/by-uuid/6443e3b1-12bc-41d0-83d8-e5c25477b5a0   none    swap    sw      0       " >> /etc/fstab
			run "sudo chmod 644 /etc/fstab"
		fi
	fi

	return 0
}

##################################################################
##.............. Setting Proxy Setup .........
function ProxySetUp() {
        run "echo '$(date): Setting up Proxies...'"
        run "echo 'Acquire::ftp::Proxy \"$http_proxy\";' > /etc/apt/apt.conf.d/99proxy.conf"
        run "echo 'Acquire::http::Proxy \"$http_proxy\";' >> /etc/apt/apt.conf.d/99proxy.conf"
        run "echo 'Acquire::https::Proxy \"$http_proxy\";' >> /etc/apt/apt.conf.d/99proxy.conf"
        run "echo 'Acquire::https::proxy::af01p-png.devtools.intel.com \"DIRECT\";' >> /etc/apt/apt.conf.d/99proxy.conf"
        run "echo 'Acquire::https::proxy::af01p-png.devtools.intel.com \"DIRECT\";' >> /etc/apt/apt.conf.d/99proxy.conf"
        run "echo 'Acquire::https::proxy::ubit-artifactory-or.intel.com \"DIRECT\";' >> /etc/apt/apt.conf.d/99proxy.conf"
        run "echo 'Acquire::https::proxy::*.intel.com \"DIRECT\";' >> /etc/apt/apt.conf.d/99proxy.conf"
        run "sed -e 's@archive.ubuntu.com@mirrors.gbnetwork.com@g' -i /etc/apt/sources.list.d/ubuntu.sources"
        if [ "$(grep -R 'http_proxy=$http_proxy' /etc/environment)" == "" ]; then
                run "echo 'http_proxy=$http_proxy' >> /etc/environment"
        fi
        if [ "$(grep -R 'https_proxy=$https_proxy' /etc/environment)" == "" ]; then
                run "echo 'https_proxy=$https_proxy' >> /etc/environment"
        fi
        if [ "$(grep -R 'ftp_proxy=$http_proxy' /etc/environment)" == "" ]; then
                run "echo 'ftp_proxy=$http_proxy' >> /etc/environment"
        fi
        if [ "$(grep -R 'socks_server=$socks_server' /etc/environment)" == "" ]; then
                run "echo 'socks_server=$socks_server' >> /etc/environment"
        fi
        if [ "$(grep -R 'no_proxy=localhost,127.0.0.1,127.0.1.1,127.0.0.0/8,172.16.0.0/20,192.168.0.0/16,10.0.0.0/8,10.1.0.0/16,10.152.183.0/24,devtools.intel.com,jf.intel.com,teamcity-or.intel.com,caas.intel.com,inn.intel.com,isscorp.intel.com,gfx-assets.fm.intel.com' /etc/environment)" == "" ]; then
                run "echo 'no_proxy=localhost,127.0.0.1,127.0.1.1,127.0.0.0/8,172.16.0.0/20,192.168.0.0/16,10.0.0.0/8,10.1.0.0/16,10.152.183.0/24,devtools.intel.com,jf.intel.com,teamcity-or.intel.com,caas.intel.com,inn.intel.com,isscorp.intel.com,gfx-assets.fm.intel.com' >> /etc/environment"
        fi
        run ". /etc/environment"
        run "export http_proxy https_proxy ftp_proxy socks_server no_proxy"

        return 0
}



function reconfigureGrub()
{
	run "apt update"
	grubdrive=$(lsblk -no pkname $(findmnt -n / | awk '{ print $2 }'))
	run "apt-get purge --yes grub-efi-amd64 grub-efi grub-common grub2-common grub-pc-bin shim-signed --allow-remove-essential"
	run "rm -rf /boot/efi/EFI/ubuntu"
	run "rm -rf /boot/grub"
	run "apt-get install grub2-common grub-efi-amd64 grub-pc-bin shim-signed --yes"
	run "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck /dev/$grubdrive"
	run "update-grub"
	run "update-initramfs -u"

	return 0
}


##################################################################
##.............. Setting the Intel Proxies .......................
function PPAUpdate() {
	run "echo '$(date): Adding PPA & GPG Key...'"
	run "wget https://af01p-png.devtools.intel.com/artifactory/hspe-edge-png-local/ubuntu/keys/adl-hirsute-public.gpg -O /etc/apt/trusted.gpg.d/adl-hirsute-public.gpg"
	#run "wget https://af01p-png.devtools.intel.com/artifactory/hspe-edge-repos-png-local-png-local/ubuntu-ppa2/pub.gpg -O /etc/apt/trusted.gpg.d/hspe-edge-repos-png-local-png-local.gpg"
	echo -e "Package: *\nPin: origin af01p-png.devtools.intel.com\nPin-Priority: 1001" > /etc/apt/preferences.d/priorities
	run "cat /etc/apt/preferences.d/priorities"
      
	run "env https_proxy=$http_proxy wget -O- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB | gpg --dearmor | sudo tee /usr/share/keyrings/oneapi-archive-keyring.gpg > /dev/null"
	run "env https_proxy=$http_proxy wget -O- https://eci.intel.com/sed-repos/gpg-keys/GPG-PUB-KEY-INTEL-SED.gpg | sudo tee /usr/share/keyrings/sed-archive-keyring.gpg > /dev/null"
	run "echo deb [signed-by=/usr/share/keyrings/sed-archive-keyring.gpg] https://eci.intel.com/sed-repos/$(source /etc/os-release && echo $VERSION_CODENAME) sed main > /etc/apt/sources.list.d/sed.list"
	echo -e "Package: *\nPin: origin eci.intel.com\nPin-Priority: 1000" > /etc/apt/preferences.d/sed
	run "echo deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/openvino/2025 ubuntu24 main > /etc/apt/sources.list.d/intel-openvino-2025.list"
	

	run "apt update"
	run "echo 'N' | apt upgrade -y --allow-downgrades"
	run "apt-get install -yq curl"
	
	#Platform onboard 6.17 kernels onward will using canonical ethtool and libbpf1 	
	run "DEBIAN_FRONTEND=noninteractive apt-get install ethtool libbpf1 -y"

	run "echo deb https://af01p-png.devtools.intel.com/artifactory/hspe-edge-png-local/ubuntu/noble/noble/20260318-0012_2026_SW_A_REL2_RC03/ noble main non-free multimedia internal > /etc/apt/sources.list.d/intel-internal.list"
	#run " echo deb https://af01p-png.devtools.intel.com/artifactory/hspe-edge-repos-png-local-png-local/ubuntu-ppa2/ noble main  > /etc/apt/sources.list.d/stable.list"
	if [ "$producName" == "ASL" ] || [ "$producName" == "ADL" ] || [ "$producName" == "RPL" ] || [ "$producName" == "BTL" ] || [ "$producName" == "ACM" ]
	then
		run "echo 'deb [trusted=yes] https://af01p-png.devtools.intel.com/artifactory/hspe-edge-png-local/rtcm ./' > /etc/apt/sources.list.d/rtcm.list"
	fi
	
	if [ "$(grep -R 'rbfadmin' /etc/passwd)" == "" ]; then
		run "useradd --system -m -p jaiZ6dai -U rbfadmin"
	fi
	if [ "$(grep -R 'sys_olvtelemetry' /etc/passwd)" == "" ]; then
		run "useradd --system -m -U sys_olvtelemetry"
	fi
	run "mkdir -m 700 -p ~sys_olvtelemetry/.ssh"
	run "echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOPEVYF28+I92b3HFHOSlPQXt3kHXQ9IqtxFE4/0YkK5 swsbalabuser@BA02RNL99999' > ~sys_olvtelemetry/.ssh/authorized_keys"
	run "echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDb2P8gBvsy9DkzC1WiXfvisMFf7PQvtdvVC4n22ot4D5KOVxgoaCnjZM6qAZ2AdWPBebxInnUeMvw0u6RjRnflpYtNPgN4qiE313j62CmD80f/N+jvIxmoGhgsGE4RAMFXQ6pNaB/8KblrpmWQ5VfEIt7JcSR3Qvnkl9I2bljJU9zrMieE+Nras7hstg8fVWtGNjQjJpMWmt1YGxVbQiea0jDBqpru6TqnOYGD48JdR8QzHq++xL82I3x8kPz6annAvCDSVmiw9Mz0YtAsPIDZj4ABm866a8/U2mKVUncXYrBG1/pHBJMDJeX3ggd/UK2NvU8uEDJmITXUZRP8kBaO7b2LnRO08+Pr+nvmwukCP/wXflfS59h7kXCo8+Xjx/PEMO4OyFYHQunOUf/XTC13iig/MLY0EbqU6D+Lg1N13eJocRSta50zV+m+/PG23Zd3/6UH0noxYezQV3dQmsstzKKXbm8vkBmdqCZEvEnFSgl0VmX5HpzZLYI3L3hBH8/wgiWinrs7K13pZ8+lXN0ZhhJhdo61juiYwy1gbHP0ihqGkePw7w0DSCu5s9fA7xDTy2YTjkMsKaT8rbTYG5hunokNswdOCNYJyiCF3zJ08Z5hlDqSJJOPRdjL3YTIr6QlWSea/pTjkWmmE7Mv8M15c4V8Y77x6DsTFWlmGQbf1Q== swsbalabuser@BA02RNL99999' >> ~sys_olvtelemetry/.ssh/authorized_keys"
	run "chmod 600 ~sys_olvtelemetry/.ssh/authorized_keys"
	run "chown sys_olvtelemetry:sys_olvtelemetry -R ~sys_olvtelemetry/.ssh"
	run "sed -e 's@^GRUB_TIMEOUT_STYLE=hidden@# GRUB_TIMEOUT_STYLE=hidden@' -e 's@^GRUB_TIMEOUT=0@GRUB_TIMEOUT=5@g' -i /etc/default/grub"
	run "apt update"
	return 0
}


##################################################################
##.................. Installing Packages .........................
function InstallPackage(){
	echo "$(date): Installing Packages...................."
	package=("vim,ocl-icd-libopencl1,curl,openssh-server,net-tools,libdrm-amdgpu1,libdrm-common,libdrm-dev,libdrm-intel1,libdrm-nouveau2,libdrm-radeon1,libdrm-tests,libdrm2,libtpms-dev,libtpms0,libwayland-bin,libwayland-client0,libwayland-cursor0,libwayland-dev,libwayland-doc,libwayland-egl-backend-dev,libwayland-egl1,libwayland-server0,mesa-utils,ovmf,ovmf-ia32,xserver-xorg-core,libvirt0,libvirt-clients,libvirt-daemon,libvirt-daemon-config-network,libvirt-daemon-config-nwfilter,libvirt-daemon-driver-lxc,libvirt-daemon-driver-qemu,libvirt-daemon-driver-storage-gluster,libvirt-daemon-driver-storage-iscsi-direct,libvirt-daemon-driver-storage-rbd,libvirt-daemon-driver-storage-zfs,libvirt-daemon-driver-vbox,libvirt-daemon-driver-xen,libvirt-daemon-system,libvirt-daemon-system-systemd,libvirt-dev,libvirt-doc,libvirt-login-shell,libvirt-sanlock,libvirt-wireshark,libnss-libvirt,swtpm,swtpm-tools,bmap-tools,adb,autoconf,automake,libtool,cmake,g++,gcc,git,intel-gpu-tools,libssl3,libssl-dev,make,mosquitto,mosquitto-clients,build-essential,apt-transport-https,default-jre,docker-compose,git-lfs,gnuplot,lbzip2,libglew-dev,libglm-dev,libsdl2-dev,mc,openssl,pciutils,python3-pandas,python3-pip,python3-seaborn,terminator,vim,wmctrl,wayland-protocols,gdbserver,iperf3,msr-tools,powertop,lsscsi,tpm2-tools,tpm2-abrmd,binutils,cifs-utils,i2c-tools,xdotool,gnupg,lsb-release,socat,virt-viewer,util-linux-extra,dbus-x11,sg3-utils,rpm,iproute2=6.14.0-ppa1~noble1,xdp-tools=1.5.8-1ppa1~noble1,libxdp-dev=1.5.8-1ppa1~noble1,libxdp1=1.5.8-1ppa1~noble1,mutter-common-bin=46.2-1.0.24.04.14-1ppa1~noble2,mutter-common-bin=46.2-1.0.24.04.14-1ppa1~noble2,libmutter-14-0=46.2-1.0.24.04.14-1ppa1~noble2,gir1.2-mutter-14=46.2-1.0.24.04.14-1ppa1~noble2,libigdgmm-dev=22.9.0-1ppa1~noble1,libigdgmm12=22.9.0-1ppa1~noble1,libmfx-gen1.2=25.4.6-1ppa1~noble1,libva-dev=2.23.0-1ppa1~noble1,libva-drm2=2.23.0-1ppa1~noble1,libva-glx2=2.23.0-1ppa1~noble1,libva-wayland2=2.23.0-1ppa1~noble1,libva-x11-2=2.23.0-1ppa1~noble1,libva2=2.23.0-1ppa1~noble1,linux-firmware=20240318.git3b128b60-0.2.25-1ppa1-noble4,mesa-vulkan-drivers=25.3.4-1ppa1~noble1,libvpl-dev=1:2.16.0-1ppa1~noble1,libmfx-gen-dev=25.4.6-1ppa1~noble1,onevpl-tools=1:2.16.0-1ppa1~noble1,qemu-block-extra=4:9.1.0+git20260114-ppa1-noble5,qemu-guest-agent=4:9.1.0+git20260114-ppa1-noble5,qemu-system=4:9.1.0+git20260114-ppa1-noble5,qemu-system-arm=4:9.1.0+git20260114-ppa1-noble5,qemu-system-common=4:9.1.0+git20260114-ppa1-noble5,qemu-system-data=4:9.1.0+git20260114-ppa1-noble5,qemu-system-gui=4:9.1.0+git20260114-ppa1-noble5,qemu-system-mips=4:9.1.0+git20260114-ppa1-noble5,qemu-system-misc=4:9.1.0+git20260114-ppa1-noble5,qemu-system-ppc=4:9.1.0+git20260114-ppa1-noble5,qemu-system-s390x=4:9.1.0+git20260114-ppa1-noble5,qemu-system-sparc=4:9.1.0+git20260114-ppa1-noble5,qemu-system-x86=4:9.1.0+git20260114-ppa1-noble5,qemu-user=4:9.1.0+git20260114-ppa1-noble5,qemu-user-binfmt=4:9.1.0+git20260114-ppa1-noble5,qemu-utils=4:9.1.0+git20260114-ppa1-noble5,qemu-system-modules-opengl=4:9.1.0+git20260114-ppa1-noble5,va-driver-all=2.23.0-1ppa1~noble1,weston=10.0.0+git20250321-1ppa1~noble6,linuxptp=4.3-ppa1~noble2,libvpl-tools=2:1.5.0~1ppa1-noble1,spice-client-gtk=0.42-1ppa1~noble4,rpc-go=2.49.2-1ppa1~noble2,lms=2550.0.0.0-1ppa1~noble1,metee=5.0.0-1ppa1~noble3,intel-media-va-driver-non-free=25.4.6-1ppa1~noble1,gir1.2-gst-plugins-bad-1.0=1.26.10-1ppa1~noble1,gir1.2-gst-plugins-base-1.0=1.26.10-1ppa1~noble1,gir1.2-gstreamer-1.0=1.26.10-1ppa1~noble1,gir1.2-gst-rtsp-server-1.0=1.26.5-1ppa1~noble2,gstreamer1.0-alsa=1.26.10-1ppa1~noble1,gstreamer1.0-gl=1.26.10-1ppa1~noble1,gstreamer1.0-gtk3=1.26.10-1ppa1~noble1,gstreamer1.0-opencv=1.26.10-1ppa1~noble1,gstreamer1.0-plugins-bad=1.26.10-1ppa1~noble1,gstreamer1.0-plugins-bad-apps=1.26.10-1ppa1~noble1,gstreamer1.0-plugins-base=1.26.10-1ppa1~noble1,gstreamer1.0-plugins-base-apps=1.26.10-1ppa1~noble1,gstreamer1.0-plugins-good=1.26.10-1ppa1~noble1,gstreamer1.0-plugins-ugly=1.26.10-1ppa1~noble1,gstreamer1.0-pulseaudio=1.26.10-1ppa1~noble1,gstreamer1.0-qt5=1.26.10-1ppa1~noble1,gstreamer1.0-rtsp=1.26.5-1ppa1~noble2,gstreamer1.0-tools=1.26.10-1ppa1~noble1,gstreamer1.0-x=1.26.10-1ppa1~noble1,libgstrtspserver-1.0-dev=1.26.5-1ppa1~noble2,libgstrtspserver-1.0-0=1.26.5-1ppa1~noble2,libgstreamer-gl1.0-0=1.26.10-1ppa1~noble1,libgstreamer-opencv1.0-0=1.26.10-1ppa1~noble1,libgstreamer-plugins-bad1.0-0=1.26.10-1ppa1~noble1,libgstreamer-plugins-bad1.0-dev=1.26.10-1ppa1~noble1,libgstreamer-plugins-base1.0-0=1.26.10-1ppa1~noble1,libgstreamer-plugins-base1.0-dev=1.26.10-1ppa1~noble1,libgstreamer1.0-0=1.26.10-1ppa1~noble1,libgstreamer1.0-dev=1.26.10-1ppa1~noble1,vainfo=2.23.0-1ppa1~noble1,ffmpeg=7:8.0.0-1ppa1~noble1,xpu-smi=1.3.0-20250707.103634.3db7de07~u24.04,intel-ocloc=26.05.37020.3-0,libze-intel-gpu1=26.05.37020.3-0,intel-metrics-discovery=1.14.180-1,intel-metrics-library=1.0.196-1,intel-gsc=0.9.5-1ppa1~noble1,level-zero=1.22.4,intel-igc-core-2=2.28.4,intel-igc-opencl-2=2.28.4,intel-opencl-icd=26.05.37020.3-0,xserver-common=2:21.1.12-1ppa1~noble3,xnest=2:21.1.12-1ppa1~noble3,xserver-xorg-dev=2:21.1.12-1ppa1~noble3,xvfb=2:21.1.12-1ppa1~noble3")
	
	if [ "$producName" == "ASL" ] || [ "$producName" == "ADL" ] || [ "$producName" == "RPL" ] || [ "$producName" == "BTL" ];then
		package+=",rtcm"
	fi

	IFS=',' read -ra package_list <<< "$package"
	echo "Installing following list of packages : ${package_list[@]}"
	run "apt-get update"
	run "DEBIAN_FRONTEND=noninteractive apt-get install ${package_list[@]} -y --allow-downgrades"
	run "echo '$(date): Packages Successfully Installed....................'"
	
	#Packages information has been written to file to validate later. 
	rm -f installedPackageList.txt
	for package in "${package_list[@]}"; do
		if [[ $package =~ "=" ]]; then
			echo "$package " >> installedPackageList.txt
		fi
	done

	return 0
}

##################################################################
##.............. Setting the Intel Proxies .......................
function KernelUpdate() {
	run "echo '$(date): Updating Kernel..................'"
	kernelCmd=""
	if [ "$producName" == "ARL" ] || [ "$producName" == "BTL" ] || [ "$producName" == "ASL" ] || [ "$producName" == "RPL" ] || [ "$producName" == "MTL" ] || [ "$producName" == "ACM" ]; then
		if [ "$kernelType" == "rt" ]; then
	        	kernelCmd="apt-get -y --allow-downgrades install linux-headers-6.18rt-intel=260427t075939z-r2 linux-image-6.18rt-intel=260427t075939z-r2"
                	run "sudo sed -i 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"i915.enable_guc=3 i915.max_vfs=7 i915.force_probe=* udmabuf.list_limit=8192 processor.max_cstate=0 intel.max_cstate=0 processor_idle.max_cstate=0 intel_idle.max_cstate=0 clocksource=tsc tsc=reliable nowatchdog intel_pstate=disable idle=poll noht isolcpus=2,3 rcu_nocbs=2,3 rcupdate.rcu_cpu_stall_suppress=1 rcu_nocb_poll irqaffinity=0 i915.enable_rc6=0 i915.enable_dc=0 i915.disable_power_well=0 mce=off hpet=disable numa_balancing=disable igb.blacklist=no efi=runtime art=virtallow iommu=pt nmi_watchdog=0 nosoftlockup hugepages=1024 console=tty0 console=ttyS0,115200n8 intel_iommu=on\"/' /etc/default/grub"
                	run "sudo sed -i -e 's/GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux 6.18rt-intel\"/g' /etc/default/grub"
            	else
	        	kernelCmd="apt-get -y --allow-downgrades install linux-headers-6.18-intel=260427t075939z-r2 linux-image-6.18-intel=260427t075939z-r2"
	        		run "sudo sed -i 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"i915.enable_guc=3 i915.max_vfs=7 i915.force_probe=* udmabuf.list_limit=8192 console=tty0 console=ttyS0,115200n8\"/' /etc/default/grub"
                	run "sudo sed -i 's/GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux 6.18-intel\"/g' /etc/default/grub"
	    	fi
	elif [ "$producName" == "WCL" ] || [ "$producName" == "PTL" ]; then
		if [ "$kernelType" == "rt" ]; then
	        	kernelCmd="apt-get -y --allow-downgrades install linux-headers-6.18rt-intel=260427t075939z-r2 linux-image-6.18rt-intel=260427t075939z-r2"
                	run "sudo sed -i 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"modprobe.blacklist=i915  processor.max_cstate=0 intel.max_cstate=0 processor_idle.max_cstate=0 intel_idle.max_cstate=0 clocksource=tsc tsc=reliable nowatchdog intel_pstate=disable idle=poll nosmt isolcpus=2,3 rcu_nocbs=2,3 rcupdate.rcu_cpu_stall_suppress=1 rcu_nocb_poll irqaffinity=0 mce=off hpet=disable numa_balancing=disable igb.blacklist=no nmi_watchdog=0 nosoftlockup\"/' /etc/default/grub"
			        run "sudo sed -i -e 's/GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux 6.18rt-intel\"/g' /etc/default/grub"
                else	
				kernelCmd="apt-get -y --allow-downgrades install linux-headers-6.18-intel=260427t075939z-r2 linux-image-6.18-intel=260427t075939z-r2"
					run "sudo sed -i 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"xe.max_vfs=7 xe.force_probe=* modprobe.blacklist=i915 udmabuf.list_limit=8192 console=tty0 console=ttyS0,115200n8\"/' /etc/default/grub"
					run "sudo sed -i 's/GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux 6.18-intel\"/g' /etc/default/grub"
		fi
	elif [ "$producName" == "NVL" ]; then
		if [ "$kernelType" == "rt" ]; then
		kernelCmd="apt-get -y --allow-downgrades install linux-headers-6.19rt-intel=260408t073214z-r2 linux-image-6.19rt-intel=260408t073214z-r2"
			run "sudo sed -i 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"modprobe.blacklist=i915 processor.max_cstate=0 intel.max_cstate=0 processor_idle.max_cstate=0 intel_idle.max_cstate=0 clocksource=tsc tsc=reliable nowatchdog intel_pstate=disable idle=poll nosmt isolcpus=2,3 rcu_nocbs=2,3 rcupdate.rcu_cpu_stall_suppress=1 rcu_nocb_poll irqaffinity=0 mce=off hpet=disable numa_balancing=disable igb.blacklist=no nmi_watchdog=0 nosoftlockup\"/' /etc/default/grub"
			run "sudo sed -i -e 's/GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux 6.19rt-intel\"/g' /etc/default/grub"
			else	
			kernelCmd="apt-get -y --allow-downgrades install linux-headers-6.19-intel=260408t073214z-r2 linux-image-6.19-intel=260408t073214z-r2"
			run "sudo sed -i 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"xe.max_vfs=7 xe.force_probe=* modprobe.blacklist=i915 udmabuf.list_limit=8192 console=tty0 console=ttyS0,115200n8\"/' /etc/default/grub"
			run "sudo sed -i 's/GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux 6.19-intel\"/g' /etc/default/grub"
		fi
	fi
	run "sh -c \"printf 'install esp4 /bin/false\ninstall esp6 /bin/false\ninstall rxrpc /bin/false\n' > /etc/modprobe.d/dirtyfrag.conf; rmmod esp4 esp6 rxrpc 2>/dev/null; echo 3 > /proc/sys/vm/drop_caches; true\""
	run "$kernelCmd"
	
	#Update GRUB
	run "sudo update-grub"
	
	IFS=' ' read -ra kernel_list <<< "$kernelCmd"
	for kernelName in "${kernel_list[@]}"; do
		if [[ $kernelName =~ "=" ]]; then
			echo "$kernelName " >> installedPackageList.txt
		fi
	done
	
	return 0
}


##################################################################
##.............. Setting the Intel Internal Config Setup .........
function InternalConfigSetup() {
	run "echo '$(date): Setting up Internal Config...'"
	run "sed -i 's/#WaylandEnable=/WaylandEnable=/g' /etc/gdm3/custom.conf"
	run "sed -i 's/"1"/"0"/g' /etc/apt/apt.conf.d/20auto-upgrades"
	if [ "$(grep -R 'source /etc/profile.d/mesa_driver.sh' /etc/bash.bashrc)" == "" ]; then
		run "echo 'source /etc/profile.d/mesa_driver.sh' | sudo tee -a /etc/bash.bashrc"
	fi
	if [ "$(grep -R 'set enable-bracketed-paste off' /etc/inputrc)" == "" ]; then
		run "echo 'set enable-bracketed-paste off' >> /etc/inputrc"
	fi
	run "echo 'sys_olvtelemetry ALL=(ALL) NOPASSWD: /usr/sbin/biosdecode, /usr/sbin/dmidecode, /usr/sbin/ownership, /usr/sbin/vpddecode' > /etc/sudoers.d/user-sudo"
	run "echo 'user ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers.d/user-sudo"
	run "chmod 440 /etc/sudoers.d/user-sudo"
	run "sed -i 's/.*AutomaticLoginEnable =.*/AutomaticLoginEnable = true/g' /etc/gdm3/custom.conf"
	run "sed -i 's/.*AutomaticLogin = user1/AutomaticLogin = user/g' /etc/gdm3/custom.conf"
	run "echo 'kernel.printk = 7 4 1 7' > /etc/sysctl.d/99-kernel-printk.conf"
	run "echo 'kernel.dmesg_restrict = 0' >> /etc/sysctl.d/99-kernel-printk.conf"
	
	if [ "$producName" == "MTL" ] || [ "$producName" == "ARL"  ] || [ "$producName" == "PTL"  ]  || [ "$producName" == "WCL" ] || [ "$producName" == "NVL" ] || [ "$producName" == "BMG"  ]; then
		run "mkdir -p /tmp/npu-drv-package"
		run "curl -s \https://af01p-ir.devtools.intel.com/artifactory/drivers_vpu_linux_client-ir-local/builds/opensource-linux-vpu-driver/ci/opensource_main/npu-linux-driver-ci-1.32.0.20260402-23905121947/linux-npu-driver-v1.32.0.20260402-23905121947-ubuntu2404.tar.gz | tar -zxv --strip-components=1 -C /tmp/npu-drv-package -f -"
		run "cd /tmp/npu-drv-package && dpkg -i *.deb"
		run "mkdir -pv /lib/firmware/intel/sof-ipc4/mtl/ /lib/firmware/intel/sof-ace-tplg/"
		run "wget https://af01p-png.devtools.intel.com/artifactory/hspe-edge-png-local/ubuntu-mtl-audio-tplg-6/c0/intel/sof-ipc4/mtl/sof-mtl.ldc -O /lib/firmware/intel/sof-ipc4/mtl/sof-mtl.ldc"
		run "wget https://af01p-png.devtools.intel.com/artifactory/hspe-edge-png-local/ubuntu-mtl-audio-tplg-6/c0/intel/sof-ipc4/mtl/sof-mtl.ri  -O /lib/firmware/intel/sof-ipc4/mtl/sof-mtl.ri"
		run "wget https://af01p-png.devtools.intel.com/artifactory/hspe-edge-png-local/ubuntu-mtl-audio-tplg-6/c0/intel/sof-ace-tplg/sof-mtl-rt711-4ch.tplg -O /lib/firmware/intel/sof-ace-tplg/sof-mtl-rt711-4ch.tplg"
		run "wget https://af01p-png.devtools.intel.com/artifactory/hspe-edge-png-local/ubuntu-mtl-audio-tplg-6/c0/intel/sof-ace-tplg/sof-mtl-rt711.tplg -O /lib/firmware/intel/sof-ace-tplg/sof-mtl-rt711.tplg"
		run "wget https://af01p-png.devtools.intel.com/artifactory/hspe-edge-png-local/ubuntu-mtl-audio-tplg-6/c0/intel/sof-ace-tplg/sof-hda-generic.tplg -O /lib/firmware/intel/sof-ace-tplg/sof-hda-generic.tplg"
		run "wget https://af01p-png.devtools.intel.com/artifactory/hspe-edge-png-local/ubuntu-mtl-audio-tplg-6/c0/intel/sof-ace-tplg/sof-mtl-es83x6-ssp1-hdmi-ssp02.tplg -O /lib/firmware/intel/sof-ace-tplg/sof-mtl-es83x6-ssp1-hdmi-ssp02.tplg"
		run "wget https://af01p-png.devtools.intel.com/artifactory/hspe-edge-png-local/ubuntu-mtl-audio-tplg-6/c0/intel/sof-ace-tplg/sof-mtl-hdmi-ssp02.tplg -O /lib/firmware/intel/sof-ace-tplg/sof-mtl-hdmi-ssp02.tplg"
	fi
	if [ "$producName" == "NVL" ]; then
		run "wget https://af01p-png.devtools.intel.com/artifactory/hspe-edge-png-local/NVL/GuC/nvl_guc_70.55.4.bin -O /lib/firmware/xe/nvl_guc_70.55.4.bin"
	fi
	
	run "echo Bom-list.txt Dumped into cbkc_output.log"
	run "apt list --installed 2>/dev/null | tail -n +1 | sudo tee /opt/Bom-list.txt"
	run "echo 'BUILD_TIME='$(date +%Y%m%d-%H%M) > /opt/jenkins-build-timestamp"
	run "echo 'PLATFORM=$producName' >> /opt/jenkins-build-timestamp"
	if [ "$producName" == "ARL" ] || [ "$producName" == "BTL" ] || [ "$producName" == "ASL" ] || [ "$producName" == "MTL" ]; then
		if [ "$kernelType" == "rt" ]; then
			run "echo -e '$producName KERNEL=6.18rt-intel' >> /opt/jenkins-build-timestamp"
		else
			run "echo -e '$producName KERNEL=6.18-intel' >> /opt/jenkins-build-timestamp"
		fi
	elif [ "$producName" == "WCL" ] || [ "$producName" == "PTL" ]; then
		if [ "$kernelType" == "rt" ]; then
			run "echo -e '$producName KERNEL=6.18rt-intel' >> /opt/jenkins-build-timestamp"
		else
			run "echo -e '$producName KERNEL=6.18-intel' >> /opt/jenkins-build-timestamp"
		fi
	elif [ "$producName" == "NVL"  ]; then
		if [ "$kernelType" == "rt" ]; then
			run "echo -e '$producName KERNEL=mainline-preprod-rt-6.19' >> /opt/jenkins-build-timestamp"
		else
			run "echo -e '$producName KERNEL=mainline-preprod-6.19' >> /opt/jenkins-build-timestamp"
		fi
	elif [ "$producName" == "BMG" ]; then
                run "echo -e '$producName KERNEL=mainline-tracking-6.15-rc3' >> /opt/jenkins-build-timestamp"
	fi
	
	if [ "$producName" != "RPL" ] || [ "$producName" != "ACM" ]; then
		run "echo '#!/bin/bash' > /opt/snapd_refresh.sh"
		run "echo 'snap set system proxy.http=$http_proxy' >> /opt/snapd_refresh.sh"
		run "echo 'snap set system proxy.https=$https_proxy' >> /opt/snapd_refresh.sh"
		run "echo 'sleep 60 && snap refresh snapd-desktop-integration' >> /opt/snapd_refresh.sh"
		run "chmod +x /opt/snapd_refresh.sh"
		run "(crontab -l 2>/dev/null; echo '@reboot sudo /opt/snapd_refresh.sh 2>&1 | tee /opt/snapd_refresh_logs.txt') | crontab -"
	fi
	
	return 0
}


##################################################################
##.............. Validate installed package ......................
function ValidatePackages()
{
	file="installedPackageList.txt"

	while read -r line; do
		package_name=$(echo "$line" | cut -d'=' -f1)
		installer_version=$(echo "$line" | cut -d'=' -f2)
		eval $(cat /opt/Bom-list.txt | grep -q "${package_name}/")
		if [ $? -eq 0 ]; then
			installed_version=$(cat /opt/Bom-list.txt | grep "${package_name}/"  | awk '{print $2}')
			echo "Package Name: $package_name ==> Installed_Version: $installed_version \
					==> Installer_Version: $installer_version"
			if [ "$installed_version" != "$installer_version" ]; then
				echo "ERROR: $package_name is not identical!"
				echo "ERROR: SUT installed version : $installed_version"
				echo "ERROR: Version mentioned in installer.sh: $installer_version"
				exit 1
			fi
		else
			echo "ERROR: $package_name package not found in Bom-list.txt"
			exit 1;
		fi
	done <$file
	echo "All installed version is identical to the version mentioned in installer.sh"
	
	return 0
}

ProxySetUp 2>&1 | tee -a "$current_workspace/cbkc_output.log" || exit 1
reconfigureGrub 2>&1 | tee -a "$current_workspace/cbkc_output.log" || exit 1
PPAUpdate 2>&1 | tee -a "$current_workspace/cbkc_output.log" || exit 1
InstallPackage 2>&1 | tee -a "$current_workspace/cbkc_output.log" || exit 1
KernelUpdate 2>&1 | tee -a "$current_workspace/cbkc_output.log" || exit 1
InternalConfigSetup 2>&1 | tee -a "$current_workspace/cbkc_output.log" || exit 1
ValidatePackages 2>&1 | tee -a "$current_workspace/cbkc_output.log" || exit 1

echo "Rebooting Device now" | tee -a "$current_workspace/cbkc_output.log"

echo "Done"


