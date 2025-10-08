# RELEASE NOTES

## Full Moon Release 7 - Harvest Moon

**Branch name**: `release/harvest_moon`

**Date**: 2025-10-06 Sun

---

The **Harvest Moon** release arrives under tonight's full moon, bringing production-ready UEFI support to Aegix Linux. This milestone release makes Aegix fully compatible with modern UEFI-only hardware like the Framework 13 laptop, while expanding our documentation to support 4K displays, LUKS management, and custom ISO creation.

---

### Major Changes

- **🚀 Production UEFI Installer (`uefi_install.sh`)**
- **📖 Comprehensive Documentation Suite**
- **🎨 4K Display Support**
- **🔐 LUKS Encryption Management Guide**
- **💿 Custom ISO Creation Documentation**

#### 🚀 Production-Ready UEFI Installation

The cornerstone of this release: `uefi_install.sh` - a complete UEFI-native installer designed for modern hardware.

**Features:**
- GPT partitioning with ESP at `/boot`
- UEFI boot requirement check
- Optional LUKS full-disk encryption
- Choice of ext4 (default) or btrfs filesystems
- Robust error handling (`set -euo pipefail`)
- Interactive configuration (hostname, users, timezone, locale)
- Artix base with runit init

**Supported Hardware:**
- Framework 13 (UEFI-only, fully tested)
- Any modern UEFI system (2012+)
- Graceful fallback if UEFI not detected

**Usage:**
```bash
curl -LO aegixlinux.org/uefi_install.sh
bash uefi_install.sh
```

**Technical Details:**
- ESP: 512 MiB at `/boot` (no `/boot/efi` mount point)
- Root: Optional LUKS encryption on remaining space
- GRUB UEFI bootloader installed to ESP
- initramfs with LUKS hooks when encryption enabled

#### 📖 Documentation Expansion

**CLAUDE.md** - AI-assisted development guide:
- Complete repository structure
- Installation workflows
- Suckless component build process
- Website development commands
- Git submodule management
- System architecture documentation

**4K_README.md** - High-DPI display configuration:
- Native 4K resolution settings (no scaling blur)
- Suckless software font size adjustments (dwm, st, dmenu)
- Smart Brave browser wrapper (auto-detects resolution)
- Seamless switching between 4K laptop and 1080p external displays
- Tested on Framework 13 internal 4K panel

**LUKS_MANAGEMENT.md** - Encryption passphrase management:
- Safe two-step passphrase change process
- Multi-key slot management
- Emergency recovery procedures
- Best practices for LUKS security
- Partition identification for BIOS vs UEFI systems

**ISO.md** - Custom ISO creation guide:
- Artix ISO building with archiso/artools
- Package customization
- Pre-install Aegix branding and scripts
- QEMU testing workflows
- Distribution and versioning

---

### Installation

**UEFI Systems (Framework 13, modern laptops):**
```bash
curl -LO aegixlinux.org/uefi_install.sh
bash uefi_install.sh
```

**Legacy BIOS Systems:**
```bash
curl -LO aegixlinux.org/install.sh
sh install.sh
```

**Desktop Environment (post-install):**
```bash
cd barbs && sh barbs.sh
```

---

### Contributors to this Release

Under the Harvest Moon, we give thanks to:

