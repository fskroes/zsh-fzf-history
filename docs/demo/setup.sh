#!/usr/bin/env bash
# Build the sandbox that docs/demo/demo.tape records: a made-up history,
# a fake pbcopy/pbpaste and a minimal zsh config that sources ../../fzf.zsh.
# Your own history, clipboard and ~/.zshrc are not used.
# Usage: bash docs/demo/setup.sh DIR
set -euo pipefail
D=${1:?usage: setup.sh DIR}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
rm -rf "$D"; mkdir -p "$D/zdot" "$D/bin" "$D/app"

t=$(( $(date +%s) - 86400 ))
h() { printf ': %s:0;%s\n' "$t" "$1"; t=$((t + 60)); }
{
  h 'brew upgrade'
  h 'git status'
  h 'git pull --rebase'
  h 'docker compose up -d'
  h 'docker compose logs -f api'
  h 'ssh deploy@staging.example.com'
  h 'git log --oneline -10'
  h 'npm run test -- --watch'
  h 'kubectl get pods -n web'
  h 'for f in *.log; do\
  gzip "$f"\
done'
  h 'git switch -c fix-login'
  h 'git commit -am "Fix login redirect"'
  h 'git push -u origin HEAD'
  h 'curl -s localhost:8080/health | jq .'
} > "$D/hist"

# Fake clipboard: the demo shows the copy without touching the real one.
printf '#!/bin/sh\ncat > "%s/clip"\n' "$D" > "$D/bin/pbcopy"
printf '#!/bin/sh\ncat "%s/clip"\n'   "$D" > "$D/bin/pbpaste"
chmod +x "$D/bin/pbcopy" "$D/bin/pbpaste"

cat > "$D/zdot/.zshrc" <<ZSHRC
HISTFILE=$D/hist; HISTSIZE=1000; SAVEHIST=1000
# Per-tab history, like Otty's per-pane scope: this is the case fzf.zsh fixes.
setopt extended_history inc_append_history hist_ignore_space
unsetopt share_history
bindkey -e
path=($D/bin \$path)
PROMPT='%F{245}~/app%f %F{magenta}\$%f '
deploy() { print "Deploying to \$1 ... done"; }
# Caption in the tmux status bar. The leading space keeps it out of history.
cap() { tmux set -g status-left " \$* "; clear; }
cd $D/app
source $REPO/fzf.zsh
ZSHRC

cat > "$D/tmux.conf" <<TMUX
set -g default-command "ZDOTDIR=$D/zdot exec zsh -i"
set -g status-position top
set -g status-style "bg=colour236,fg=colour230"
set -g status-left-length 100
set -g status-left " "
set -g status-right ""
set -g window-status-format ""
set -g window-status-current-format ""
set -g pane-border-status bottom
set -g pane-border-format " #{?pane_active,#[fg=colour212 bold],}tab #{pane_index} "
set -g pane-base-index 1
set -g pane-active-border-style "fg=colour212"
set -g escape-time 0
# VHS cannot type Shift-Tab. Ctrl-G sends a real Shift-Tab (BTab) to fzf.
bind -n C-g send-keys BTab
TMUX
