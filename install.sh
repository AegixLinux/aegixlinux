#!/bin/sh

##
# Metadata
##

# install.sh
# by Timothy Beach
# +-+-+-+-+-+-+-+-+-+-+-+-+-+-+
# |A|e|g|i|x|L|i|n|u|x|.|o|r|g|
# +-+-+-+-+-+-+-+-+-+-+-+-+-+-+
# License: GNU GPLv3
# VERSION: Centrifugal_Bumblepuppy_2024-09-20_Wed

# Exit on any error
set -e

# Ensure dialog is installed
pacman -Sy --noconfirm dialog || { echo "Error at script start: Are you sure you're running this as the root user? Are you sure you have an internet connection?"; exit; }

# Fetch available block devices
devices=$(lsblk -d -p -n -l -o NAME,SIZE,MODEL -e 7,11)

# Parse block devices for dialog display
device_list=""

while IFS= read -r line; do
    device=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    model=$(echo "$line" | awk '{print $3}')
    device_list="${device_list} $device \"$size $model\""
done <<< "$devices"

# Prompt user to select a block device for installation
selected_device=$(eval dialog --stdout --menu \"Select a block device for your Aegix installation:\" 15 60 5 $device_list)
if [ -n "$selected_device" ]; then
    selected_device_path=$selected_device
    echo "Selected block device: $selected_device_path"
else
    echo "No block device was selected."
    exit
fi

# Warn user about potential data loss
dialog --defaultno \
    --title "HIC SUNT DRACONES" \
    --backtitle "HIC SUNT DRACONES" \
    --yesno "DANGER! HERE BE DRAGONS\n\nSelecting < Yes > will destroy the contents of: \n\n$selected_device_path"  10 60 || exit

# Download necessary installation files
curl -LO aegixlinux.org/barbs.sh
# curl -LO aegixlinux.org/aegix-programs.csv
curl -LO aegixlinux.org/ascii-aegix
curl -LO aegixlinux.org/README.md

# Get encryption passphrase
luks_pass1=$(dialog --no-cancel \
    --backtitle "SET LUKS ENCRYPTION PASSPHRASE" \
    --title "SET LUKS PASSPHRASE" \
    --passwordbox "Enter a passphrase for the LUKS encryption.\n\nMake it unique, and write it down." 10 60 3>&1 1>&2 2>&3 3>&1)
luks_pass2=$(dialog --no-cancel \
    --backtitle "SET LUKS ENCRYPTION PASSPHRASE" \
    --title "SET LUKS PASSPHRASE" \
    --passwordbox "Retype the encryption passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)

while true; do
    [[ "$luks_pass1" != "" && "$luks_pass1" == "$luks_pass2" ]] && break
    luks_pass1=$(dialog --no-cancel --passwordbox "Uh oh! Your passphrases do not match. Try again." 10 60 3>&1 1>&2 2>&3 3>&1)
    luks_pass2=$(dialog --no-cancel --passwordbox "Retype the passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)
done

# Collect user input for hostname
hostname=$(dialog --stdout \
    --backtitle "SET HOSTNAME" \
    --title "SET HOSTNAME" \
    --no-cancel --inputbox "Enter a hostname for your system." 10 60)

# Set system's time zone
if dialog --defaultno \
    --backtitle "Set your system's time zone." \
    --title "Set your system's time zone." \
    --yesno "\nDo you want to set the time zone to something other than Eastern time: America/New_York ?\n\nSelect yes to choose a different time zone."  10 60
then
    timezone=$(tzselect)
else
    timezone="America/New_York"
fi

# Get root user passphrase
rootpass1=$(dialog --no-cancel \
    --backtitle "SET ROOT PASSPHRASE" \
    --title "SET ROOT PASSPHRASE" \
    --passwordbox "Enter a passphrase for the root user.\n\nMake it unique, and write it down." 10 60 3>&1 1>&2 2>&3 3>&1)
rootpass2=$(dialog --no-cancel \
    --backtitle "SET ROOT PASSPHRASE" \
    --title "SET ROOT PASSPHRASE" \
    --passwordbox "Retype the root passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)
while true; do
	[[ "$rootpass1" != "" && "$rootpass1" == "$rootpass2" ]] && break
	rootpass1=$(dialog --no-cancel --passwordbox "Uh oh! Your passwordphrases do not match. Try again." 10 60 3>&1 1>&2 2>&3 3>&1)
	rootpass2=$(dialog --no-cancel --passwordbox "Retype the passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)
done

# Provide option to write zeros across block device
dialog --defaultno \
    --backtitle "WRITE ALL ZEROS instead of 1s and 0s across block device" \
    --title "WRITE ZEROS" \
    --yesno "\nATTENTION HACKERMAN:\n\nSelect < Yes > to commence a lengthy process of writing zeros across the entirety of:\n\n$selected_device_path" 15 60 && dd if=/dev/zero of=$selected_device_path bs=1M status=progress || echo "Let's continue then..."

# Get disk setup packages
pacman -S openssl glibc parted cryptsetup lvm2 --noconfirm

# Create partitions
parted -s -a optimal $selected_device_path mklabel msdos
parted -s -a optimal $selected_device_path mkpart primary fat32 1MiB 1GiB

# Determine if the block device is nvme or not
if [[ $selected_device_path =~ [0-9]$ ]]; then
    boot_partition="${selected_device_path}p1"
else
    boot_partition="${selected_device_path}1"
fi

# Setup the boot partition
mkfs.fat -F32 "$boot_partition"
parted -s $selected_device_path set 1 boot on
parted -s -a optimal $selected_device_path mkpart primary 1GiB 100%

# Setup the encryption partition
if [[ $selected_device_path =~ [0-9]$ ]]; then
    luks_partition="${selected_device_path}p2"
else
    luks_partition="${selected_device_path}2"
fi

# Check if LUKS container already exists
luks_container_exists=$(cryptsetup isLuks "$luks_partition" && echo "yes" || echo "no")

# Detect if a LUKS superblock signature is present
if [ "$luks_container_exists" = "yes" ]; then
    # Automatically proceed to remove existing LUKS setup
    echo "LUKS Container Exists on ${luks_partition}. Proceeding with removal..."

    if cryptsetup status aegixluks >/dev/null 2>&1; then
        echo "Removing existing aegixluks mapping..."
        cryptsetup remove aegixluks
    fi

    batch_mode_flag="-q"
else
    batch_mode_flag=""
fi

# Set boot partition for nvme or standard ssd
echo -n "$luks_pass1" | cryptsetup ${batch_mode_flag} luksFormat "$luks_partition" -
echo -n "$luks_pass1" | cryptsetup open --type luks "$luks_partition" aegixluks -

# BTRFS setup with subvolumes for timeshift auto-backup compatibility
mkfs.btrfs -f -L BUTTER /dev/mapper/aegixluks
mount /dev/mapper/aegixluks /mnt

btrfs sub cr /mnt/@
btrfs sub cr /mnt/@home

# Unmount and remount with subvolumes
umount /mnt
mount -o relatime,space_cache=v2,ssd,compress=lzo,subvol=@ /dev/mapper/aegixluks /mnt
mkdir -p /mnt/home
mount -o relatime,space_cache=v2,ssd,compress=lzo,subvol=@home /dev/mapper/aegixluks /mnt/home

# Create boot directory and mount boot partition
mkdir -p /mnt/boot
mount "$boot_partition" /mnt/boot

# Block devices looking pretty
lsblk -f
sleep 10s

# Bootstrap the based system
basestrap /mnt base base-devel runit elogind-runit linux linux-firmware vim neovim grub btrfs-progs dosfstools brightnessctl htop cryptsetup lvm2 lvm2-runit efibootmgr go xorg

echo "basestrap ran"

# Setup hosts file
echo "127.0.0.1    localhost" > /mnt/etc/hosts
echo "::1    localhost" >> /mnt/etc/hosts
echo "127.0.1.1    $hostname.localdomain $hostname" >> /mnt/etc/hosts

# Generate fstab
fstabgen -U /mnt >> /mnt/etc/fstab

# Collect UUIDs
# encrypted_partition_uuid=$(lsblk -f "$luks_partition" -o UUID | awk 'NR==2')
encrypted_partition_uuid=$(cryptsetup luksUUID "$luks_partition")
luks_container_uuid=$(findmnt -no UUID /mnt)

echo "Encrypted partition UUID: $encrypted_partition_uuid"
echo "LUKS container UUID: $luks_container_uuid"

# Setup crypttab
echo "aegixluks UUID=$encrypted_partition_uuid none luks" >> /mnt/etc/crypttab

# Copy files to new system
cp barbs.sh /mnt/root/
# cp aegix-programs.csv /mnt/root/

###

# Display dialog and capture user choice for desktop background
user_choice_desktop_bg=$(dialog --clear \
    --backtitle "Aegix Desktop Background Image" \
    --title "Choose a Desktop Background" \
    --no-tags \
    --item-help \
    --menu "Choose your desktop background image\nSelect one:" 15 50 4 \
    "aurora-bg.png" "North Davis Heights Aurora" "" \
    "bays_elliott_aegix.png" "Bays Mountain" "" \
    "fuji-san-bg.png" "Mt Fuji Sunset" "" \
    2>&1 >/dev/tty)

# Download the selected desktop background image
case $user_choice_desktop_bg in
    "aurora-bg.png")  
        curl -LO aegixlinux.org/images/aurora-bg.png
        ;;
    "bays_elliott_aegix.png")
        curl -LO aegixlinux.org/images/bays_elliott_aegix.png
        ;;
    "fuji-san-bg.png")
        curl -LO aegixlinux.org/images/fuji-san-bg.png
        ;;
esac

# Assign choice to desktop_bg and copy the file to new system's wallpaper directory
desktop_bg=$user_choice_desktop_bg
# Assuming the path to the wallpaper directory in the installed system is /mnt/root/usr/share/backgrounds/
cp $desktop_bg /mnt/root/aegix-bg.png

###

# Display dialog and capture user choice
user_choice_grub_bg=$(dialog --clear \
    --backtitle "Aegix GRUB Menu Background Image" \
    --title "Choose a GRUB Background" \
    --no-tags \
    --item-help \
    --menu "Choose your GRUB background image\nSelect one:" 15 50 4 \
    "starfield.png" "Star Field" "" \
    "mt-aso-penguin.png" "Mt Aso Pixels" "" \
    2>&1 >/dev/tty)

# Download the selected image
case $user_choice_grub_bg in
    "starfield.png")
        curl -LO aegixlinux.org/images/starfield.png
        ;;
    "mt-aso-penguin.png")
        curl -LO aegixlinux.org/images/mt-aso-penguin.png
        ;;
