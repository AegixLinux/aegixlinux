#!/usr/bin/env bash
# Aegix/Artix installer — unified UEFI + legacy BIOS
# - Auto-detects boot mode (UEFI vs BIOS)
# - GPT + ESP for UEFI, msdos + boot for BIOS
# - Optional LUKS on root
# - btrfs root by default with subvolumes and compression
# - Aegix base (Artix-based) with runit services

set -euo pipefail
IFS=$'\n\t'

### -------------------------------
### helpers
### -------------------------------
log() { printf "\n\033[1;32m[+] %s\033[0m\n" "$*"; }
warn() { printf "\n\033[1;33m[!] %s\033[0m\n" "$*"; }
err() { printf "\n\033[1;31m[✗] %s\033[0m\n" "$*"; }
error_exit() { err "$*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || error_exit "missing dependency: $1"; }

### -------------------------------
### sanity checks (live ISO env)
### -------------------------------
# Check for root
if [[ $EUID -ne 0 ]]; then
  error_exit "This script must be run as root"
fi

# Check for internet
ping -c 1 8.8.8.8 >/dev/null 2>&1 || error_exit "No internet connection detected"

# Install required tools not in base ISO
log "Installing required packages..."
pacman -Sy --noconfirm parted cryptsetup btrfs-progs || error_exit "Failed to install required packages"

# Now check for everything we need
need parted; need lsblk; need sed; need awk; need cryptsetup; need mkfs.fat
need basestrap; need fstabgen; need artix-chroot; need mkinitcpio

### -------------------------------
### detect boot mode
### -------------------------------
if [[ -d /sys/firmware/efi ]]; then
  BOOT_MODE="uefi"
  log "Detected UEFI boot mode"
else
  BOOT_MODE="bios"
  log "Detected legacy BIOS boot mode"
fi

### -------------------------------
### config (edit if you like)
### -------------------------------
FS_TYPE=${FS_TYPE:-btrfs}        # btrfs or ext4
ESP_SIZE_MIB=${ESP_SIZE_MIB:-512}
HOST_TZ_DEFAULT=${HOST_TZ_DEFAULT:-America/New_York}
LOCALE_DEFAULT=${LOCALE_DEFAULT:-en_US.UTF-8}
KEYMAP_DEFAULT=${KEYMAP_DEFAULT:-us}
BOOTLABEL=${BOOTLABEL:-Aegix}
ROOT_MAPPER_NAME=${ROOT_MAPPER_NAME:-cryptroot}
AEGIX_BASE_URL="https://aegixlinux.org"

### -------------------------------
### pick target disk
### -------------------------------
log "Detecting block devices..."
mapfile -t DEV_CHOICES < <(lsblk -dpno NAME,SIZE,MODEL | grep -E "/dev/(nvme|sd|vd|mmcblk)" || true)
(( ${#DEV_CHOICES[@]} )) || error_exit "No suitable disks found."

printf "\nAvailable disks:\n"; printf "  %s\n" "${DEV_CHOICES[@]}"; printf "\n"
read -rp "Enter target disk (e.g., /dev/nvme0n1): " selected_device
[[ -b "$selected_device" ]] || error_exit "Not a block device: $selected_device"

warn "THIS WILL WIPE $selected_device completely."
read -rp "Type YES to confirm: " really
[[ "$really" == "YES" ]] || error_exit "Aborted."

### -------------------------------
### basic questions
### -------------------------------
read -rp "Hostname [aegix]: " HOSTNAME; HOSTNAME=${HOSTNAME:-aegix}
read -rp "Username to create [aegix]: " NEWUSER; NEWUSER=${NEWUSER:-aegix}
read -rsp "Password for $NEWUSER: " USERPASS; echo
read -rsp "Password for root: " ROOTPASS; echo
read -rp "Timezone [$HOST_TZ_DEFAULT]: " HOST_TZ; HOST_TZ=${HOST_TZ:-$HOST_TZ_DEFAULT}
read -rp "Locale to enable [$LOCALE_DEFAULT]: " LOCALE; LOCALE=${LOCALE:-$LOCALE_DEFAULT}
read -rp "Keymap [$KEYMAP_DEFAULT]: " KEYMAP; KEYMAP=${KEYMAP:-$KEYMAP_DEFAULT}

# LUKS is mandatory on Aegix. Full-disk encryption is part of the distro's
# identity, not an option. (If you don't want LUKS, don't install Aegix.)
USE_LUKS=y
while :; do
  read -rsp "LUKS passphrase (required): " LUKS_PASS; echo
  read -rsp "Confirm LUKS passphrase: " LUKS_PASS2; echo
  [[ -n "$LUKS_PASS" && "$LUKS_PASS" == "$LUKS_PASS2" ]] && break
  echo "Passphrases empty or mismatched, try again."
done

### -------------------------------
### download installation files
### -------------------------------
# Use a known working directory so curl -LO lands files predictably
WORK_DIR="$(mktemp -d)"
cd "$WORK_DIR"
log "Gathering BARBS, program list, and backgrounds in ${WORK_DIR}..."
# Prefer the copies baked into this ISO (they match the ISO's skel and package
# set exactly); fall back to the website only when the ISO copy is absent.
if [[ -f /root/barbs.sh ]]; then
  cp /root/barbs.sh . && log "Using barbs.sh from ISO"
else
  curl -LO ${AEGIX_BASE_URL}/barbs.sh || warn "Failed to download barbs.sh (will skip desktop environment)"
fi
if [[ -f /root/aegix-programs.csv ]]; then
  cp /root/aegix-programs.csv . && log "Using aegix-programs.csv from ISO"
else
  curl -LO ${AEGIX_BASE_URL}/aegix-programs.csv || warn "Failed to download aegix-programs.csv"
fi
curl -L -o aegix-bg.jpg ${AEGIX_BASE_URL}/images/ndh_aurora_mason.jpg || warn "Failed to download desktop background"
curl -LO ${AEGIX_BASE_URL}/images/mt-aso-penguin.png || warn "Failed to download GRUB background"

### -------------------------------
### partitioning (by boot mode)
### -------------------------------
ESP_END_MIB=$((1 + ESP_SIZE_MIB))

if [[ "$BOOT_MODE" == "uefi" ]]; then
  log "Partitioning $selected_device (GPT, ESP ${ESP_SIZE_MIB}MiB)..."
  parted -s -a optimal "$selected_device" mklabel gpt
  parted -s -a optimal "$selected_device" mkpart ESP fat32 1MiB ${ESP_END_MIB}MiB
  parted -s "$selected_device" set 1 esp on
else
  log "Partitioning $selected_device (msdos, boot ${ESP_SIZE_MIB}MiB)..."
  parted -s -a optimal "$selected_device" mklabel msdos
  parted -s -a optimal "$selected_device" mkpart primary fat32 1MiB ${ESP_END_MIB}MiB
  parted -s "$selected_device" set 1 boot on
fi
parted -s -a optimal "$selected_device" mkpart primary ${ESP_END_MIB}MiB 100%

# choose partition names based on device type
if [[ "$selected_device" =~ (nvme|mmcblk) ]]; then
  boot_partition="${selected_device}p1"
  root_partition="${selected_device}p2"
else
  boot_partition="${selected_device}1"
  root_partition="${selected_device}2"
fi

sleep 2

log "Formatting boot partition as FAT32..."
mkfs.fat -F32 -n EFI "$boot_partition"

### -------------------------------
### root filesystem (LUKS -> FS or plain FS)
### -------------------------------
if [[ "$USE_LUKS" =~ ^[Yy]$ ]]; then
  log "Setting up LUKS on $root_partition..."
  printf "%s" "$LUKS_PASS" | cryptsetup luksFormat --type luks2 "$root_partition" -q --batch-mode --pbkdf argon2id --iter-time 3000 --use-urandom --label AEGIX_ROOT --cipher aes-xts-plain64 --key-size 512 --hash sha512
  printf "%s" "$LUKS_PASS" | cryptsetup open "$root_partition" "$ROOT_MAPPER_NAME" -q --key-file -
  MAPPED_ROOT="/dev/mapper/${ROOT_MAPPER_NAME}"
else
  MAPPED_ROOT="$root_partition"
fi

case "$FS_TYPE" in
  ext4)
    log "Creating ext4 filesystem on $MAPPED_ROOT..."
    mkfs.ext4 -L ROOT "$MAPPED_ROOT";;
  btrfs)
    need mkfs.btrfs
    log "Creating btrfs filesystem on $MAPPED_ROOT..."
    mkfs.btrfs -f -L ROOT "$MAPPED_ROOT"
    ;;
  *) error_exit "Unsupported FS_TYPE: $FS_TYPE";;
esac

### -------------------------------
### mount target
### -------------------------------
log "Mounting target filesystem..."
mkdir -p /mnt
if [[ "$FS_TYPE" == btrfs ]]; then
  mount "$MAPPED_ROOT" /mnt
  btrfs subvolume create /mnt/@
  btrfs subvolume create /mnt/@home
  umount /mnt
  mount -o relatime,space_cache=v2,ssd,compress=lzo,subvol=@ "$MAPPED_ROOT" /mnt
  mkdir -p /mnt/home
  mount -o relatime,space_cache=v2,ssd,compress=lzo,subvol=@home "$MAPPED_ROOT" /mnt/home
else
  mount "$MAPPED_ROOT" /mnt
fi
mkdir -p /mnt/boot
mount "$boot_partition" /mnt/boot

### -------------------------------
### base system install
### -------------------------------
log "Installing base system (Aegix/Artix + runit)..."
PKGS_BASE=(base base-devel linux linux-firmware grub efibootmgr sudo vim neovim nano less man-db man-pages xorg-server xorg-xinit go zsh)
PKGS_FS=(dosfstools e2fsprogs btrfs-progs)
PKGS_MISC=(openssh cryptsetup lvm2 brightnessctl htop networkmanager)
PKGS_RUNIT=(runit elogind-runit networkmanager-runit openssh-runit openntpd openntpd-runit cronie cronie-runit lvm2-runit)

basestrap /mnt "${PKGS_BASE[@]}" "${PKGS_FS[@]}" "${PKGS_MISC[@]}" "${PKGS_RUNIT[@]}"

### -------------------------------
### fstab
### -------------------------------
log "Generating fstab..."
fstabgen -U /mnt >> /mnt/etc/fstab

# Get UUIDs for bootloader and crypttab configuration
ROOT_UUID=$(blkid -s UUID -o value "$root_partition")
ESP_UUID=$(blkid -s UUID -o value "$boot_partition")

# Add crypttab for LUKS
if [[ "$USE_LUKS" =~ ^[Yy]$ ]]; then
  log "Configuring crypttab..."
  echo "${ROOT_MAPPER_NAME} UUID=${ROOT_UUID} none luks" >> /mnt/etc/crypttab
fi

# Seed the target's /etc/skel from this ISO's skel (the pipeline-synced Aegix
# dotfiles). useradd -m in barbs then populates the user's home from it, making
# the ISO the single source of truth for the desktop experience. The gohan
# repo remains a published mirror, not the installer's source.
if [[ -d /etc/skel/.config ]]; then
  log "Seeding target /etc/skel from ISO skel..."
  cp -aT /etc/skel /mnt/etc/skel || warn "Failed to seed /etc/skel (barbs will fall back to gohan clone)"
fi

# Record which ISO this system was installed from. Invaluable when a bug report
# has to be tied back to an exact build.
if [[ -f /etc/aegix-release ]]; then
  cp /etc/aegix-release /mnt/etc/aegix-release
  echo "AEGIX_INSTALL_DATE=$(date -Is)" >> /mnt/etc/aegix-release
  log "Recorded install provenance in /etc/aegix-release"
fi

# Copy BARBS files and backgrounds to new system
log "Copying BARBS and backgrounds to new system..."
[[ -f "$WORK_DIR/barbs.sh" ]] && cp "$WORK_DIR/barbs.sh" /mnt/root/ || warn "Failed to copy barbs.sh"
[[ -f "$WORK_DIR/aegix-programs.csv" ]] && cp "$WORK_DIR/aegix-programs.csv" /mnt/root/ || warn "Failed to copy aegix-programs.csv"
[[ -f "$WORK_DIR/aegix-bg.jpg" ]] && cp "$WORK_DIR/aegix-bg.jpg" /mnt/root/aegix-bg.jpg || warn "Failed to copy desktop background"
[[ -f "$WORK_DIR/mt-aso-penguin.png" ]] && cp "$WORK_DIR/mt-aso-penguin.png" /mnt/root/ || warn "Failed to copy GRUB background"

### -------------------------------
### chroot configuration
### -------------------------------

# Export all variables needed in chroot
export HOSTNAME NEWUSER USERPASS ROOTPASS HOST_TZ LOCALE KEYMAP
export FS_TYPE USE_LUKS ROOT_MAPPER_NAME ROOT_UUID ESP_UUID BOOTLABEL selected_device BOOT_MODE
export BARBS_USER="$NEWUSER" BARBS_PASS="$USERPASS"

log "Entering chroot for system config..."
artix-chroot /mnt /bin/bash -euo pipefail << CHROOT_EOF
set -euo pipefail
log() { printf "\n\033[1;32m[chroot] %s\033[0m\n" "\$*"; }

# shell variables passed through env from outer script
: "\${HOSTNAME:?}" "\${NEWUSER:?}" "\${USERPASS:?}" "\${ROOTPASS:?}" "\${HOST_TZ:?}" "\${LOCALE:?}" "\${KEYMAP:?}" "\${FS_TYPE:?}" "\${USE_LUKS:?}" "\${ROOT_MAPPER_NAME:?}" "\${ROOT_UUID:?}" "\${ESP_UUID:?}" "\${BOOTLABEL:?}" "\${BOOT_MODE:?}"

log "Locale, time, hostname..."
echo "KEYMAP=\${KEYMAP}" > /etc/vconsole.conf
sed -i "s/^#\(\${LOCALE//\//\/}\)/\1/" /etc/locale.gen || true
echo "\${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=\${LOCALE}" > /etc/locale.conf
ln -sf "/usr/share/zoneinfo/\${HOST_TZ}" /etc/localtime
hwclock --systohc

echo "\${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   \${HOSTNAME}.localdomain \${HOSTNAME}
EOF

log "Initramfs hooks (encrypt if needed)..."
# mkinitcpio hooks
if [[ "\${USE_LUKS}" =~ ^[Yy]$ ]]; then
  sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard keymap encrypt filesystems fsck)/' /etc/mkinitcpio.conf
