#!/bin/sh

#########################################
# Metadata
#########################################

# Base Automation Routine for Building Systems (BARBS)
# by TANKLINUX.com
# License: GNU GPLv3
# VERSION: 20230616.2

# Verbosity of comments are for pedagogical purposes.

#########################################
# Script
#########################################

# Enable the script to exit immediately if a command or pipeline has an error. 
# This is the safest way to ensure that an unexpected error won't continue to execute further commands.
set -e

# Updates the installer system and installs the dialog and whiptail packages
pacman -Sy --noconfirm dialog || { echo "Error at script start: Are you sure you're running this as the root user? Are you sure you have an internet connection?"; exit; }

################################
## Block device selection
################################

# List all available block devices, excluding loop devices (7) and CD-ROM devices (11)
# `lsblk` command options:
# -d, --nodeps: Omits device dependencies, displaying only the primary block devices.
# -p, --paths: Outputs complete device path, e.g., "/dev/sda" instead of "sda".
# -n, --noheadings: Removes the header line, resulting in a clean list of devices.
# -l, --list: Arranges the output in list format, with one device per line, for easier parsing.
# -o, --output NAME,SIZE,MODEL: Specifies the columns to display - device name, size, and model in this case.
devices=$(lsblk -d -p -n -l -o NAME,SIZE,MODEL -e 7,11)

# Initialize an empty string to store the list of devices
device_list=""

# Loop through each line in the output of the lsblk command
# `read -r line` reads a line from the input and stores it in the variable `line`
while IFS= read -r line; do
    # Extract the device name, size, and model from the line
    device=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    model=$(echo "$line" | awk '{print $3}')
    # Append the device name, size, and model to the list of devices
    device_list="${device_list} $device \"$size $model\""
    # The <<< operator is a "here string" that feeds the output of the lsblk command line by line into the while loop
done <<< "$devices"

# Display a dialog to the user to select a block device for installation
# The selected device will be stored in the selected_device variable

