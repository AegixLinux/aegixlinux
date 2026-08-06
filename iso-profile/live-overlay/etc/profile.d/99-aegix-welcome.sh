# Aegix Linux live ISO -- run welcome script on first login (covers any login shell)
if [ -t 0 ] && [ -z "$AEGIX_WELCOMED" ] && [ -x /usr/local/bin/aegix-welcome ]; then
    export AEGIX_WELCOMED=1
    /usr/local/bin/aegix-welcome
fi
