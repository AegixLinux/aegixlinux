# ~/Applications

This is where AppImages live on Aegix.

An **AppImage** is a single self-contained file holding an entire application:
no installer, no root, no package manager. Download it, mark it executable,
run it. Deleting the file uninstalls it completely.

## Using one

```sh
chmod +x ~/Applications/Something-1.2.3.AppImage
~/Applications/Something-1.2.3.AppImage
```

## Letting Aegix manage it for you

Aegix ships tooling that registers an AppImage with your desktop, so it shows
up in the launcher with a proper name and icon instead of living as a loose
file you have to remember:

```sh
aegix-appimage add ~/Applications/Something-1.2.3.AppImage
aegix-appimage list
aegix-appimage-tui          # interactive manager
```

Under the hood it writes a `.desktop` entry and extracts the icon; the
registry lives in `~/.config/aegix/appimages.json` (per-machine, not synced).

## Prefer a real package when one exists

AppImages are the right answer for software that isn't packaged, ships its own
release cadence, or that you want pinned to an exact version. When a program
*is* in the repositories, install it normally instead: you get signature
verification, dependency handling, and updates with the rest of the system.

```sh
pacman -Ss <name>     # search the repos first
yay -Ss <name>        # then the AUR
```

Some software is simply better as an AppImage. Obsidian is the usual example:
the upstream AppImage tracks releases closely and behaves predictably, while
packaged builds can lag or misbehave. Aegix does not ship it, so that you can
grab the current release yourself and manage it here.
