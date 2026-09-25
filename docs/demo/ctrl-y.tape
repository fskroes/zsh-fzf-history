# Ctrl-Y in the Ctrl-R list: copy the exact command. pbpaste shows the copy.
# Record all demos: bash docs/demo/record.sh   (from the repo root)
Output docs/demo/ctrl-y.gif
Source docs/demo/start.tape

Type " cap 'Ctrl-Y in the list: copy the exact command, also multi-line ones.'" Enter
Sleep 500ms
Show

Sleep 500ms
Ctrl+R
Sleep 1.2s
Type "gzip"
Sleep 1.5s
Ctrl+Y
Sleep 1.2s
Type "pbpaste"
Sleep 500ms
Enter
Sleep 3s

Hide
Type "tmux -L zfh-demo kill-server" Enter