else
  sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/' /etc/mkinitcpio.conf
fi
mkinitcpio -P

log "Users and passwords..."
echo "root:\${ROOTPASS}" | chpasswd
useradd -m -G wheel,audio,video,storage,lp,network -s /bin/zsh "\${NEWUSER}"
echo "\${NEWUSER}:\${USERPASS}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

log "Enabling runit services (NetworkManager, sshd, openntpd, cronie, dbus, elogind)..."
ln -sf /etc/runit/sv/dbus /etc/runit/runsvdir/default/
ln -sf /etc/runit/sv/elogind /etc/runit/runsvdir/default/
ln -sf /etc/runit/sv/NetworkManager /etc/runit/runsvdir/default/
ln -sf /etc/runit/sv/sshd /etc/runit/runsvdir/default/
ln -sf /etc/runit/sv/openntpd /etc/runit/runsvdir/default/
ln -sf /etc/runit/sv/cronie /etc/runit/runsvdir/default/

# Make openntpd wait for network before starting
printf '#!/bin/sh\nip route get 1.1.1.1 >/dev/null 2>&1\n' > /etc/runit/sv/openntpd/check
chmod +x /etc/runit/sv/openntpd/check

# Sync system clock (ntpd -s is deprecated, use direct date correction)
log "Syncing system clock..."
hwclock --systohc --utc || true

