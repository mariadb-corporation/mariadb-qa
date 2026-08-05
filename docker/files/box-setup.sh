#!/bin/bash
# Per-user setup for the box, taken from the in-box part of setup_server.sh.
# The kernel and limit settings of that script belong to the host, because a
# container cannot set them. Safe to run again at any time.

set -u

# linkit links the framework skills into ~/.claude and adds the cheatsheet to
# the memory index, but only when the directory is already there
mkdir -p "${HOME}/.claude"

# Editor: two-space indents, as used across mariadb-qa
if [ ! -s "${HOME}/.vimrc" ]; then
  cat > "${HOME}/.vimrc" << 'EOF'
set tabstop     =2
set softtabstop =2
set shiftwidth  =2
set expandtab
set nocompatible
colo torte
syntax on
EOF
fi

# gdb: remote symbol fetching can stall gdb for many minutes on a large
# mariadbd core, so it stays off
if ! grep -qs 'debuginfod enabled off' "${HOME}/.gdbinit"; then
  cat > "${HOME}/.gdbinit" << 'EOF'
add-auto-load-safe-path /usr/lib/x86_64-linux-gnu/libthread_db.so
add-auto-load-safe-path /usr/lib/x86_64-linux-gnu/libthread_db.so.1
set auto-load safe-path /
set libthread-db-search-path /usr/lib/x86_64-linux-gnu/libthread_db.so
set debuginfod enabled off
EOF
fi

# Same cap for any tool that reads the elfutils environment instead of .gdbinit
if ! grep -qs DEBUGINFOD_TIMEOUT "${HOME}/.bashrc"; then
  cat >> "${HOME}/.bashrc" << 'EOF'
export DEBUGINFOD_TIMEOUT=13
export DEBUGINFOD_PROGRESS=0
EOF
fi

if ! grep -qs 'termcapinfo xterm' "${HOME}/.screenrc"; then
  cat > "${HOME}/.screenrc" << 'EOF'
# General settings
vbell on
vbell_msg '!Bell!'
autodetach on
startup_message off
defscrollback 10000

# Termcapinfo for xterm
termcapinfo xterm* Z0=\E[?3h:Z1=\E[?3l:is=\E[r\E[m\E[2J\E[H\E[?7h\E[?1;4;6l
termcapinfo xterm* OL=1000

# Remove keyboard bindings that lock the screen or write it to disk
bind x
bind ^x
bind h
bind ^h
bind ^\
bind .

# Add keyboard bindings
bind } history
bind k kill
EOF
fi

exit 0
