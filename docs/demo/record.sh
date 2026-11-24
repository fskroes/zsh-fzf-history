#!/usr/bin/env bash
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
tmux -L zfh-demo kill-server 2>/dev/null || true
