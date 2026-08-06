# 4K Display Configuration for Aegix Linux

This guide covers running Aegix Linux on 4K displays (3840x2160) standalone, without external monitors.

## Problem

On 4K displays, the default suckless software (dwm, st, dmenu) and browser UI elements are tiny and hard to read. Using `xrandr --scale 0.5x0.5` produces blurry, scuffed output due to software scaling.

## Solution

Scale everything natively by doubling font sizes and using proper display resolution.

### 1. Display Settings

Always run at native 4K resolution for crisp output:

```bash
xrandr --output DP-4 --mode 3840x2160 --scale 1x1
```

Replace `DP-4` with your actual output name (check with `xrandr`).

### 2. Suckless Software Font Sizes

Edit the following config files and **double** the font sizes:

#### dwm: `~/.local/src/dwm/config.h`
```c
// Change from size=14 to size=28
static char *fonts[] = { "monospace:size=28", "NotoColorEmoji:pixelsize=28:antialias=true:autohint=true" };
```

#### st: `~/.local/src/st/config.h`
```c
// Change from pixelsize=16 to pixelsize=32
static char *font = "mono:pixelsize=32:antialias=true:autohint=true";
static char *font2[] = { "JoyPixels:pixelsize=32:antialias=true:autohint=true" };
```

#### dmenu: `~/.local/src/dmenu/config.h`
```c
// Change from size=14 to size=28
static const char *fonts[] = {
	"monospace:size=28",
	"NotoColorEmoji:pixelsize=28:antialias=true:autohint=true"
};
```

### 3. Rebuild and Install

After editing config files:

```bash
cd ~/.local/src/dwm && make clean && make && sudo make install
cd ~/.local/src/st && make clean && make && sudo make install
cd ~/.local/src/dmenu && make clean && make && sudo make install
```

Then restart dwm (Mod+Shift+Q → Restart dwm).

### 4. Brave Browser UI Scaling

Create a smart wrapper at `~/.local/bin/brave` that auto-detects display resolution:

```bash
#!/bin/sh
# Check if we're on 4K (3840x2160 or higher) and scale accordingly
res=$(xrandr | grep ' connected' | grep -oP '\d+x\d+' | head -1)
width=$(echo "$res" | cut -d'x' -f1)

if [ "$width" -ge 3840 ]; then
    # 4K or higher - use 2x scaling
    exec /usr/bin/brave --force-device-scale-factor=2.0 "$@"
else
    # 1080p or lower - no scaling
    exec /usr/bin/brave "$@"
fi
```

Make it executable:
```bash
chmod +x ~/.local/bin/brave
```

This wrapper:
- Scales Brave UI 2x on 4K displays (tabs, address bar, everything)
- Uses normal scaling on 1080p/external monitors
- Works with Mod+W keybinding and dmenu
- Auto-adapts when switching displays

### 5. Optional: Xresources DPI (if needed)

If terminal or other X apps still look small, add to `~/.config/x11/xresources`:

```
!! DPI setting for 4K displays (192 = 2x scaling, 144 = 1.5x)
Xft.dpi: 192
```

Then reload:
```bash
xrdb -merge ~/.config/x11/xresources
```

## Usage Notes

- **On the road (4K standalone)**: Everything scales 2x automatically
- **At desk (external 1080p)**: Everything returns to normal size
- No manual intervention needed when switching displays
- Restart Brave if you hot-plug displays for scaling to update

## Tested Hardware

- Framework 13 (internal 4K display)
- Works with any 4K laptop display (3840x2160 or higher)

## Reverting Changes

To go back to normal sizes:
1. Restore original font sizes (14 for dwm/dmenu, 16 for st)
2. Rebuild suckless software
3. Remove `~/.local/bin/brave` wrapper
4. Restart dwm

---

**Last updated**: 2025-10-06
