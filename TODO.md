# Aegix Linux TODO - Implementation Plans

## IMMEDIATE

### ✅ Get uefi_install.sh working with barbs-canary.sh
**STATUS**: Mostly working! GRUB background ✓, Desktop background ✓, System boots ✓
**REMAINING**: Fix nvim config snag

#### Fix nvim plugin install hang
**Problem**: `nvim -c "PlugInstall|q|q"` in barbs-canary.sh:234 leaves nvim open if PlugInstall fails
**Root cause**: Interactive nvim waits for user input on errors

**Implementation**:
```bash
# In barbs-canary.sh vim_plugin_install() function (line 228-235):
# Change from:
sudo -u "${user_name}" nvim -c "PlugInstall|q|q"

# To (headless mode with better error handling):
sudo -u "${user_name}" nvim --headless -c "PlugInstall" -c "qa" >> "${LOG_FILE}" 2>&1 || {
    log_message "✗ FAILED: Vim plugin install" | tee -a "${INSTALL_LOG}" "${ERROR_LOG}"
    log_message "You can install manually later with: nvim -c PlugInstall"
    return 0  # Don't fail entire script for vim plugins
}
```

**Files to edit**: `barbs/barbs-canary.sh`

---

### 🔧 Pass username/password from uefi_install.sh to barbs-canary.sh
**Problem**: User enters same username/password twice (uefi_install.sh → barbs-canary.sh)
**User experience**: Annoying repetition, creates confusion

#### Implementation Option A: Environment Variables (RECOMMENDED)
**Why**: Cleanest approach, no script signature changes, secure within chroot

```bash
# In uefi_install.sh (around line 202-205, in chroot exports section):
# Add to existing exports:
export HOSTNAME NEWUSER USERPASS ROOTPASS HOST_TZ LOCALE KEYMAP
export FS_TYPE USE_LUKS ROOT_MAPPER_NAME ROOT_UUID ESP_UUID BOOTLABEL selected_device
export BARBS_USER="${NEWUSER}"      # ADD THIS
export BARBS_PASS="${USERPASS}"     # ADD THIS

# In barbs-canary.sh get_user_and_pw() function (line 242-257):
# Add this at the START of the function:
get_user_and_pw() {
    # Check if credentials provided by installer
    if [[ -n "${BARBS_USER}" && -n "${BARBS_PASS}" ]]; then
        user_name="${BARBS_USER}"
        pass1="${BARBS_PASS}"
        pass2="${BARBS_PASS}"
        whiptail --title "Installer Credentials" --msgbox "Using username from installer: ${user_name}" 8 60
        return 0
    fi

    # Otherwise prompt as normal (existing code continues)
    user_name=$(whiptail --inputbox "Enter a username..." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
    # ... rest of existing code
}
```

#### Implementation Option B: Command-line Arguments
```bash
# In uefi_install.sh (line 293):
# Change from:
bash /root/barbs-canary.sh

# To:
bash /root/barbs-canary.sh --user "${NEWUSER}" --pass "${USERPASS}"

# In barbs-canary.sh, add argument parsing BEFORE main() (line 10-15):
# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --user) BARBS_USER="$2"; shift 2 ;;
        --pass) BARBS_PASS="$2"; shift 2 ;;
        *) shift ;;
    esac
done
```

**Recommended**: **Option A** - cleaner, more secure, no changes to script calling convention

**Files to edit**: `uefi_install.sh`, `barbs/barbs-canary.sh`

---

### 🔒 Confirm passphrases by entering twice
**Problem**: Users mistype passphrases, don't realize until reboot/login fails
**Current state**: LUKS + root confirmed, but user password is NOT confirmed

#### Implementation: Add confirmation loop for user password
```bash
# In uefi_install.sh (around line 62-63):
# Change from:
read -rsp "Password for $NEWUSER: " USERPASS; echo
read -rsp "Password for root: " ROOTPASS; echo

# To:
# User password with confirmation
while true; do
    read -rsp "Password for $NEWUSER: " USERPASS1; echo
    read -rsp "Confirm password for $NEWUSER: " USERPASS2; echo

    if [[ -z "$USERPASS1" ]]; then
        echo "Password cannot be empty. Try again."
        continue
    fi

    if [[ "$USERPASS1" == "$USERPASS2" ]]; then
        USERPASS="$USERPASS1"
        unset USERPASS1 USERPASS2
        break
    else
        echo "Passwords do not match. Try again."
    fi
done

# Root password with confirmation (check if already confirmed)
while true; do
    read -rsp "Password for root: " ROOTPASS1; echo
    read -rsp "Confirm password for root: " ROOTPASS2; echo

    if [[ -z "$ROOTPASS1" ]]; then
        echo "Password cannot be empty. Try again."
        continue
    fi

    if [[ "$ROOTPASS1" == "$ROOTPASS2" ]]; then
        ROOTPASS="$ROOTPASS1"
        unset ROOTPASS1 ROOTPASS2
        break
    else
        echo "Passwords do not match. Try again."
    fi
done
```

