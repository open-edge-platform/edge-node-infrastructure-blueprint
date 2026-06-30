#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#set -x

set -euo pipefail

# Change to the directory where this script is located
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

os_filename=""

# Read the build mode from the make cmd line
# Makefile passes: "$(MODE)" "$(ICT_IMG)"
MODE="${1:-standard-image}"
ICT_IMG="${2:-}"

# Make sure host access the container files
container-file-permissions() {
if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
    chown -R "${HOST_UID}:${HOST_GID}" out ../micro-os/build/output ../micro-os/output 2>/dev/null || true
fi
}
# Build the micro OS (Alpine) with kernel and initramfs
build-alpine-os(){

echo "Started Alpine OS build!!,it will take some time"

pushd ../micro-os/ || exit 1

if bash build-in-docker.sh; then
    echo "Alpine OS Build Successful"
else
    echo "Alpine build Failed,Please check!!"
    exit 1
fi
popd > /dev/null || exit 1

}

# Build the CDI GPU spec generator binary using Docker (no Go required on host)
build-cdi-generator() {
    CDI_BINARY="../installation-scripts/cdi/intel-cdi-specs-generator-gpu"
    if [ -x "$CDI_BINARY" ]; then
        echo "CDI GPU generator already built, skipping"
    else
        echo "Building CDI GPU spec generator using Docker..."
        if bash ../installation-scripts/cdi/build-in-docker.sh; then
            echo "CDI GPU generator built successfully"
            # Verify binary
            if [ -x "$CDI_BINARY" ]; then
                echo "Binary verified - executable"
            else
                echo "ERROR: Binary not executable after build!"
                exit 1
            fi
        else
            echo "ERROR: CDI GPU generator build failed. Aborting build."
            exit 1
        fi
    fi
}

# Build Host OS (Ubuntu desktop) using custom Docker approach
build-host-os(){

pushd ../host-os > /dev/null || exit 1

echo "Building Host OS from Dockerfile using custom-image-setup.sh..."
chmod +x custom-image-setup.sh
bash custom-image-setup.sh || exit 1

echo "Host OS image created successfully!!"
os_filename="../host-os/build/custom-desktop.raw.gz"

if [ -n "$os_filename" ] && [ -f "$os_filename" ]; then
    cp "$os_filename" ../build-artifacts/
    echo "Copied $os_filename to build-artifacts/"
else
    echo "Host OS image file not found"
    popd > /dev/null || exit 1
    exit 1
fi
popd > /dev/null || exit 1
}
# Create alpine-iso
create-alpine-os-iso(){
#Check hook_x86_64.tar.gz file  present under build directory
OUTPUT_DIR="../micro-os/output"
if [[ ! -e "$OUTPUT_DIR/initramfs" && ! -e "$OUTPUT_DIR/vmlinuz" ]]; then
    echo "Looks initrams and kernel files  not presnet, build the Alpine OS first!!"
    exit 1
else
    # Cleanup the files if exist
    if [ -d out ]; then
        rm -rf out
    fi
    mkdir -p out
    cp "$OUTPUT_DIR/initramfs" out/
    cp "$OUTPUT_DIR/vmlinuz" out/
    pushd out/ || exit 1

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
        
        # Check number of partitions in the ISO
        echo "Checking partitions in alpine-os.iso..."
        PARTITION_COUNT=$(fdisk -l alpine-os.iso | grep -c "^alpine")
        if [ "$PARTITION_COUNT" -eq 4 ]; then
            echo "ISO partition check passed: 4 partitions found"
        else
            echo "ISO partition check failed: expected 4 partitions, found $PARTITION_COUNT"
            popd >/dev/null || exit 1
        fi
    else
        echo "ISO creation failed,please check!!"
        popd >/dev/null || exit 1
	    exit 1
    fi
    popd >/dev/null || exit 1
fi

}

# Pack the ISO image,Ubuntu Image,config-file 
pack-artifacts(){

    os_filename=$(find . -maxdepth 1 -type f \( -name "*.gz" -o -name "*.raw.gz" \) | head -1)
    if [[ -n "$os_filename" ]]; then
        os_filename=$(basename "$os_filename")
        mv "$os_filename" out/
    else
        os_filename=""
    fi
cp bootable-usb-prepare.sh out/
cp config-file out/
cp ven-deployment.sh out/

pushd out > /dev/null || exit 1

echo "Creating usb-bootable-files.tar.gz (ISO + OS image). This can take several minutes..."
# Use pigz for parallel compression (much faster than gzip)
if [[ -n "$os_filename" ]]; then
    tar_cmd="tar -I pigz -cf usb-bootable-files.tar.gz alpine-os.iso $os_filename"
else # for reuse-image mode where OS image is not generated.
    tar_cmd="tar -I pigz -cf usb-bootable-files.tar.gz alpine-os.iso"
fi
if eval "$tar_cmd" > /dev/null; then
    echo "usb-bootable-files.tar.gz created"
    echo "Creating usb-installation-files.tar.gz..."
    # Use pigz for parallel compression
    if tar -I pigz -cf usb-installation-files.tar.gz bootable-usb-prepare.sh config-file usb-bootable-files.tar.gz ven-deployment.sh; then
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
	popd > /dev/null || exit 1
	exit 1
    fi
else
    echo "usb-bootable-files.tar.gz not created, please check!!!"
    popd > /dev/null || exit 1
    exit 1
fi
popd > /dev/null || exit 1

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
    standard-image)
        echo "Preparing Custom Host OS. It will take some time Please wait...."
	build-host-os
        ;;
    image-from-tool)
        echo "Building using ICT-generated image..."
        use-ict-image
        ;;
    reuse-image)
        echo "Skipping Host OS generation..."
        ;;
    *)
        echo "Invalid mode: $MODE"
        echo "Usage....."
        echo " make build MODE=standard-image"
        echo "or"
        echo " make build MODE=image-from-tool "
        echo "or"
        echo " make build MODE=reuse-image"
        exit 1
        ;;
esac 

build-cdi-generator

build-alpine-os

create-alpine-os-iso

pack-artifacts

container-file-permissions
}

######@main#####
main