selected_device=$(eval dialog --stdout --menu \"Select a block device for TANKLINUX installation:\" 15 60 5 $device_list)
if [ -n "$selected_device" ]; then
    selected_device_path=$selected_device
    echo "Selected block device: $selected_device_path"
else
    echo "No block device was selected."
    exit
fi

# User warning
dialog --defaultno --title "HIC SUNT DRACONES" --yesno "\nCAUTION: Here Be Dragons\nIf you proceed, the contents of the block device you just selected will be destroyed. Make sure you have the data of all attached hard drives backed up.\nProceed only if certain. Are you certain?"  10 60 || exit

# Download tanklinux.com scripts
curl -LO tanklinux.com/barbs.sh
curl -LO tanklinux.com/tank-programs.csv 
curl -LO tanklinux.com/ascii-tank 
curl -LO tanklinux.com/README.md

# Get hostname from user
hostname=$(dialog --stdout --no-cancel --inputbox "Enter a hostname for your system." 10 60)

# # Get timezone from user
# dialog --defaultno --title "Set your system's time zone." --yesno "Do you want to set the time zone to something other than Eastern time: America/New_York ?\n\nSelect yes to select your own time zone.\nSelect no to set system to Eastern time."  10 60 || echo "America/New_York" > timezone || tzselect > timezone

# Get timezone from user
if dialog --defaultno --title "Set your system's time zone." --yesno "Do you want to set the time zone to something other than Eastern time: America/New_York ?\n\nSelect yes to select your own time zone.\nSelect no to set system to Eastern time."  10 60
then
    timezone=$(tzselect)
else
    timezone="America/New_York"
fi

# Get root pw from user
rootpass1=$(dialog --no-cancel --passwordbox "Enter password for root user. Make it unique, and write it down." 10 60 3>&1 1>&2 2>&3 3>&1)
rootpass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
while true; do
	[[ "$rootpass1" != "" && "$rootpass1" == "$rootpass2" ]] && break
	rootpass1=$(dialog --no-cancel --passwordbox "Oy mate! Your passwords do not match. Try again." 10 60 3>&1 1>&2 2>&3 3>&1)
	rootpass2=$(dialog --no-cancel --passwordbox "Enter same pw twice." 10 60 3>&1 1>&2 2>&3 3>&1)
done

# Write zeros. Takes time
dialog --defaultno --title "HIC SUNT DRACONES" --yesno "\nDo you want to write zeros across the entire hard drive before setting it up? Selecting yes can take time. Even a small 120G drive can take about 5 minutes.\n\nThis is a blunt intrument. If you already have a LUKS container setup that is not tankluks from a prior encrypted installation, select yes. Otherwise select no if you want to save time." 15 60 && dd if=/dev/zero of=$selected_device_path bs=1M status=progress || echo "Let's continue then..."

# Get the passphrase for the LUKS partition
luks_pass1=$(dialog --no-cancel --passwordbox "Enter a passphrase for symmetrical LUKS encryption. Make it unique, and write it down." 10 60 3>&1 1>&2 2>&3 3>&1)
luks_pass2=$(dialog --no-cancel --passwordbox "Retype the passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)

# Check if both passphrases match and ask again if they don't
while true; do
    [[ "$luks_pass1" != "" && "$luks_pass1" == "$luks_pass2" ]] && break
    luks_pass1=$(dialog --no-cancel --passwordbox "Passphrases do not match. Enter the encryption passphrase again." 10 60 3>&1 1>&2 2>&3 3>&1)
    luks_pass2=$(dialog --no-cancel --passwordbox "Retype the passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)
done

# Install additional dependencies on installer system
pacman -S parted cryptsetup lvm2 --noconfirm

# Create a new, empty partition table on $selected_device_path
parted -s -a optimal $selected_device_path mklabel msdos

# Create a 1GB unencrypted FAT32 partition for boot (start at 1MiB for proper alignment)
parted -s -a optimal $selected_device_path mkpart primary fat32 1MiB 1GiB

# Determine the boot partition name
if [[ $selected_device_path =~ [0-9]$ ]]; then
    boot_partition="${selected_device_path}p1"
else
    boot_partition="${selected_device_path}1"
fi

mkfs.fat -F32 "$boot_partition"
parted -s $selected_device_path set 1 boot on

# Create a second partition for LUKS, using the remaining disk space
parted -s -a optimal $selected_device_path mkpart primary 1GiB 100%

# Determine the LUKS partition name
if [[ $selected_device_path =~ [0-9]$ ]]; then
    luks_partition="${selected_device_path}p2"
else
    luks_partition="${selected_device_path}2"
fi

# Check if the LUKS container already exists
luks_container_exists=$(cryptsetup isLuks "$luks_partition" && echo "yes" || echo "no")

if [ "$luks_container_exists" = "yes" ]; then
    dialog --defaultno --title "LUKS Container Exists" --yesno "\nQuit now and manually resolve? Select Yes to quit. \n\nSelect No to proceed and remove the superblock signature from the device ${luks_partition}.\n\nIf you are stuck here, you may want to run the script again and at a prior step choose to WRITE ZEROS across the entire block device to get a clean slate before proceeding." 15 60 && exit || batch_mode_flag="-q"
    
    # dialog --defaultno --title "LUKS Container Exists" --yesno "\nThe device ${selected_device_path}2 already contains a LUKS superblock signature. Remove it?\n\nIf it is from a prior tanklinux.com installation, selecting yes will remove it. Otherwise things will probably fall apart here, and you'll want to run the script again and select yes on a prior step to WRITE ZEROS across the entire block device to get a clean slate before proceeding." 15 60 || exit
    # # Set the batch-mode flag
    # batch_mode_flag="-q"

    # Check for tankluks and remove it if it exists
    if cryptsetup status tankluks >/dev/null 2>&1; then
        echo "Removing existing tankluks mapping..."
        cryptsetup remove tankluks
    fi
else
    batch_mode_flag=""
fi

# Create LUKS container on the second partition using the passphrase
# echo -n "$luks_pass1" | cryptsetup ${batch_mode_flag} luksFormat "${selected_device_path}2" -
echo -n "$luks_pass1" | cryptsetup ${batch_mode_flag} luksFormat "$luks_partition" -

# Open the LUKS container
# echo -n "$luks_pass1" | cryptsetup open --type luks "${selected_device_path}2" tankluks -
echo -n "$luks_pass1" | cryptsetup open --type luks "$luks_partition" tankluks -

# # Create LUKS container on the second partition using the passphrase
# echo -n "$luks_pass1" | cryptsetup luksFormat "${selected_device_path}2" -

# # Open the LUKS container
# echo -n "$luks_pass1" | cryptsetup open --type luks "${selected_device_path}2" tankluks -

# Format the system partition as btrfs
mkfs.btrfs -f -L BUTTER /dev/mapper/tankluks
# Mount btrfs
mount /dev/mapper/tankluks /mnt 

# Create btrfs subvolumes
# These btrfs subvolumes can only be created while the file system is mounted. In order for a simple btrfs timeshift system snapshot system to work, we only need two subvolumes.

# Create `/` subvolume
btrfs sub cr /mnt/@
# Create `/home` subvolume
btrfs sub cr /mnt/@home

# Umount /mnt & mount subvolumes directly
umount /mnt
# Mount @ root subvolume
mount -o relatime,space_cache=v2,ssd,compress=lzo,subvol=@ /dev/mapper/tankluks /mnt
# Create and mount @home subvolume
mkdir -p /mnt/home
mount -o relatime,space_cache=v2,ssd,compress=lzo,subvol=@home /dev/mapper/tankluks /mnt/home

# Create the boot directory
mkdir -p /mnt/boot
# Mount the 1GB unencrypted FAT32 boot partition
# mount "${selected_device_path}1" /mnt/boot
mount "$boot_partition" /mnt/boot
## BACKLOG: Detect if UEFI and use /mnt/boot/efi if so. Above only works for Legacy BIOS

lsblk -f
sleep 10s

# basestrap /mnt 
basestrap /mnt base base-devel runit elogind-runit linux linux-firmware vim neovim grub btrfs-progs dosfstools brightnessctl htop cryptsetup lvm2 lvm2-runit efibootmgr

echo "basestrap ran"

# Set up /etc/hosts
echo "127.0.0.1    localhost" > /mnt/etc/hosts
echo "::1    localhost" >> /mnt/etc/hosts
echo "127.0.1.1    $hostname.localdomain $hostname" >> /mnt/etc/hosts

# /etc/fstab
fstabgen -U /mnt >> /mnt/etc/fstab
# I think this might be happening in the wrong order
####################################################################################

# echo "cryptroot UUID=$(findmnt -no UUID /mnt) none luks" >> /mnt/etc/crypttab

# Get the UUID values for the partition and container for use in /mnt/etc/default/grub
# encrypted_partition_uuid=$(lsblk -f "${selected_device_path}2" -o UUID | awk 'NR==2')
encrypted_partition_uuid=$(lsblk -f "$luks_partition" -o UUID | awk 'NR==2')
# luks_container_uuid=$(lsblk -f /dev/mapper/tankluks -o UUID | awk 'NR==2')
luks_container_uuid=$(findmnt -no UUID /mnt)

echo "Encrypted partition UUID: $encrypted_partition_uuid"
echo "LUKS container UUID: $luks_container_uuid"
# Encrypted partition UUID: 9cda77e2-cf24-478c-a052-4b4c09cad92c
# LUKS container UUID: 98879a00-896e-4c5d-91e2-1685ee38439c
# sde
# ├─sde1       vfat        FAT32            D9B3-66CB
# └─sde2       crypto_LUKS 2                9cda77e2-cf24-478c-a052-4b4c09cad92c
#   └─tankluks btrfs             BUTTER     98879a00-896e-4c5d-91e2-1685ee38439c

# echo "cryptroot UUID=$encrypted_partition_uuid none luks" >> /mnt/etc/crypttab
# echo "tankluks UUID=$luks_container_uuid none luks" >> /mnt/etc/crypttab
echo "tankluks UUID=$encrypted_partition_uuid none luks" >> /mnt/etc/crypttab

# Copy barbs.sh and tank-programs.csv over to be accessed from within chroot
cp barbs.sh /mnt/root/
cp tank-programs.csv /mnt/root/

# Time to chroot
artix-chroot /mnt /bin/bash <<EOF

echo "Still have Encrypted partition UUID: $encrypted_partition_uuid"
echo "Still have LUKS container UUID: $luks_container_uuid"

sleep 4s

# C3PO
# Add encrypt lvm2 to mkinitcpio.conf "$selected_device_path"
sed -i 's/\(HOOKS=(.*block \)\(.*filesystems.*\))/\1encrypt lvm2 \2)/' /etc/mkinitcpio.conf
# Generate the initial ramdisk image specifically for the 'linux' kernel, based on the configuration in /etc/mkinitcpio.conf
mkinitcpio -p linux

#### GRUB Section Start ####

# Configure /etc/default/grub
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=$encrypted_partition_uuid:tankluks root=/dev/mapper/tankluks\"|" /etc/default/grub

# Install - Only works on Legacy BIOS at this time #backlog
grub-install "$selected_device_path"
# Make config
grub-mkconfig -o /boot/grub/grub.cfg

# # GRUB Installation
# # Ask the user if they are using Legacy BIOS or UEFI
# dialog --clear --title "GRUB Installation" --no-cancel --menu "Select your system type:" 10 60 2 \
# "1" "Legacy BIOS" \
# "2" "UEFI" 2> system_type_temp
# # Read the user's selection
# system_type=$(cat system_type_temp)
# rm system_type_temp
# # Install GRUB based on the user's selection
# if [ "$system_type" = "1" ]; then
#     # Legacy BIOS
#     grub-install "$selected_device_path"
# else
#     # UEFI
#     grub-install --target=x86_64-efi --efi-directory=/boot/efi --boot-directory=/boot --bootloader-id=grub
# fi
# # NOTE: We must use grub-mkconfig from within the chroot

#### GRUB Section End ####

# Set root pw
echo "root:$rootpass1" | chpasswd

# ADMINISTRIVIA #

# Set hardware clock to system clock
hwclock --systohc

# Set timezone
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
# Apply hostname set above
# mv hostname /mnt/etc/hostname
echo "$hostname" > /etc/hostname

# Locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US ISO-8859-1" >> /etc/locale.gen
locale-gen  
echo "LANG=en_US.UTF-8" > /etc/locale.conf
export "LANG=en_US.UTF-8"
echo "LC_COLLATE=C" >> /etc/locale.conf
export LC_COLLATE="C"

# Setup networkmanager
pacman -S networkmanager networkmanager-runit --noconfirm
ln -s /etc/runit/sv/NetworkManager/ /etc/runit/runsvdir/current

# Setup NTP
pacman -S openntpd openntpd-runit --noconfirm
ln -s /etc/runit/sv/openntpd/ /etc/runit/runsvdir/current

# Now we can install xorg
pacman -Sy xorg --noconfirm
echo "full xorg install or reinstall"
sleep 3s

# Next we will install barbs
sh /root/barbs.sh

EOF

dialog --msgbox "\nTANKLINUX is now installed (,or you cancelled somewhere in BARBS :-)\n\n- Type:\nshutdown -h now\n\n- Remove the installer USB thumbdrive & reboot into your new system.\n\n                     ~Zenshin Suru~\n\n-TANKLINUX.COM" 20 60

# This cron section was breaking the script, or maybe barbs broke above
# # Setup cron # Let BARBS above install it from the AUR with yay, then symlink
# ln -s /etc/runit/sv/cronie/ /etc/runit/runsvdir/current

# # Set cron to sync with NTP every 5 minutes
# echo "0 5 * * * ntpd -qg" | crontab -

cat ascii-tank 