# Record the README demo:  bash docs/demo/record.sh demo   (run from the repo root)
# Needs vhs, tmux and fzf 0.68+ (brew install vhs tmux fzf).
# Uses a sandbox from docs/demo/setup.sh: made-up history, fake clipboard.

Output docs/demo/demo.gif
Require tmux
Require fzf

Set Shell bash
Set FontSize 18
Set Width 1400
Set Height 760
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 70ms

Hide
Type "bash docs/demo/setup.sh /tmp/zfh-demo && tmux -L zfh-demo -f /tmp/zfh-demo/tmux.conf new -s demo \; split-window -h \; select-pane -L" Enter
Sleep 2s
Type " cap 'Ctrl-R: fuzzy search. Enter puts the command in the prompt, it does not run.'" Enter
Sleep 500ms
Show

# 1. Fuzzy search
Sleep 300ms
Ctrl+R
Sleep 1s
Type "dcklogs"
Sleep 1.5s
Enter
Sleep 2s
Ctrl+U

# 2. Another open tab
Hide
Type " cap 'Ctrl-R sees commands from your other open tabs at once.'" Enter
Sleep 500ms
Show
Sleep 1s
Type "deploy staging"
Sleep 500ms
Enter
Sleep 1s
Ctrl+B
Right
Sleep 1s
Ctrl+R
Sleep 1s
Type "depl"
Sleep 1.5s
Enter
Sleep 2.5s
Ctrl+U

# 3. Ctrl-Y copies the exact command
Hide
Type " cap 'Ctrl-Y copies the exact command, also multi-line ones.'" Enter
Sleep 500ms
Show
Sleep 1s
Ctrl+R
Sleep 1s
Type "gzip"
Sleep 1.5s
Ctrl+Y
Sleep 1s
Type "pbpaste"
Sleep 500ms
Enter
Sleep 2.5s

# 4. Mark more than one (Ctrl+G = Shift-Tab, see setup.sh)
Hide
Type " cap 'Shift-Tab marks more than one command. Enter puts all of them in the prompt.'" Enter
Sleep 500ms
Show
Sleep 1s
Ctrl+R
Sleep 1s
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
