# Ctrl-R and Ctrl-/ in the Ctrl-R list: sort by match or by time, wrap long lines.
# VHS cannot type Ctrl-/: Ctrl+O sends a real Ctrl-/ (see setup.sh).
# Record all demos: bash docs/demo/record.sh   (from the repo root)
Output docs/demo/list-keys.gif
Source docs/demo/start.tape

Type " cap 'Ctrl-R in the list: sort by match or by time.'" Enter
Sleep 500ms
Show

Sleep 500ms
Ctrl+R
Sleep 1.2s
Type "gl"
Sleep 1.5s
Ctrl+R
Sleep 2s
Ctrl+R
Sleep 2s

Hide
Escape
Sleep 300ms
Type " cap 'Ctrl-/ in the list: wrap long lines on or off.'" Enter
Sleep 500ms
Show

Sleep 500ms
Ctrl+R
Sleep 1.2s
Type "docker run"
Sleep 1.5s
Ctrl+O
Sleep 2.5s
Ctrl+O
Sleep 2s

Hide
Escape
Type "tmux -L zfh-demo kill-server" Enter
