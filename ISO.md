# Aegix Linux Custom ISO Creation Guide

## Overview

After a successful Aegix installation, we can create a custom ISO that includes:
- Pre-configured base system
- Pre-installed packages from aegix-programs.csv
- Suckless components (dwm, st, dmenu, dwmblocks)
- Aegix branding and backgrounds
- Installation scripts (uefi_install.sh, barbs-canary.sh)

## Approach: Artix ISO with Customizations

Artix Linux (our base) uses a modified version of archiso. We'll create a custom profile based on Artix's base-runit ISO.

---

## Prerequisites

### On Your Working Aegix System:
```bash
# Install ISO building tools
sudo pacman -S archiso git squashfs-tools

# For Artix specifically, we need artools
sudo pacman -S artools
```

---

## Step 1: Prepare Build Environment

### 1.1 Create Build Directory Structure
```bash
mkdir -p ~/aegix-iso
cd ~/aegix-iso

# Copy Artix base profile as starting point
cp -r /usr/share/archiso/configs/releng ./aegix-profile
# OR for Artix:
# cp -r /usr/share/artools/iso-profiles/base-runit ./aegix-profile
```

### 1.2 Directory Structure
```
aegix-profile/
├── airootfs/           # Root filesystem overlay
│   ├── etc/            # System configs
│   ├── root/           # Root user files (install scripts!)
│   └── usr/
├── efiboot/            # EFI boot files
├── syslinux/           # BIOS boot files
├── packages.x86_64     # List of packages to include
├── pacman.conf         # Pacman configuration
└── profiledef.sh       # ISO metadata
```

---

## Step 2: Customize Package List

### 2.1 Edit `packages.x86_64`
This file lists all packages to pre-install on the ISO.

```bash
# Base system (keep Artix defaults)
base
base-devel
linux
linux-firmware

# Aegix essentials from our working system
vim
neovim
networkmanager
networkmanager-runit
git
curl
...

# Copy from aegix-programs.csv (official repo packages only, no AUR)
# We'll install AUR packages during live boot or post-install
```

**Strategy:**
- Include all official repo packages from aegix-programs.csv
- Skip AUR packages (A tag) - these install via BARBS
- Skip Git packages (G tag) - these install via BARBS
- Include essential tools for installation (parted, cryptsetup, etc.)

### 2.2 Add Artix Repositories
Edit `pacman.conf` to include universe and Arch repos:
```ini
[universe]
Server = https://universe.artixlinux.org/$arch

[extra]
Include = /etc/pacman.d/mirrorlist-arch
```

---

## Step 3: Add Aegix Files to ISO

### 3.1 Installation Scripts
```bash
# Copy install scripts to root home on ISO
mkdir -p aegix-profile/airootfs/root/
cp uefi_install.sh aegix-profile/airootfs/root/
cp barbs-canary.sh aegix-profile/airootfs/root/
cp barbs/aegix-programs.csv aegix-profile/airootfs/root/
```

### 3.2 Aegix Branding
```bash
# Desktop backgrounds
mkdir -p aegix-profile/airootfs/root/backgrounds/
cp images/ndh_aurora_mason.jpg aegix-profile/airootfs/root/backgrounds/
cp images/alcove_bg.png aegix-profile/airootfs/root/backgrounds/
cp images/mt-aso-penguin.png aegix-profile/airootfs/root/backgrounds/

# ASCII art and branding
cp ascii-aegix aegix-profile/airootfs/root/
cp README.md aegix-profile/airootfs/root/
```

### 3.3 Pre-built Suckless Components (Optional)
Two approaches:

**Option A: Build during install (current approach)**
- Include source in ISO
- BARBS builds during installation

**Option B: Pre-compile and include binaries**
```bash
# Build on working system
cd dwm && sudo make install
cd ../st && sudo make install
cd ../dmenu && sudo make install
cd ../dwmblocks && sudo make install

# Copy binaries to ISO
mkdir -p aegix-profile/airootfs/usr/local/bin/
cp /usr/local/bin/dwm aegix-profile/airootfs/usr/local/bin/
cp /usr/local/bin/st aegix-profile/airootfs/usr/local/bin/
# etc...
```

