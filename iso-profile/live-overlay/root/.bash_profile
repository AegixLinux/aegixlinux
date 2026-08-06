# Aegix Linux live ISO -- ensure terminal type is set, then run welcome script on first login

# Set TERM if unset (auto-login can leave it empty on some kernel consoles)
[ -z "$TERM" ] && export TERM=linux

if [ -t 0 ] && [ -z "$AEGIX_WELCOMED" ]; then
    export AEGIX_WELCOMED=1
    /usr/local/bin/aegix-welcome
fi
