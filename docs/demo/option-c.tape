# Left Option+C (Alt-C): cd into a folder.
# VHS Alt+c sends a plain "c": Ctrl+X sends a real Option+C (see setup.sh).
# Record all demos: bash docs/demo/record.sh   (from the repo root)
Output docs/demo/option-c.gif
Source docs/demo/start.tape

Type " cap 'Left Option+C: cd into a folder. Look at the prompt.'" Enter
Sleep 500ms
Show

Sleep 800ms
Ctrl+X
Sleep 1.2s
Type "comp"
Sleep 1.2s
Enter
Sleep 1.5s
Type "ls"
Sleep 500ms
Enter
Sleep 3s

Hide
Type "tmux -L zfh-demo kill-server" Enter