**Note**: LUKS passphrase already has confirmation (lines 83-84), so that's good!

**Files to edit**: `uefi_install.sh`

---

### 📢 Tell user to shutdown at end
**Problem**: Script says "you can reboot now" but doesn't give clear shutdown instructions
**Better UX**: Explicit shutdown command + next steps

#### Implementation: Enhanced completion message
```bash
# In uefi_install.sh (around line 305-306):
# Change from:
log "Installation finished. You can reboot now. Use F12 → select your NVMe (UEFI) entry."

# To:
log ""
log "========================================="
log "  Aegix Linux Installation Complete!"
log "========================================="
log ""
log "NEXT STEPS:"
log ""
log "1. Remove the installation USB drive"
log ""
log "2. Shutdown the system:"
log "   shutdown -h now"
log ""
log "3. Power on and access boot menu:"
log "   - Spam F12 key starting BEFORE you press power"
log "   - Select 'Aegix' or NVMe UEFI entry"
log ""
log "4. First boot login:"
log "   Username: ${NEWUSER}"
log "   Password: (what you just set)"
log ""
log "5. Start graphical environment:"
log "   startx"
log ""
log "Installation logs:"
log "   /root/barbs-install.log  (progress)"
log "   /root/barbs-errors.log   (failures)"
log ""
log "========================================="
log ""
```

**Files to edit**: `uefi_install.sh`

---

## MEDIUM TERM

### 📐 Detect screen resolution and adjust for HiDPI displays
**Problem**: Framework 13 has high-DPI screen (2256×1504), makes everything tiny
**Affected**: dwm, st, dmenu, dwmblocks - all suckless components with hardcoded pixel sizes

#### Analysis: Where DPI settings live

**dwm (window manager)**:
- `dwm/config.h`: Font sizes for bar, window titles
- Default: `static const char *fonts[] = { "monospace:size=10" };`
- HiDPI needs: `size=14` or `size=16`

**st (terminal)**:
- `st/config.h`: Terminal font size
- Default: `static char *font = "Liberation Mono:pixelsize=12";`
- HiDPI needs: `pixelsize=18` or `pixelsize=20`

**dmenu (launcher)**:
- `dmenu/config.h`: Menu font size
- Default: `static const char *fonts[] = { "monospace:size=10" };`
- HiDPI needs: `size=14` or `size=16`

**dwmblocks (status bar)**:
- `dwmblocks/config.h`: No direct font control (inherits from dwm)
- Script outputs may need adjustment

#### Implementation Strategy

**Option A: Detect and patch during BARBS install**
```bash
# In barbs-canary.sh, add function before git_make_install():

detect_and_patch_hidpi() {
    local component="$1"  # dwm, st, dmenu
    local config_file="${src_repo_dir}/${component}/config.h"

    # Detect screen resolution
    if command -v xrandr &>/dev/null; then
        # Get primary display resolution
        resolution=$(xrandr | grep -oP '\d+x\d+' | head -1)
        width=$(echo $resolution | cut -d'x' -f1)

        # Framework 13 or similar HiDPI (>1920 width)
        if [[ $width -gt 1920 ]]; then
            log_message "HiDPI display detected ($resolution), patching $component fonts..."

            case $component in
                dwm|dmenu)
                    # Increase font from size=10 to size=14
                    sed -i 's/size=10/size=14/g' "$config_file"
                    ;;
                st)
                    # Increase from pixelsize=12 to pixelsize=18
                    sed -i 's/pixelsize=12/pixelsize=18/g' "$config_file"
                    ;;
            esac
        fi
    fi
}

# Then modify git_make_install() to call it:
git_make_install() {
    # ... existing clone code ...

    cd "${dir}" || exit 1

    # Patch HiDPI if this is a suckless component
    case "$program_name" in
        dwm|st|dmenu) detect_and_patch_hidpi "$program_name" ;;
    esac

    # ... existing make/install code ...
}
```

**Option B: Post-install detection script**
```bash
# Create ~/bin/aegix-hidpi-fix script that user runs after first startx
#!/bin/bash
# Detect HiDPI and rebuild suckless components

resolution=$(xrandr | grep -oP '\d+x\d+' | head -1)
width=$(echo $resolution | cut -d'x' -f1)

if [[ $width -gt 1920 ]]; then
    echo "HiDPI detected! Rebuilding suckless components with larger fonts..."

    for component in dwm st dmenu; do
        cd ~/.local/src/$component
        sed -i 's/size=10/size=14/g' config.h 2>/dev/null
        sed -i 's/pixelsize=12/pixelsize=18/g' config.h 2>/dev/null
        sudo make clean install
    done

    echo "Done! Restart X to see changes (Mod+Shift+Q then startx)"
fi
```

**Option C: Xresources scaling (global)**
```bash
# In barbs-canary.sh or gohan dotfiles, add to ~/.Xresources:
! HiDPI scaling for Framework 13 and similar
Xft.dpi: 144
Xft.autohint: 0
Xft.lcdfilter: lcddefault
Xft.hintstyle: hintslight
Xft.hinting: 1
Xft.antialias: 1
Xft.rgba: rgb

# Then in ~/.xinitrc (before exec dwm):
xrdb -merge ~/.Xresources
```

