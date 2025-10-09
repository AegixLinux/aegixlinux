# Stuck Cursor Fix (IBeam/Text Selection Mode)

## Problem
Cursor shows as "I" (text selection beam) instead of normal pointer, and won't click on anything. The cursor moves but doesn't respond to clicks.

## Quick Fix
```bash
xdotool key Escape
```

This sends an Escape key to cancel whatever is holding the cursor in text selection mode.

## Full Troubleshooting Steps

### 1. Send Escape (First Try)
```bash
xdotool key Escape
```

### 2. Reset Cursor Appearance
```bash
xsetroot -cursor_name left_ptr
```

### 3. Release Stuck Modifier Keys
```bash
xdotool keyup Super_L Alt_L Control_L Shift_L
```

### 4. Check What Has Focus
```bash
xdotool getactivewindow getwindowname
```

### 5. Restart Notification/Compositor Daemons
```bash
killall dunst 2>/dev/null; dunst &
```

### 6. Nuclear Option - Restart DWM
```bash
# Mod+Shift+Q (if configured)
# or
killall dwm
```

## What Causes This

The IBeam cursor typically appears when:
- **st terminal** is in text selection mode and something prevents it from exiting
- A modifier key gets stuck (Shift, Alt, etc.)
- Text selection was initiated but not properly cancelled
- A notification or dialog box grabbed focus incorrectly

## Prevention Strategies

### 1. Add Escape Keybinding in st
Modify `st/config.h` to ensure Escape always works:
```c
{ ControlMask, XK_bracketleft, "\033", 0, 0},  // Ctrl+[ also sends Escape
```

### 2. Create Helper Script
Save as `~/bin/fix-cursor`:
```bash
#!/bin/sh
xdotool key Escape
xsetroot -cursor_name left_ptr
xdotool keyup Super_L Alt_L Control_L Shift_L
```
Make executable: `chmod +x ~/bin/fix-cursor`

Bind to a key in `dwm/config.h`:
```c
{ MODKEY|ShiftMask, XK_c, spawn, SHCMD("fix-cursor") },
```

### 3. Terminal Configuration
In st, avoid accidental text selection mode by:
- Being careful with middle-click (paste) operations
- Not holding Shift while clicking
- Using Escape regularly to clear selection states

### 4. Add to dwmblocks Status
Could add a visual indicator when in selection mode (advanced)

### 5. Automatic Timeout
Create a cron job or timer that periodically runs:
```bash
*/5 * * * * DISPLAY=:0 xsetroot -cursor_name left_ptr
```

## Quick Reference
**Most Common Fix:** Just press `Escape` key or run `xdotool key Escape`

## See Also
- st source: `st/st.c` (selection handling)
- dwm keybindings: `dwm/config.h`
- xdotool manual: `man xdotool`