- [Mason U. Borchard](https://github.com/mason-u-borchard)
- [Timothy D. Beach](https://github.com/timbeach)
- [AegixLinux Community](https://github.com/AegixLinux)

---

## Full Moon Release 6 - Scooter Pie

**Branch name**: `release/scooter_pie`

**Date**: 2025-09-07 Sun 

---

The **Scooter Pie** release marks our return after an extended period of deep development and experimentation. This release consolidates months of iterative improvements, system refinements, and the introduction of our first custom media management tool. Built on our proven Artix Linux foundation with runit init, Scooter Pie brings enhanced workflow tools for content creators and power users while maintaining the lightweight, terminal-centric philosophy that defines AEGIX.

---

### Major Changes

- **[Golden ISO Refreshed](https://aegixlinux.org/artix-base-runit-20241014-x86_64.iso)**  
- New video management script **grideo**
- Minor iterative improvements

#### 📼✨ New video management functionality ✨📼 (terminal-based ofc :) 

- **grideo**: thumbnail-first video reviewer and organizer
  - Browse recordings in a fast thumbnail grid, then play, rename, or delete without leaving the gallery.
  - Installs/updates an `sxiv` key-handler with video-aware shortcuts.
  - Installed to `~/.local/bin/grideo` and on your PATH, so you can run it from any terminal.

Usage:

```shell
grideo [--dir /path/to/videos]
```

What it does:

- Scans `~/Videos/obs` by default (override with `--dir`).
- Generates a thumbnail cache in `/tmp/video_thumbs` and opens a grid in `sxiv`.
- Maps thumbnails back to the real video for safe actions (rename/delete/play/info).
- Writes the active directory to `/tmp/vidgrid_dir` for robust thumb→video mapping and drops a compatible key-handler in `~/.config/sxiv/exec/key-handler`.

Gallery shortcuts (inside `sxiv`):

- p: play video
- P: play from ~30%
- r: rename underlying video (thumbnail follows)
- d: delete underlying video (with confirmation)
- i: show size, duration, and resolution

Dependencies:

- Required: `sxiv`, `ffmpeg`/`ffprobe`, `mpv`
- Optional: `dmenu`, `notify-send`, `mediainfo`, `ImageMagick`

Notes:

- Thumbnails are cached and can be kept or cleared on exit.
- Renames preserve file extensions; deletes always confirm.

---

### Contributors to this Release

A heartfelt thank you & quantum-gratulations to our contributors 🪐

- [Mason U. Borchard](https://github.com/mason-u-borchard)
- [Timothy D. Beach](https://github.com/timbeach)
- [AegixLinux Community](https://github.com/AegixLinux)

---

## Full Moon Release 5 - Blood Moon

**Branch name**: `release/blood_moon`

**Date**: 2025-03-14 Fri, The Second Week of Great Lent

---

The **Blood Moon** release coincides with the total lunar eclipse of March 14, 2025. This celestial event symbolizes transformation, resilience, and illumination through adversity—perfectly aligning with the spirit of Great Lent, a time of reflection, struggle, and renewal.

Aegix Linux continues its commitment to simplicity, efficiency, and freedom, refining the system while maintaining its core philosophy of parsimony, minimalism, and user empowerment.

![Blood Moon](https://aegixlinux.org/images/blood_moon.png)

*Image by [Ringo H.W. Chiu/Associated Press](https://www.houstonchronicle.com/news/houston-texas/trending/article/blood-moon-houston-march-20191381.php)*

With this release, we introduce several key improvements and refinements to enhance the Aegix Linux experience.

---

### Major Changes

- **Refined `install.sh` and `barbs.sh` Installer Scripts**: Optimized for a smoother, faster installation process with better error handling.
- **24 Hour Time**: Updated status bar to 24 hour time along with calendar UI fix.
- **Updated Official ISO**: Latest Artix Runit stable hosted.
- **New Default Desktop Background**: A fresh background suggesting the feeling of looking out from your CypherText Alcove.
- **Unified GRUB Background**: Branded Aegix GRUB background now the default.
- **PyWal by Default**: PyWal comes bundled so your system theme will automatically match your desktop background image via the `setbg` script.
- **gocryptfs by Default**: Aegix now ships with gocryptfs by default such that the `alcove` script for CypherText Alcove works out of the box.

---

### Contributors to this Release

A heartfelt thank you to our contributors:

- [Mason U. Borchard](https://github.com/mason-u-borchard)
- [Timothy D. Beach](https://github.com/timbeach)
- [AegixLinux Community](https://github.com/AegixLinux)

---

This release embodies the essence of Aegix Linux—streamlined, powerful, and built for those who demand efficiency without compromise. The **Blood Moon** represents both an eclipse and a revelation, marking another milestone in the evolution of Aegix Linux.

Install the latest version and experience the power of Aegix Linux **Blood Moon**.

---

## Full Moon Release 4 - Shipwrecked 

**Branch name**: release/shipwrecked

**Date**: 2024-12-18 Wed, in the Nativity Fast (both old and new calendars)

---

"Shipwrecked" reflects a state of surrender and rediscovery, inspired by ancient journeys where adversity led to unexpected transformations. In the spirit of those journeys, this release is a reminder to embrace challenges as opportunities for growth, innovation, and renewal.

- **Stranded Yet Resilient**: Like mariners finding strength amidst the chaos of the seas, we refine our systems under pressure.
- **Discovery Through Loss**: Stripping away what is non-essential, this release focuses on functionality and clarity.
- **Navigating Together**: With collaborative spirit, contributors have steered this ship to new horizons.

![Shipwrecked](https://aegixlinux.org/images/shipwrecked.png)

*Image by Timothy D. Beach from Bodega Bay, CA*

---

## Full Moon Release 3 - Yolo County

**Branch name**: release/yolo_county

**Date**: 2024-11-15 Fri, 21st Week after Pentecost

---

Yolo County is more than just a name—it represents a mosaic of meaningful locations and experiences tied to roots, faith, and community:

- **Esparto**: A quiet town surrounded by fields and hills, reflecting simplicity, hard work, and the grounding connection to home.
- **North Davis Heights**: A place of cherished memories and family, evoking the comfort and formative strength of childhood.
- **Holy Virgin Mary Orthodox Church in West Sacramento**: A space of spiritual connection and shared faith, where tradition and modern life meet in harmony.

![North Davis Heights Aurora](https://aegixlinux.org/images/ndh_aurora_mason.jpg)

*Image by [Milly Borchard](https://www.youtube.com/@pantsberg)*

With this release, we aim to embody the spirit of Yolo County: rooted yet forward-looking, resilient yet serene, and always centered on what truly matters.

---

### Major Changes

- **vpn Alias Update**: The `vpn` alias has been updated to work with AnyConnect verion 5.x, ensuring seamless VPN connections for users.
- **Improved Documentation**: Enhanced documentation across the system
- **New Default Desktop Background**: A fresh desktop background has been added to the default configuration, reflecting the beauty and tranquility of Yolo County.

### Contributors to this Release

A heartfelt thank you to our contributors:

- [Mason U. Borchard](https://github.com/mason-u-borchard)
- [Timothy D. Beach](https://github.com/timbeach)

---

## Full Moon Release 2 - The Northern Thebaid

**Branch name**: `release/the_northern_thebaid`

**Date**: 2024-10-18 Fri, The week of The Protection of Our Most Holy Lady the Theotokos and Ever-Virgin Mary

---

The term **"[The Northern Thebaid](https://www.sainthermanmonastery.com/product-p/nth.htm)"** refers to a collection of hagiographies and spiritual writings about monastic saints who lived in the remote northern forests of Russia. Drawing inspiration from the original Thebaid desert in Egypt—a cradle of early Christian monasticism—the Northern Thebaid embodies:

- **Spiritual Solitude**: Like the desert fathers who sought isolation to deepen their spiritual lives, the monks of the Northern Thebaid embraced the solitude of the wilderness to focus on inner growth and reflection.
- **Simplicity and Asceticism**: Living in harsh climates demanded a life of simplicity and self-denial. This stripped away excess, allowing for a concentrated pursuit of what truly matters.
- **Inner Transformation**: Their stories emphasize personal transformation through discipline, contemplation, and unwavering dedication to higher principles.

With this release, we aspire to capture the essence of the Northern Thebaid by offering tools that promote focus, simplicity, and a return to essentials, empowering users to eliminate distractions and engage deeply with their work.

---

### Major Changes

- **Golden ISO Refresh**: The [Golden ISO](https://aegixlinux.org/artix-base-runit-20241014-x86_64.iso) based on a very recent Artix weekly build has been updated with the latest software and configurations, ensuring a smooth and efficient user experience.
- **passgen**: A new script `passgen` has been added to generate secure passwords with customizable length and complexity, enhancing security for users across various applications.
- **Enhanced Emoji Support**: Continued improvements to the emojis in Aegix, including the ability to search for emojis by name and copy them directly to the clipboard for easy use in text-based applications.

### Contributors to this Release

A huge thanks to everyone involved in making this release possible:

- [AegixLinux](https://github.com/AegixLinux)
- [Mason U. Borchard](https://github.com/mason-u-borchard)
- [Timothy D. Beach](https://github.com/timbeach)

---

## Full Moon Release 1 - Centrifugal Bumblepuppy

**Branch name**: `release/centrifugal_bumblepuppy`

**Date**: 2024-09-20 Fri, The Eve of the Nativity of the Most Holy Theotokos

---

The term **"centrifugal bumblepuppy"** comes from Aldous Huxley's *Brave New World*. It refers to a complicated, machine-based game played by children in the novel's dystopian society. Here's what it represents:

- **Meaningless Complexity**: The game involves intricate equipment and serves no real purpose other than entertainment. It exemplifies how society invests time and resources into trivial pursuits.
- **Promotion of Consumption**: By designing games that require expensive machinery, the society encourages continuous consumption, fueling the economy while keeping citizens distracted.
- **Distraction from Substance**: The game symbolizes how superficial activities replace meaningful experiences, diverting attention from critical thought or genuine human connection.

With this release, we aim to cut through meaningless complexity, offering simple, powerful tools that help users stay focused on what matters.

---

### Main Repository

- **Added** `unixtime` script to get the current Unix time that continues to count up.
- **Added** `pomodoro` script to track time spent on tasks, using the well-known Pomodoro technique to boost productivity.
- **Added** `today` alias to create a new markdown file with the current date as the filename.
- General repo cleanup for improved maintainability and clarity.

### Gohan Sub-Repository

- **Added** scripts for keybindings to add/remove snippets.
- **Added** CLI tools to select snippets/special chars and add/remove snippets for faster coding or text-editing.

### dwm Sub-Repository

- **Added** keybindings to add or remove a snippet using mod+shift+insert and mod+shift+delete respectively.

### Contributors to this Release

A huge thanks to everyone involved in making this release possible:

- [AegixLinux](https://github.com/AegixLinux)
- [Mason U. Borchard](https://github.com/mason-u-borchard)
- [Timothy D. Beach](https://github.com/timbeach)
