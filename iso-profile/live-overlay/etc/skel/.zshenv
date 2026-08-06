#!/bin/zsh

# This file is sourced on all invocations of the shell.
# It should contain commands to set the command search path,
# plus other important environment variables.
# It should not contain commands that produce output or assume
# the shell is attached to a tty.

# XDG Base Directory Specification
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"

# Tell zsh where to find its config
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"

# Password store location
export PASSWORD_STORE_DIR="$XDG_DATA_HOME/password-store"
