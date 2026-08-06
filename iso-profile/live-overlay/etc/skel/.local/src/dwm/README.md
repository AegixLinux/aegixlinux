# Aegix dwm

## Configuration & Key Bindings

Check out [config.h](config.h).

The `barbs.mom` file contains some documentation.
Press <kbd>Ultra+F1</kbd> to view it in dwm (zathura PDF viewer required).
Updates for `man dwm`/`dwm.1` are needed.

## Patches and features

- [Clickable statusbar](https://dwm.suckless.org/patches/statuscmd/) with the aegixlinux build of [dwmblocks](https://github.com/aegixlinux/dwm).
- Reads [xresources](https://dwm.suckless.org/patches/xresources/) colors/variables (i.e. works with `pywal`, etc.).
- scratchpad: Accessible with <kbd>mod+shift+enter</kbd>.
- New layouts: bstack, fibonacci, deck, centered master and more. All bound to keys <kbd>Ultra+(shift+)t/y/u/i</kbd>.
- True fullscreen (<kbd>Ultra+f</kbd>) and prevents focus shifting.
- Windows can be made sticky (<kbd>Ultra+s</kbd>).
- [hide vacant tags](https://dwm.suckless.org/patches/hide_vacant_tags/) hides tags with no windows.
- [stacker](https://dwm.suckless.org/patches/stacker/): Move windows up the stack manually (<kbd>Ultra-K/J</kbd>).
- [shiftview](https://dwm.suckless.org/patches/nextprev/): Cycle through tags (<kbd>Ultra+g/;</kbd>).
- [vanitygaps](https://dwm.suckless.org/patches/vanitygaps/): Gaps allowed across all layouts.
- [swallow patch](https://dwm.suckless.org/patches/swallow/): if a program run from a terminal would make it inoperable, it temporarily takes its place to save space.


## Installation outside of Aegix

```bash
git clone https://github.com/aegixlinux/dwm.git
cd dwm
sudo make install
```
