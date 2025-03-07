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
# VERSION: Blood Moon 2025-03-14

# Configuration variables
AEGIX_BASE_URL="aegixlinux.org"
DEST_ROOT="/mnt"

# Exit on any error
set -e

# Function to display error messages and exit
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    error_exit "This script must be run as root"
fi

# Check for internet connection
ping -c 1 8.8.8.8 >/dev/null 2>&1 || error_exit "No internet connection detected"

# Ensure dialog is installed
pacman -Sy --noconfirm dialog || error_exit "Failed to install dialog. Check your internet connection and Pacman."

# Function to get device selection
get_device_selection() {
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
    if [ -z "$selected_device" ]; then
        error_exit "No block device was selected."
    fi
    
    echo "Selected block device: $selected_device"
    
    # Warn user about potential data loss
    dialog --defaultno \
        --title "HIC SUNT DRACONES" \
        --backtitle "HIC SUNT DRACONES" \
        --yesno "DANGER! HERE BE DRAGONS\n\nSelecting < Yes > will destroy the contents of: \n\n$selected_device"  10 60 || exit
    
    echo "User confirmed device selection"
    return 0
}

# Function to download required files
download_installation_files() {
    echo "Downloading installation files..."
    curl -LO $AEGIX_BASE_URL/barbs.sh || error_exit "Failed to download barbs.sh"
    curl -LO $AEGIX_BASE_URL/ascii-aegix || error_exit "Failed to download ascii-aegix"
    curl -LO $AEGIX_BASE_URL/README.md || error_exit "Failed to download README.md"
    echo "Download complete"
}

# Function to collect user input
collect_user_input() {
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

    # Ask if user wants to securely wipe the disk
    dialog --defaultno \
        --backtitle "WRITE ALL ZEROS instead of 1s and 0s across block device" \
        --title "WRITE ZEROS" \
        --yesno "\nATTENTION HACKERMAN:\n\nSelect < Yes > to commence a lengthy process of writing zeros across the entirety of:\n\n$selected_device" 15 60 && {
            echo "Wiping disk with zeros..."
            dd if=/dev/zero of=$selected_device bs=1M status=progress || error_exit "Failed to wipe disk"
        } || echo "Skipping disk wiping..."
}

# Function to set up disk partitions and encryption
setup_disk() {
    echo "Installing disk setup packages..."
    pacman -S openssl glibc parted cryptsetup lvm2 --noconfirm || error_exit "Failed to install disk setup packages"

    echo "Creating partitions..."
    parted -s -a optimal $selected_device mklabel msdos || error_exit "Failed to create partition table"
    parted -s -a optimal $selected_device mkpart primary fat32 1MiB 1GiB || error_exit "Failed to create boot partition"
    
    # Determine if the block device is nvme or not
    if [[ $selected_device =~ [0-9]$ ]]; then
        boot_partition="${selected_device}p1"
    else
        boot_partition="${selected_device}1"
    fi

    # Setup the boot partition
    echo "Formatting boot partition..."
    mkfs.fat -F32 "$boot_partition" || error_exit "Failed to format boot partition"
    parted -s $selected_device set 1 boot on
    parted -s -a optimal $selected_device mkpart primary 1GiB 100% || error_exit "Failed to create system partition"

    # Setup the encryption partition
    if [[ $selected_device =~ [0-9]$ ]]; then
        luks_partition="${selected_device}p2"
    else
        luks_partition="${selected_device}2"
    fi

    # Check if LUKS container already exists
    luks_container_exists=$(cryptsetup isLuks "$luks_partition" && echo "yes" || echo "no")

    # Handle existing LUKS container
    if [ "$luks_container_exists" = "yes" ]; then
        echo "LUKS Container Exists on ${luks_partition}. Proceeding with removal..."
        if cryptsetup status aegixluks >/dev/null 2>&1; then
            echo "Removing existing aegixluks mapping..."
            cryptsetup remove aegixluks
        fi
        batch_mode_flag="-q"
    else
        batch_mode_flag=""
    fi

    # Set up LUKS encryption
    echo "Setting up LUKS encryption..."
    echo -n "$luks_pass1" | cryptsetup ${batch_mode_flag} luksFormat "$luks_partition" - || error_exit "Failed to format LUKS partition"
    echo -n "$luks_pass1" | cryptsetup open --type luks "$luks_partition" aegixluks - || error_exit "Failed to open LUKS container"

    # BTRFS setup with subvolumes for timeshift auto-backup compatibility
    echo "Setting up BTRFS filesystem..."
    mkfs.btrfs -f -L BUTTER /dev/mapper/aegixluks || error_exit "Failed to create BTRFS filesystem"
    mount /dev/mapper/aegixluks $DEST_ROOT || error_exit "Failed to mount BTRFS filesystem"

    echo "Creating BTRFS subvolumes..."
    btrfs sub cr $DEST_ROOT/@ || error_exit "Failed to create @ subvolume"
    btrfs sub cr $DEST_ROOT/@home || error_exit "Failed to create @home subvolume"

    # Unmount and remount with subvolumes
    echo "Remounting with subvolumes..."
    umount $DEST_ROOT
    mount -o relatime,space_cache=v2,ssd,compress=lzo,subvol=@ /dev/mapper/aegixluks $DEST_ROOT || error_exit "Failed to mount @ subvolume"
    mkdir -p $DEST_ROOT/home
    mount -o relatime,space_cache=v2,ssd,compress=lzo,subvol=@home /dev/mapper/aegixluks $DEST_ROOT/home || error_exit "Failed to mount @home subvolume"

    # Create boot directory and mount boot partition
    mkdir -p $DEST_ROOT/boot
    mount "$boot_partition" $DEST_ROOT/boot || error_exit "Failed to mount boot partition"

    # Show the partition layout
    echo "Partition layout:"
    lsblk -f
    sleep 3
}

