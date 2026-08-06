# Install Aegix Linux

    sh install.sh

That is the whole thing. The installer asks for a target disk, a hostname and
user, a LUKS passphrase (encryption is mandatory on Aegix), and then does the
rest unattended.

## Before you start

    lsblk                # list disks; find your target, e.g. /dev/nvme0n1
    nmtui                # connect to wifi if you are not on ethernet
    ping -c1 8.8.8.8     # confirm the network is really up

The installer needs a working network connection: it fetches the base system
and the desktop packages while it runs.

## What you get

Full-disk LUKS encryption, a btrfs root with subvolumes, runit as init, and
the Aegix desktop (dwm, st, dmenu, dwmblocks) built from source during the
install. Expect 20 to 60 minutes depending on your connection.

## When it finishes

    poweroff

Wait for the machine to power off completely, *then* remove the installation
media, then boot from your drive.

## If something goes wrong

Installer output scrolls past, but the desktop stage keeps logs:

    /root/barbs-errors.log     # anything that failed to install
    /root/barbs-output.log     # full output

Bring those to https://aegixlinux.org or the issue tracker and they will tell
us exactly what broke.