log "GRUB configuration..."
# Kernel command line configuration
if [[ "\${USE_LUKS}" =~ ^[Yy]$ ]]; then
  # Enable GRUB cryptodisk support for LUKS
  if grep -q '^#\?GRUB_ENABLE_CRYPTODISK' /etc/default/grub 2>/dev/null; then
    sed -i 's/^#\?GRUB_ENABLE_CRYPTODISK.*/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
  else
    echo 'GRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub
  fi
  # Use UUID of the physical LUKS container; GRUB unlocks to /dev/mapper/\${ROOT_MAPPER_NAME}
  sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\${ROOT_UUID}:\${ROOT_MAPPER_NAME} root=/dev/mapper/\${ROOT_MAPPER_NAME}\"|" /etc/default/grub
else
  # Non-encrypted: use filesystem UUID directly
  sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"root=UUID=\${ROOT_UUID}\"|" /etc/default/grub
fi

# Aegix branding
sed -i 's/GRUB_DISTRIBUTOR="Artix"/GRUB_DISTRIBUTOR="Aegix"/' /etc/default/grub

# GRUB background image
if [[ -f /root/mt-aso-penguin.png ]]; then
  mkdir -p /boot/grub
  cp /root/mt-aso-penguin.png /boot/grub/
  sed -i "s|^#GRUB_BACKGROUND=.*|GRUB_BACKGROUND=\"/boot/grub/mt-aso-penguin.png\"|" /etc/default/grub