---

## Step 4: Configure ISO Metadata

### 4.1 Edit `profiledef.sh`
```bash
iso_name="aegix"
iso_label="AEGIX_$(date +%Y%m)"
iso_publisher="Aegix Linux <https://aegixlinux.org>"
iso_application="Aegix Linux Live/Rescue CD"
iso_version="$(date +%Y.%m.%d)"
install_dir="aegix"
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito' 'uefi-x64.systemd-boot.esp' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
```

### 4.2 Customize Boot Menu
Edit `syslinux/archiso_sys-linux.cfg` and `efiboot/loader/entries/*.conf`:
- Change "Artix" to "Aegix"
- Update branding text
- Set custom kernel parameters if needed

---

## Step 5: Build the ISO

### 5.1 Using mkarchiso (Arch) or buildiso (Artix)

**For Arch-based:**
```bash
sudo mkarchiso -v -w /tmp/aegix-work -o ~/aegix-iso/out ~/aegix-iso/aegix-profile
```

**For Artix (recommended):**
```bash
# Using artools buildiso
sudo buildiso -p aegix-profile -o ~/aegix-iso/out
```

### 5.2 Build Output
```
~/aegix-iso/out/aegix-2025.10.02-x86_64.iso
```

---

## Step 6: Test the ISO

### 6.1 Quick Test with QEMU
```bash
# Install qemu if needed
sudo pacman -S qemu-full

# Test ISO boot (UEFI)
qemu-system-x86_64 \
  -enable-kvm \
  -m 4G \
  -boot d \
  -cdrom ~/aegix-iso/out/aegix-*.iso \
  -bios /usr/share/ovmf/x64/OVMF.fd

# Test ISO boot (BIOS)
qemu-system-x86_64 \
  -enable-kvm \
  -m 4G \
  -boot d \
  -cdrom ~/aegix-iso/out/aegix-*.iso
```

### 6.2 Test Installation
```bash
# Create virtual disk for install test
qemu-img create -f qcow2 /tmp/test-disk.qcow2 20G

# Boot ISO with test disk
qemu-system-x86_64 \
  -enable-kvm \
  -m 4G \
  -boot d \
  -cdrom ~/aegix-iso/out/aegix-*.iso \
  -drive file=/tmp/test-disk.qcow2,format=qcow2 \
  -bios /usr/share/ovmf/x64/OVMF.fd
```

### 6.3 Flash to USB and Test on Real Hardware
```bash
# Find USB device
lsblk

# Flash ISO to USB (CAREFUL - this ERASES the USB!)
sudo dd if=~/aegix-iso/out/aegix-*.iso of=/dev/sdX bs=4M status=progress oflag=sync

# Test on Framework 13 or other hardware
```

---

## Step 7: Auto-run Install Script on Boot (Optional)

### 7.1 Add to Root's .zshrc or .bashrc
```bash
# In aegix-profile/airootfs/root/.zshrc
cat << 'EOF' >> aegix-profile/airootfs/root/.zshrc

# Auto-display Aegix welcome on first login
if [ -f ~/ascii-aegix ]; then
  cat ~/ascii-aegix
  echo ""
  echo "Welcome to Aegix Linux Live ISO!"
  echo ""
  echo "To install Aegix to your system, run:"
  echo "  bash ~/uefi_install.sh"
  echo ""
fi
EOF
```

### 7.2 Auto-start Install (Aggressive Approach)
```bash
# This immediately starts install on boot (use with caution!)
cat << 'EOF' >> aegix-profile/airootfs/root/.zshrc
if [ -f ~/uefi_install.sh ] && [ ! -f ~/.install_prompted ]; then
  touch ~/.install_prompted
  read -p "Run Aegix installer now? [y/N]: " response
  if [[ "$response" =~ ^[Yy]$ ]]; then
    bash ~/uefi_install.sh
  fi
fi
EOF
```

