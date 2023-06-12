# TANKLINUX.COM

## Security-Hardened Personal Computing for REAL HUMAN BEINGS

https://tanklinux.com 

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
curl -LO tanklinux.com/tl.sh && sh tl.sh
```

### Prepare USB Thumbdrive Installation Medium

Put the latest "artix-base-runit" ISO from
https://artixlinux.org/download.php onto your usb thumbdrive, such that it's bootable from the computer you are installing TANKLINUX on.
At the time of writing, the current ISO is here:
https://download.artixlinux.org/iso/artix-base-runit-20220713-x86_64.iso

### Boot Target Computer from USB Thumbdrive

On an old ThinkPad, you can push a few times and hold the F12 key to get the BIOS to allow to choose what storage device to boot from. Other machines have something similar.

Boot your target computer from your USB thumbdrive, login as "root"/"artix"

Run this one-liner:
``` Shell
curl -LO tanklinux.com/tl.sh && sh tl.sh
```

Follow the prompts.

## Target Hardware

TANKLINUX is tested and working on a range of ThinkPads including all the best ones 🤔

- X220
- T420, T420s
- T430
- P50, P50s

It's also been tested on an HP Z800 office server. 

Testing on other hardware platforms is welcomed. Please share your results.

## A Note on Git Submodules

Nested within this git repository are six submodules representing other TANKLINUX repos. They are:

- barbs (TANKLINUX Base Automation Routine for Building Systems)
- gohan (TANKLINUX dotfiles and configuration)
- dwm (TANKLINUX build of suckless dwm)
- dwmblocks (TANKLINUX build of suckless dwmblocks)
- st (TANKLINUX build of suckless simple terminal)

## For the LARBS-aware

TANKLINUX's barbs.sh script is inspired by Luke Smith's larbs.sh script. Big thank you to him for that as well as his voidrice repo from which TANKLINUX gohan liberally borrows. As TANKLINUX continues to develop, more divergence will be likely to take place, but having the reference to get started was a tremendous help. 

## Art

TANKLINUX desktop artwork from remote location in Nagano, Japan:

![misty-nagano](https://github.com/tanklinux/gohan/blob/main/.local/share/misty-nagano.jpg)

TANKLINUX ASCII Art:
``` Shell
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@J|EQ@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
QSL>^#Q@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@#Qq\i4QH8@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@QKX!::LkQ@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@8ez\>!:e@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@QdoeNz\4Q@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@#Al>rFR@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@QHu\^l$Q@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@Q#X7*|aB@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@QDuL?uD@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@Q8al|tKQ@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@QdyLlEQ@@@@@@@@@@@@@@#@NKXojC}}CFo#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@Q#AClaN@Q@4iDclcLLLLLLiccl77vvzzzzzzzzzzCN@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@QRH^y>::>vu.```...'',,,"~:::::::::!>zz@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@QuH>^^rzqr?|\LLll7zzJ}CFFFuujjjyyyjS@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@QEaNeaaaoooaewwwXEA6$qpKHBQQQQQQ@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@N#N$Xeoyu}JzvzzzzzSAzvvzvzzz}FjoeXNNd8Q@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@4::;":!"""^~~~^:~~!!rJ:^~~~^~~~!!~":^!;""LQ@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@QgW%DHKq6kXwaotiiL///\||?*>>rrr^^^^r?!!!!!!!:::::::!!^r*|LoaewE6qKOHD8gQ@@@@@
@@@@@@@@@@@@@@@@@@@@@Qz/w4jAwXF^^rrr^^rr^^rr^rrr^^r^^^^^^^^^^^^^^^^^^^^^^^^^r^^^^^r^r^^LEXEwSk7\#@@@
@@@@@@@@@@@@@@@@@@@@@6B8Dggkwp6::::::::::::::::::::::::::::::::::::::::::::::::::::::::7#AEq#HDNK@@@
@@@@@@@@@@@@@@@@@@@@Q?%SSSBqd6QNAotlccl77zzvzv7llciLLic7J}FuFtz7cciiLcl77vvzzv77lcLltaqQAqONESSwjD@@
@@@@@@@@@@@@@@@@@@@@@#^D6KeoKHozJFk#O6AkE6NAoCyw8N6AkEEWRojuSdWkEEkAOBAouoXR%EXkk6#Hy}JyHHooKAOi4Q@@
@@@@@@@@@@@@@@@@@@@@@@N'ozzwX~:!^^^iRtzzzDl,:!^^*EXJzzqo,:!;^^uHzzzzR|,:;^^?KozzzOC,:;^^^yOvzy!S@@@@
@@@@@@@@@@@@@@@@@@@@@@@B`6QQ? ',~::"pQBBQH,`',:::\QQQQQ^`',"::?HQQQQO``,":::zQQQQR!`'"~::/%QN.e@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@^;@6,.,,""\B@@@@Ql`',"~;E@@@@@o'',,~:J@@@@@B\`',"~^H@@@@@t'',"":u@4'B@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@B!!Fu\|lkQ@@@@@@Qpl?\yN@@@@@@@WC||zd@@@@@@@QAL?/oB@@@@@@@DJ||}KF:u@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@yr*|||???????????????|????|>r>*>r*??????????????????????||>>d@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
```
