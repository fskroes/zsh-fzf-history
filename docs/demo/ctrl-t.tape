# Ctrl-T: pick files, their paths go in the prompt.
# Record all demos: bash docs/demo/record.sh   (from the repo root)
Output docs/demo/ctrl-t.gif
Source docs/demo/start.tape

Type " cap 'Ctrl-T: pick files. Their paths go in the prompt.'" Enter
Sleep 500ms
Show

Sleep 500ms
Type "vim "
Sleep 500ms
Ctrl+T
Sleep 1.2s
Type "login"
Sleep 1.2s
Tab
Sleep 700ms
Tab
Sleep 1s
Enter
Sleep 3s

Hide
Type "tmux -L zfh-demo kill-server" Enter
