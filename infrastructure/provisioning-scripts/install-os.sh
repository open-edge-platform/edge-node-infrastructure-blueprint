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
    # Remove previous LVM's data if exist
    #vgname="lvmvg"
    #vgremove -f "$vgname"
    #rm -rf  "/dev/${vgname:?}/"
    #rm -rf  /dev/mapper/lvmvg-pv*
    #dmsetup remove_all
    # Remove previous Physical volumes if exist
    #for pv_disk in $(pvscan 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i ~ /^\/dev\//) print $i}'); do
    #    echo "Removing LVM metadata from $pv_disk"
    #    pvremove -ff -y "$pv_disk"
    #done
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

# Install cloud-init file on OS
install_cloud_init_file() {

    # Copy the cloud init file from Hook OS to target OS
    echo -e "${BLUE}Installing the Cloud-init file!!${NC}" 


    CLOUD_INIT_FILE="/etc/scripts/cloud-init.yaml"
    custom_cloud_init_updates
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
	  NEW_LINES=$(cat <<'EOF'
         systemctl disable k3s
         systemctl stop k3s
         bash /opt/edge/scripts/container-provision.sh
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
             exit 1
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
            exit 1
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
create_os-partition() {
    echo -e "${BLUE}Creating the OS Partitions on disk $os_disk!!${NC}"
    os_partition_script=/etc/scripts/os-partition.sh

    if bash $os_partition_script "$lvm_size";  then
        success "OS Partitions successful on $os_disk"
    else
        failure "OS Partitions failed on $os_disk,Please check!!"
        return 1
    fi
    return 0

}
custom_ntp_server_configuration() {
    
    echo -e "${BLUE}Custom NTP Server Configuration!!${NC}"
    # Check if Custom NTP Server configuration provided as input
    # ignore if not provide
    CONFIG_FILE="/etc/scripts/config-file"

    ntp_server=$(grep '^USER_CUSTOM_NTP_SERVERS=' "$CONFIG_FILE" \
    | cut -d '=' -f2- \
    | sed 's/^"//;s/"$//')

    ntp_yaml=$(printf '%s\n' "$ntp_server" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | sed '/^$/d' \
    | sed 's/^/    - /')

    if [ -n "$ntp_server" ]; then
	check_mnt_mount_exist
        mount "${os_disk}${os_rootfs_part}" /mnt
	sed -i "/^[[:space:]]*-[[:space:]]*time\.google\.com[[:space:]]*$/{
        s|.*||
        r /dev/stdin
        d
    }" /mnt/etc/cloud/cloud.cfg.d/installer.cfg <<EOF
$ntp_yaml
EOF
     umount /mnt
     fi 
}

# Check provision pre-conditions
system_readiness_check() {

    get_usb_details || return 1

    get_block_device_details || return 1
}

# Configure the system with username/proxy/cloud-init files
platform_config_manager() {

    setup_proxy_settings || return 1

    copy_scripts_to_target || return 1

    install_cloud_init_file || return 1

    update_ssh_settings || return 1


    #custom_ntp_server_configuration || return 1

}

# Post installation tasks
system_finalizer() {

    boot_order_change_to_disk || return 1

    dump_logs_to_usb || return 1
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
    #show_progress_bar "$PROVISION_STEP" "Enable OS-Partitions on Platform"
    #if ! create_os-partition  >> "$LOG_FILE" 2>&1; then
    #    echo -e "${RED}\nERROR:OS-Partitions Creation Failed on platform,please check $LOG_FILE for more details,Aborting.${NC}"| tee /dev/tty1
     #  drop_to_shell 
    #fi

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
