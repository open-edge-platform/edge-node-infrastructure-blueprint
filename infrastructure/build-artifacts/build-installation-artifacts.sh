#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#set -x

os_filename=""

# Read the build mode from the make cmd line 
MODE="$1"
ISO_URL="$2"
ICT_IMG="$3"

source /etc/environment
# Build the hook os with and generate kernel && initramfs file
build-alpine-os(){

echo "Started Alpine OS build!!,it will take some time"

pushd ../micro-os/

if bash build-alpine-os.sh; then
    echo "Alpine OS Build Successful"
else
    echo "Alpine build Failed,Please check!!"
    exit 1
fi
popd > /dev/null

}

# TODO: Move CDI binary build to Host OS preparation stage — temporary solution
# Build the CDI GPU spec generator binary if not already present (requires Go 1.22+)
build-cdi-generator(){

CDI_BINARY="../installation-scripts/cdi/intel-cdi-specs-generator-gpu"
if [ -x "$CDI_BINARY" ]; then
    echo "CDI GPU generator already built, skipping"
elif ! command -v go >/dev/null 2>&1; then
    echo "WARNING: Go 1.22+ not found — skipping CDI GPU generator build. GPU CDI support will not be available."
else
    echo "Building CDI GPU spec generator (one-time)..."
    if bash ../installation-scripts/cdi/build-gpu-generator.sh; then
        echo "CDI GPU generator built successfully"
    else
        echo "WARNING: CDI GPU generator build failed. GPU CDI support will not be available."
    fi
fi

}

# Download Ubuntu image and store it under out directory
download-Ubuntu_img(){

pushd ../host-os > /dev/null

chmod +x prepare-host-img.sh 
if [ -z "$ISO_URL" ]; then
    echo "ISO_URL is not provided please check!!!"
    exit 1
fi
bash prepare-host-img.sh -i "$ISO_URL" -c auto-install-pkgs.yaml
if [ "$?" -eq 0 ]; then
    echo "Host OS image created successfuly!!"
    os_filename=$(printf "%s\n" *.raw.img.gz 2>/dev/null | head -n 1)
    cp $os_filename ../build-artifacts/
else
    echo "Host OS image download failed,please chheck!!!"
    popd
    exit 1
fi
popd > /dev/null 
}

# Create alpine-iso
create-alpine-os-iso(){
#Check hook_x86_64.tar.gz file  present under build directory
if [[ ! -e "../micro-os/build/output/initramfs" && ! -e "../micro-os/build/output/vmlinuz" ]]; then
    echo "Looks initrams and kernel files  not presnet, build the Alpine OS first!!"
    exit 1
else
    # Install the required tool
    sudo apt update
    sudo apt install grub2-common xorriso mtools dosfstools -y > /dev/null
    # Cleanup the files if exist
    if [ -d out ]; then
        rm -rf out
    fi
    mkdir -p out
    cp ../micro-os/build/output/initramfs out/
    cp ../micro-os/build/output/vmlinuz out/
    pushd out/

    # Create the ISO structure
    mkdir -p iso/boot/grub
    mkdir -p iso/EFI/BOOT

    cp vmlinuz  iso/boot/vmlinuz
    cp initramfs iso/boot/initrd
       
    # Create the grub config file
    cat <<EOF > iso/boot/grub/grub.cfg
        set timeout=0
        set default=0
        set gfxpayload=text
        set gfxmode=text

        menuentry "Alpine Linux" {
	linux /boot/vmlinuz console=tty0 console=ttyS0 ro quite loglevel=3 usbcore.delay_ms=2000 usbcore.autosuspend=-1 modloop=none text
        initrd /boot/initrd
}
EOF
    # Create the bootable iso that support uefi && bios formats
    grub-mkrescue -o alpine-os.iso iso

    if [ "$?" -eq 0 ]; then
        echo "ISO created successfully under $(pwd)"
    else
        echo "ISO creation failed,please check!!"
        popd >/dev/null
	exit 1
    fi
    popd >/dev/null
fi

}

# Pack the ISO image,Ubuntu Image,config-file 
pack-artifacts(){

# Create the tar file for k8 scripts
if [ -n "$os_filename" ]; then
    mv $os_filename out/ 
else
    os_filename=""
fi
cp bootable-usb-prepare.sh out/
cp config-file out/
cp ven-deployment.sh out/

pushd out > /dev/null

echo "Creating usb-bootable-files.tar.gz (ISO + OS image). This can take several minutes..."
tar -czf usb-bootable-files.tar.gz alpine-os.iso $os_filename  > /dev/null
echo "usb-bootable-files.tar.gz created"

if [ "$?" -eq 0 ]; then
    echo "Creating usb-installation-files.tar.gz..."
    tar -czf usb-installation-files.tar.gz bootable-usb-prepare.sh config-file usb-bootable-files.tar.gz ven-deployment.sh 
    if [ "$?" -eq 0 ]; then
        echo ""
	echo ""
	echo ""
	# Delete all other generated files other than sen-installation-files.tar.gz
        find . -mindepth 1 -not -name "usb-installation-files.tar.gz" -delete
        echo "##############################################################################################"
        echo "                                                                                              "
        echo "                                                                                              "
        echo "USB Installation files--> usb-installation-files.tar.gz created successfully, under $(pwd)"
        echo "                                                                                              "
        echo "                                                                                              "
        echo "###############################################################################################"
    else
	echo "Failed to create usb Installation files, please check!!!"
	popd
	exit 1
    fi
else
    echo "usb-bootable-files.tar.gz not created, please check!!!"
    popd
    exit 1
fi
popd

}

# Use a pre-built ICT image as the OS image
use-ict-image(){

if [ -z "$ICT_IMG" ]; then
    echo "ICT_IMG is not provided."
    echo "Usage: make build MODE=image-from-tool ICT_IMG=/path/to/image.raw.gz"
    exit 1
fi

if [ ! -f "$ICT_IMG" ]; then
    echo "ICT image not found: $ICT_IMG"
    exit 1
fi

if ! [[ "$ICT_IMG" =~ \.(raw\.gz|raw\.img\.gz)$ ]]; then
    echo "Error: ICT image must have a .raw.gz or .raw.img.gz extension"
    exit 1
fi

os_filename=$(basename "$ICT_IMG")
cp "$ICT_IMG" .
if [ "$?" -eq 0 ]; then
    echo "ICT image ready: $os_filename"
else
    echo "Failed to copy ICT image, please check!"
    exit 1
fi

}

main(){

case "$MODE" in
    image-from-iso)
        echo "Building from ISO. It will take some time Please wait...."
	download-Ubuntu_img
        ;;
    image-from-tool)
        echo "Building using ICT-generated image..."
        use-ict-image
        ;;
    reuse-image)
        echo "Skipping image generation..."
        ;;
    *)
        echo "Invalid mode: $MODE"
	echo "Usage....."
	echo " make build MODE=image-from-iso ISO_URL=http://ubuntu-iso-url"
	echo       "or"
        echo " make build MODE=image-from-tool "
	echo       "or"
	echo " make build MODE=reuse-image"
        exit 1
        ;;
esac 

build-cdi-generator

build-alpine-os

create-alpine-os-iso

pack-artifacts
}

######@main#####
main
