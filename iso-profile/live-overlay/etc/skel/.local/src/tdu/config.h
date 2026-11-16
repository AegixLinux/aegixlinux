/* tdu configuration. Rebuild after editing: make clean install */

/* Colors, 24-bit 0xRRGGBB. Defaults match the Aegix st gruvbox
 * theme so the bars look native in the terminal. */
static const long okcolor    = 0xb8bb26; /* bar below warn */
static const long warncolor  = 0xfabd2f; /* bar from warn */
static const long critcolor  = 0xfb4934; /* bar from crit */
static const long labelcolor = 0x928374; /* names and mountpoints */
static const long trackcolor = 0x3c3836; /* unfilled bar cells */

/* Fill fractions where the bar changes color. */
static const double warnat = 0.70;
static const double critat = 0.90;

/* Entries shown in the drill-down. */
static const int topn = 10;

/* Bar cell glyphs; the track is drawn in trackcolor. */
static const char *barfill  = "█";
static const char *bartrack = "█";