fi

# Boot timeout and cosmetics
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=14/' /etc/default/grub

# Install GRUB based on boot mode
if [[ "\${BOOT_MODE}" == "uefi" ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=\${BOOTLABEL} --recheck
else
  grub-install --target=i386-pc "\${selected_device}"
fi

grub-mkconfig -o /boot/grub/grub.cfg

# Run BARBS if available
if [[ -f /root/barbs.sh ]]; then
  log "Running BARBS for desktop environment setup..."
  bash /root/barbs.sh || log "BARBS failed or was cancelled. Check /root/barbs-errors.log for details."
else
  log "BARBS not found. Skipping desktop environment setup."
  log "You can download and run barbs.sh manually after rebooting."
fi

log "Done inside chroot."
CHROOT_EOF

# Fix fstab for timeshift compatibility if using btrfs
if [[ "$FS_TYPE" == "btrfs" ]]; then
  log "Fixing fstab for timeshift compatibility..."
  sed -i 's/subvolid=[0-9]*,//' /mnt/etc/fstab
fi

### -------------------------------
### wrap up
### -------------------------------
log "Syncing and unmounting..."
sync
umount -R /mnt || true

log "Installation finished!"
log "Run: poweroff"
log "Once the machine is fully off, remove the installation media."
log "Then power on and select your drive from the boot menu."
