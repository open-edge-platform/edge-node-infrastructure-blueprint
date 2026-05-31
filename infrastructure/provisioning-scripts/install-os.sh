#!/bin/bash

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0


### Global Variables ###
usb_disk=""
usb_devices=""
# shellcheck disable=SC2034
usb_count=""
blk_devices=""
os_disk=""
OS_IMG_PART=5
USER_CONF_PART=6
os_rootfs_part=
os_data_part=
deploy_mode="real"
user_apps_data="false"
LOG_FILE="/var/log/os-installer.log"
lvm_size=""
USER_SELECTED_DISK=""
CUSTOM_PARTITIONS=""
proxy_settings="false"
#########################

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m'
YELLOW='\033[0;33m'

BAR_WIDTH=50
TOTAL_PROVISION_STEPS=7
PROVISION_STEP=0
MAX_STATUS_MESSAGE_LENGTH=25

# Dynamically updating the cloud-init file.
TMP_YAML=$(mktemp)
CONFIG_FILE=""
CLOUD_INIT_FILE=""

: >"$LOG_FILE"

exec 3>>"$LOG_FILE"

# Redirect ALL standard output and error to that file descriptor

# Send 'set -x' traces to descriptor 3
export BASH_XTRACEFD="3"

# Parse command line arguments
if [[ -z "$1" ]]; then
    ATTENDEDMODE="false"
elif [[ "$1" == "-i" ]]; then
    ATTENDEDMODE="true"
else
    echo -e "${RED}ERROR: Invalid argument '$1'${NC}"
    echo "Usage:"
    echo "  /usr/local/bin/os-install.sh              # Run in UNATTENDED mode (config-file: installation_mode=false)"
    echo "  /usr/local/bin/os-install.sh -i           # Run in ATTENDED mode (config-file: installation_mode=true)"
    exit 1
fi

set -x


# Dump the failure logs to USB for debugging
dump_logs_to_usb() {
    # Mount the USB
    mount "${usb_disk}${USER_CONF_PART}" /mnt
    cp /var/log/os-installer.log /mnt
    umount /mnt
}

success() {
    echo -e "${GREEN}$1${NC}" 
}

failure() {
    echo ""
    echo -e "\n${RED}$1${NC}" 
    dump_logs_to_usb
    echo -e "\n${RED}Exit the Installation. Please check /var/log/os-installer.log file for more details.${NC}" 
}

# Check if mnt is already mounted,if yes unmount it
check_mnt_mount_exist() {
    mounted=$(lsblk -o MOUNTPOINT | grep "/mnt")
    if [ -n "$mounted" ]; then
        umount -l /mnt
    fi
}

# Wait for a few seconds for USB emulation as hook OS boots fast
detect_usb() {
    for _ in {1..15}; do
	usb_devices=$(lsblk -dn -o NAME,TYPE,SIZE,TRAN | awk '$2 == "disk" && $4 == "usb" && $3 != "0B" {print $1}')
        # shellcheck disable=SC2086
        for disk_name in $usb_devices; do
            # Bootable USB has 6 partitions,ignore other disks
            if [ "$(lsblk -l "/dev/$disk_name" | grep -c "^$(basename "/dev/$disk_name")[0-9]")" -eq 6 ]; then
                usb_disk="/dev/$disk_name"
                echo "$usb_disk"
                return
            fi
        done
        sleep 1
    done
}

