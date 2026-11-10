/* ttt configuration. Rebuild after editing: make clean install */

/* Colors, 24-bit 0xRRGGBB. Defaults match the Aegix st gruvbox
 * theme so the dial looks native in the terminal. */
static const long wedgecolor = 0xfb4934; /* remaining-time wedge */
static const long rimcolor   = 0xa89984; /* dial ring */
static const long textcolor  = 0x928374; /* mm:ss readout */

/* Extra horizontal stretch multiplied into the cell aspect that is
 * measured from the terminal. Only touch this if the dial is still
 * oval: above 1.0 widens it, below 1.0 narrows it. */
static const double xscale = 1.0;

/* run when the timer reaches zero */
static const char *alarmcmd =
	"ttt-flash & pw-play /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga >/dev/null 2>&1 &";