esac

# Assign choice to grub_bg and copy the file to new system
grub_bg=$user_choice_grub_bg
cp $grub_bg /mnt/root/

# Enter new system via chroot
artix-chroot /mnt /bin/bash <<EOF

echo "Still have Encrypted partition UUID: $encrypted_partition_uuid"
echo "Still have LUKS container UUID: $luks_container_uuid"

sleep 4s

# Modify the mkinitcpio configuration to include encryption and LVM hooks, then regenerate the initramfs for the Linux kernel
sed -i 's/\(HOOKS=(.*block \)\(.*filesystems.*\))/\1encrypt lvm2 \2)/' /etc/mkinitcpio.conf
mkinitcpio -p linux

# Update the GRUB configuration to set kernel parameters for LUKS encryption and specify the root device as the encrypted LVM volume
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 cryptdevice=UUID=$encrypted_partition_uuid:aegixluks root=/dev/mapper/aegixluks\"|" /etc/default/grub

sudo sed -i 's/GRUB_DISTRIBUTOR="Artix"/GRUB_DISTRIBUTOR="Aegix"/' /etc/default/grub

# Install GRUB and generate the configuration file
grub-install "$selected_device_path"

# Copy GRUB bg now that /boot/grub exists
cp /root/$grub_bg /boot/grub/

