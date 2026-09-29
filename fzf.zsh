# zsh-fzf-history: fzf Ctrl-R history search for zsh (macOS), tuned.
# Source this file from ~/.zshrc AFTER oh-my-zsh and your other plugins.
#
# Keys: Ctrl-R history, Ctrl-T file picker, Left Option+C (Alt-C) cd into a folder.
# The Ctrl-R list shows the date and time of each command, newest first, also
# while you type. In the list: Enter inserts (does not run), Shift-Tab marks more,
# Ctrl-R sorts by match instead (again: by time), Ctrl-/ toggles line wrap, Ctrl-Y copies.
# Docs: https://github.com/junegunn/fzf#key-bindings-for-command-line

if (( $+commands[fzf] )); then
  # Ctrl-Y uses printf, not the fzf README's `echo -n`: zsh's echo would turn
  # \n and \t inside a command into real newlines/tabs. It copies {} (the whole
  # line), not {3..}: fzf trims spaces at the ends of {3..}. perl removes the
  # "<event><tab><time> │ " prefix (see the line format below) and the
  # "<tab><spaces>│ " that the widget adds after each newline of a multi-line
  # entry. Like Esc, Ctrl-Y leaves
  # the text you typed in the prompt. This file sets FZF_CTRL_R_OPTS each time
  # it loads, so an exported value from an older version does not stay.
  export FZF_CTRL_R_OPTS="
    --bind 'ctrl-y:execute-silent(printf %s {} | perl -0pe \"s/^[^\t]*\t[^\t]*? │ //; s/\n\t *│ /\n/g\" | pbcopy)+abort'
    --color header:italic
    --header 'CTRL-Y: copy to clipboard'"
  source <(fzf --zsh)

  # Ctrl-R widget. It replaces fzf's fzf-history-widget, and uses the same fzf
  # options, so that the list can be sorted by time. fzf's own widget lists by
  # event number and, when you type, sorts by match score.
  #
  # When share_history is off, this shell's history list does not get the
  # commands that other open tabs write to $HISTFILE. (The Otty terminal turns
  # share_history off at the first prompt when its history scope is per-pane.)
  # So just before the Ctrl-R list opens, fc -RI reads $HISTFILE and adds only
  # the events that are not already in this shell's history list.
  # Only when share_history is off: with it on, fc -RI adds duplicate entries.
  # fc -RI gives the new events higher numbers than the commands of this tab,
  # also when they are older. That is why the list sorts on time.
  #
  # One line per command: "<event>\t<YYYY-MM-DD HH:MM> │ <command>", NUL at the end.
  # perl gets the time of each event from `fc -l -t %s` (it prints one line per
  # event: it writes a newline in a command as \n) and the exact command text
  # from $history. It sorts newest first (same time: higher event first), keeps
  # only the newest copy of each command, and after each newline of a
  # multi-line command it adds "<tab><16 spaces> │ ", so that the next line
  # starts under the command. " │ " and not a tab after the time: the time ends
  # on a tab stop, so a tab would add 8 empty columns. --nth=3.. searches only
  # the command.
  #
  # zsh does not let a widget run `fc -l` ("no interactive history within ZLE"),
  # so fc runs in a subshell. On macOS, localtime() in a forked child that
  # did not exec reads the time zone file again at each call: `fc -l -t` then
  # takes 11 s instead of 0.15 s for 50,000 commands. With TZ set to empty,
  # libc reads no zone file. %s is Unix time, so the time zone does not change
  # it. perl is a new program, so it formats the time in your own time zone.
  fzf-history-widget-all-tabs() {
    [[ -o share_history ]] || fc -RI
    if ! { zmodload -F zsh/parameter p:{commands,history} 2>/dev/null &&
           (( $+commands[perl] && $+functions[__fzf_defaults] && $+functions[__fzfcmd] )) }; then
      zle fzf-history-widget
      return
    fi
    setopt localoptions noglobsubst noposixbuiltins pipefail no_aliases no_glob no_sh_glob no_ksharrays extendedglob 2> /dev/null
    local selected line ret
    local -a cmds mbegin mend match
    local opts="--delimiter='\t| │ ' --nth=3.. --no-sort --scheme=history
      --bind=ctrl-r:toggle-sort,alt-r:toggle-raw --wrap-sign '\t↳ ' --highlight-line --multi"
    selected="$(printf '%s\t%s\000' "${(kv)history[@]}" |
      perl -e '
        use POSIX "strftime";
        my (%t, @e, %seen);
        my $pad = " " x 16;
        open my $fc, "<", shift or exit 1;
        while (<$fc>) { $t{$1} = $2 if /^\s*(\d+)\*?\s+(\d+)\s/ }
        { local $/ = "\0"; while (<STDIN>) { chomp; push @e, [$1, $t{$1} // 0, $2] if /^(\d+)\t(.*)\z/s } }
        for (sort { $b->[1] <=> $a->[1] || $b->[0] <=> $a->[0] } @e) {
          next if $seen{$_->[2]}++;
          (my $c = $_->[2]) =~ s/\n/\n\t$pad │ /g;
          print "$_->[0]\t", ($_->[1] ? strftime("%Y-%m-%d %H:%M", localtime $_->[1]) : $pad), " │ $c\0";
        }' <(export TZ=; fc -l -t '%s' 1 2> /dev/null) |
      FZF_DEFAULT_OPTS=$(__fzf_defaults "" "$opts ${FZF_CTRL_R_OPTS-} --query=${(qqq)LBUFFER} --read0") \
      FZF_DEFAULT_OPTS_FILE='' $(__fzfcmd))"
    ret=$?
    if [[ -n $selected ]]; then
      if [[ $selected == <->$'\t'* ]]; then
        # Continuation lines of a multi-line command start with a tab, so only
        # the first line of each selected command matches.
        for line in ${(ps:\n:)selected}; do
          if [[ $line == (#b)(<->)(#B)$'\t'* ]]; then
            (( ${+history[${match[1]}]} )) && cmds+=("${history[${match[1]}]}")
          fi
        done
        if (( ${#cmds[@]} )); then
          BUFFER="${(pj:\n:)${(@)cmds%%$'\n'#}}"
          CURSOR=${#BUFFER}
        fi
      else
        LBUFFER="$selected"
      fi
    fi
    zle reset-prompt
    return $ret
  }
  zle -N fzf-history-widget-all-tabs
  bindkey -M emacs '^R' fzf-history-widget-all-tabs
  bindkey -M viins '^R' fzf-history-widget-all-tabs
  bindkey -M vicmd '^R' fzf-history-widget-all-tabs
fi
