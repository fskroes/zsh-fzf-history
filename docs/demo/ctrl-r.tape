Output docs/demo/ctrl-r.gif
Source docs/demo/start.tape

Type " cap 'Ctrl-R: fuzzy search. Enter puts the command in the prompt, it does not run.'" Enter
Sleep 500ms
Show

Sleep 500ms
Ctrl+R
Sleep 1.2s
Type "dcklogs"
Sleep 1.5s
Enter
Sleep 2.5s
Ctrl+U

Type "kubectl"
Sleep 700ms
Ctrl+R
Sleep 1.5s
Enter
Sleep 3s

Hide
Type "tmux -L zfh-demo kill-server" Enter