# Function to install the base system
install_base_system() {
    echo "Installing base system..."
    basestrap $DEST_ROOT base base-devel runit elogind-runit linux linux-firmware vim neovim grub btrfs-progs \
    dosfstools brightnessctl htop cryptsetup lvm2 lvm2-runit efibootmgr go xorg || error_exit "Failed to install base system"

    # Setup hosts file
    echo "Configuring network hosts..."
    echo "127.0.0.1    localhost" > $DEST_ROOT/etc/hosts
    echo "::1    localhost" >> $DEST_ROOT/etc/hosts
    echo "127.0.1.1    $hostname.localdomain $hostname" >> $DEST_ROOT/etc/hosts

    # Generate fstab
    echo "Generating fstab..."
    fstabgen -U $DEST_ROOT >> $DEST_ROOT/etc/fstab || error_exit "Failed to generate fstab"

    # Collect UUIDs
    encrypted_partition_uuid=$(cryptsetup luksUUID "$luks_partition")
    luks_container_uuid=$(findmnt -no UUID $DEST_ROOT)

    echo "Encrypted partition UUID: $encrypted_partition_uuid"
    echo "LUKS container UUID: $luks_container_uuid"

    # Setup crypttab
    echo "Configuring crypttab..."
    echo "aegixluks UUID=$encrypted_partition_uuid none luks" >> $DEST_ROOT/etc/crypttab
}

# Function to select desktop and GRUB backgrounds
select_backgrounds() {
    # Display dialog and capture user choice for desktop background
    user_choice_desktop_bg=$(dialog --clear \
        --backtitle "Aegix Desktop Background Image" \
        --title "Choose a Desktop Background" \
        --no-tags \
        --item-help \
        --menu "Choose your desktop background image\nSelect one:" 15 50 4 \
        "ndh_aurora_mason.jpg" "North Davis Heights Aurora" "" \
        "bays_elliott_aegix.png" "Bays Mountain" "" \
        "fuji-san-bg.png" "Mt Fuji Sunset" "" \
        2>&1 >/dev/tty)

    # Download the selected desktop background image
    case $user_choice_desktop_bg in
        "ndh_aurora_mason.jpg")  
            curl -LO $AEGIX_BASE_URL/images/ndh_aurora_mason.jpg || error_exit "Failed to download desktop background"
            ;;
        "bays_elliott_aegix.png")
            curl -LO $AEGIX_BASE_URL/images/bays_elliott_aegix.png || error_exit "Failed to download desktop background"
            ;;
        "fuji-san-bg.png")
            curl -LO $AEGIX_BASE_URL/images/fuji-san-bg.png || error_exit "Failed to download desktop background"
            ;;
    esac

    # Copy the selected file to new system
    desktop_bg=$user_choice_desktop_bg
    cp $desktop_bg $DEST_ROOT/root/aegix-bg.png || error_exit "Failed to copy desktop background"

    # Display dialog and capture user choice for GRUB background
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
            curl -LO $AEGIX_BASE_URL/images/starfield.png || error_exit "Failed to download GRUB background"
            ;;
        "mt-aso-penguin.png")
            curl -LO $AEGIX_BASE_URL/images/mt-aso-penguin.png || error_exit "Failed to download GRUB background"
            ;;
    esac

    # Assign choice to grub_bg and copy the file to new system
    grub_bg=$user_choice_grub_bg
    cp $grub_bg $DEST_ROOT/root/ || error_exit "Failed to copy GRUB background"
}

