#!/usr/bin/env bash
# Build the sandbox that the tapes in docs/demo/ record: a made-up history,
# a made-up project folder, a fake pbcopy/pbpaste and a minimal zsh config
# that sources ../../fzf.zsh. Your own history, clipboard, files and ~/.zshrc
# are not used.
# Usage: bash docs/demo/setup.sh DIR
set -euo pipefail
D=${1:?usage: setup.sh DIR}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
# A tape that ended early can leave the demo tmux server running.
tmux -L zfh-demo kill-server 2>/dev/null || true
rm -rf "$D"; mkdir -p "$D/zdot" "$D/bin" "$D/app"

t=$(( $(date +%s) - 86400 ))
h() { printf ': %s:0;%s\n' "$t" "$1"; t=$((t + 60)); }
{
  h 'docker run --rm -it -p 8080:8080 -e LOG_LEVEL=debug -e DATABASE_URL=postgres://app:app@localhost:5432/app -v "$PWD/config:/etc/app" ghcr.io/example/app:latest'
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

# Made-up project for Ctrl-T, Left Option+C and ** completion.
for f in README.md package.json docker-compose.yml \
         src/auth/login.ts src/auth/session.ts src/api/health.ts src/api/users.ts \
         src/components/Button.tsx src/components/Header.tsx src/components/LoginForm.tsx \
         tests/login.test.ts tests/session.test.ts \
         config/nginx.conf config/app.env.example docs/deploy.md; do
  mkdir -p "$D/app/$(dirname "$f")"; : > "$D/app/$f"
done

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
# HOME is the sandbox, so the prompt shows ~/app and changes after Left Option+C.
HOME=$D
PROMPT='%F{245}%~%f %F{magenta}\$%f '
deploy() { print "Deploying to \$1 ... done"; }
# Caption in the tmux status bar. The leading space keeps it out of history.
# It also clears the key badge (see tmux.conf).
cap() { tmux set -g status-left " \$* " \; set -g @key ""; clear; }
cd $D/app
source $REPO/fzf.zsh
ZSHRC

cat > "$D/tmux.conf" <<TMUX
set -g default-command "ZDOTDIR=$D/zdot exec zsh -i"
set -g status-position top
set -g status-style "bg=colour236,fg=colour230"
set -g status-left-length 100
set -g status-left " "
# Key badge: the last demo key that was pressed, on the right of the status bar.
set -g @key ""
set -g status-right "#{?#{@key},#[bg=colour212 fg=colour234 bold] #{@key} ,}"
set -g status-right-length 40
set -g window-status-format ""
set -g window-status-current-format ""
set -g pane-border-status bottom
set -g pane-border-format " #{?pane_active,#[fg=colour212 bold],}tab #{pane_index} "
set -g pane-base-index 1
set -g pane-active-border-style "fg=colour212"
set -g escape-time 0
# Each demo key sets the badge, then goes to the shell unchanged.
bind -n C-r   set -g @key "Ctrl-R"        \; send-keys C-r
bind -n C-t   set -g @key "Ctrl-T"        \; send-keys C-t
bind -n M-c   set -g @key "Left Option+C" \; send-keys M-c
bind -n C-y   set -g @key "Ctrl-Y"        \; send-keys C-y
bind -n Tab   set -g @key "Tab"           \; send-keys Tab
bind -n Enter set -g @key "Enter"         \; send-keys Enter
# VHS cannot type Shift-Tab or Ctrl-/, and its Alt+c sends a plain "c".
# Ctrl-G sends a real Shift-Tab (BTab), Ctrl-O a real Ctrl-/ (C-_),
# Ctrl-X a real Left Option+C (M-c, which is ESC c).
bind -n C-g   set -g @key "Shift-Tab"     \; send-keys BTab
bind -n C-o   set -g @key "Ctrl-/"        \; send-keys C-_
bind -n C-x   set -g @key "Left Option+C" \; send-keys M-c
TMUX
