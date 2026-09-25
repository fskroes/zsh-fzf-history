# Ctrl-R: fuzzy history search. Enter puts the command in the prompt.
# Record all demos: bash docs/demo/record.sh   (from the repo root)
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

# Text you already typed becomes the search.
Type "kubectl"
Sleep 700ms
Ctrl+R
Sleep 1.5s
Enter
Sleep 3s

Hide
Type "tmux -L zfh-demo kill-server" Enter
