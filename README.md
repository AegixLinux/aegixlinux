# aegixlinux.org

https://aegixlinux.org

## Security-Hardened Personal Computing for REAL HUMAN BEINGS

### Elite, Turn-Key Linux

- Suckless software graphical environment with dwm
- LUKS-encrypted system drive
- Artix base w/ runit init system (no systemd)
- BTRFS filesystem auto-snapshotable
- Wireplumber & pipewire audio system
- Familiar vim-centric key bindings

## Installation

TL;DR: Install after booting from an artix base runit ISO, with this one liner:
``` Shell
curl -LO aegixlinux.org/install.sh && sh install.sh
```

### Prepare USB Thumbdrive Installation Medium

Put the latest "artix-base-runit" ISO from
https://artixlinux.org/download.php onto your usb thumbdrive, such that it's bootable from the computer you are installing Aegix Linux on.
At the time of writing, the current ISO is here:
https://download.artixlinux.org/iso/artix-base-runit-20220713-x86_64.iso

### Boot Target Computer from USB Thumbdrive

On an old ThinkPad, you can push a few times and hold the F12 key to get the BIOS to allow to choose what storage device to boot from. Other machines have something similar.

Boot your target computer from your USB thumbdrive, login as "root"/"artix"

Run this one-liner:
``` Shell
curl -LO aegixlinux.org/install.sh && sh install.sh
```

Follow the prompts.

## Target Hardware

Aegix Linux is tested and working on a range of ThinkPads including all the best ones 🤔

- X220
- T420, T420s
- T430
- P50, P50s

It's also been tested on an HP Z800 office server.

Testing on other hardware platforms is welcomed. Please share your results.

## A Note on Git Submodules

Nested within this git repository are six submodules representing other Aegix Linux repos. They are:

- barbs (Aegix Beach Automation Routine for Building Systems)
- gohan (Aegix dotfiles and configuration)
- dwm (Aegix build of suckless dwm)
- dwmblocks (Aegix build of suckless dwmblocks)
- st (Aegix build of suckless simple terminal)

## For the LARBS-aware

Aegix's barbs.sh script is inspired by Luke Smith's larbs.sh script. Big thank you to him for that as well as his voidrice repo from which Aegix gohan liberally borrows. As Aegix continues to develop, more divergence will be likely to take place, but having the reference to get started was a tremendous help.

## Art

Aegix Linux desktop artwork from remote location in Nagano, Japan:

![misty-nagano](https://github.com/aegix/gohan/blob/master/.local/share/misty-nagano.jpg)

Aegix ASCII Art:
``` Shell
################################################################################
################################################################################
##################################SS%%?????%%SS#################################
#################################%;;;;;++++;;;;*################################
######################%::?S#######%...........*########?;:?#####################
####################S#S%##%;:%#@##%,..+%%%?,..*##@#S;:%##SS#S###################
##################S+:%@@@##??#@@##%,..*@@@S,..*##@@#%*S##@@#;:%#################
##################;:%#############%,..*@@@S,..*#############S+:S################
####################@#S::::,,,,:S#%,..*@@@S,..*##+,,,,,:::?#####@###############
@@@@@#####@@####%;S@@#S,..,::::;S#%,..*@@@S,..*##+::::,...?##@#+*#####@#########
@@@@@@@@#######S,;#@@#S,..;#######%,..*@@@S,,.*##@####?...?#@@#*.%########@@@@@@
@@@@@@@@@S:*@@@S;%@@@@#+++?#@@@@@#S,..*@@@S,..*##@@@@@S+++%@@@@#+%@#@S,?@@@@@@@@
@@@@@@@@@S,*@##@@@@@@@@@@@@@@@@@@@S,..*@@@S,..*@@@@@@@@@@@@@@@@@@@@@@S,*@@@@@@@@
@@@@@@@@@#S##@#;;;;;;;;;;;;;;;;;;;:...*@@@S,..:;;;;;;;;;;;;;;;;;;;%@@#S#@@@@@@@@
@@@@@@@@@#%S@@S,...,,,,,,,,,,,,,,,,,,,*@@@S:,,,,,,,,,,,,,,,,,,,...?@@#%S@@@@@@@@
@@@@@@@@@S,+@@S,..+SSSSSSSSSSSSSSSSSSS#@@@#SSSSSSSSSSSSSSSSSSS?...?@@S.*@@@@@@@@
@@@@@@@@@S,+@@S,..+@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%...?@@S.*@@@@@@@@
@@@@@@@@@S,+@@S,..,::::::::::;#@@@S:::?@@@S:::?@@@@*::::::::::,...?@@S.*@@@@@@@@
@@@@@@@@@#%S@@#:::::::::::::::#@@#%,..*@@@S,..*#@@@*,:::::::::::::%@@#?S@@@@@@@@
@@@@@@@@@@@@@@@###############@@@@S,..*@@@S,..*@@@@###############@@@@@@@@@@@@@@
@@@@@@@@@#:*@@@@@@@@@@@@@@@@@@@@@@S,..*@@@S,..*@@@@@@@@@@@@@@@@@@@@@@#:?@@@@@@@@
@@@@@@@@@S,+@@@@@@@@@@#;::*@@@@@@@S,..*@@@S,..*@@@@@@@%:::%@@@@@@@@@@S.*@@@@@@@@
@@@@@@@@@#,*@@@#S@@@@@S,..+#@@@@@@S,..*@@@S,..*@@@@@@@?...?@@@@@SS@@@S.*@@@@@@@@
@@@@@@@@@@S#@@@+,#@@@@S,..+@@@@@@@S,..*@@@S,..*@@@@@@@%...%@@@@@::@@@#%#@@@@@@@@
@@@@@@@@@@#@@@@%*@@@@@S,..+@@@@@@@S,..*@@@S,..*@@@@@@@%...?@@@@@??@@@@#@@@@@@@@@
@@@@@@@@@#:*@@@@@@@@@@S,..+@@@@@@@S,..*@@@S,..*@@@@@@@%...?@@@@@@@@@@S,?@@@@@@@@
@@@@@@@@@#,+@@@#+%@@@@S,..+@@@@@@@S,..*@@@S,..*@@@@@@@%...?@@@@#+S@@@S.*@@@@@@@@
@@@@@@@@@#,+@@@S.*@@@@S,..+@@@@@@@S,..*@@@S,..*@@@@@@@%...?@@@@%.?@@@S.*@@@@@@@@
@@@@@@@@@@%S@@@@?S@@@@S,..+@@@@@@@S,..*@@@S,..*@@@@@@@%...?@@@@#?#@@@#?#@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@S,..:?#@@@@@S,..*@@@S,..*@@@@@@S;...?@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@#?:...:?#@@@S,..*@@@S,..*@@@@%;,..,+#@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@#?;...:?@@S,..*@@@S,..*@@S;,..:*S@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@#%;,.,#@S,..*@@@S,..*@@;..:?#@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@#%+:#@S,..*@@@S,..*@@;:?#@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@#@@@@@@@#@@S,..*@@@S,..*@@##@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@#++S@@@@@@@@S,..;***+,..*@@@@@@@@#?;%@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@#%++#@@@@@@S,..........*@@@@@@@*+*S@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@#@@@@@@@#%%%%%%%%%%%S@@@@@@@#@@@@@@@@@@@@@@@@@@@@@@@@@
    |_   _|/ \  | \ | | |/ / |   |_ _| \ | | | | \ \/ / / ___/ _ \|  \/  |
      | | / _ \ |  \| | ' /| |    | ||  \| | | | |\  / | |  | | | | |\/| |
      | |/ ___ \| |\  | . \| |___ | || |\  | |_| |/  \ | |__| |_| | |  | |
      |_/_/   \_\_| \_|_|\_\_____|___|_| \_|\___//_/\_(_)____\___/|_|  |_|
```