#### Recommended Approach: **Combination of B + C**
1. Ship `~/bin/aegix-hidpi-fix` script with gohan dotfiles
2. Add Xft.dpi to .Xresources as fallback
3. Document in first-boot message or README

**Files to create**: `gohan/bin/aegix-hidpi-fix`, update `gohan/.Xresources`
**Files to edit**: `barbs/barbs-canary.sh` (optional detection), `uefi_install.sh` (post-install message)

---

## LONGER TERM

### 🔀 Unified script for UEFI and LEGACY BIOS
**Goal**: Single `install.sh` that auto-detects boot mode or asks user
**Current**: Separate `install.sh` (LEGACY) and `uefi_install.sh` (UEFI)

#### Implementation: Detect boot mode and branch

```bash
#!/usr/bin/env bash
# Unified Aegix installer - auto-detects UEFI vs LEGACY BIOS

set -euo pipefail

### Detect boot mode ###
detect_boot_mode() {
    if [[ -d /sys/firmware/efi ]]; then
        echo "UEFI"
    else
        echo "LEGACY"
    fi
}

### Main entry point ###
BOOT_MODE=$(detect_boot_mode)
log "Detected boot mode: ${BOOT_MODE}"

# Ask user to confirm or override
read -rp "Detected ${BOOT_MODE} boot. Is this correct? [Y/n]: " confirm
if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "1) UEFI"
    echo "2) LEGACY BIOS"
    read -rp "Select boot mode [1-2]: " choice
    case $choice in
        1) BOOT_MODE="UEFI" ;;
        2) BOOT_MODE="LEGACY" ;;
        *) error_exit "Invalid choice" ;;
    esac
fi

# Branch to appropriate installer logic
case $BOOT_MODE in
    UEFI)
        log "Using UEFI installation method..."
        # Source or call UEFI-specific functions
        source install_uefi_functions.sh
        run_uefi_install
        ;;
    LEGACY)
        log "Using LEGACY BIOS installation method..."
        # Source or call LEGACY-specific functions
        source install_legacy_functions.sh
        run_legacy_install
        ;;
esac
```

#### Refactoring strategy:
1. Extract common functions to `install_common.sh`:
   - User input collection
   - Package installation
   - BARBS integration
   - Network/service setup

2. UEFI-specific in `install_uefi_functions.sh`:
   - GPT partitioning
   - ESP setup at /boot
   - GRUB UEFI install

3. LEGACY-specific in `install_legacy_functions.sh`:
   - MBR/msdos partitioning
   - /boot as regular partition
   - GRUB BIOS install

4. Main `install.sh` orchestrates:
   - Detects mode
   - Sources appropriate functions
   - Calls unified workflow

**Files to create**: `install_common.sh`, `install_uefi_functions.sh`, `install_legacy_functions.sh`
**Files to refactor**: Current `install.sh` and `uefi_install.sh` → extract to functions

#### Benefits:
- ✅ One command for users: `bash install.sh`
- ✅ Auto-detection reduces errors
- ✅ Easier to maintain (shared code in one place)
- ✅ Can still support both boot modes

#### Challenges:
- 🔧 Requires significant refactoring
- 🔧 Testing needed on both UEFI and LEGACY hardware
- 🔧 Need to preserve backward compat (or document breaking change)

---

## BACKLOG / FUTURE IDEAS

### 🎨 Desktop background selection during install
- Download multiple backgrounds to ISO
- Show thumbnails with feh or similar during install
- Let user choose (like current install.sh)

### 🔐 TPM2 integration for auto-unlock
- Framework 13 has TPM 2.0
- Could auto-unlock LUKS with TPM + PIN
- See: systemd-cryptenroll

### 📦 Pre-download packages to ISO
- Include package cache in ISO
- Speeds up installs without internet
- Trade-off: larger ISO size

### 🌐 Network installer variant
- Minimal ISO (200MB vs 2GB)
- Downloads packages on demand
- Always gets latest versions

### 🐋 Docker/container testing
- Test install in container before ISO
- CI/CD for automated install testing
- Catch regressions faster

### 📱 Mobile device integration
- Auto-mount Android via simple-mtpfs
- Configure KDE Connect / scrcpy
- Phone backup scripts

---

## Implementation Priority (Recommended Order)

1. ✅ **Fix nvim hang** - Quick win, blocks current install
2. ✅ **Password confirmation** - Safety issue, important UX
3. ✅ **Pass user/pass to BARBS** - Removes annoying duplication
4. ✅ **Better shutdown message** - Simple, helps new users
5. 🔧 **HiDPI detection** - Affects Framework 13 (primary target)
6. 🔧 **Unified UEFI/LEGACY** - Major refactor, lower priority
7. 🎯 **ISO creation** - After install is stable (see ISO.md)

---

*Last updated: 2025-10-02*
*Next review: After successful Framework 13 install test*
