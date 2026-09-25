# ** then Tab: fzf completion for the command you are typing.
# Record all demos: bash docs/demo/record.sh   (from the repo root)
Output docs/demo/star-tab.gif
Source docs/demo/start.tape

Type " cap 'Type ** then Tab: pick a path for the command you are typing.'" Enter
Sleep 500ms
Show

Sleep 500ms
Type "vim **"
Sleep 700ms
Tab
Sleep 1.2s
Type "nginx"
Sleep 1.2s
Enter
Sleep 2s
Ctrl+U

Type "cd **"
Sleep 700ms
Tab
Sleep 1.2s
Type "auth"
Sleep 1.2s
Enter
Sleep 1s
Enter
Sleep 3s

Hide
Type "tmux -L zfh-demo kill-server" Enter
