#!/usr/bin/env bash
# Aegix/Artix installer — UEFI‑ready for Framework 13 (UEFI‑only)
# Works on any UEFI PC; falls back to legacy GRUB only if firmware isn't UEFI.
# - GPT + ESP at /boot (no /boot/efi needed)
# - Optional LUKS on root
# - ext4 root by default (set FS_TYPE=btrfs to use btrfs — basic layout)
# - Artix base with runit services

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
need parted; need lsblk; need sed; need awk; need cryptsetup; need mkfs.fat
need basestrap; need fstabgen; need artix-chroot; need mkinitcpio

if [[ ! -d /sys/firmware/efi ]]; then
  error_exit "This machine is not booted in UEFI mode. Framework 13 requires UEFI. Reboot firmware in UEFI mode."
fi

### -------------------------------
### config (edit if you like)
### -------------------------------
FS_TYPE=${FS_TYPE:-ext4}        # ext4 or btrfs
ESP_SIZE_MIB=${ESP_SIZE_MIB:-512}
HOST_TZ_DEFAULT=${HOST_TZ_DEFAULT:-America/New_York}
LOCALE_DEFAULT=${LOCALE_DEFAULT:-en_US.UTF-8}
KEYMAP_DEFAULT=${KEYMAP_DEFAULT:-us}
BOOTLABEL=${BOOTLABEL:-Aegix}
ROOT_MAPPER_NAME=${ROOT_MAPPER_NAME:-cryptroot}

### -------------------------------
### pick target disk
### -------------------------------
log "Detecting block devices…"
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

read -rp "Encrypt root with LUKS? [y/N]: " USE_LUKS; USE_LUKS=${USE_LUKS:-N}
if [[ "$USE_LUKS" =~ ^[Yy]$ ]]; then
  read -rsp "LUKS passphrase: " LUKS_PASS; echo
fi

### -------------------------------
### partitioning (GPT + ESP at /boot)
### -------------------------------
log "Partitioning $selected_device (GPT, ESP ${ESP_SIZE_MIB}MiB)…"
parted -s -a optimal "$selected_device" mklabel gpt
# 1MiB-(${ESP_SIZE_MIB}+1)MiB ESP + rest root
ESP_END_MIB=$((1 + ESP_SIZE_MIB))
parted -s -a optimal "$selected_device" mkpart ESP fat32 1MiB ${ESP_END_MIB}MiB
parted -s "$selected_device" set 1 esp on
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

log "Formatting ESP as FAT32…"
mkfs.fat -F32 -n EFI "$boot_partition"

### -------------------------------
### root filesystem (LUKS -> FS or plain FS)
### -------------------------------
if [[ "$USE_LUKS" =~ ^[Yy]$ ]]; then
  log "Setting up LUKS on $root_partition…"
  printf "%s" "$LUKS_PASS" | cryptsetup luksFormat --type luks2 "$root_partition" -q --batch-mode --pbkdf argon2id --iter-time 3000 --use-urandom --label AEGIX_ROOT --cipher aes-xts-plain64 --key-size 512 --hash sha512
  printf "%s" "$LUKS_PASS" | cryptsetup open "$root_partition" "$ROOT_MAPPER_NAME" -q --key-file -
  MAPPED_ROOT="/dev/mapper/${ROOT_MAPPER_NAME}"
else
  MAPPED_ROOT="$root_partition"
fi

case "$FS_TYPE" in
  ext4)
    log "Creating ext4 filesystem on $MAPPED_ROOT…"
    mkfs.ext4 -L ROOT "$MAPPED_ROOT";;
  btrfs)
    need mkfs.btrfs
    log "Creating btrfs filesystem on $MAPPED_ROOT…"
    mkfs.btrfs -L ROOT "$MAPPED_ROOT"
    ;;
  *) error_exit "Unsupported FS_TYPE: $FS_TYPE";;
esac

### -------------------------------
### mount target
### -------------------------------
log "Mounting target filesystem…"
mkdir -p /mnt
if [[ "$FS_TYPE" == btrfs ]]; then
  mount "$MAPPED_ROOT" /mnt
  btrfs subvolume create /mnt/@
  btrfs subvolume create /mnt/@home
  umount /mnt
  mount -o subvol=@ "$MAPPED_ROOT" /mnt
  mkdir -p /mnt/home
  mount -o subvol=@home "$MAPPED_ROOT" /mnt/home
else
  mount "$MAPPED_ROOT" /mnt
fi
mkdir -p /mnt/boot
mount "$boot_partition" /mnt/boot

### -------------------------------
### base system install
### -------------------------------
log "Installing base system (Artix + runit)…"
PKGS_BASE=(base base-devel linux linux-firmware grub efibootmgr sudo vim neovim nano less man-db man-pages)
PKGS_FS=(dosfstools e2fsprogs btrfs-progs)
PKGS_MISC=(openssh cryptsetup lvm2 brightnessctl htop networkmanager)
PKGS_RUNIT=(runit elogind polkit-elogind networkmanager-runit openssh-runit openntpd openntpd-runit cronie cronie-runit lvm2-runit)

basestrap -i /mnt "${PKGS_BASE[@]}" "${PKGS_FS[@]}" "${PKGS_MISC[@]}" "${PKGS_RUNIT[@]}"

