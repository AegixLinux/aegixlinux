//Modify this file to change what commands output to your statusbar, and recompile using the make command.
static const Block blocks[] = {
	/*Icon*/	/*Command*/		/*Update Interval*/	/*Update Signal*/
	// CENTER BLOCKS (clock/utc) - these come first
	{"",	"sb-clock",	60,	1},
	{"",	"sb-utc",	60,	2},
	// RIGHT BLOCKS - everything else
	{"", "cat /tmp/recordingicon 2>/dev/null",	0,	9},
	{"",	"fm-status",	0,	11},	// futureme: ✉ N unread; refreshed by `futureme tick` via RTMIN+11
	/*{"",	"sb-price xmr \"Monero\" 🔒",			9000,	24}, */
	/*{"",	"sb-price btc Bitcoin 💰",				9000,	21}, */
	{"",	"sb-memory",	10,	14},
	{"",	"sb-cpu",		10,	18},
	/*{"",	"sb-moonphase",	18000,	17}, */
	{"",	"sb-volume",	0,	10},
	{"",	"sb-battery",	5,	3},
	{"",	"sb-internet",	5,	4},
};

//Sets delimiter between status commands. NULL character ('\0') means no delimiter.
static char *delim = " │ ";  // Visual separator between modules

// Index after which to insert the center delimiter ";;"
// Set to -1 to disable center status
static const int center_delim_after = 1;  // After block 1 (sb-utc)

// Have dwmblocks automatically recompile and run when you edit this file in
// vim with the following line in your vimrc/init.vim:

// autocmd BufWritePost ~/.local/src/dwmblocks/config.h !cd ~/.local/src/dwmblocks/; sudo make install && { killall -q dwmblocks;setsid dwmblocks & }