# Update the GRUB configuration to set the GRUB background
sed -i "s|^#GRUB_BACKGROUND=\".*\"|GRUB_BACKGROUND=\"/boot/grub/$grub_bg\"|" /etc/default/grub

# Update GRUB_TIMEOUT 
sed -i 's/^GRUB_TIMEOUT=5$/GRUB_TIMEOUT=14/' /etc/default/grub

# Generate the GRUB configuration file
grub-mkconfig -o /boot/grub/grub.cfg

# Set the root password.
echo "root:$rootpass1" | chpasswd

# Configure system clock, time zone, and hostname.
hwclock --systohc
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
echo "$hostname" > /etc/hostname

# Generate and set up system locale settings for the US English language and default collation order.
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US ISO-8859-1" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
export "LANG=en_US.UTF-8"
echo "LC_COLLATE=C" >> /etc/locale.conf
export LC_COLLATE="C"

# Install NetworkManager and its runit service
pacman -S networkmanager networkmanager-runit --noconfirm
# Create a symlink for NetworkManager runit service
ln -s /etc/runit/sv/NetworkManager/ /etc/runit/runsvdir/current

# Install openntpd and its runit service
pacman -S openntpd openntpd-runit --noconfirm
# Create a symlink for openntpd runit service
ln -s /etc/runit/sv/openntpd/ /etc/runit/runsvdir/current