### -------------------------------
### fstab
### -------------------------------
log "Generating fstab…"
fstabgen -U /mnt >> /mnt/etc/fstab

# Get UUIDs for bootloader and crypttab configuration
ROOT_UUID=$(blkid -s UUID -o value "$root_partition")
ESP_UUID=$(blkid -s UUID -o value "$boot_partition")

# Add crypttab for LUKS
if [[ "$USE_LUKS" =~ ^[Yy]$ ]]; then
  log "Configuring crypttab…"
  echo "${ROOT_MAPPER_NAME} UUID=${ROOT_UUID} none luks" >> /mnt/etc/crypttab
fi

### -------------------------------
### chroot configuration
### -------------------------------

# Export all variables needed in chroot
export HOSTNAME NEWUSER USERPASS ROOTPASS HOST_TZ LOCALE KEYMAP
export FS_TYPE USE_LUKS ROOT_MAPPER_NAME ROOT_UUID ESP_UUID BOOTLABEL selected_device

log "Entering chroot for system config…"
artix-chroot /mnt /bin/bash -euo pipefail << CHROOT_EOF
set -euo pipefail
log() { printf "\n\033[1;32m[chroot] %s\033[0m\n" "$*"; }

# shell variables passed through env from outer script
: "${HOSTNAME:?}" "${NEWUSER:?}" "${USERPASS:?}" "${ROOTPASS:?}" "${HOST_TZ:?}" "${LOCALE:?}" "${KEYMAP:?}" "${FS_TYPE:?}" "${USE_LUKS:?}" "${ROOT_MAPPER_NAME:?}" "${ROOT_UUID:?}" "${ESP_UUID:?}" "${BOOTLABEL:?}"

log "Locale, time, hostname…"
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
sed -i "s/^#\(${LOCALE//\//\/}\)/\1/" /etc/locale.gen || true
echo "${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
ln -sf "/usr/share/zoneinfo/${HOST_TZ}" /etc/localtime
hwclock --systohc

echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

log "Initramfs hooks (encrypt if needed)…"
# mkinitcpio hooks
if [[ "${USE_LUKS}" =~ ^[Yy]$ ]]; then
  sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block keyboard keymap encrypt filesystems fsck)/' /etc/mkinitcpio.conf
else
  sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/' /etc/mkinitcpio.conf
fi
mkinitcpio -P

log "Users and passwords…"
echo "root:${ROOTPASS}" | chpasswd
useradd -m -G wheel,audio,video,storage,lp,network -s /bin/bash "${NEWUSER}"
echo "${NEWUSER}:${USERPASS}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

log "Enabling runit services (NetworkManager, sshd, openntpd, cronie)…"
ln -sf /etc/runit/sv/NetworkManager /etc/runit/runsvdir/default/
ln -sf /etc/runit/sv/sshd /etc/runit/runsvdir/default/
ln -sf /etc/runit/sv/openntpd /etc/runit/runsvdir/default/
ln -sf /etc/runit/sv/cronie /etc/runit/runsvdir/default/

log "GRUB configuration…"
# Kernel command line configuration
if [[ "${USE_LUKS}" =~ ^[Yy]$ ]]; then
  # Enable GRUB cryptodisk support for LUKS
  if grep -q '^#\?GRUB_ENABLE_CRYPTODISK' /etc/default/grub 2>/dev/null; then
    sed -i 's/^#\?GRUB_ENABLE_CRYPTODISK.*/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
  else
    echo 'GRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub
  fi
  # Use UUID of the physical LUKS container; GRUB unlocks to /dev/mapper/${ROOT_MAPPER_NAME}
  sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=${ROOT_UUID}:${ROOT_MAPPER_NAME} root=/dev/mapper/${ROOT_MAPPER_NAME}\"|" /etc/default/grub
else
  # Non-encrypted: use filesystem UUID directly
  sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"root=UUID=${ROOT_UUID}\"|" /etc/default/grub
fi

# Aegix branding
sed -i 's/GRUB_DISTRIBUTOR="Artix"/GRUB_DISTRIBUTOR="Aegix"/' /etc/default/grub

# Quiet boot cosmetics optional (comment out if unwanted)
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub
sed -i 's/^#GRUB_DISABLE_SUBMENU.*/GRUB_DISABLE_SUBMENU=y/' /etc/default/grub

# Install GRUB (UEFI primary; legacy fallback if ever on an old box)
if [[ -d /sys/firmware/efi ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=\${BOOTLABEL} --recheck
else
  # You won't hit this on Framework, but keep for portability
  grub-install --target=i386-pc "\${selected_device}"
fi

grub-mkconfig -o /boot/grub/grub.cfg

log "Done inside chroot."
CHROOT_EOF

# Fix fstab for timeshift compatibility if using btrfs
if [[ "$FS_TYPE" == "btrfs" ]]; then
  log "Fixing fstab for timeshift compatibility…"
  sed -i 's/subvolid=[0-9]*,//' /mnt/etc/fstab
fi

### -------------------------------
### wrap up
### -------------------------------
log "Syncing and unmounting…"
sync
umount -R /mnt || true

log "Installation finished. You can reboot now. Use F12 → select your NVMe (UEFI) entry."