# Function to configure the system with chroot
configure_system() {
    echo "Configuring system..."
    
    # Copy files to new system
    cp barbs.sh $DEST_ROOT/root/ || error_exit "Failed to copy barbs.sh"
    
    # Enter new system via chroot
    artix-chroot $DEST_ROOT /bin/bash <<EOF || error_exit "Chroot configuration failed"

echo "Configuring system with UUIDs:"
echo "Encrypted partition UUID: $encrypted_partition_uuid"
echo "LUKS container UUID: $luks_container_uuid"

# Modify the mkinitcpio configuration for encryption and LVM
sed -i 's/\\(HOOKS=(.*block \\)\\(.*filesystems.*\\))/\\1encrypt lvm2 \\2)/' /etc/mkinitcpio.conf
mkinitcpio -p linux || exit 1

# Update GRUB configuration for LUKS encryption
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 cryptdevice=UUID=$encrypted_partition_uuid:aegixluks root=/dev/mapper/aegixluks\"|" /etc/default/grub

# Update GRUB distributor
sed -i 's/GRUB_DISTRIBUTOR="Artix"/GRUB_DISTRIBUTOR="Aegix"/' /etc/default/grub

# Install GRUB
grub-install "$selected_device" || exit 1

# Copy GRUB background
cp /root/$grub_bg /boot/grub/

# Update GRUB background configuration
sed -i "s|^#GRUB_BACKGROUND=\".*\"|GRUB_BACKGROUND=\"/boot/grub/$grub_bg\"|" /etc/default/grub

# Update GRUB timeout
sed -i 's/^GRUB_TIMEOUT=5$/GRUB_TIMEOUT=14/' /etc/default/grub

# Generate GRUB configuration
grub-mkconfig -o /boot/grub/grub.cfg || exit 1

# Set root password
echo "root:$rootpass1" | chpasswd

# Configure system clock, timezone, and hostname
hwclock --systohc
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
echo "$hostname" > /etc/hostname

# Generate and configure locale settings
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US ISO-8859-1" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
export "LANG=en_US.UTF-8"
echo "LC_COLLATE=C" >> /etc/locale.conf
export LC_COLLATE="C"

# Install and configure NetworkManager
pacman -S networkmanager networkmanager-runit --noconfirm || exit 1
ln -s /etc/runit/sv/NetworkManager/ /etc/runit/runsvdir/current

# Install and configure NTP
pacman -S openntpd openntpd-runit --noconfirm || exit 1
ln -s /etc/runit/sv/openntpd/ /etc/runit/runsvdir/current

# Install and configure SSH
pacman -S openssh openssh-runit --noconfirm || exit 1
ln -s /etc/runit/sv/sshd/ /etc/runit/runsvdir/current

# Install and configure cron
pacman -S cronie cronie-runit --noconfirm || exit 1
ln -s /etc/runit/sv/cronie/ /etc/runit/runsvdir/current

# Run BARBS script for desktop environment setup
sh /root/barbs.sh || exit 1

EOF

    # Fix fstab for timeshift compatibility
    echo "Fixing fstab for timeshift compatibility..."
    sed -i 's/subvolid=[0-9]*,//' $DEST_ROOT/etc/fstab
}

# Function to show completion message
show_completion() {
    dialog --title "Aegix Installation Complete" \
        --backtitle "Aegix Installation Complete" \
        --msgbox "\nCongrats! Aegix Linux is now fully installed, and you have a truly secure and professional GNU/Linux system at your disposal...\n\n(unless you cancelled somewhere in BARBS :-)\n\nAfter you hit Enter one more time, you'll receive instructions to shutdown, remove the installer medium, and reboot into your new system.\n\nZenshin Suru!\n-Aegix" 18 60

    cat ascii-aegix
}

# Main execution flow
main() {
    # Get device selection
    get_device_selection
    
    # Download installation files
    download_installation_files
    
    # Collect user input
    collect_user_input
    
    # Set up disk
    setup_disk
    
    # Install base system
    install_base_system
    
    # Select background images
    select_backgrounds
    
    # Configure system
    configure_system
    
    # Show completion message
    show_completion
}

# Run the main function
main