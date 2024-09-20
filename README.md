# Aegix Linux 

https://aegixlinux.org

## For Professional Computer Users

### Elite, Turn-Key Linux

- Suckless software graphical environment with dwm, dmenu, st, dwmblocks 💻✨
- LUKS-encrypted system drive 🔒💽
- Artix base w/ runit init system (no systemd) 🐧⚙️
- BTRFS filesystem with subvolumes for snapshots and rollback 📁🔄
- Audio system with pipewire & wireplumber 🎧🎶
- Familiar vim-centric key bindings throughout ⌨️🖊️

## Installation

TL;DR: Install after booting from an artix base runit ISO, run these commands:
``` Shell
curl -LO aegixlinux.org/install.sh 
sh install.sh
```

### Prepare USB Thumbdrive Installation Medium

The Aegix Linux Project hosts a known-to-work version of the artix-base-runit ISO at: https://aegixlinux.org/artix-base-runit-20240516-x86_64.iso. Put that onto your usb thumbdrive, such that it's bootable from the computer you are installing Aegix Linux on.

If you're feeling adventurous try the very latest "artix-base-runit" ISO directly from Artix [downloads](https://artixlinux.org/download.php).

### Boot Target Computer from USB Thumbdrive

Research how to boot your machine to its boot menu. On an old ThinkPad, you can hold the F12 key to get the BIOS or BOOT MENU to allow to choose what storage device to boot from. Other machines have something similar.

Boot your target computer from your USB thumbdrive, login as "root"/"artix"

Run this one-liner:
``` Shell
curl -LO aegixlinux.org/install.sh && sh install.sh
```

Follow the prompts.

## Target Hardware

Installation should be a smooth process on any machine you can set to LEGACY BIOS. We are assuming normative x86 CPU architecture. Aegix Linux is tested and working on a range of ThinkPads including all the best ones:

- X220
- T2370
- T420, T420s
- T430
- T440
- P50, P50s

It's also been successfully tested on a HP Z800 office server.

Testing on other hardware platforms is welcomed. Please share your results.

## A Note on Git Submodules

Nested within this git repository are six submodules representing other Aegix Linux repos. They are:

- barbs (Beach Automation Routine for Building Systems)
- gohan (Aegix dotfiles and configuration)
- dwm (Aegix build of suckless dwm)
- dwmblocks (Aegix build of suckless dwmblocks)
- st (Aegix build of suckless simple terminal)

## For the LARBS-aware

Aegix's barbs.sh script is inspired by [Luke Smith](https://lukesmith.xyz/)'s larbs.sh. Big thank you to him for that as well as his voidrice repo from which Aegix gohan liberally borrows. As Aegix continues to develop, more divergence will be likely to take place, but having the reference to get started was a tremendous help.

## What Does it Look Like?

Using Aegix: 

![Default Aegix desktop image](https://github.com/AegixLinux/aegixlinux/blob/release/centrifugal_bumblepuppy/images/Centrifugal_Bumblepuppy.png)

Aegix ASCII Art:
``` Shell

   .=:.                                   ..::--=--=--::..                                   .:=
    ###*+=-:..              ..:::--==++**########++########**++==--:::..              ..:-=+*##*
    *###########********#########################++#########################********###########+
    =############################################++############################################=
    -############################################++############################################-
    :############################################++############################################:
    .###########*################################++################################*###########.
     ############**+*############################++############################*+**###########*
     *##############+--=*########################++########################*=--*##############*
     +################+:.:-=*####################++####################*=-:.:+################=
     =#################+.....:-=*###############+::+###############*=-:.....+#################=
     -#################+.........:=*#########*=:....:=*#########*=:.........+#################-
     -###############*=:.::-==+*###########*-:........:-*###########*+==-::.:=*###############:
     :############**+++*#################+:..............:+#################*+++**############:
     :################################*=:..................:=*################################:
     :##############################*-:......................:-*##############################:
     :############################+:............................:+############################
     :#########################*=:................................:=*#########################
     :#######################+-:....................................:-*#######################.
     :#####################+:..........................................:+#####################:
     :##################*=:..............................................:=*##################:
     -################+-:..................................................:-*################:
     -##############+:.........................:----:.........................:+##############-
     =###########*=:......................:-=+*##++##*+=-:......................:=*###########=
     +#########*-:....................:-+*#######++#######*+=::...................:-*#########+
     ########+-..................:-=+############++############*+-::.................-+#######*
    :#####*=:...............:-=+*################++#################*+-::..............:=*#####.
    -###*-:............:-=+*#####################++######################*=-:............:-*###-
    +#+-..........::=+*##########################++##########################*+=-:..........-+#+
   .=:.:.....::=+*###############################++###############################*+=-:.....:.:=
       ....:=*###################################++###################################*=:....
              .:-=+*#############################++#############################*+=-:.
                    .:-+*########################++########################*+-:.
                         .-=*####################++####################*=-.
                             .:=*################++################*=:.
                                 .-=*############++############*=-.
                                     :=+#########++#########*-:
                                        .-+*#####++#####*+:.
                                            :=*##++##*=:
                                               :--=-.
                  _              _      _     _
                 / \   ___  __ _(_)_  _| |   (_)_ __  _   ___  __  ___  _ __ __ _
                / _ \ / _ \/ _` | \ \/ / |   | | '_ \| | | \ \/ / / _ \| '__/ _` |
               / ___ \  __/ (_| | |>  <| |___| | | | | |_| |>  < | (_) | | | (_| |
              /_/   \_\___|\__, |_/_/\_\_____|_|_| |_|\__,_/_/\_(_)___/|_|  \__, |
                           |___/                                            |___/

                      # RUN: shutdown -h now
                      # Remove USB thumbdrive installation medium
                      # Reboot into Aegix Linux
                      # Enjoy!
                      
```