---

## Step 8: Advanced Customizations

### 8.1 Include AUR Helper Pre-installed
```bash
# Build yay on working system
git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
cd /tmp/yay-bin
makepkg -si

# Copy binary to ISO
mkdir -p aegix-profile/airootfs/usr/local/bin/
cp /usr/bin/yay aegix-profile/airootfs/usr/local/bin/
```

### 8.2 Pre-cache Package Downloads
```bash
# Include package cache on ISO to speed up installs
mkdir -p aegix-profile/airootfs/var/cache/pacman/pkg/
cp /var/cache/pacman/pkg/*.pkg.tar.zst aegix-profile/airootfs/var/cache/pacman/pkg/
```

### 8.3 Custom Kernel Parameters
Edit `syslinux/archiso_sys-linux.cfg`:
```
LABEL aegix
    MENU LABEL Aegix Linux
    LINUX /%INSTALL_DIR%/boot/x86_64/vmlinuz-linux
    INITRD /%INSTALL_DIR%/boot/x86_64/initramfs-linux.img
    APPEND archisobasedir=%INSTALL_DIR% archisolabel=%ARCHISO_LABEL% cow_spacesize=4G
```

---

## Step 9: Versioning and Distribution

### 9.1 Naming Convention
```bash
# Follow lunar/cultural themes (like current releases)
aegix-harvest_moon-2025.10.02-x86_64.iso
aegix-blood_moon-2025.03.14-x86_64.iso
```

### 9.2 Generate Checksums
```bash
cd ~/aegix-iso/out/
sha256sum aegix-*.iso > aegix-*.iso.sha256
md5sum aegix-*.iso > aegix-*.iso.md5
```

### 9.3 Upload to aegixlinux.org
```bash
# Using your existing deploy.sh pattern
rsync -avz ~/aegix-iso/out/aegix-*.iso* vultr:/var/www/aegixlinux.org/iso/
```

---

## Troubleshooting

### ISO Won't Boot
- Check UEFI/BIOS boot modes in profiledef.sh
- Verify syslinux/grub configs
- Test with different QEMU BIOS options

### Missing Packages
- Check pacman.conf has all required repos
- Run `pacman -Syu` before building
- Verify packages.x86_64 syntax (one package per line)

### ISO Too Large
- Remove unnecessary packages
- Don't include package cache
- Use compression in mksquashfs options

### Installation Script Not Found
- Verify files in aegix-profile/airootfs/root/
- Check file permissions (chmod +x for scripts)
- Rebuild ISO after adding files

---

## Next Steps After First ISO

1. **Automate Builds**: Create build script that pulls latest from git
2. **CI/CD**: Set up GitHub Actions to build ISO on each release
3. **Persistence**: Add option for persistent live USB
4. **Network Install**: Create minimal ISO that downloads packages on-demand
5. **Multiple Flavors**: Create variants (minimal, full, developer, etc.)

---

## References

- Arch Wiki: https://wiki.archlinux.org/title/Archiso
- Artix ISO Profiles: https://gitea.artixlinux.org/artix/artools-iso
- ArchISO GitLab: https://gitlab.archlinux.org/archlinux/archiso

---

## TODO for Aegix ISO v1.0

- [ ] Test buildiso on working Aegix system
- [ ] Create aegix-profile based on Artix base-runit
- [ ] Include uefi_install.sh, barbs-canary.sh, aegix-programs.csv
- [ ] Add both backgrounds (ndh_aurora_mason.jpg, mt-aso-penguin.png)
- [ ] Test ISO boot in QEMU (UEFI and BIOS)
- [ ] Test full installation from ISO to virtual disk
- [ ] Test on Framework 13 hardware
- [ ] Generate checksums and upload to aegixlinux.org
- [ ] Document ISO usage in website/docs
- [ ] Create automated build script