# Get the USB disk where the OS image and K8* scripts are copied
get_usb_details() {
    echo -e "${BLUE}Get the USB details!!${NC}" 
    # Check if the USB is detected at Hook OS
    usb_disk=$(detect_usb)

    # Exit if no USB device found
    if [ -z "$usb_disk" ]; then
        failure "No valid USB device found, exiting the installation."
        return 1 
    fi
    success "Found the USB Device $usb_disk"

    # Check partition 5 and 6 for OS and user defined files if exists 
    #check_mnt_mount_exist
    mount -o ro "${usb_disk}${OS_IMG_PART}" /mnt
    if ! ls /mnt/*.gz  >/dev/null 2>&1; then
        failure "OS Image File not Found, exiting the installation."
        umount /mnt
        return 1 
    else
        umount /mnt
    fi
    mount -o ro "${usb_disk}${USER_CONF_PART}" /mnt
    if ! ls /mnt/config-file >/dev/null 2>&1; then
        failure "Configuration file not Found, exiting the installation."
        umount /mnt
        return 1 
    fi
    # Check for installation_mode=true in config-file to set attended mode/ unattended mode
    installation_mode=$(grep '^installation_mode=' "/mnt/config-file" | cut -d '=' -f2 | tr -d '"')
        if [ "$installation_mode" == "true" ]; then
            ATTENDEDMODE="true"
        fi
    umount /mnt
    return 0
}

# Get the list of block devices on the device and choose the best disk for installation
get_block_device_details() {
    echo -e "${BLUE}Get the block device for OS installation${NC}" 

    # List of block devices attached to the system, ignore USB and loopback devices
    blk_devices=$(lsblk -dn -o NAME,TYPE,SIZE,TRAN | awk '$2 == "disk" && $4 ~ /^(sata|nvme)$/ && $3 != "0B" {print $1}')
    blk_dev_count=$(echo "$blk_devices" | wc -l)

    if [ -z "$blk_dev_count" ]; then
        failure "No valid hard disk found for installation, exiting the installation!!"
        return 1 
    fi

    # If only one disk found, use that for installation
    if [ "$blk_dev_count" -eq 1 ]; then
        os_disk="/dev/$blk_devices"
    else
        # If more than one block disk found, choose the disk with the smallest size
        # NVME is preferred as Rank1 compared to SATA
	min_size_disk=$(lsblk -bdn -o NAME,SIZE,RM,TYPE | awk '
  		$3 == 0 && $4 == "disk" && $2 > 0 {
    		rank = ($1 ~ /^nvme/) ? 1 : 2;
    		print rank, $2, "/dev/"$1
  		}' | sort -n | awk 'NR==1 {print $3}')
        os_disk="$min_size_disk"
    fi
    echo -e "${GREEN}Found the OS disk  $os_disk${NC}" 

    # Clear the disk partitions
    # shellcheck disable=SC2086
    for disk_name in ${blk_devices}; do
        dd if=/dev/zero of="/dev/$disk_name" bs=100M count=20
	wipefs --all "/dev/$disk_name"
    done
    return 0
}

# Attended MODE 
print_block_device_details() {
    echo -e "${BLUE}Print the block device for OS installation${NC}"
    TTY=/dev/tty1 
    local TMPFILE DIALOG_EXIT

    # List all the available disks with size and model, ignore USB and loopback devices 
    DISK_LIST=""
    for disk in $(lsblk -dn -o NAME,TYPE,SIZE,TRAN | awk '$2 == "disk" && $4 ~ /^(sata|nvme)$/ && $3 != "0B" {print $1}'); do
        SIZE=$(lsblk -dn -o SIZE /dev/$disk 2>/dev/null)
        MODEL=$(lsblk -dn -o MODEL /dev/$disk 2>/dev/null | tr ' ' '_')
        MODEL=${MODEL:-"Unknown"}
        DISK_LIST="$DISK_LIST /dev/$disk ${SIZE}-${MODEL}"
    done

    if [ -z "$DISK_LIST" ]; then
        echo "No disks found!" >>/dev/tty1
        return 1
    fi

    TMPFILE=$(mktemp /tmp/dialog.XXXXXX)
    dialog --title "Disk Selection" --menu "Choose disk for OS install:" 0 0 0 $DISK_LIST </dev/tty1 >/dev/tty1 2>"$TMPFILE"
    DIALOG_EXIT=$?

    USER_SELECTED_DISK=$(cat "$TMPFILE")
    rm -f "$TMPFILE"
    clear >/dev/tty1

    if [ $DIALOG_EXIT -ne 0 ] || [ -z "$USER_SELECTED_DISK" ]; then
        echo "No disk selected. Aborting." >>/dev/tty1
        return 1
    fi

    echo "User selected: $USER_SELECTED_DISK"
    os_disk="$USER_SELECTED_DISK"
    return 0
}

# Install the OS image
install_os_on_disk() {

    check_mnt_mount_exist
    mount "$usb_disk${OS_IMG_PART}" /mnt
    os_file=$(find /mnt -type f -name "*.gz" | head -n 1)

    if [ -n "$os_file" ]; then
        # Install the OS image on the Disk
        echo -e "${BLUE}Installing $os_file on disk $os_disk!!${NC}"
        dd if=/dev/zero of="$os_disk" bs=1M count=500

        # Check if the OS image flash was successful
        if gzip -dc "$os_file" | dd of="$os_disk" bs=4M && sync; then
            success "Successfully Installed OS on the Disk $os_disk"
            umount /mnt
            partprobe "$os_disk" && sync
            blockdev --rereadpt "$os_disk"
	    udevadm settle --timeout=15
            sleep 5
        else
            failure "Failed to Install OS on the Disk $os_disk, please check!!"
            umount /mnt
            return 1
        fi
    else
        failure "OS image file not found in the USB, please check!!"
        umount /mnt
        return 1
    fi

    # Detect rootfs by extracting partition suffix from full device path
    rootfs_dev=$(blkid | grep -Ei 'cloudimg-rootfs|rootfs|ROOT' | awk -F: '{print $1}')
    if [ -z "$rootfs_dev" ]; then
        failure "Unable to detect rootfs partition from blkid output, please check!!"
        return 1
    fi

    # Extract partition suffix (p1, p2, 1, 2, etc.) by removing the os_disk prefix
    os_rootfs_part=$(echo "$rootfs_dev" | sed "s|^${os_disk}||")

    if [ -z "$os_rootfs_part" ]; then
        failure "Failed to parse rootfs partition from device $rootfs_dev, please check!!"
        return 1
    fi

    echo -e "${GREEN}Detected rootfs partition: ${os_disk}${os_rootfs_part}${NC}"

    return 0
}
# Attended MODE - User account creation with dialog
create_user_account() {
    echo -e "${BLUE}Create a new user account${NC}"
    TTY=/dev/tty1
    local TMPFILE=$(mktemp /tmp/dialog.XXXXXX)
    trap "rm -f '$TMPFILE'" RETURN
    
    # Ask if user wants to create an account 
    if ! dialog --title "User Account" \
        --yesno "Do you want to create a user account?\n\n(Select 'No' to skip if you have already created a user account)" \
        0 0 </dev/tty1 >/dev/tty1 2>"$TMPFILE"; then
        echo "User account creation skipped." >> $LOG
        return 0
    fi

    # Ask for username 
    while true; do
        if ! dialog --title "User Account" \
            --inputbox "Enter username:" 0 0 </dev/tty1 >/dev/tty1 2>"$TMPFILE"; then
            return 0
        fi
        
        USERNAME=$(cat "$TMPFILE")

        # Empty username
        if [ -z "$USERNAME" ]; then
            dialog --title "Error" --msgbox "Username cannot be empty!" \
                0 0 </dev/tty1 >/dev/tty1 2>/dev/null
            continue
        fi

        # Validate username (only lowercase, numbers, underscore, hyphen)
        if ! echo "$USERNAME" | grep -qE '^[a-z][a-z0-9_-]*$'; then
            dialog --title "Error" \
                --msgbox "Invalid username!\nMust start with a letter.\nOnly lowercase, numbers, _ and - allowed." \
                0 0 </dev/tty1 >/dev/tty1 2>/dev/null
            continue
        fi

        break 
    done

    # Ask password 
    while true; do
        # Enter password
        if ! dialog --title "User Account" \
            --passwordbox "Enter password for '$USERNAME':" 0 0 </dev/tty1 >/dev/tty1 2>"$TMPFILE"; then
            return 0
        fi
        PASSWORD=$(cat "$TMPFILE")

        # Confirm password
        if ! dialog --title "User Account" \
            --passwordbox "Confirm password for '$USERNAME':" 0 0 </dev/tty1 >/dev/tty1 2>"$TMPFILE"; then
            return 0
        fi
        PASSWORD_CONFIRM=$(cat "$TMPFILE")

        # Check empty
        if [ -z "$PASSWORD" ]; then
            dialog --title "Error" --msgbox "Password cannot be empty!" \
                0 0 </dev/tty1 >/dev/tty1 2>/dev/null
            continue
        fi

        # Check match
        if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
            dialog --title "Error" \
                --msgbox "Passwords do not match! Please try again." \
                0 0 </dev/tty1 >/dev/tty1 2>/dev/null
            continue
        fi

        break 
    done
    
    # Create user account inside the chroot environment of the installed OS
    check_mnt_mount_exist
    mount "$os_disk$os_rootfs_part" /mnt
    
    # Check if user already exists
    chroot /mnt /bin/bash <<EOT
id $USERNAME >/dev/null 2>&1
EOT
    
    if [ $? -eq 0 ]; then
        dialog --title "User Exists" \
            --msgbox "User '$USERNAME' already exists!" \
            0 0 </dev/tty1 >/dev/tty1 2>/dev/null
        echo "User $USERNAME already exists." >> $LOG
        return 0
    fi
    
    # Create user account if not exists
    chroot /mnt /bin/bash <<EOT
set -e
useradd -m -s /bin/bash $USERNAME && echo "$USERNAME:$PASSWORD" | chpasswd && echo '$USERNAME ALL=(ALL) NOPASSWD:ALL' | tee /etc/sudoers.d/$USERNAME
EOT
    
    if [ $? -eq 0 ]; then
        dialog --title "Success" \
            --msgbox "User '$USERNAME' created successfully!" \
            0 0 </dev/tty1 >/dev/tty1 2>/dev/null
        echo "User $USERNAME created successfully." >> $LOG
    else
        dialog --title "Error" \
            --msgbox "Failed to create user '$USERNAME'!\nCheck $LOG for details." \
            0 0 </dev/tty1 >/dev/tty1 2>/dev/null
        return 1
    fi
    clear >/dev/tty1
    return 0
}
# Attended MODE - Custom partition setup with dialog
create_partitions() {

    echo -e "${BLUE}Custom Partition Setup${NC}"
    TTY=/dev/tty1
    local tmpfile disk_total_mb rootfs_size_mb existing_partitions_mb free_mb free_gb rootfs_size_gb remaining_mb remaining_gb current_layout partition_num
    
    tmpfile=$(mktemp /tmp/dialog.XXXXXX)
    CUSTOM_PARTITIONS=""
    partition_num=1
    
    # Ask if user wants to create custom partitions or use default layout
    dialog --title "Partition Setup" \
        --yesno "Do you want to create custom partitions?\n\n(Select 'No' to use default layout)" \
        0 0 <$TTY >$TTY 2>/dev/null
    if [ $? -ne 0 ]; then
        log "Using default partition layout."
        rm -f "$tmpfile"
        return 0
    fi
    
    ROOTFS_PARTITION="${os_disk}${os_rootfs_part}"
    ROOTFS_PART_NUM=$(echo "$os_rootfs_part" | tr -dc '0-9')
    
    # Get total disk size
    disk_total_mb=$(parted -s "$USER_SELECTED_DISK" unit MB print 2>/dev/null | grep "^Disk" | cut -d: -f2 | tr -d 'MB ')
    # Get current rootfs partition size
    rootfs_size_mb=$(parted -s "$USER_SELECTED_DISK" unit MB print 2>/dev/null \
        | awk -v p="$ROOTFS_PART_NUM" '
            $1 == p {
                val=$4
                sub("MB","",val)
                split(val,a,".")
                print a[1]
            }')
   
    # Get the default partition sizes of existing partitions to calculate free space
    existing_partitions_mb=$(parted -s "$USER_SELECTED_DISK" unit MB print 2>/dev/null \
        | awk '
            $1 ~ /^[0-9]+$/ {
                val=$4
                sub("MB","",val)
                split(val,a,".")
                total+=a[1]
            }
            END {
                print total+0
            }')
    [ -z "$disk_total_mb" ] && disk_total_mb=0
    [ -z "$rootfs_size_mb" ] && rootfs_size_mb=0
    [ -z "$existing_partitions_mb" ] && existing_partitions_mb=0
   
    # Get free space available for partitioning
    free_mb=$((disk_total_mb - existing_partitions_mb))
    if [ "$free_mb" -lt 0 ]; then
        free_mb=0
    fi
    free_gb=$((free_mb / 1024))
    rootfs_size_gb=$((rootfs_size_mb / 1024))
    FREE_MB=$free_mb
    FREE_GB=$free_gb
    
    current_layout=$(parted -s "$USER_SELECTED_DISK" unit MB print 2>/dev/null)
    dialog \
        --title "Current Disk Layout — $USER_SELECTED_DISK" \
        --msgbox "$current_layout

─────────────────────────────────
Disk Size            : $((disk_total_mb / 1024))GB
Existing Partitions  : $((existing_partitions_mb / 1024))GB
Available Free Space : ${free_gb}GB

Current Rootfs Size  : ${rootfs_size_gb}GB

Rootfs Needs to be resized first to accommodate additional space." \
        0 0 <$TTY >$TTY 2>/dev/null
    while true; do
        dialog \
            --title "Resize Rootfs" \
            --inputbox "Current rootfs size : ${rootfs_size_gb}GB

Enter ADDITIONAL size in GB.

Example:
Current : 40
Input   : 20
Final   : 60

Available free space : ${free_gb}GB" \
            0 0 \
            <$TTY >$TTY 2>"$tmpfile"
        if [ $? -ne 0 ]; then
            rm -f "$tmpfile"
            return 1
        fi
        ROOTFS_ADDITIONAL_GB=$(cat "$tmpfile")
        if ! echo "$ROOTFS_ADDITIONAL_GB" | grep '^[0-9][0-9]*$' >/dev/null; then
            dialog --title "Error" \
                --msgbox "Enter valid numeric size." \
                0 0 <$TTY >$TTY 2>/dev/null
            continue
        fi
        ROOTFS_ADDITIONAL_MB=$((ROOTFS_ADDITIONAL_GB * 1024))
        if [ "$ROOTFS_ADDITIONAL_MB" -gt "$free_mb" ]; then
            dialog --title "Error" \
                --msgbox "Requested size exceeds available free space." \
                0 0 <$TTY >$TTY 2>/dev/null
            continue
        fi
        ROOTFS_FINAL_MB=$((rootfs_size_mb + ROOTFS_ADDITIONAL_MB))
        ROOTFS_FINAL_GB=$((ROOTFS_FINAL_MB / 1024))
        dialog \
            --title "Confirm Rootfs Resize" \
            --yesno "Resize rootfs from

        ${rootfs_size_gb}GB → ${ROOTFS_FINAL_GB}GB ?" \
            0 0 <$TTY >$TTY 2>/dev/null
        if [ $? -eq 0 ]; then
            CUSTOM_PARTITIONS="/ $ROOTFS_FINAL_MB ext4"
            FREE_MB=$((FREE_MB - ROOTFS_ADDITIONAL_MB))
            break
        fi
    done
    
    while true; do
        remaining_mb=$FREE_MB
        remaining_gb=$((remaining_mb / 1024))
        if [ "$remaining_mb" -le 0 ]; then
            dialog --title "Partition Setup" \
                --msgbox "No remaining free space available." \
                0 0 <$TTY >$TTY 2>/dev/null
            break
        fi
        
        # Partition type
        dialog \
            --title "Custom Partition Type — Slot $partition_num" \
            --menu "Choose partition type you want to create:" \
            0 0 0 \
            data "Data partition" \
            swap "Swap partition" \
            2>"$tmpfile" <$TTY >$TTY
        if [ $? -ne 0 ]; then
            break
        fi
        PART_TYPE=$(cat "$tmpfile")
        if [ "$PART_TYPE" = "swap" ]; then
            MOUNTPOINT="swap"
        else
            while true; do
                dialog \
                    --title "Partition $partition_num — Mount Point" \
                    --inputbox "Enter mount point
Examples:
/home
/data
/var

Leave empty to finish." \
                    0 0 \
                    <$TTY >$TTY 2>"$tmpfile"
                if [ $? -ne 0 ]; then
                    break 2
                fi
                MOUNTPOINT=$(cat "$tmpfile")
                [ -z "$MOUNTPOINT" ] && break 2
                if ! echo "$MOUNTPOINT" \
                    | grep '^/[a-zA-Z0-9/_-]*$' >/dev/null; then
                    dialog --title "Error" \
                        --msgbox "Invalid mount point." \
                        0 0 <$TTY >$TTY 2>/dev/null
                    continue
                fi
                # Duplicate check
                if echo "$CUSTOM_PARTITIONS" \
                    | awk '{print $1}' \
                    | grep -x "$MOUNTPOINT" >/dev/null; then
                    dialog --title "Error" \
                        --msgbox "Mount point already exists." \
                        0 0 <$TTY >$TTY 2>/dev/null
                    continue
                fi
                break
            done
        fi
       
        # Partition size
        while true; do
            remaining_mb=$FREE_MB
            remaining_gb=$((remaining_mb / 1024))
            dialog \
                --title "Partition $partition_num — Size" \
                --inputbox "Enter partition size in GB

Remaining free space : ${remaining_gb}GB" \
                0 0 \
                <$TTY >$TTY 2>"$tmpfile"
            if [ $? -ne 0 ]; then
                break 2
            fi
            PART_SIZE_GB=$(cat "$tmpfile")
            if ! echo "$PART_SIZE_GB" \
                | grep '^[0-9][0-9]*$' >/dev/null; then
                dialog --title "Error" \
                    --msgbox "Invalid numeric size." \
                    0 0 <$TTY >$TTY 2>/dev/null
                continue
            fi
            if [ "$PART_SIZE_GB" -le 0 ]; then
                dialog --title "Error" \
                    --msgbox "Size must be greater than 0." \
                    0 0 <$TTY >$TTY 2>/dev/null
                continue
            fi
            PART_SIZE_MB=$((PART_SIZE_GB * 1024))
            if [ "$PART_SIZE_MB" -gt "$remaining_mb" ]; then
                dialog --title "Error" \
                    --msgbox "Partition exceeds remaining free space." \
                    0 0 <$TTY >$TTY 2>/dev/null
                continue
            fi
            break
        done
       
        if [ "$PART_TYPE" = "swap" ]; then
            FSTYPE="swap"
        else
            dialog \
                --title "Partition $partition_num — Filesystem" \
                --menu "Choose filesystem:" \
                0 0 0 \
                ext4  "Standard Linux filesystem" \
                xfs   "High performance filesystem" \
                btrfs "Snapshot capable filesystem" \
                vfat  "FAT32 filesystem" \
                <$TTY >$TTY 2>"$tmpfile"
            if [ $? -ne 0 ]; then
                break 2
            fi
            FSTYPE=$(cat "$tmpfile")
        fi
        if [ "$PART_TYPE" = "swap" ]; then
            CONFIRM_MSG="Add swap partition?

Size : ${PART_SIZE_GB}GB"
        else
            CONFIRM_MSG="Add partition?

Mount Point : $MOUNTPOINT
Size        : ${PART_SIZE_GB}GB
Filesystem  : $FSTYPE"
        fi
        dialog \
            --title "Confirm Partition $partition_num" \
            --yesno "$CONFIRM_MSG" \
            0 0 <$TTY >$TTY 2>/dev/null
        if [ $? -ne 0 ]; then
            continue
        fi
        CUSTOM_PARTITIONS="$CUSTOM_PARTITIONS
$MOUNTPOINT $PART_SIZE_MB $FSTYPE"
        FREE_MB=$((FREE_MB - PART_SIZE_MB))
        partition_num=$((partition_num + 1))
        remaining_mb=$FREE_MB
        remaining_gb=$((remaining_mb / 1024))
        dialog \
            --title "Partition Setup" \
            --yesno "Partition added.

Remaining free space : ${remaining_gb}GB

Add another partition?" \
            0 0 <$TTY >$TTY 2>/dev/null
        if [ $? -ne 0 ]; then
            break
        fi
    done
    
    # Show summary of partitions to be created and confirm before applying
    if [ -n "$CUSTOM_PARTITIONS" ]; then
        SUMMARY=""
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            MP=$(echo "$line" | awk '{print $1}')
            SZ=$(echo "$line" | awk '{print $2}')
            FS=$(echo "$line" | awk '{print $3}')
            SZ_GB=$((SZ / 1024))
            if [ "$MP" = "/" ]; then
                SUMMARY="${SUMMARY}$(printf '%-12s : %6sGB  %s\n' 'rootfs' "$SZ_GB" "$FS")\n"
            elif [ "$FS" = "swap" ]; then
                SUMMARY="${SUMMARY}$(printf '%-12s : %6sGB  %s\n' '[swap]' "$SZ_GB" 'swap')\n"
            else
                SUMMARY="${SUMMARY}$(printf '%-12s : %6sGB  %s\n' "$MP" "$SZ_GB" "$FS")\n"
            fi
        done <<EOF
$CUSTOM_PARTITIONS
EOF
        dialog \
            --title "Final Partition Layout — $USER_SELECTED_DISK" \
            --yesno "Review partition layout:

$SUMMARY

Proceed with partitioning?" \
            0 0 <$TTY >$TTY 2>/dev/null
        if [ $? -ne 0 ]; then
            dialog \
                --title "Partition Setup" \
                --yesno "Do you want to restart partition setup?" \
                0 0 <$TTY >$TTY 2>/dev/null
            if [ $? -eq 0 ]; then
                rm -f "$tmpfile"
                CUSTOM_PARTITIONS=""
                create_partitions
                return $?
            else
                CUSTOM_PARTITIONS=""
                rm -f "$tmpfile"
                return 0
            fi
        fi
        apply_partitions || {
            rm -f "$tmpfile"
            return 1
        }
    fi
    rm -f "$tmpfile"
    return 0
}

apply_partitions() {
    echo -e "${BLUE}Applying custom partitions on $USER_SELECTED_DISK${NC}"

    # Fix the disk label if needed to avoid parted errors when modifying partitions    
    echo "Fix" | parted ---pretend-input-tty "$USER_SELECTED_DISK" print

    sgdisk -e "$USER_SELECTED_DISK"

    # Prepare fstab entries for new partitions
    FSTAB_ENTRIES=""
    PARTITION_NUM_LIST=""
    
    # Loop through collected partitions
    START_MB=$(parted -s "$USER_SELECTED_DISK" unit MB print \
        | awk '/^ [0-9]/ {print $3}' \
        | tr -d 'MB' \
        | sort -n \
        | tail -1)
    START_MB=${START_MB:-1}

    while IFS= read -r line; do
        [ -z "$line" ] && continue

        MP=$(echo "$line" | awk '{print $1}')
        SZ=$(echo "$line" | awk '{print $2}')
        FS=$(echo "$line" | awk '{print $3}')
        END_MB=$((START_MB + SZ))

        # Handle rootfs resize (when MP is "/" and it's the first entry)
        if [ "$MP" = "/" ]; then
            echo "Resizing rootfs partition to ${SZ}MB"
            ROOTFS_PART_NUM=$(parted -s "$USER_SELECTED_DISK" print \
                | awk '/^ [0-9]/ {print $1}' \
                | sort -n \
                | tail -1)
            if [ -n "$ROOTFS_PART_NUM" ]; then
                ROOTFS_START=$(parted -s "$USER_SELECTED_DISK" unit MB print \
                    | awk "/ $ROOTFS_PART_NUM / {print \$2}" \
                    | tr -d 'MB')
                ROOTFS_NEW_END=$((ROOTFS_START + SZ))
                parted -s "$USER_SELECTED_DISK" resizepart "$ROOTFS_PART_NUM" "${ROOTFS_NEW_END}MB" 2>/dev/null || true
                resize2fs "${USER_SELECTED_DISK}${ROOTFS_PART_NUM}" 2>/dev/null || true
                blockdev --rereadpt "$USER_SELECTED_DISK" 2>/dev/null || true
                sleep 1
                START_MB=$ROOTFS_NEW_END
            fi
        else
            # Create new partition
            echo "Creating partition: $MP ${START_MB}MB → ${END_MB}MB ($FS)"

            # Add partition without touching existing ones
            parted -s "$USER_SELECTED_DISK" mkpart primary \
                "${START_MB}MB" "${END_MB}MB" 

            # Get the new partition number
            PART_NUM=$(parted -s "$USER_SELECTED_DISK" print \
                | awk '/^ [0-9]/ {print $1}' \
                | sort -n \
                | tail -1)

            # Construct partition path
            PART_PATH="${USER_SELECTED_DISK}${PART_NUM}"
            if [[ "$USER_SELECTED_DISK" == *"nvme"* ]]; then
                PART_PATH="${USER_SELECTED_DISK}p${PART_NUM}"
            fi

            # Format
            case "$FS" in
                ext4)  mkfs.ext4  -F "$PART_PATH"  ;;
                xfs)   mkfs.xfs   -f "$PART_PATH"  ;;
                btrfs) mkfs.btrfs -f "$PART_PATH"  ;;
                vfat)  mkfs.vfat     "$PART_PATH"  ;;
                swap)
                    mkswap "$PART_PATH" 
                    blockdev --rereadpt ${USER_SELECTED_DISK}
                    swapon "$PART_PATH" 
                    ;;
            esac

            echo " Created $PART_PATH → $MP (${SZ}MB $FS)"
            PARTITION_NUM_LIST="${PARTITION_NUM_LIST}${PART_NUM} "

            # Generate fstab entry 
            PART_UUID=$(blkid -s UUID -o value "$PART_PATH")
            if [ -z "$PART_UUID" ]; then
                PART_UUID="$PART_PATH"
            fi
            
            if [ "$FS" = "swap" ]; then
                FSTAB_ENTRIES="${FSTAB_ENTRIES}UUID=$PART_UUID none swap sw 0 0"$'\n'
            else
                MOUNT_OPTS="defaults"
                if [ "$FS" = "xfs" ]; then
                    MOUNT_OPTS="defaults,relatime"
                fi
                FSTAB_ENTRIES="${FSTAB_ENTRIES}UUID=$PART_UUID $MP $FS $MOUNT_OPTS 0 2"$'\n'
            fi

            START_MB=$END_MB
        fi

    done <<< "$CUSTOM_PARTITIONS"

    # Verify all created partitions exist
    echo "Verifying all partitions created by user..."
    RETRY_COUNT=0
    MAX_RETRIES=5
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        ALL_EXIST=true
        if [ -z "$PARTITION_NUM_LIST" ]; then
            echo "No partitions created. PARTITION_NUM_LIST is empty"
            ALL_EXIST=true
        else
            for PNUM in $PARTITION_NUM_LIST; do
                PART_PATH="${USER_SELECTED_DISK}${PNUM}"
                if [[ "$USER_SELECTED_DISK" == *"nvme"* ]]; then
                    PART_PATH="${USER_SELECTED_DISK}p${PNUM}"
                fi
                if [ ! -b "$PART_PATH" ]; then
                    ALL_EXIST=false
                    break
                fi
            done
        fi
        
        if [ "$ALL_EXIST" = false ]; then
            echo "Not all partitions found. Retrying..."
            umount "${USER_SELECTED_DISK}"* 2>/dev/null || true
            blockdev --rereadpt "$USER_SELECTED_DISK" 2>/dev/null || blockdev --flushbufs "$USER_SELECTED_DISK" 2>/dev/null || true
            sleep 2
            ((RETRY_COUNT++))
        else
            echo "All partitions verified successfully"
            break
        fi
    done
    
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "Warning: Could not verify all partitions after $MAX_RETRIES retries"
        return 1
    fi

    # Add fstab entries to target system
    if [ -n "$FSTAB_ENTRIES" ]; then
        check_mnt_mount_exist
        if mount "$os_disk$os_rootfs_part" /mnt 2>/dev/null; then
            if [ -f /mnt/etc/fstab ]; then
                echo "Adding new partition entries to /etc/fstab"
                echo -e "$FSTAB_ENTRIES" >> /mnt/etc/fstab
                
                if [ $? -eq 0 ]; then
                    success "fstab entries added successfully"
                else
                    error "Failed to write fstab entries"
                    return 1
                fi
            else
                error "/mnt/etc/fstab not found"
                return 1
            fi
            umount /mnt 2>/dev/null || true
        else
            error "Failed to mount $os_disk$os_rootfs_part at /mnt"
        fi
    fi

    if [ "$?" -eq 0 ]; then 

    dialog \
        --title "Partitioning Complete" \
        --msgbox "All partitions created successfully!.\nfstab entries added for new partitions." \
        0 0 <$TTY >$TTY 2>/dev/null
    else

    dialog \
        --title "Partitioning Creation Failed" \
        --msgbox "Partition Creation Failed,please check!!" \
        0 0 <$TTY >$TTY 2>/dev/null
        return 1
    fi
     clear >/dev/tty1
    return 0
}
# Install cloud-init file on OS
install_cloud_init_file() {

    # Copy the cloud init file from Hook OS to target OS
    echo -e "${BLUE}Installing the Cloud-init file!!${NC}" 


    CLOUD_INIT_FILE="/etc/scripts/cloud-init.yaml"
    if ! custom_cloud_init_updates; then
        return 1
    fi
    sync
    check_mnt_mount_exist
    mount "$os_disk$os_rootfs_part" /mnt
    if cp /mnt/etc/cloud/cloud-init.yaml /mnt/etc/cloud/cloud.cfg.d/installer.cfg && chmod +x /mnt/etc/cloud/cloud.cfg.d/installer.cfg; then
        success "Successfully copied the cloud-init file"
	rm /mnt/etc/cloud/cloud-init.yaml
    else
        failure "Fail to copy the cloud-init file,please check!!!"
        umount /mnt
        return 1 
    fi

    # Create the cloud-init Dsi identity
    rm /mnt/etc/cloud/ds-identify.cfg
    touch /mnt/etc/cloud/ds-identify.cfg
    echo "policy: enabled" > /mnt/etc/cloud/ds-identify.cfg
    echo "datasource: NoCloud" >> /mnt/etc/cloud/ds-identify.cfg
    chmod 600 /mnt/etc/cloud/ds-identify.cfg

    umount /mnt
    return 0
}

# Update the Proxy settings under /etc/environment
setup_proxy_settings() {
    echo -e "${BLUE}Set the Proxy Settings!!${NC}"

    mount -o ro "${usb_disk}${USER_CONF_PART}" /tmp

    # Mount the OS disk
    check_mnt_mount_exist
    mount "${os_disk}${os_rootfs_part}" /mnt
    if cp /tmp/config-file /mnt/etc/cloud/; then

        CONFIG_FILE="/mnt/etc/cloud/config-file"

        # Read a variable from config-file, stripping surrounding quotes.
        # Returns empty string if the variable is not present or set to "".
        read_cfg() {
            grep "^${1}=" "$CONFIG_FILE" | cut -d'=' -f2- | sed 's/^"//; s/"$//'
        }

        # Write VAR=value into a file.
        # If the variable already exists (any value), replace it in-place.
        # If not present, append it.  Always written – even when value is empty –
        # so stale baked-in proxy values are overwritten with the config-file value.
        set_proxy_var() {
            local var="$1" val="$2" file="$3"
            if grep -q "^${var}=" "$file"; then
                sed -i "s|^${var}=.*|${var}=${val}|" "$file"
            else
                echo "${var}=${val}" >> "$file"
            fi
        }

        # Read all proxy variables from config-file
        http_proxy=$(read_cfg http_proxy)
        https_proxy=$(read_cfg https_proxy)
        no_proxy=$(read_cfg no_proxy)
        HTTP_PROXY=$(read_cfg HTTP_PROXY)
        HTTPS_PROXY=$(read_cfg HTTPS_PROXY)
        NO_PROXY=$(read_cfg NO_PROXY)

	# Apply to /etc/environment – replace stale entries or append.
        # Also handle socks_server and ftp_proxy which are baked into the image
        # by both the QEMU (auto-install-pkgs.yaml) and ICT build paths but are
        # not sourced from config-file.  Derive their values from http_proxy so
        # they stay consistent; clear them when http_proxy is empty.
        ftp_proxy="$http_proxy"
        socks_server=""

        if [ -n "$http_proxy" ] || [ -n "$https_proxy" ] || [ -n "$no_proxy" ]; then
            proxy_settings="true"
        else
            proxy_settings="false"
        fi
         
        # Apply to /etc/environment – replace stale entries or append
        ENV_FILE="/mnt/etc/environment"
        # Deduplicate: remove all existing proxy lines first, then write once
        sed -i '/^\(http_proxy\|https_proxy\|no_proxy\|HTTP_PROXY\|HTTPS_PROXY\|NO_PROXY\|ftp_proxy\|FTP_PROXY\|socks_server\)=/d' "$ENV_FILE"
        for var in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY ftp_proxy socks_server; do
            echo "${var}=${!var}" >> "$ENV_FILE"
        done

        # Update /etc/apt/apt.conf.d/99proxy.conf if it exists (baked by ICT build)
        APT_PROXY_CONF="/mnt/etc/apt/apt.conf.d/99proxy.conf"
        if [ -f "$APT_PROXY_CONF" ]; then
            if [ -n "$http_proxy" ]; then
                cat > "$APT_PROXY_CONF" <<EOF
Acquire::http::Proxy "${http_proxy}";
Acquire::https::Proxy "${https_proxy}";
EOF
            else
                # No proxy configured – remove the file so APT uses direct connections
                rm -f "$APT_PROXY_CONF"
            fi
            success "APT proxy config updated from config-file"
        fi

        # Apply the same values to k3s.service.env if k3s is installed in the image
        K3S_ENV_FILE="/mnt/etc/systemd/system/k3s.service.env"
        if [ -f "$K3S_ENV_FILE" ]; then
            sed -i '/^\(http_proxy\|https_proxy\|no_proxy\|HTTP_PROXY\|HTTPS_PROXY\|NO_PROXY\|ftp_proxy\|socks_server\)=/d' "$K3S_ENV_FILE"
            for var in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
                echo "${var}=${!var}" >> "$K3S_ENV_FILE"
            done
            success "K3s proxy settings updated from config-file"
        fi

        umount /mnt
        umount /tmp
        success "Proxy Settings updated"
        return 0
    else
        umount /mnt
        umount /tmp
        failure "Proxy Settings Failed"
        return 1
    fi
}
# Ask for proxy settings in Attended MODE with dialog
ask_for_proxy_settings(){
    echo -e "${BLUE}Configure Proxy Settings (Optional)${NC}"
    TTY=/dev/tty1
    local TMPFILE=$(mktemp /tmp/dialog.XXXXXX)
    trap "rm -f '$TMPFILE'" RETURN

    dialog --title "Proxy Configuration" \
        --yesno "Do you want to configure proxy settings?" \
        0 0 </dev/tty1 >/dev/tty1 2>"$TMPFILE"

    if [ $? -ne 0 ]; then
        echo "Proxy configuration skipped." 
        return 0
    fi

    # Ask for HTTP_PROXY
    while true; do
        dialog --title "Proxy Configuration" \
            --inputbox "Enter HTTP proxy URL (e.g. http://proxy.example.com:8080):" \
            0 0 </dev/tty1 >/dev/tty1 2>"$TMPFILE"

        if [ $? -ne 0 ]; then
            echo "HTTP proxy configuration skipped." 
            return 0
        fi

        HTTP_PROXY=$(cat "$TMPFILE")
        
        if [ -z "$HTTP_PROXY" ]; then
            dialog --title "Proxy Configuration" \
                --yesno "No HTTP proxy value provided. Continue without HTTP proxy?" \
                0 0 </dev/tty1 >/dev/tty1 2>&1
            if [ $? -eq 0 ]; then
                break
            fi
        else
            break
        fi
    done

    # Ask for HTTPS_PROXY
    while true; do
        dialog --title "Proxy Configuration" \
            --inputbox "Enter HTTPS proxy URL (e.g. https://proxy.example.com:8080):" \
            0 0 </dev/tty1 >/dev/tty1 2>"$TMPFILE"

        if [ $? -ne 0 ]; then
            echo "HTTPS proxy configuration skipped." 
            return 0
        fi

        HTTPS_PROXY=$(cat "$TMPFILE")
        
        if [ -z "$HTTPS_PROXY" ]; then
            dialog --title "Proxy Configuration" \
                --yesno "No HTTPS proxy value provided. Continue without HTTPS proxy?" \
                0 0 </dev/tty1 >/dev/tty1 2>&1
            if [ $? -eq 0 ]; then
                break
            fi
        else
            break
        fi
    done

    # Ask for FTP_PROXY
    while true; do
        dialog --title "Proxy Configuration" \
            --inputbox "Enter FTP proxy URL (e.g. ftp://proxy.example.com:8080):" \
            0 0 </dev/tty1 >/dev/tty1 2>"$TMPFILE"

        if [ $? -ne 0 ]; then
            echo "FTP proxy configuration skipped."
            break
        fi

        FTP_PROXY=$(cat "$TMPFILE")
        
        if [ -z "$FTP_PROXY" ]; then
            dialog --title "Proxy Configuration" \
                --yesno "No FTP proxy value provided. Continue without FTP proxy?" \
                0 0 </dev/tty1 >/dev/tty1 2>&1
            if [ $? -eq 0 ]; then
                break
            fi
        else
            break
        fi
    done

    # Ask for SOCKS_SERVER
    while true; do
        dialog --title "Proxy Configuration" \
            --inputbox "Enter SOCKS server (e.g. socks5://proxy.example.com:1080):" \
            0 0 </dev/tty1 >/dev/tty1 2>"$TMPFILE"

        if [ $? -ne 0 ]; then
            echo "SOCKS server configuration skipped." 
            break
        fi

        SOCKS_SERVER=$(cat "$TMPFILE")
        
        if [ -z "$SOCKS_SERVER" ]; then
            dialog --title "Proxy Configuration" \
                --yesno "No SOCKS server value provided. Continue without SOCKS server?" \
                0 0 </dev/tty1 >/dev/tty1 2>&1
            if [ $? -eq 0 ]; then
                break
            fi
        else
            break
        fi
    done

    # Ask for NO_PROXY
    while true; do
        dialog --title "Proxy Configuration" \
            --inputbox "Enter NO_PROXY domains (comma-separated, e.g. localhost,127.0.0.1):" \
            0 0 </dev/tty1 >/dev/tty1 2>"$TMPFILE"

        if [ $? -ne 0 ]; then
            echo "NO_PROXY configuration skipped." 
            return 0
        fi

        NO_PROXY=$(cat "$TMPFILE")
        
        if [ -z "$NO_PROXY" ]; then
            dialog --title "Proxy Configuration" \
                --yesno "No NO_PROXY value provided. Continue without NO_PROXY?" \
                0 0 </dev/tty1 >/dev/tty1 2>&1
            if [ $? -eq 0 ]; then
                break
            fi
        else
            break
        fi
    done
    # Save to a temporary file for later use
    {
        echo "http_proxy=\"$HTTP_PROXY\""
        echo "https_proxy=\"$HTTPS_PROXY\""
        [ -n "$FTP_PROXY" ] && echo "ftp_proxy=\"$FTP_PROXY\""
        [ -n "$SOCKS_SERVER" ] && echo "socks_server=\"$SOCKS_SERVER\""
        echo "no_proxy=\"$NO_PROXY\""
    } > "$TMPFILE"

    # Mount the rootfs and add proxy settings to /etc/environment
    check_mnt_mount_exist
    mount "${os_disk}${os_rootfs_part}" /mnt
    cat "$TMPFILE" >> /mnt/etc/environment
    if [ $? -ne 0 ]; then
        dialog --title "Error" \
            --msgbox "Failed to save proxy settings to /etc/environment" \
            0 0 </dev/tty1 >/dev/tty1 2>&1
        failure "Failed to save proxy settings to /etc/environment"
        umount /mnt
        clear >/dev/tty1
        return 1
    fi
    umount /mnt
    dialog --title "Success" \
        --msgbox "Proxy settings saved and will be applied on first boot" \
        0 0 </dev/tty1 >/dev/tty1 2>&1
    success "Proxy settings saved and will be applied on first boot"
    clear >/dev/tty1
    return 0    
}
    

# Update  SSH config settings
update_ssh_settings() {
    echo -e "${BLUE}Updating the SSH Settings!!${NC}" 

    # Mount the OS disk
    check_mnt_mount_exist
    mount "${os_disk}${os_rootfs_part}" /mnt

    CONFIG_FILE="/mnt/etc/cloud/config-file"

    # Get the lvm_size_ingb from config-file for creating the LVM
    lvm_size=$(grep '^lvm_size_ingb=' "$CONFIG_FILE" | cut -d '=' -f2)
    lvm_size=$(echo "$lvm_size" | tr -d '"')

    # Check the deployment mode, is it for VM or Real hardware
    deploy_mode=$(grep '^deploy_envmt=' "$CONFIG_FILE" | cut -d '=' -f2)
    deploy_mode=$(echo "$deploy_mode" | tr -d '"')

    # SSH Configure
    if grep -q '^ssh_key=' "$CONFIG_FILE"; then
	ssh_key=$(sed -n 's/^ssh_key="\?\(.*\)\?"$/\1/p' "$CONFIG_FILE")
	user_name=$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "nobody" && $7 !~ /(nologin|false|sync)/ {print $1; exit}' /mnt/etc/passwd)
        # Write the SSH key to authorized_keys
        if [ -z "$ssh_key" ]; then
            echo "No SSH Key provided skipping the ssh configuration"
        else
            chroot /mnt /bin/bash <<EOT
        set -e
        # Configure the SSH for the user $user_name
        su - $user_name 
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
	cat <<EOF >> ~/.ssh/authorized_keys
$ssh_key
EOF
        chmod 600 ~/.ssh/authorized_keys
        # export the /etc/environment values to .bashrc
	echo "source /etc/environment" >> /home/$user_name/.bashrc
        #exit the su -$user_name
        exit
EOT
            # shellcheck disable=SC2181
            if [ "$?" -eq 0 ]; then
                success "SSH-KEY Configuration Success"
            else
                failure "SSH-KEY Configuration Failure!!"
                return 1 
            fi
        fi
    fi
    umount /mnt
    return 0
}

# Copy provisioning scripts from hook OS to target disk.
# Hook OS bundles scripts at /etc/scripts/ (via hook-os.yaml).
# They are staged on the target at /opt/edge/scripts/ so cloud-init
# can call them on first boot.
copy_scripts_to_target() {
    echo -e "${BLUE}Copying provisioning scripts to target disk!!${NC}"

    check_mnt_mount_exist
    mount "$os_disk$os_rootfs_part" /mnt

    SOURCE_SCRIPTS_DIR="/etc/scripts"
    TARGET_SCRIPTS_DIR="/mnt/opt/edge/scripts"

    if [ -d "$SOURCE_SCRIPTS_DIR" ]; then
        mkdir -p "$TARGET_SCRIPTS_DIR"
        cp -a "${SOURCE_SCRIPTS_DIR}/." "$TARGET_SCRIPTS_DIR/"
	find "$TARGET_SCRIPTS_DIR" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
        success "Provisioning scripts copied to target /opt/edge/scripts/"
    else
        echo "WARNING: ${SOURCE_SCRIPTS_DIR} not found in hook OS — scripts will not be installed"
    fi
    umount /mnt
    return 0
}

# Dynamically update the cloud-init file based on User configuration and host type
custom_cloud_init_updates() {
    echo -e "${BLUE}Updating the cloud-init file !${NC}"

    # Get the custom details from config-file
    # Mount the OS disk
    check_mnt_mount_exist
    mount "$os_disk$os_rootfs_part" /mnt

    CONFIG_FILE="/mnt/etc/cloud/config-file"

    # Check the host type and update cloud-init accordingly
    host_type=$(grep '^host_type=' "$CONFIG_FILE" | cut -d '=' -f2)
    host_type=$(echo "$host_type" | tr -d '"')
    user=$(awk -F: '$3 >= 1000 && $3 < 60000 && $6 ~ /^\/home\// && $7 !~ /nologin|false/ {print $1; exit}' /mnt/etc/passwd)

    # Update cloud-init file to start k3s stack installations for hosty type kubernetes
    if [ "$host_type" == "kubernetes" ]; then
    
        #############################################################
        # User can add as many commands as they wish under NEW_LINES
        # to EOF section.
        # Example:
        #
        # bash /usr/local/bin/test.sh
        # systemctl stop docker
        #
        ############################################################
	NEW_LINES=$(cat <<EOF

       cp /etc/rancher/k3s/k3s.yaml /home/$user/.kube/config && chown -R $user:$user /home/$user/.kube && chmod 600 /home/$user/.kube/config
       systemctl stop docker
       systemctl disable docker
       bash /opt/edge/scripts/kubernetes-provision.sh
       bash /opt/edge/scripts/setup-kernel-depended-pkgs.sh
EOF
)
        awk -v new_lines="$NEW_LINES" '
        BEGIN {
            in_runcmd = 0
            in_block = 0
            block_indent = "    "
            n = split(new_lines, lines, "\n")
        }

        /^runcmd:/ { in_runcmd = 1 }

        /^[^[:space:]]/ {
        if ($0 !~ /^runcmd:/) in_runcmd = 0
        }

        in_runcmd && /^  - \|/ {
        in_block = 1
        }

        {
            print
        }
	# Insert right after ". /etc/environment"
        in_block && $0 ~ /^[[:space:]]*\. \/etc\/environment/ {
        for (i = 1; i <= n; i++) {
            if (lines[i] != "")
                print block_indent lines[i]
            }
        inserted=1
        }

        END {
        # fallback: if pattern not found, append at end of block
        if (in_block && !inserted) {
            for (i = 1; i <= n; i++) {
                if (lines[i] != "")
                    print block_indent lines[i]
                }
            }
        }
        ' "$CLOUD_INIT_FILE" > "/mnt/etc/cloud/cloud-init.yaml.tmp" && mv "/mnt/etc/cloud/cloud-init.yaml.tmp" "/mnt/etc/cloud/cloud-init.yaml"

	
    elif [ "$host_type" == "container" ]; then
	  #############################################################
        # User can add as many commands as they wish under NEW_LINES
        # to EOF section.
        # Example:
        #
        # bash /usr/local/bin/test.sh
        # systemctl stop docker
        #
        ############################################################
         # Docker configuration
	  NEW_LINES=$(cat <<EOF
         systemctl disable k3s
         systemctl stop k3s
         bash /opt/edge/scripts/container-provision.sh
	 bash /opt/edge/scripts/setup-kernel-depended-pkgs.sh
EOF
)
         awk -v new_lines="$NEW_LINES" '
         BEGIN {
            in_runcmd = 0
            in_block = 0
            block_indent = "    "
            n = split(new_lines, lines, "\n")
        }

        /^runcmd:/ { in_runcmd = 1 }

        /^[^[:space:]]/ {
        if ($0 !~ /^runcmd:/) in_runcmd = 0
        }

        in_runcmd && /^  - \|/ {
        in_block = 1
        }

        {
            print
        }

        # Insert right after ". /etc/environment"
        in_block && $0 ~ /^[[:space:]]*\. \/etc\/environment/ {
        for (i = 1; i <= n; i++) {
            if (lines[i] != "")
                print block_indent lines[i]
            }
        inserted=1
        }
	END {
        # fallback: if pattern not found, append at end of block
        if (in_block && !inserted) {
            for (i = 1; i <= n; i++) {
                if (lines[i] != "")
                    print block_indent lines[i]
                }
            }
        }
         ' "$CLOUD_INIT_FILE" > "/mnt/etc/cloud/cloud-init.yaml.tmp" && mv "/mnt/etc/cloud/cloud-init.yaml.tmp" "/mnt/etc/cloud/cloud-init.yaml"
	  # Update the Docker proxy settings
         # Mount the OS disk
         check_mnt_mount_exist
         mount "$os_disk$os_rootfs_part" /mnt
         mount --bind /proc /mnt/proc
         mount --bind /sys /mnt/sys
         # Enable the docker service first
         chroot /mnt /bin/bash <<EOT
         set -e
         systemctl enable docker
EOT
         # shellcheck disable=SC2181
         if [ "$?" -eq 0 ]; then
             success "Enabled the docker services"
         else
             failure "Failed to enable the docker services"
             umount  /mnt/proc
             umount  /mnt/sys
             umount /mnt
             return 1
         fi
         umount  /mnt/proc
         umount  /mnt/sys
	 export docker_proxy_file=/mnt/etc/systemd/system/docker.service.d/proxy.conf
         if [ ! -d $docker_proxy_file ]; then
               #create the docker service directory
               mkdir -p /mnt/etc/systemd/system/docker.service.d
               http_proxy_val=$(grep -i '^http_proxy=' /mnt/etc/environment | head -n1 | cut -d= -f2- | tr -d '"')
               export http_proxy_val
               https_proxy_val=$(grep -i '^https_proxy=' /mnt/etc/environment | head -n1 | cut -d= -f2- | tr -d '"')
               export https_proxy_val
               no_proxy_val=$(grep -i '^no_proxy=' /mnt/etc/environment | head -n1 | cut -d= -f2- | tr -d '"')
               export no_proxy_val

               bash -c 'echo "[Service]" >> $docker_proxy_file'
               bash -c 'echo "Environment=\"HTTP_PROXY=${http_proxy_val}\"" >> $docker_proxy_file'
               bash -c 'echo "Environment=\"HTTPS_PROXY=${https_proxy_val}\"" >> $docker_proxy_file'
               bash -c 'echo "Environment=\"NO_PROXY=${no_proxy_val}\"" >> $docker_proxy_file'
         fi
         chroot /mnt /bin/bash <<EOT
         set -e
         # Configure the docker proxy for the user $user_name
         su - $user
         mkdir -p ~/.docker
         chmod 755 ~/.docker
         cat <<EOF >> ~/.docker/config.json
         {
        "proxies":
 {
  "default":
  {
   "httpProxy": "$http_proxy_val",
   "httpsProxy": "$https_proxy_val",
    "noProxy": "$no_proxy_val"
  }
 }
}
EOF
    chmod 660 ~/.docker/config.json
     # exit the su - $user
        exit
EOT
        # shellcheck disable=SC2181
        if [ "$?" -eq 0 ]; then
            success "docker proxy services updated successfully"
        else
            failure "Failed to updated the docker proxy settings"
            umount /mnt
            return 1
        fi
        umount /mnt
    fi
}

# Change the boot order to disk
boot_order_change_to_disk() {
    echo -e "${BLUE}Changing the Boot order to disk!!${NC}"
    boot_order=$(efibootmgr -D)
    echo $boot_order
    usb_boot_number=$(efibootmgr | grep -i "Bootcurrent" | awk '{print $2}')

    boot_order=$(efibootmgr | grep -i "Bootorder" | awk '{print $2}')

    # Convert boot_order to an array and remove , between the entries
    IFS=',' read -ra boot_order_array <<< "$boot_order"

    # Remove PXE boot entry from Array
    final_boot_array=()
    for element in "${boot_order_array[@]}"; do
        if [[ "$element" != "$usb_boot_number" ]]; then
            final_boot_array+=("$element")
        fi
    done

    # Add the USB  boot entry to the end of the boot order array
    final_boot_array+=("$usb_boot_number")

    # Join the elements of boot_order_array into a comma-separated string
    final_boot_order=$(IFS=,; echo "${final_boot_array[*]}")

    #remove trail and leading , if preset
    final_boot_order=$(echo "$final_boot_order" | sed -e  's/^,//;s/,$//' )

    echo "final_boot order--->" $final_boot_order

    # Update the boot order using efibootmgr
    efibootmgr -o "$final_boot_order"
    return 0
}

# Create OS Partitions
# For now we are going with a default partition layout for OS disk with rootfs and boot partition, but this can be enhanced in future.
create_os-partition() {
    echo -e "${BLUE}Creating the OS Partitions on disk $os_disk!!${NC}"
    #os_partition_script=/etc/scripts/os-partition.sh

    #if bash $os_partition_script "$lvm_size";  then
    #    success "OS Partitions successful on $os_disk"
    #else
    #    failure "OS Partitions failed on $os_disk,Please check!!"
    #    return 1
    #fi
    return 0

}

# Ask for confirmation to reboot the system after provisioning is done in Attended MODE 
ask_confirmation_for_reboot() {
    TTY=/dev/tty1
    dialog --title "Reboot Confirmation" \
        --yesno "Provisioning completed successfully! Do you want to reboot now?" \
        0 0 </dev/tty1 >/dev/tty1 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "Rebooting system..."
        return 0
    else
        echo "Please remember to reboot the system as soon as possible to complete the provisioning process."
        clear >/dev/tty1
        drop_to_shell
        
     fi 
}

# Check provision pre-conditions
system_readiness_check() {

    get_usb_details || return 1

    if [[ "$ATTENDEDMODE" == "true" ]]; then
        print_block_device_details || return 1
    else
        get_block_device_details || return 1
    fi
}

# Configure the system with username/proxy/cloud-init files
platform_config_manager() {

    if [[ "$ATTENDEDMODE" == "true" ]]; then
        
        create_user_account || return 1
    fi

    setup_proxy_settings || return 1

    if [[ "$proxy_settings" == "false"  ]] && [[ "$ATTENDEDMODE" == "true" ]]; then
        ask_for_proxy_settings || return 1
    fi

    copy_scripts_to_target || return 1

    install_cloud_init_file || return 1

    update_ssh_settings || return 1
}

# Post installation tasks
system_finalizer() {

    boot_order_change_to_disk || return 1

    dump_logs_to_usb || return 1

    if [[ "$ATTENDEDMODE" == "true" ]]; then
       
        ask_confirmation_for_reboot || return 1
    fi
   
}

# Progress Bar Function
show_progress_bar() {
    progress=$1
    message=$2

    # Calculate percentage
    percentage=$(( (progress * 100) / TOTAL_PROVISION_STEPS ))

    # Calculate number of green and red characters
    green_chars=$(( (progress * BAR_WIDTH) / TOTAL_PROVISION_STEPS ))
    red_chars=$(( BAR_WIDTH - green_chars-1 ))
    padded_status_message=$(printf "%-*s" "$MAX_STATUS_MESSAGE_LENGTH" "$message")
    green_bar=$(printf "%0.s#" $(seq 1 $green_chars))
    red_bar=$(printf "%0.s-" $(seq 1 $red_chars))
    progress_line=$(printf "\r\033[K${YELLOW}%s${NC} [${GREEN}%s${YELLOW}%s${NC}] %3d%%" \
        "$padded_status_message" "$green_bar" "$red_bar" "$percentage")
    printf "%b" "$progress_line" | tee /dev/tty1
}
drop_to_shell() {

    dump_logs_to_usb || return 1

    echo "Dropping to an interactive shell on tty1..."
    # Give a proper interactive shell
    setsid /sbin/agetty --autologin root --noclear 0 tty1 linux
    # If agetty not available fallback
    /bin/sh -i </dev/tty1 >/dev/tty1 2>/dev/tty1
}

# Cleaning mounts
cleanup() {
    mount "${usb_disk}${USER_CONF_PART}" /mnt
    cp /var/log/os-installer.log /mnt
    umount /mnt
}

# Main function
main() {

    # Print the provision flow with progress status bar with provisions steps 
    # Step 1: System Readniness Check 
    PROVISION_STEP=0
    show_progress_bar "$PROVISION_STEP" "System Readiness Check"
    if ! system_readiness_check  >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nERROR:System not in ready state for Provision,Please check $LOG_FILE for more details,.Aborting.${NC}" | tee /dev/tty1
        drop_to_shell 
    fi
    PROVISION_STEP=1
    show_progress_bar "$PROVISION_STEP" "System Ready for Provision"

    # Step 2: Install OS on the disk 
    PROVISION_STEP=2
    show_progress_bar "$PROVISION_STEP" "OS Setup "
    if ! install_os_on_disk >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nERROR:OS Installation failed,Please check $LOG_FILE for more details,Aborting.${NC}" | tee /dev/tty1
        drop_to_shell 
    fi

    # Step 3: create user,copy cloud-int,ssh-key,other configuration
    PROVISION_STEP=3
    show_progress_bar "$PROVISION_STEP" "Platform Configuration Manager"
    if ! platform_config_manager  >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nERROR:Platform Configuration failed,please check $LOG_FILE for more details,Aborting.${NC}" | tee /dev/tty1
        drop_to_shell 
    fi

    # Step 4: Enable OS-Partitions on the platform 
    PROVISION_STEP=4
    show_progress_bar "$PROVISION_STEP" "Enable OS-Partitions on Platform"
    if [[ "$ATTENDEDMODE" == "true" ]]; then

       if ! create_partitions  >> "$LOG_FILE" 2>&1; then
             echo -e "${RED}\nERROR:OS-Partitions Creation Failed on platform,please check $LOG_FILE for more details,Aborting.${NC}"| tee /dev/tty1
           drop_to_shell
       fi
    else 
        if ! create_os-partition  >> "$LOG_FILE" 2>&1; then
            echo -e "${RED}\nERROR:OS-Partitions Creation Failed on platform,please check $LOG_FILE for more details,Aborting.${NC}"| tee /dev/tty1
           drop_to_shell 
        fi
    fi

    # Step 5: Post install Setup and reboot 
    PROVISION_STEP=5
    show_progress_bar "$PROVISION_STEP" "Post Install Setup"
    if ! system_finalizer  >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}\nERROR:Post install Setup Failed,please check $LOG_FILE for more details,Aborting.${NC}" | tee /dev/tty1
        drop_to_shell 
    fi

    PROVISION_STEP=6
    show_progress_bar "$PROVISION_STEP" ""
    sync

    # Final bar completion and message
    show_progress_bar "$TOTAL_PROVISION_STEPS" "Complete!" | tee /dev/tty1

}
##### Main Execution #####
trap cleanup EXIT
echo -e "${BLUE}Started the OS Provisioning, it will take a few minutes. Please wait!!!${NC}" | tee /dev/tty1
sleep 5
main
success "\nOS Provisioning Done!!!"
sleep 2
echo b >/host/proc/sysrq-trigger
reboot -f
