# Aegix .zshrc initially borrowed from Luke's config for the Zoomer Shell

# Enable colors and change prompt:
autoload -U colors && colors	# Load colors
#PS1='%B%{%F{64}%}🪶Aegix:[%{%F{107}%}%n✨%M %~%{%F{64}%}]$%b '

# PS1='%B%{%F{64}%}🪶Aegix:[%{%f%}%B%{%F{12}%}%n%{%f%}%B%{%F{107}%}✨%{%f%}%B%{%F{107}%}%M %{%f%}%{%F{12}%}%~%{%f%}%B%{%F{64}%}]%{%f%}$%b '

#PS1='%B%{%F{15}%}🪶Aegix:%B%{%F{13}%}[%{%f%}%B%{%F{12}%}%n%{%f%}%B%{%F{107}%}✨%{%f%}%B%{%F{15}%}%M %{%f%}%{%F{12}%}%~%{%f%}%B%{%F{13}%}]%{%f%}$%b '

# Minimal
#PS1='✨ %~ '
#PS1='🦝 %~ '
PS1='🐧 %~ '

setopt autocd		# Automatically cd into typed directory.
stty stop undef		# Disable ctrl-s to freeze terminal.
setopt interactive_comments

# History in cache directory:
HISTSIZE=10000000
SAVEHIST=10000000
HISTFILE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/history"

# Load aliases and shortcuts if existent.
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/shell/shortcutrc" ] && source "${XDG_CONFIG_HOME:-$HOME/.config}/shell/shortcutrc"
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/shell/aliasrc" ] && source "${XDG_CONFIG_HOME:-$HOME/.config}/shell/aliasrc"
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/shell/zshnameddirrc" ] && source "${XDG_CONFIG_HOME:-$HOME/.config}/shell/zshnameddirrc"

# Basic auto/tab complete:
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit
_comp_options+=(globdots)		# Include hidden files.

# vi mode
bindkey -v
export KEYTIMEOUT=1

# Use vim keys in tab complete menu:
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char
bindkey -M menuselect 'j' vi-down-line-or-history
bindkey -v '^?' backward-delete-char

# Change cursor shape for different vi modes.
function zle-keymap-select () {
    case $KEYMAP in
        vicmd) echo -ne '\e[1 q';;      # block
        viins|main) echo -ne '\e[5 q';; # beam
    esac
}
zle -N zle-keymap-select
zle-line-init() {
    zle -K viins # initiate `vi insert` as keymap (can be removed if `bindkey -V` has been set elsewhere)
    echo -ne "\e[5 q"
}
zle -N zle-line-init
echo -ne '\e[5 q' # Use beam shape cursor on startup.
preexec() { echo -ne '\e[5 q' ;} # Use beam shape cursor for each new prompt.

# Use nnn to switch directories and bind it to ctrl-o
ncd() {
    [ "${NNNLVL:-0}" -eq 0 ] || { echo "nnn is already running"; return; }
    export NNN_TMPFILE="${XDG_CONFIG_HOME:-$HOME/.config}/nnn/.lastd"
    command nnn -c "$@"
    [ ! -f "$NNN_TMPFILE" ] || { . "$NNN_TMPFILE"; rm -f -- "$NNN_TMPFILE" >/dev/null; }
}
bindkey -s '^o' '^uncd\n'

# psqueal - create and cd into date-stamped directory
psqueal() {
    local dir_name=$(date +%Y-%m-%d_%a)
    mkdir -p "$dir_name" && cd "$dir_name"
}

bindkey -s '^a' '^ubc -lq\n'

bindkey -s '^f' '^ucd "$(dirname "$(fzf)")"\n'

bindkey '^[[P' delete-char

# Edit line in vim with ctrl-e:
autoload edit-command-line; zle -N edit-command-line
bindkey '^e' edit-command-line
bindkey -M vicmd '^[[P' vi-delete-char
bindkey -M vicmd '^e' edit-command-line
bindkey -M visual '^[[P' vi-delete

# Load syntax highlighting; should be last.
source /usr/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh 2>/dev/null

# Scaling via Xft.dpi only (GDK_SCALE=2 was causing 4x scaling)
# export GDK_SCALE=2
# export QT_SCALE_FACTOR=2

# Cursor configuration (smaller cursor for scaled displays)
export XCURSOR_SIZE=20
export XCURSOR_THEME=capitaine-cursors


# Quick markdown -> clipboard (rich text) for pasting into Medium/Substack/Ghost
mdclip() { pandoc -f gfm -t html "${1:-/dev/stdin}" | xclip -selection clipboard -t text/html; }

