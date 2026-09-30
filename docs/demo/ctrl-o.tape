# Ctrl-O in the Ctrl-R list: only the commands that ran in this folder and its subfolders.
# Record all demos: bash docs/demo/record.sh   (from the repo root)
Output docs/demo/ctrl-o.gif
Source docs/demo/start.tape

Type " cap 'Ctrl-O in the list: only the commands that ran in this folder (~/app).'" Enter
Sleep 500ms
Show

Sleep 500ms
Ctrl+R
Sleep 2s
Ctrl+O
Sleep 2.5s
Ctrl+O
Sleep 2s
Ctrl+O
Sleep 1.5s
Type "push"
Sleep 1.5s
Enter
Sleep 2s

Hide
Type "tmux -L zfh-demo kill-server" Enter
