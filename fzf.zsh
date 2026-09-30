# zsh-fzf-history: fzf Ctrl-R history search for zsh (macOS), tuned.
# Source this file from ~/.zshrc AFTER oh-my-zsh and your other plugins.
#
# Keys: Ctrl-R history, Ctrl-T file picker, Left Option+C (Alt-C) cd into a folder.
# The Ctrl-R list shows the date and time of each command, newest first, also
# while you type. In the list: Enter inserts (does not run), Shift-Tab marks more,
# Ctrl-R sorts by match instead (again: by time), Ctrl-/ toggles line wrap, Ctrl-Y copies,
# Ctrl-O shows only the commands that ran in this folder and its subfolders (again: all).
# Docs: https://github.com/junegunn/fzf#key-bindings-for-command-line

# zsh expands aliases when it reads a function. Aliases are off while this file
# is read, so that an alias such as rm=trash does not change the functions.
if [[ -o aliases ]]; then _zfh_aliases=1; setopt no_aliases; else _zfh_aliases=0; fi
if (( ${+commands[fzf]} )); then
  # Ctrl-Y uses printf, not the fzf README's `echo -n`: zsh's echo would turn
  # \n and \t inside a command into real newlines/tabs. It copies {} (the whole
  # line), not {3..}: fzf trims spaces at the ends of {3..}. perl removes the
  # "<event><tab><time> │ " prefix (see the line format below) and the
  # "<tab><16 spaces> │ " that the widget adds after each newline of a
  # multi-line entry. In fzf's own widget (the fallback below) the prefix is
  # "<event><tab>" and a newline gets only a tab: perl removes those too.
  # Like Esc, Ctrl-Y leaves
  # the text you typed in the prompt. This file sets FZF_CTRL_R_OPTS each time
  # it loads, so an exported value from an older version does not stay. The
  # header names only Ctrl-Y: fzf's own widget (the fallback below) also reads
  # FZF_CTRL_R_OPTS and has no Ctrl-O. The widget adds Ctrl-O to its header.
  export FZF_CTRL_R_OPTS="
    --bind 'ctrl-y:execute-silent(printf %s {} | perl -0pe \"s/^[0-9]+\t(?:(?:[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}| {16}) │ )?//; s/\n\t(?: {16} │ )?/\n/g\" | pbcopy)+abort'
    --color header:italic
    --header 'CTRL-Y: copy to clipboard'"
  source <(fzf --zsh)

  # The folder of each command, for Ctrl-O in the Ctrl-R list. zsh history does
  # not save the folder, so this file appends "<time>\t<folder>\t<command>\0" to
  # ${HISTFILE}_dirs (mode 600). The command text comes from $history, so it is
  # the same text that Ctrl-R lists (also with hist_reduce_blanks).
  #
  # Rule: a line goes to the folder file only if zsh wrote it to $HISTFILE for
  # this command. So a line that zsh keeps out of $HISTFILE does not go there
  # either: a leading space (also from an alias) with hist_ignore_space, a match
  # with HISTORY_IGNORE, a zshaddhistory hook that returns 1 or 2, no HISTFILE,
  # SAVEHIST=0. In preexec such lines still look normal in $history, so the
  # file itself is the proof. At each prompt, precmd saves the size and inode
  # of $HISTFILE (_zfh_dirs_mark). _zfh_dirs_saved looks for the line only in
  # the bytes that were added after that mark, so an older copy of the same
  # text (from another folder or tab) does not count. If the file was replaced
  # or became smaller (zsh rewrote it), the line is not saved. preexec clears
  # the mark, so it is good for one command only: if a precmd hook before ours
  # fails (zsh then skips the hooks after it), no mark means nothing is saved.
  # Our precmd hook goes first in precmd_functions for that reason.
  #
  # inc_append_history and share_history write the line before preexec, so
  # preexec saves it at once. inc_append_history_time writes it when the
  # command ends: the line waits in _zfh_dirs_wait, and precmd saves it.
  # Without these options zsh writes history only at exit: nothing is saved.
  # A folder with a tab in its name is not saved.
  if zmodload -F zsh/parameter p:history 2>/dev/null &&
     zmodload -F zsh/datetime p:EPOCHSECONDS 2>/dev/null &&
     zmodload -F zsh/system b:sysopen b:sysread b:sysseek 2>/dev/null &&
     zmodload -F zsh/stat b:zstat 2>/dev/null; then
    typeset -ga _zfh_dirs_wait _zfh_dirs_mark
    # reply=(<file> <inode> <size>), "-" and 0 if the file does not exist.
    _zfh_dirs_stat() {
      local -A st
      if zstat -H st -- "$HISTFILE" 2>/dev/null; then
        reply=("$HISTFILE" "$st[inode]" "$st[size]")
      else
        reply=("$HISTFILE" - 0)
      fi
    }
    # True if zsh wrote the command $1 to $HISTFILE after the mark $2 $3 $4
    # (file, inode, size).
    # In the file a newline is "\<newline>", and zsh writes the bytes 0x83 to
    # 0xa2 (in many UTF-8 characters, for example "↳") as 0x83 and the byte
    # XOR 32. 0x83 goes first: no replacement makes a byte in that range.
    # Without extended_history, a command that starts with ":" gets a "\" first.
    _zfh_dirs_saved() {
      emulate -L zsh -o no_multibyte -o extended_glob
      local -a reply mark=("${(@)argv[2,-1]}")
      (( $#mark == 3 )) && [[ $mark[1] == "$HISTFILE" ]] || return 1
      _zfh_dirs_stat
      [[ $mark[2] == - || $mark[2] == $reply[2] ]] || return 1
      local -i b n=$(( reply[3] - mark[3] ))
      (( n > 0 && n <= 4194304 )) || return 1
      local e=${1//$'\n'/\\$'\n'} buf fd x=
      # zsh writes a space after a "\" (and the spaces after it) at the end, so
      # that the line does not continue.
      [[ $e == *\\( )# ]] && e+=' '
      e+=$'\n'
      [[ $1 == :* ]] && x='\'
      if [[ $e == *[$'\x83'-$'\xa2']* ]]; then
        for (( b = 0x83; b <= 0xa2; b++ )); do e=${e//${(#)b}/$'\x83'${(#)$(( b ^ 32 ))}}; done
      fi
      sysopen -r -u fd -- "$HISTFILE" 2>/dev/null || return 1
      sysseek -u $fd $mark[3] && sysread -i $fd -s $n buf
      exec {fd}<&-
      buf=$'\n'$buf
      # A full line, with or without extended_history (": <start>:<elapsed>;").
      [[ $buf == *$'\n'(": "<->:<->";"|"$x")"$e"* ]]
    }
    _zfh_dirs_add() {
      emulate -L zsh
      local f=${HISTFILE}_dirs
      [[ -e $f ]] || ( umask 077; : >>| "$f" ) 2>/dev/null
      print -rn -- "$1"$'\t'"$2"$'\t'"$3"$'\0' >>| "$f" 2>/dev/null
    }
    _zfh_dirs_preexec() {
      emulate -L zsh
      local -a mark=("${(@)_zfh_dirs_mark}")
      _zfh_dirs_wait=() _zfh_dirs_mark=()
      local cmd=${history[$HISTCMD]-}
      [[ -n ${HISTFILE-} && -n $cmd && $PWD != *$'\t'* ]] && (( ${SAVEHIST:-0} > 0 )) || return 0
      if _zfh_dirs_saved "$cmd" "${(@)mark}"; then
        _zfh_dirs_add $EPOCHSECONDS "$PWD" "$cmd"
      elif [[ -o inc_append_history_time && ! -o inc_append_history && ! -o share_history ]]; then
        # With the other two options zsh already wrote the line or it will not
        # write it for this command. The line waits with its mark.
        _zfh_dirs_wait=($EPOCHSECONDS "$PWD" "$cmd" "${(@)mark}")
      fi
    }
    _zfh_dirs_precmd() {
      emulate -L zsh
      local -a reply
      (( $#_zfh_dirs_wait == 6 )) && _zfh_dirs_saved "${(@)_zfh_dirs_wait[3,6]}" &&
        _zfh_dirs_add "${(@)_zfh_dirs_wait[1,3]}"
      _zfh_dirs_wait=()
      _zfh_dirs_mark=()
      [[ -n ${HISTFILE-} ]] && _zfh_dirs_stat && _zfh_dirs_mark=("${(@)reply}")
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook preexec _zfh_dirs_preexec
    add-zsh-hook precmd _zfh_dirs_precmd
    precmd_functions=(_zfh_dirs_precmd "${precmd_functions[@]:#_zfh_dirs_precmd}")
  fi

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
  #
  # perl writes two lists to a temp folder: "all" (above) and "here", the
  # commands that ran in $PWD or a subfolder (from ${HISTFILE}_dirs), sorted by their last time there. fzf starts with "all".
  # Ctrl-O runs the "toggle" script: it reloads the other list and changes the
  # prompt ("~/folder > " for "here"). The temp path is written into the fzf
  # options and the script as it is, with no quotes: fzf-tmux passes only the
  # options to fzf, not other environment variables. So the path may only have
  # letters, digits and "/._-"; if $TMPDIR has other characters, /tmp is used.
  # The lists hold all of $history, so _zfh_tmp_clean deletes them when fzf
  # exits, and also at shell exit (zshexit runs also when the tab closes while
  # the list is open).
  typeset -g _zfh_tmp
  _zfh_tmp_clean() {
    emulate -L zsh
    [[ -n $_zfh_tmp ]] || return 0
    command rm -f -- "$_zfh_tmp/all" "$_zfh_tmp/here" "$_zfh_tmp/here.name" "$_zfh_tmp/toggle" "$_zfh_tmp/prompt" "$_zfh_tmp/on"
    command rmdir -- "$_zfh_tmp" 2> /dev/null
    _zfh_tmp=
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook zshexit _zfh_tmp_clean
  fzf-history-widget-all-tabs() {
    setopt localoptions noglobsubst noposixbuiltins pipefail no_aliases no_glob no_sh_glob no_ksharrays extendedglob no_nounset 2> /dev/null
    [[ -o share_history ]] || fc -RI
    if ! { zmodload -F zsh/parameter p:{commands,history} 2>/dev/null &&
           (( $+commands[perl] && $+functions[__fzf_defaults] && $+functions[__fzfcmd] )) }; then
      zle fzf-history-widget
      return
    fi
    local selected line ret tmp base=${TMPDIR:-/tmp}
    local -a cmds mbegin mend match
    [[ $base == [[:alnum:]/._-]## ]] || base=/tmp
    tmp=$(command mktemp -d "${base%/}/zfh.XXXXXX" 2> /dev/null) || { zle fzf-history-widget; return }
    _zfh_tmp=$tmp
    # "always" also runs after Ctrl-C while perl or fzf runs.
    {
    local opts="--delimiter='\t| │ ' --nth=3.. --no-sort --scheme=history
      --bind=ctrl-r:toggle-sort,alt-r:toggle-raw --wrap-sign '\t↳ ' --highlight-line --multi
      --bind='ctrl-o:transform:sh $tmp/toggle'"
    if printf '%s\t%s\000' "${(kv)history[@]}" |
      command perl -e '
        use POSIX "strftime";
        my ($fcf, $out, $dirs, $here) = @ARGV;
        my (%t, @e, %seen, %last, @r);
        my $pad = " " x 16;
        open my $fc, "<", $fcf or exit 1;
        while (<$fc>) { $t{$1} = $2 if /^\s*(\d+)\*?\s+(\d+)\s/ }
        {
          local $/ = "\0";
          while (<STDIN>) { chomp; push @e, [$1, $t{$1} // 0, $2] if /^(\d+)\t(.*)\z/s }
          if (open my $d, "<", $dirs) { while (<$d>) { chomp; push @r, [split /\t/, $_, 3] } }
        }
        my $sub = $here eq "/" ? "/" : "$here/";
        for (@r) {
          my ($tm, $p, $c) = @$_;
          next unless defined $c && $tm =~ /^\d+\z/ && ($p eq $here || index($p, $sub) == 0);
          $last{$c} = $tm if $tm > ($last{$c} // -1);
        }
        my $by_time = sub { $b->[1] <=> $a->[1] || $b->[0] <=> $a->[0] };
        my @all = grep { !$seen{$_->[2]}++ } sort $by_time @e;
        my @in = sort $by_time map { [$_->[0], $last{$_->[2]}, $_->[2]] } grep { exists $last{$_->[2]} } @all;
        for (["all", \@all], ["here", \@in]) {
          open my $o, ">", "$out/$_->[0]" or exit 1;
          for (@{$_->[1]}) {
            (my $c = $_->[2]) =~ s/\n/\n\t$pad │ /g;
            print $o "$_->[0]\t", ($_->[1] ? strftime("%Y-%m-%d %H:%M", localtime $_->[1]) : $pad), " │ $c\0";
          }
          close $o or exit 1;
        }' <(export TZ=; fc -l -t '%s' 1 2> /dev/null) "$tmp" "${HISTFILE:+${HISTFILE}_dirs}" "$PWD" &&
      print -rn -- "${(%):-%~}" >| "$tmp/here.name" &&
      print -r -- "cd $tmp || exit 1
if [ -e on ]; then
  rm -f on
  printf 'reload(cat $tmp/all)+change-prompt:%s' \"\$(cat prompt)\"
else
  printf %s \"\$FZF_PROMPT\" > prompt && : > on
  printf 'reload(cat $tmp/here)+change-prompt:%s %s' \"\$(cat here.name)\" \"\$FZF_PROMPT\"
fi" >| "$tmp/toggle"
    then
      selected="$(FZF_DEFAULT_OPTS=$(__fzf_defaults "" "$opts ${FZF_CTRL_R_OPTS-} --header='CTRL-Y: copy to clipboard, CTRL-O: only this folder' --query=${(qqq)LBUFFER} --read0") \
        FZF_DEFAULT_OPTS_FILE='' $(__fzfcmd) < "$tmp/all")"
      ret=$?
    else
      ret=-1
    fi
    } always { _zfh_tmp_clean }
    if (( ret == -1 )); then
      zle fzf-history-widget
      return
    fi
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
(( _zfh_aliases )) && setopt aliases
unset _zfh_aliases
