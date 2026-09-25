#!/usr/bin/env bash
# Record every GIF in docs/demo/ again, from its .tape file.
# Needs vhs, tmux and fzf 0.68+ (brew install vhs tmux fzf).
# Usage: bash docs/demo/record.sh [NAME ...]   e.g. bash docs/demo/record.sh ctrl-t option-c
# One at a time: all tapes use the same sandbox (/tmp/zfh-demo) and tmux socket.
set -euo pipefail
cd "$(dirname "$0")/../.."
if (( $# )); then names=("$@"); else
  names=()
  for t in docs/demo/*.tape; do
    [[ $t == */start.tape ]] || names+=("$(basename "$t" .tape)")
  done
fi
for n in "${names[@]}"; do
  echo "== $n"
  vhs "docs/demo/$n.tape" > /dev/null
  ls -l "docs/demo/$n.gif"
done
# VHS can exit before the tape's last "kill-server" runs.
tmux -L zfh-demo kill-server 2>/dev/null || true