# SSH gets first class citizen status ~ Install openssh and its runit service
pacman -S openssh openssh-runit --noconfirm
# Create a symlink for openssh runit service
ln -s /etc/runit/sv/sshd/ /etc/runit/runsvdir/current

# Cron gets first class citizen status ~ Install and enable the cron daemon
pacman -S cronie cronie-runit --noconfirm
# Create a symlink for cronie runit service
ln -s /etc/runit/sv/cronie/ /etc/runit/runsvdir/current

# pacman -Sy xorg --noconfirm
# echo "full xorg install or reinstall"
# sleep 3s

# btrfs quota enable /

# sed -i \
#     -e 's/"do_first_run" : "true"/"do_first_run" : "false"/' \
#     -e 's/"btrfs_mode" : "false"/"btrfs_mode" : "true"/' \
#     -e 's/"include_btrfs_home" : "false"/"include_btrfs_home" : "true"/' \
#     /etc/timeshift/timeshift.json

# sed -i -e 's/"do_first_run" : "true"/"do_first_run" : "false"/' -e 's/"btrfs_mode" : "false"/"btrfs_mode" : "true"/' -e 's/"include_btrfs_home" : "false"/"include_btrfs_home" : "true"/' /etc/timeshift/timeshift.json

###### 

sh /root/barbs.sh

EOF

# sed command to remove subvolid= from /mnt/etc/fstab
# We do this for timeshift compatibility
sed -i 's/subvolid=[0-9]*,//' /mnt/etc/fstab


dialog --title "Aegix Installation Complete" \
    --backtitle "Aegix Installation Complete" \
    --msgbox "\nCongrats! Aegix Linux is now fully installed, and you have a truly secure and professional GNU/Linux system at your disposal...\n\n(unless you cancelled somewhere in BARBS :-)\n\nAfter you hit Enter one more time, you'll receive instructions to shutdown, remove the installer medium, and reboot into your new system.\n\nZenshin Suru!\n-Aegix" 18 60

cat ascii-aegix
