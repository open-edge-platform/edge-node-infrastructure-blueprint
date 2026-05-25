#!/bin/sh

# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -x

##global variables#####
os_disk=""
part_number=""
rootfs_part_number=""
data_persistent_part=""
swap_part=""
###############

lvm_size=0
user_name="$2"


# Sync file system
function sync_file_system(){
block_disk_part=$1
blockdev --rereadpt "/dev/$os_disk" 2>/dev/null
udevadm settle --timeout=15 2>/dev/null
# Check if the partition available
count=0
while [ ! -b "$block_disk_part" ]; do
    sleep 1
    count=$((count+1))
    if [ "$count" -ge 15 ]; then
         echo "Partition table not synced,exiting the installation"
         exit 1
    fi
done
}

#lvm creation on disk
create_lvm_partition(){
blk_device_count=$1
shift
lvm_disks="$@"

#if one disk found and it has rootfs
if [ "$blk_device_count" -eq "1" ];then
    echo "starting the LVM creation for the disk volume ${lvm_disks}"
    lvm_part=$(echo "Fix" | parted -ms ${lvm_disks}  print | tail -n 1 | awk -F: '{print $1}')
    disks="${lvm_disks}${part_number}${lvm_part}"

#more than one disk found
else
    set -- $lvm_disks
    disks=""
    while [ "$1" ]; do
        disk="/dev/$1"
        echo "starting the LVM creation for the disk volume $disk"
        echo "Fix" | parted -s "$disk" mklabel gpt mkpart primary 0% 100%
        echo "Fix" | parted --script "$disk" set 1 lvm on
        partprobe
        fdisk -l "$disk"
        sync
        if echo "$disk" | grep -q "nvme"; then
            part_number="p"
        else
            part_number=""
        fi
        if [ -z "$disks" ]; then
             disks="${disk}${part_number}1"
        else
             disks="$disks ${disk}${part_number}1"
        fi
    shift
    done
fi
#wipse the crypt luck offset if its created during FDE enabled case
#otherwise LVM creation will fail
set -- $disks
while [ "$1" ];do
    wipefs --all "$1"
    shift
done

#remove previously created lvm if exist
vgs=$(vgs --noheadings -o vg_name)
#remove trailing and leading spaces
vgs=$(echo "$vgs" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
if [ -n "$vgs" ]; then
    vgremove -f "$vgs"
    rm -rf  "/dev/${vgs:?}/"
    rm -rf  /dev/mapper/lvmvg-pv*
    dmsetup remove_all
    echo "successfully deleted the previous lvm"
fi

#remove previously created pv if exist
for pv_disk in $(pvscan 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i ~ /^\/dev\//) print $i}'); do
        echo "Removing LVM metadata from $pv_disk"
        pvremove -ff -y "$pv_disk"
done

#pv create
set -- $disks
while [ "$1" ];do
    if echo "y" | pvcreate "$1"; then
            echo "Successfuly done pvcreate"
        else
            echo "Failure in pvcreate"
            exit 1
        fi
        shift
done

#vgcreate
if echo "y" | vgcreate lvmvg $disks; then
    echo "Successfuly done vgcreate"
else
    echo "Failure in vgcreate"
    exit 1
fi

vgscan
vgchange -ay

if vgchange -ay; then
    echo "Successfuly created the logical volume group"
else
    echo "Failure in creating the logical volume group"
    exit 1
fi
}

#disk partition for rootfs,data-persistent,swap
partition_disk(){
ram_size=$1
disk_size=$2

disk="/dev/$os_disk"

#get the number of devices attached to system ignoreing USB/Virtual/Removabale disks
blk_devices=$(lsblk -o NAME,TYPE,SIZE,RM | grep -i disk | awk '$1 ~ /sd*|nvme*/ {if ($3 !="0B" && $4 ==0)  {print $1}}')
set -- $blk_devices
blk_disk_count=$#
final_disk_list=""
for disk_name in ${blk_devices}
do
    #skip for rootfs disk
    if echo "$disk_name" | grep -q "$os_disk"; then
        continue;
    else
        if [ -z "$final_disk_list" ]; then
            final_disk_list="$disk_name"
        else
            final_disk_list="$final_disk_list $disk_name"
        fi
    fi
done
if [ "$blk_disk_count" -eq 1 ]; then
    #create the SAWP size as square root of ram size
    swap_size=$(echo "scale=0; sqrt($ram_size)" | bc)
else
    #create the swap size as half of RAM size
    swap_size=$((ram_size/2))
    #cap the swap_size to 128GB
    if [ "$swap_size" -gt 128 ]; then
        swap_size=128
    fi
fi
#make sure swap size should not exceed the total disk size
if [ "$swap_size" -ge "$disk_size" ]; then
    echo "Looks the Disk size is very Minimal and can't proceed with partition!!!!"
    exit 1
fi

#Create the Partitions on Ubuntu with
### Rootfs size to 50GB
### data-persistent to ( MAX_DISK - ( rootfs+swap+lvm)
### swap partition

### For dual disk LVM will be created on Secondary disk
rootfs_size=50


if [ "$blk_disk_count" -eq 1 ]; then
    disk_size_in_use=$((rootfs_size + swap_size + lvm_size))
    data_persistent=$(echo "$disk_size" - "$disk_size_in_use" | bc)
    data_persistent_end_size=$(echo "$rootfs_size" + "$data_persistent" | bc )
else
    disk_size_in_use=$((rootfs_size + swap_size))
    data_persistent=$(echo "$disk_size" - "$disk_size_in_use" | bc)
    data_persistent_end_size=$(echo "$rootfs_size" + "$data_persistent" | bc )
fi

parted --script "${disk}" \
    resizepart "${rootfs_part_number}" "${rootfs_size}GB" \
    mkpart primary ext4 "${rootfs_size}GB" "${data_persistent_end_size}GB" \
    mkpart primary linux-swap "${data_persistent_end_size}GB" "$((swap_size + data_persistent_end_size))GB"

if [ "$?" -eq 0 ]; then
    echo "Successfully created the Ubuntu partitions"
else
    echo "Failed to create the Ubuntu partitions,please check!!"
    exit 1
fi
sgdisk -e "${disk}"
blockdev --rereadpt "${disk}"
udevadm settle --timeout=15

# Resize the rootfs partition
rootfs_part="${disk}${part_number}${rootfs_part_number}"
sync_file_system "$rootfs_part"
e2fsck -f -y "$rootfs_part"

sleep 3
data_persistent_part=$((rootfs_part_number + 1))
swap_part=$((data_persistent_part+1))

# Creating the data-persistent volume and enabling the swap partition
sync_file_system "${disk}${part_number}${data_persistent_part}"
/sbin/mke2fs -t ext4 -L data_persistent -F "${disk}${part_number}${data_persistent_part}"
mkswap "${disk}${part_number}${swap_part}"

blockdev --rereadpt "${disk}"
udevadm settle --timeout=15

swapon "${disk}${part_number}${swap_part}"
sleep 2

# Create the /var/lib/rancher,kubelet mount-point on data-persistent volume

mkdir -p /mnt1
sync_file_system "${disk}${part_number}${rootfs_part_number}"
mount "${disk}${part_number}${rootfs_part_number}" /mnt1

# Create the rancher,kubelet mount points to persistent volume
mkdir -p /mnt1/data_persistent
mkdir -p /mnt1/var/lib/rancher
mkdir -p /mnt1/var/lib/kubelet

# Create the user_data directory to copy the data from external sources

mkdir -p /mnt1/home/"$user_name"/user_data

sync_file_system "${disk}${part_number}${data_persistent_part}"
mount "${disk}${part_number}${data_persistent_part}" /mnt1/data_persistent

mkdir -p /mnt1/data_persistent/rancher
mkdir -p /mnt1/data_persistent/kubelet
mkdir -p /mnt1/data_persistent/user_data

# Bind the volumes to persistent partitions
mount --bind /mnt1/data_persistent/rancher /mnt1/var/lib/rancher
mount --bind /mnt1/data_persistent/kubelet /mnt1/var/lib/kubelet
mount --bind /mnt1/data_persistent/user_data /mnt1/home/"$user_name"/user_data

# Update /etc/fstab for swap && data-persistent partitions

data_persistent_uuid=$(blkid -s UUID -o value "${disk}${part_number}${data_persistent_part}")
swap_uuid=$(blkid -s UUID -o value "${disk}${part_number}${swap_part}")


mount "${disk}${part_number}${rootfs_part_number}" /mnt

cat >> /mnt/etc/fstab <<EOF

# Data persistent volume
UUID=$data_persistent_uuid   /data_persistent   ext4  discard,errors=remount-ro 0 1
/data_persistent/rancher /var/lib/rancher none bind 0 0
/data_persistent/kubelet /var/lib/kubelet none bind 0 0
/data_persistent/user_data /home/$user_name/user_data none bind 0 0

# Swap space
UUID=$swap_uuid   none   swap   sw   0 0
EOF
sync
if [ "$?" -eq 0 ]; then
    echo "Successfully Updated the /etc/fstable"
    umount -f -l /mnt1
    umount -f -l /mnt
else
    echo "Failed to update /etcfstab,please check!!"
    umount -f -l /mnt1
    umount -f -l /mnt
fi
rm -rf /mnt1

### Create LVM partitions based Single && Multiple disks
if [ "$blk_disk_count" -eq 1 ] && [ "$lvm_size" -ge 1 ]; then
    swap_partition_size_end=$( echo "Fix" | parted -ms $disk  print | tail -n 1 | awk -F: '{print $3}' | sed 's/[^0-9]*//g')
    echo "Fix" | parted "${disk}" --script mkpart primary ext4 "${swap_partition_size_end}GB" "$((lvm_size + swap_partition_size_end))GB"
    echo "Fix" | parted --script "${disk}" set 4 lvm on
    partprobe "${disk}"

    create_lvm_partition "${blk_disk_count}" "${disk}"

#if more than 1 disk ditected then create the LVM partition on secondary disks
elif [ "$blk_disk_count" -ge 2 ]; then
    echo "found more than 1 disk for LVM creation"
    #create_lvm_partition  "${blk_disk_count}" "${final_disk_list}"
fi
}

####@main#################

echo "--------Starting the Partition creation on Ubuntu OS---------"
#get the rootfs partition from the disk

rootfs_part=$(blkid | grep -Ei 'cloudimg-rootfs|rootfs|ROOT' | grep -i ext4 | awk -F: '{print $1}' | head -n 1)
efiboot_part=$(blkid | grep -i uefi | grep -i vfat |  awk -F: '{print $1}')
boot_part=$(blkid | grep -i boot | grep -i ext4 |  awk -F: '{print $1}')

if echo "$rootfs_part" | grep -q "nvme"; then
    os_disk=$(echo "$rootfs_part" | grep -oE 'nvme[0-9]+n[0-9]+' | head -n 1)
    part_number="p"
    rootfs_part_suffix=$(echo "$rootfs_part" | sed "s|^/dev/${os_disk}||")
    rootfs_part_number=$(echo "$rootfs_part_suffix" | sed 's/^p//')
else
    os_disk=$(echo "$rootfs_part" | grep -oE 'sd[a-z]+' | head -n 1)
    part_number=""
    rootfs_part_suffix=$(echo "$rootfs_part" | sed "s|^/dev/${os_disk}||")
    rootfs_part_number=$(echo "$rootfs_part_suffix" | sed 's/[^0-9]*//g')
fi

echo "Partitions detected root:$rootfs_part efi:$efiboot_part"

#check the ram size && decide the sawp size based on it

ram_size=$(free -g | grep -i mem | awk '{ print $2 }')

#get the total rootfs partition disk size

sgdisk -e "/dev/$os_disk"
total_disk_size=$(echo "Fix" | parted -m "/dev/$os_disk" unit GB print | grep "^/dev" | cut -d: -f2 | sed 's/GB//')
if echo "$total_disk_size" | grep -qE '^[0-9]+\.[0-9]+$'; then
    total_disk_size=$(printf "%.0f" "$total_disk_size")
fi

#partition the disk with swap and LVM

partition_disk "$ram_size" "$total_disk_size"

echo "OS disk partition completed successfully"
