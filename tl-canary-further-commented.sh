#!/bin/sh

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
selected_device=$(eval dialog --stdout --menu \"Select a block device for your TANKLINUX installation:\" 15 60 5 $device_list)
if [ -n "$selected_device" ]; then
    selected_device_path=$selected_device
    echo "Selected block device: $selected_device_path"
else
# Download necessary files from tanklinux.com
    echo "No block device was selected."
    exit
fi

# Warn user about potential data loss
dialog --defaultno --title "HIC SUNT DRACONES" --yesno "DANGER! HERE BE DRAGONS\n\nSelecting < Yes > will destroy the contents of: \n\n$selected_device_path"  10 60 || exit

curl -LO tanklinux.com/barbs.sh
curl -LO tanklinux.com/tank-programs.csv
# Collect user input for root passphrase
curl -LO tanklinux.com/ascii-tank
curl -LO tanklinux.com/README.md

# Collect user input for hostname
hostname=$(dialog --stdout --no-cancel --inputbox "Enter a hostname for your system." 10 60)

# Set system's time zone
if dialog --defaultno --title "Set your system's time zone." --yesno "\nDo you want to set the time zone to something other than Eastern time: America/New_York ?\n\nSelect yes to choose a different time zone."  10 60
# Prepare disks for installation
then
    timezone=$(tzselect)
else
    timezone="America/New_York"
fi

# Get root user passphrase
rootpass1=$(dialog --no-cancel --passwordbox "Enter a passphrase for the root user.\n\nMake it unique, and write it down." 10 60 3>&1 1>&2 2>&3 3>&1)
rootpass2=$(dialog --no-cancel --passwordbox "Retype the root passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)
while true; do
	[[ "$rootpass1" != "" && "$rootpass1" == "$rootpass2" ]] && break
	rootpass1=$(dialog --no-cancel --passwordbox "Uh oh! Your passwordphrases do not match. Try again." 10 60 3>&1 1>&2 2>&3 3>&1)
	rootpass2=$(dialog --no-cancel --passwordbox "Retype the passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)
done

# Disk partitioning, formatting, and mounting

# Install the base system
dialog --defaultno --title "HIC SUNT DRACONES" --yesno "\nATTENTION HACKERMAN:\n\nSelect < Yes > to commence a lengthy process of writing zeros across the entirety of:\n\n$selected_device_path" 15 60 && dd if=/dev/zero of=$selected_device_path bs=1M status=progress || echo "Let's continue then..."

luks_pass1=$(dialog --no-cancel --passwordbox "Enter a passphrase for the LUKS encryption.\n\nMake it unique, and write it down." 10 60 3>&1 1>&2 2>&3 3>&1)
luks_pass2=$(dialog --no-cancel --passwordbox "Retype the encryption passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)

while true; do
    [[ "$luks_pass1" != "" && "$luks_pass1" == "$luks_pass2" ]] && break
    luks_pass1=$(dialog --no-cancel --passwordbox "Uh oh! Your passphrases do not match. Try again." 10 60 3>&1 1>&2 2>&3 3>&1)
    luks_pass2=$(dialog --no-cancel --passwordbox "Retype the passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)
done

pacman -S parted cryptsetup lvm2 --noconfirm

parted -s -a optimal $selected_device_path mklabel msdos

parted -s -a optimal $selected_device_path mkpart primary fat32 1MiB 1GiB

if [[ $selected_device_path =~ [0-9]$ ]]; then
    boot_partition="${selected_device_path}p1"
else
    boot_partition="${selected_device_path}1"
fi

mkfs.fat -F32 "$boot_partition"
parted -s $selected_device_path set 1 boot on

parted -s -a optimal $selected_device_path mkpart primary 1GiB 100%

if [[ $selected_device_path =~ [0-9]$ ]]; then
    luks_partition="${selected_device_path}p2"
else
# Chroot into the new installation
    luks_partition="${selected_device_path}2"
fi

luks_container_exists=$(cryptsetup isLuks "$luks_partition" && echo "yes" || echo "no")

if [ "$luks_container_exists" = "yes" ]; then
    dialog --defaultno --title "LUKS Container Exists" --yesno "\nYou have an extant LUKS superblock signature on ${luks_partition}.\n\nSelect < Yes > to abort installation.\n\nSelect < No > to proceed, allowing the installation process to remove it. This will take ~ 10s" 15 60 && exit || batch_mode_flag="-q"

    if cryptsetup status tankluks >/dev/null 2>&1; then
        echo "Removing existing tankluks mapping..."
        cryptsetup remove tankluks
    fi
else
    batch_mode_flag=""
fi

echo -n "$luks_pass1" | cryptsetup ${batch_mode_flag} luksFormat "$luks_partition" -
echo -n "$luks_pass1" | cryptsetup open --type luks "$luks_partition" tankluks -

mkfs.btrfs -f -L BUTTER /dev/mapper/tankluks
mount /dev/mapper/tankluks /mnt

btrfs sub cr /mnt/@
btrfs sub cr /mnt/@home

umount /mnt
mount -o relatime,space_cache=v2,ssd,compress=lzo,subvol=@ /dev/mapper/tankluks /mnt
mkdir -p /mnt/home
mount -o relatime,space_cache=v2,ssd,compress=lzo,subvol=@home /dev/mapper/tankluks /mnt/home

mkdir -p /mnt/boot
mount "$boot_partition" /mnt/boot

lsblk -f
sleep 10s

# Bootstrap the base system
basestrap /mnt base base-devel runit elogind-runit linux linux-firmware vim neovim grub btrfs-progs dosfstools brightnessctl htop cryptsetup lvm2 lvm2-runit efibootmgr

echo "basestrap ran"

echo "127.0.0.1    localhost" > /mnt/etc/hosts
echo "::1    localhost" >> /mnt/etc/hosts
echo "127.0.1.1    $hostname.localdomain $hostname" >> /mnt/etc/hosts

fstabgen -U /mnt >> /mnt/etc/fstab

# encrypted_partition_uuid=$(lsblk -f "$luks_partition" -o UUID | awk 'NR==2')
encrypted_partition_uuid=$(cryptsetup luksUUID "$luks_partition")
luks_container_uuid=$(findmnt -no UUID /mnt)

echo "Encrypted partition UUID: $encrypted_partition_uuid"
echo "LUKS container UUID: $luks_container_uuid"

echo "tankluks UUID=$encrypted_partition_uuid none luks" >> /mnt/etc/crypttab

cp barbs.sh /mnt/root/
cp tank-programs.csv /mnt/root/

# Chroot into the new system
artix-chroot /mnt /bin/bash <<EOF
# Set system hostname and locale

echo "Still have Encrypted partition UUID: $encrypted_partition_uuid"
echo "Still have LUKS container UUID: $luks_container_uuid"

sleep 4s

# Install and enable networking services
sed -i 's/\(HOOKS=(.*block \)\(.*filesystems.*\))/\1encrypt lvm2 \2)/' /etc/mkinitcpio.conf
mkinitcpio -p linux

sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 cryptdevice=UUID=$encrypted_partition_uuid:tankluks root=/dev/mapper/tankluks\"|" /etc/default/grub
# Install and enable time synchronization services

grub-install "$selected_device_path"
grub-mkconfig -o /boot/grub/grub.cfg
# Execute the post-installation script
# Set root password, time, locale, and hostname

echo "root:$rootpass1" | chpasswd

hwclock --systohc

ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
# Setup network and time services
echo "$hostname" > /etc/hostname

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US ISO-8859-1" >> /etc/locale.gen
# Install full xorg
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
export "LANG=en_US.UTF-8"
# (Optional) Btrfs settings for Timeshift (currently commented out)
echo "LC_COLLATE=C" >> /etc/locale.conf
export LC_COLLATE="C"

pacman -S networkmanager networkmanager-runit --noconfirm
ln -s /etc/runit/sv/NetworkManager/ /etc/runit/runsvdir/current

pacman -S openntpd openntpd-runit --noconfirm
ln -s /etc/runit/sv/openntpd/ /etc/runit/runsvdir/current

# Execute barbs.sh script
pacman -Sy xorg --noconfirm
echo "full xorg install or reinstall"
# Display post-installation message
sleep 3s

# btrfs quota enable /

# sed -i \
# Display ASCII art of tank
#     -e 's/"do_first_run" : "true"/"do_first_run" : "false"/' \
#     -e 's/"btrfs_mode" : "false"/"btrfs_mode" : "true"/' \
#     -e 's/"include_btrfs_home" : "false"/"include_btrfs_home" : "true"/' \
#     /etc/timeshift/timeshift.json

# sed -i -e 's/"do_first_run" : "true"/"do_first_run" : "false"/' -e 's/"btrfs_mode" : "false"/"btrfs_mode" : "true"/' -e 's/"include_btrfs_home" : "false"/"include_btrfs_home" : "true"/' /etc/timeshift/timeshift.json

sh /root/barbs.sh

EOF

dialog --title "TANKLINUX Installation Complete" --msgbox "\nCongrats! TANKLINUX is now fully installed, and you have a truly secure and professional GNU/Linux system at your disposal...\n\n(unless you cancelled somewhere in BARBS :-)\n\nAfter you hit Enter one more time, you'll receive instructions to shutdown, remove the installer medium, and reboot into your new system.\n\nZenshin Suru!\n-TANKLINUX.COM" 18 60

cat ascii-tank