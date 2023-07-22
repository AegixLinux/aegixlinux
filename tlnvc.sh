#!/bin/sh

set -e

pacman -Sy --noconfirm dialog || { echo "Error at script start: Are you sure you're running this as the root user? Are you sure you have an internet connection?"; exit; }

devices=$(lsblk -d -p -n -l -o NAME,SIZE,MODEL -e 7,11)

device_list=""

while IFS= read -r line; do
    device=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    model=$(echo "$line" | awk '{print $3}')
    device_list="${device_list} $device \"$size $model\""
done <<< "$devices"


selected_device=$(eval dialog --stdout --menu \"Select a block device for TANKLINUX installation:\" 15 60 5 $device_list)
if [ -n "$selected_device" ]; then
    selected_device_path=$selected_device
    echo "Selected block device: $selected_device_path"
else
    echo "No block device was selected."
    exit
fi

dialog --defaultno --title "HIC SUNT DRACONES" --yesno "\nCAUTION: Here Be Dragons\nIf you proceed, the contents of the block device you just selected will be destroyed. Make sure you have the data of all attached hard drives backed up.\nProceed only if certain. Are you certain?"  10 60 || exit

curl -LO tanklinux.com/barbs.sh
curl -LO tanklinux.com/tank-programs.csv
curl -LO tanklinux.com/ascii-tank
curl -LO tanklinux.com/README.md

hostname=$(dialog --stdout --no-cancel --inputbox "Enter a hostname for your system." 10 60)

if dialog --defaultno --title "Set your system's time zone." --yesno "Do you want to set the time zone to something other than Eastern time: America/New_York ?\n\nSelect yes to select your own time zone.\nSelect no to set system to Eastern time."  10 60
then
    timezone=$(tzselect)
else
    timezone="America/New_York"
fi

rootpass1=$(dialog --no-cancel --passwordbox "Enter password for root user. Make it unique, and write it down." 10 60 3>&1 1>&2 2>&3 3>&1)
rootpass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
while true; do
	[[ "$rootpass1" != "" && "$rootpass1" == "$rootpass2" ]] && break
	rootpass1=$(dialog --no-cancel --passwordbox "Oy mate! Your passwords do not match. Try again." 10 60 3>&1 1>&2 2>&3 3>&1)
	rootpass2=$(dialog --no-cancel --passwordbox "Enter same pw twice." 10 60 3>&1 1>&2 2>&3 3>&1)
done

dialog --defaultno --title "HIC SUNT DRACONES" --yesno "\nDo you want to write zeros across the entire hard drive before setting it up? Selecting yes can take time. Even a small 120G drive can take about 5 minutes.\n\nThis is a blunt intrument. If you already have a LUKS container setup that is not tankluks from a prior encrypted installation, select yes. Otherwise select no if you want to save time." 15 60 && dd if=/dev/zero of=$selected_device_path bs=1M status=progress || echo "Let's continue then..."

luks_pass1=$(dialog --no-cancel --passwordbox "Enter a passphrase for symmetrical LUKS encryption. Make it unique, and write it down." 10 60 3>&1 1>&2 2>&3 3>&1)
luks_pass2=$(dialog --no-cancel --passwordbox "Retype the passphrase." 10 60 3>&1 1>&2 2>&3 3>&1)

while true; do
    [[ "$luks_pass1" != "" && "$luks_pass1" == "$luks_pass2" ]] && break
    luks_pass1=$(dialog --no-cancel --passwordbox "Passphrases do not match. Enter the encryption passphrase again." 10 60 3>&1 1>&2 2>&3 3>&1)
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
    luks_partition="${selected_device_path}2"
fi

luks_container_exists=$(cryptsetup isLuks "$luks_partition" && echo "yes" || echo "no")

if [ "$luks_container_exists" = "yes" ]; then
    dialog --defaultno --title "LUKS Container Exists" --yesno "\nQuit now and manually resolve? Select Yes to quit. \n\nSelect No to proceed and remove the superblock signature from the device ${luks_partition}.\n\nIf you are stuck here, you may want to run the script again and at a prior step choose to WRITE ZEROS across the entire block device to get a clean slate before proceeding." 15 60 && exit || batch_mode_flag="-q"

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

artix-chroot /mnt /bin/bash <<EOF

echo "Still have Encrypted partition UUID: $encrypted_partition_uuid"
echo "Still have LUKS container UUID: $luks_container_uuid"

sleep 4s

sed -i 's/\(HOOKS=(.*block \)\(.*filesystems.*\))/\1encrypt lvm2 \2)/' /etc/mkinitcpio.conf
mkinitcpio -p linux

sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 cryptdevice=UUID=$encrypted_partition_uuid:tankluks root=/dev/mapper/tankluks\"|" /etc/default/grub

grub-install "$selected_device_path"
grub-mkconfig -o /boot/grub/grub.cfg



echo "root:$rootpass1" | chpasswd


hwclock --systohc

ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
echo "$hostname" > /etc/hostname

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US ISO-8859-1" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
export "LANG=en_US.UTF-8"
echo "LC_COLLATE=C" >> /etc/locale.conf
export LC_COLLATE="C"

pacman -S networkmanager networkmanager-runit --noconfirm
ln -s /etc/runit/sv/NetworkManager/ /etc/runit/runsvdir/current

pacman -S openntpd openntpd-runit --noconfirm
ln -s /etc/runit/sv/openntpd/ /etc/runit/runsvdir/current

pacman -Sy xorg --noconfirm
echo "full xorg install or reinstall"
sleep 3s

sh /root/barbs.sh

EOF

dialog --msgbox "\nTANKLINUX is now installed (,or you cancelled somewhere in BARBS :-)\n\n- Type:\nshutdown -h now\n\n- Remove the installer USB thumbdrive & reboot into your new system.\n\n                     ~Zenshin Suru~\n\n-TANKLINUX.COM" 20 60



cat ascii-tank
