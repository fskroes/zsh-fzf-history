# Shared start for the one-key tapes. They load it with Source; it records nothing itself.
# Opens the sandbox from setup.sh in one tmux pane, hidden.
Require tmux
Require fzf

Set Shell bash
Set FontSize 18
Set Width 1200
Set Height 600
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 70ms

Hide
Type "bash docs/demo/setup.sh /tmp/zfh-demo && tmux -L zfh-demo -f /tmp/zfh-demo/tmux.conf new -s demo" Enter
Sleep 2s

Type " tmux set -g pane-border-status off" Enter
Sleep 300ms
