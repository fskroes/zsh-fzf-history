# Ctrl-R sees a command from another open tab at once. Two tmux panes = two tabs.
# Record all demos: bash docs/demo/record.sh   (from the repo root)
Output docs/demo/other-tabs.gif
Require tmux
Require fzf

Set Shell bash
Set FontSize 18
Set Width 1400
Set Height 600
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 70ms

Hide
Type "bash docs/demo/setup.sh /tmp/zfh-demo && tmux -L zfh-demo -f /tmp/zfh-demo/tmux.conf new -s demo \; split-window -h \; select-pane -L" Enter
Sleep 2s
Type " cap 'Ctrl-R sees commands from your other open tabs at once.'" Enter
Sleep 500ms
Show

Sleep 800ms
Type "deploy staging"
Sleep 500ms
Enter
Sleep 1.2s
Ctrl+B
Right
Sleep 1s
Ctrl+R
Sleep 1.2s
Type "depl"
Sleep 1.5s
Enter
Sleep 3s

Hide
Type "tmux -L zfh-demo kill-server" Enter
