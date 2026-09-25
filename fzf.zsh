# zsh-fzf-history: fzf Ctrl-R history search for zsh (macOS), tuned.
# Source this file from ~/.zshrc AFTER oh-my-zsh and your other plugins.
#
# Keys: Ctrl-R history, Ctrl-T file picker, Left Option+C (Alt-C) cd into a folder.
# In the Ctrl-R list: Enter inserts (does not run), Shift-Tab marks more,
# Ctrl-R toggles sort, Ctrl-/ toggles line wrap, Ctrl-Y copies.
# Docs: https://github.com/junegunn/fzf#key-bindings-for-command-line

if (( $+commands[fzf] )); then
  # Ctrl-Y uses printf, not the fzf README's `echo -n`: zsh's echo would turn
  # \n and \t inside a command into real newlines/tabs. It copies {} (the whole
  # line), not {2..}: fzf trims spaces at the ends of {2..}. perl removes the
  # "<number><tab>" prefix and the tab fzf adds after each newline of a
  # multi-line entry. Like Esc, Ctrl-Y leaves the text you typed in the prompt.
  export FZF_CTRL_R_OPTS="
    --bind 'ctrl-y:execute-silent(printf %s {} | perl -0pe \"s/^[^\t]*\t//; s/\n\t/\n/g\" | pbcopy)+abort'
    --color header:italic
    --header 'CTRL-Y: copy to clipboard'"
  source <(fzf --zsh)

  # When share_history is off, this shell's history list does not get the
  # commands that other open tabs write to $HISTFILE. (The Otty terminal turns
  # share_history off at the first prompt when its history scope is per-pane.)
  # So just before the Ctrl-R list opens, fc -RI reads $HISTFILE and adds only
  # the events that are not already in this shell's history list.
  # Only when share_history is off: with it on, fc -RI adds duplicate entries.
  fzf-history-widget-all-tabs() {
    [[ -o share_history ]] || fc -RI
    zle fzf-history-widget
  }
  zle -N fzf-history-widget-all-tabs
  bindkey -M emacs '^R' fzf-history-widget-all-tabs
  bindkey -M viins '^R' fzf-history-widget-all-tabs
  bindkey -M vicmd '^R' fzf-history-widget-all-tabs
fi
