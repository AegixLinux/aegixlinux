# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About Aegix Linux

Aegix Linux is a minimal, security-focused Linux distribution built on Artix Linux (using runit init instead of systemd). It features a suckless software environment (dwm, dmenu, st, dwmblocks) with LUKS encryption, BTRFS filesystem, and vim-centric keybindings throughout.

## Repository Structure

This is the main Aegix Linux repository containing:
- **Installation scripts**: `install.sh` (BIOS/LUKS/BTRFS), `uefi_install.sh` (UEFI/Framework 13), `install-no-luks.sh`
- **Git submodules**: barbs, gohan, dwm, st, dmenu, dwmblocks (see .gitmodules)
- **Website**: Hugo-based documentation site in `website/`
- **Scripts**: Novel scripts in `novel_scripts/` (e.g., `grideo` video manager)
- **Deployment**: `deploy.sh` rsync script to push to Vultr VPS

## Common Commands

### Installation
```bash
# Standard installation (from Artix base runit ISO)
curl -LO aegixlinux.org/install.sh && sh install.sh

# UEFI installation (Framework 13 and modern hardware)
bash uefi_install.sh

# Desktop environment post-install
cd barbs && sh barbs.sh
```

### Suckless Components
Each component (dwm, st, dmenu, dwmblocks) has its own directory with C source:
```bash
cd dwm && make && sudo make install
cd st && make && sudo make install
cd dmenu && make && sudo make install
cd dwmblocks && make && sudo make install
```

### Website Development
```bash
cd website
npm install                    # Install dependencies
npm run serve                  # Development server
npm run build:production       # Production build
npm run clean                  # Clean build artifacts
```

### Deployment
```bash
# Deploy installation files and website to Vultr VPS
./deploy.sh                    # Requires SSH access to 'vultr' host
```

### Git Submodule Management
```bash
git submodule update --init --recursive    # Initialize submodules
git submodule update --remote              # Update all submodules
```

## Architecture

### Installation System Flow
1. **install.sh**: BIOS boot, LUKS encryption, BTRFS subvolumes (@, @home), base system
2. **uefi_install.sh**: UEFI boot (GPT+ESP), optional LUKS, ext4/btrfs, Framework 13 optimized
3. **barbs.sh**: Desktop environment installer
   - Reads `aegix-programs.csv` for package lists
   - Installs from pacman repos (no tag), AUR (A tag), git (G tag), pip (P tag)
   - Clones gohan dotfiles from GitHub
   - Configures suckless components

### Package Management via CSV
`barbs/aegix-programs.csv` defines all packages with tags:
- (blank): Official Artix/Arch repositories
- `A`: AUR packages (requires yay)
- `G`: Git repositories (cloned and built with make)
- `P`: Python pip packages

### Suckless Component Configuration
Each component has `config.h` with customizations:
- Consistent color scheme across dwm/st/dmenu
- Custom keybindings (vim-centric)
- Gaps, scratchpads, patches applied
- Compile with `make && sudo make install`

### Website Structure (Hugo)
- **Framework**: Hugo extended v0.120.4 with Docsy theme
- **Content**: English content in `content/en/`
- **Deployment**: Self-hosted on Vultr VPS via rsync
- **Scripts**: npm scripts for build/serve/clean

### Release System
- Named releases follow lunar/cultural themes (Pink Moon, Blood Moon, Scooter Pie, Harvest Moon)
- Branch naming: `release/name_of_release`
- Main development branch: `master`
- Current branch: `release/harvest_moon`
- All releases documented in RELEASE_NOTES.md

## Key Scripts and Tools

### grideo (Video Manager)
Located in `novel_scripts/grideo`:
- Thumbnail-first video reviewer for `~/Videos/obs`
- Uses sxiv for gallery view with key-handler for video operations
- Shortcuts: p (play), r (rename), d (delete), i (info)
- Dependencies: sxiv, ffmpeg, mpv

### install.sh (BIOS/Legacy)
- Interactive LUKS encryption setup with passphrase collection
- BTRFS subvolume creation (@ for root, @home for home)
- Downloads barbs.sh, GRUB background, ASCII art
- Base URL: aegixlinux.org
- Uses dialog for interactive prompts

### uefi_install.sh (UEFI)
- GPT partitioning with ESP at /boot (no /boot/efi)
- Framework 13 optimized (requires UEFI boot)
- Supports ext4 (default) or btrfs via FS_TYPE env var
- Optional LUKS encryption
- Uses bash with strict error handling (`set -euo pipefail`)

### barbs.sh (BARBS - Beach Automation Routine for Building Systems)
- Post-install desktop environment setup
- Enables Artix universe and Arch repositories
- Installs AUR helper (yay)
- Processes aegix-programs.csv for package installation
- Clones gohan dotfiles to user home directory

### deploy.sh
Rsync deployment to Vultr VPS (`vultr` SSH host):
- Installation scripts (install.sh, install-no-luks.sh, install-canary.sh)
- BARBS scripts and CSV
- README, ASCII art, images directory

## Important Technical Details

### Security Features
- LUKS full-disk encryption by default
- BTRFS subvolumes for snapshots and rollback
- Artix Linux base (runit init, no systemd)
- Minimal attack surface via suckless philosophy

### Filesystem Layout (BTRFS)
- Root subvolume: `@`
- Home subvolume: `@home`
- Compatible with timeshift for snapshots
- User directories: Downloads, Documents, Pictures, Music, Videos/obs, code, ss

### Color Scheme
Nature-inspired palette with earthy tones:
- #c7a162, #dca917, #b58941 (browns/golds)
- #59ac6c (green)
- #ec523e (red accent)
- PyWal integration for wallpaper-based theming

### Target Hardware
Primarily tested on ThinkPads (X220, T420/T420s/T430, T440, P50) and Framework 13 (UEFI).
Works on any x86 machine with LEGACY BIOS or UEFI support.

## Development Notes

- Each suckless component is heavily patched and customized
- Installation requires user interaction (disk selection, passwords, system config)
- BARBS inspired by Luke Smith's LARBS; gohan borrows from voidrice
- Website uses Hugo modules for Docsy theme management
- All scripts designed for Artix base runit ISO environment
- Repository contains both BIOS (install.sh) and UEFI (uefi_install.sh) installers

## Testing
- Test installations on supported hardware
- Verify LUKS encryption and BTRFS functionality
- Test suckless component builds after config.h changes
- Ensure website builds with `npm run build:production`
- Verify barbs.sh package installation from CSV
