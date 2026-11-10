# ttt - terminal time timer

A visual countdown for the terminal in the spirit of the physical
Time Timer dials: 0 at the top, minutes running clockwise like a
clock face (15 east, 30 south, 45 west), and a red wedge whose edge
sweeps counterclockwise back to noon as time runs out. Built for
ADHD time blindness: you see time leaving, you do not read a number.

The dial is deliberate chunky pixel art in the Aegix st gruvbox
colors, rendered with half blocks and corrected to a true circle
using the cell size your terminal reports.

Part of the Aegix Linux suckless-style tool set.

## Usage

    ttt 25        start a 25 minute timer
    ttt           start with an empty dial, type a number to begin

While it runs:

- type `1` to `60` to reset the dial to that many minutes
  (two digits commit at once, one digit commits after a short
  pause or Enter)
- `q` or Ctrl-C quits

At zero the whole screen flashes red (`ttt-flash`) and the
freedesktop alarm sound plays. Both are configurable in `config.h`
(`alarmcmd`), as are the colors and the dial's aspect trim
(`xscale`, for terminals that do not report their pixel size).

## The floating popup

In dwm, bind a key to spawn it in a small floating st window:

    st -c ttt -g 60x18 -e ttt 25

with a dwm rule for the `ttt` class set to floating. The dial
inherits st's transparency.

## Build

    make            build ttt and ttt-flash
    make test       run the unit tests
    sudo make clean install

Requires libX11 headers for ttt-flash. The alarm sound needs the
sound-theme-freedesktop package and a pipewire setup with pw-play.
