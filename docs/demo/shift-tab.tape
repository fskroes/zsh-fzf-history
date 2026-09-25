# Shift-Tab in the Ctrl-R list: mark more than one command.
# VHS cannot type Shift-Tab: Ctrl+G sends a real Shift-Tab (see setup.sh).
# Record all demos: bash docs/demo/record.sh   (from the repo root)
Output docs/demo/shift-tab.gif
Source docs/demo/start.tape

Type " cap 'Shift-Tab in the list: mark more than one. Enter puts all of them in the prompt.'" Enter
Sleep 500ms
Show

Sleep 500ms
Ctrl+R
Sleep 1.2s
Type "git "
Sleep 1s
Ctrl+G
Sleep 700ms
Ctrl+G
Sleep 700ms
Ctrl+G
Sleep 1s
Enter
Sleep 3s

Hide
Type "tmux -L zfh-demo kill-server" Enter
