if [[ -o aliases ]]; then _zfh_aliases=1; setopt no_aliases; else _zfh_aliases=0; fi
if (( ${+commands[fzf]} )); then
  export FZF_CTRL_R_OPTS="
    --bind 'ctrl-y:execute-silent(printf %s {} | perl -0pe \"s/^\d+\t(?:(?:\d\d\d\d-\d\d-\d\d \d\d:\d\d|                ) │ )?//; s/\n\t(?:                 │ )?/\n/g\" | pbcopy)+abort'
    --color header:italic
    --header 'CTRL-Y: copy to clipboard'"
  source <(fzf --zsh)

  if zmodload -F zsh/parameter p:history 2>/dev/null &&
     zmodload -F zsh/datetime p:EPOCHSECONDS 2>/dev/null &&
     zmodload -F zsh/system b:sysopen b:sysread b:sysseek 2>/dev/null &&
     zmodload -F zsh/stat b:zstat 2>/dev/null; then
    typeset -ga _zfh_dirs_wait _zfh_dirs_mark
    _zfh_dirs_stat() {
      local -A st
      if zstat -H st -- "$HISTFILE" 2>/dev/null; then
        reply=("$HISTFILE" "$st[inode]" "$st[size]")
      else
        reply=("$HISTFILE" - 0)
      fi
    }
    _zfh_dirs_saved() {
      emulate -L zsh -o no_multibyte -o extended_glob
      local -a reply mark=("${(@)argv[2,-1]}")
      (( $#mark == 3 )) && [[ $mark[1] == "$HISTFILE" ]] || return 1
      _zfh_dirs_stat
      [[ $mark[2] == - || $mark[2] == $reply[2] ]] || return 1
      local -i b n=$(( reply[3] - mark[3] ))
      (( n > 0 && n <= 4194304 )) || return 1
      local e=${1//$'\n'/\\$'\n'} buf fd x=
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

  typeset -g _zfh_tmp
  _zfh_tmp_clean() {
    emulate -L zsh
    [[ -n $_zfh_tmp ]] || return 0
    command rm -f -- "$_zfh_tmp/all" "$_zfh_tmp/here" "$_zfh_tmp/all.tmp" "$_zfh_tmp/here.tmp" "$_zfh_tmp/here.name" "$_zfh_tmp/toggle" "$_zfh_tmp/prompt" "$_zfh_tmp/on"
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
    {
    local opts="--delimiter='\t| │ ' --nth=3.. --no-sort --scheme=history
      --bind=ctrl-r:toggle-sort,alt-r:toggle-raw --wrap-sign '\t↳ ' --highlight-line --multi
      --bind='ctrl-o:transform:sh $tmp/toggle'"
    if print -rn -- "${(%):-%~}" >| "$tmp/here.name" &&
      print -r -- "cd $tmp || exit 1
[ -e all ] && [ -e here ] || exit 0
if [ -e on ]; then
  rm -f on
  printf 'reload(cat $tmp/all)+change-prompt:%s' \"\$(cat prompt)\"
else
  printf %s \"\$FZF_PROMPT\" > prompt && : > on
  printf 'reload(cat $tmp/here)+change-prompt:%s %s' \"\$(cat here.name)\" \"\$FZF_PROMPT\"
fi" >| "$tmp/toggle"
    then
      selected="$(printf '%s\t%s\000' "${(kv)history[@]}" |
        command perl -e '
          use POSIX "strftime";
          my ($fcf, $out, $dirs, $here) = @ARGV;
          my (%t, @e, %seen, %last, %txt);
          my $pad = " " x 16;
          my $sub = $here eq "/" ? "/" : "$here/";
          open my $fc, "<", $fcf or exit 1;
          while (<$fc>) { $t{$1} = $2 if /^\s*(\d+)\*?\s+(\d+)\s/ }
          {
            local $/ = "\0";
            while (<STDIN>) { chomp; push @e, [$1, $t{$1} // 0, $2] if /^(\d+)\t(.*)\z/s }
            if (open my $d, "<", $dirs) {
              while (<$d>) {
                chomp;
                my ($tm, $p, $c) = split /\t/, $_, 3;
                next unless defined $c && $tm =~ /^\d+\z/ && ($p eq $here || index($p, $sub) == 0);
                $last{$c} = $tm if $tm > ($last{$c} // -1);
              }
            }
          }
          my $by_time = sub { $b->[1] <=> $a->[1] || $b->[0] <=> $a->[0] };
          my @all = grep { !$seen{$_->[2]}++ } sort $by_time @e;
          my @in = sort $by_time map { [$_->[0], $last{$_->[2]}, $_->[2]] } grep { exists $last{$_->[2]} } @all;
          for (["here", \@in], ["all", \@all]) {
            my ($n, $l) = @$_;
            $txt{$n} = join "", map {
              (my $c = $_->[2]) =~ s/\n/\n\t$pad │ /g;
              "$_->[0]\t" . ($_->[1] ? strftime("%Y-%m-%d %H:%M", localtime $_->[1]) : $pad) . " │ $c\0";
            } @$l;
            open my $o, ">", "$out/$n.tmp" or exit 1;
            print $o $txt{$n};
            close $o && rename("$out/$n.tmp", "$out/$n") or exit 1;
          }
          print $txt{all};
        ' <(export TZ=; fc -l -t '%s' 1 2> /dev/null) "$tmp" "${HISTFILE:+${HISTFILE}_dirs}" "$PWD" |
        FZF_DEFAULT_OPTS=$(__fzf_defaults "" "$opts ${FZF_CTRL_R_OPTS-} --header='CTRL-Y: copy to clipboard, CTRL-O: only this folder' --query=${(qqq)LBUFFER} --read0") \
        FZF_DEFAULT_OPTS_FILE='' $(__fzfcmd))"
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
