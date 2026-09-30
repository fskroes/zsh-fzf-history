# Design notes

Why this file exists, what it does, and what I compared before I chose it.

## The problem

I wanted a fuzzy Ctrl-R list for zsh (oh-my-zsh, zsh-autosuggestions, zsh-syntax-highlighting)
in the [Otty](https://otty.sh) terminal on macOS.

Otty loads its shell integration at the **first prompt**, after `~/.zshrc`. When its history scope
is per-pane (`OTTY_HISTORY_SCOPE=per-pane`), it runs:

```sh
unsetopt share_history
setopt inc_append_history
```

(Otty 1.5.1: `Otty.app/Contents/Resources/shell-integration/otty-integration.zsh`, lines 351-372.)

So each tab writes every command to `$HISTFILE` at once, but it never reads what other tabs write.
fzf's zsh Ctrl-R widget reads zsh's `$history` array in memory (fzf `shell/key-bindings.zsh`,
`fzf-history-widget`). Result: in a tab that is already open, Ctrl-R does not show a command
that you just ran in another tab.

The same happens in any terminal when you turn `share_history` off yourself.

## Options that I compared

| | A: zsh built-in | B: fzf, tuned (this repo) | C: Atuin for Ctrl-R + fzf |
|---|---|---|---|
| Fuzzy list for Ctrl-R | no | yes | yes |
| Sees other tabs at once | no | yes (`fc -RI` wrapper) | yes (SQLite database) |
| "What did I run in this folder" | no | yes, Ctrl-O (added later, see "Only this folder") | yes |
| Exit code, duration | no | no | yes |
| New programs | 0 | 1 | 2 |
| Network | none | none | none, if `update_check = false` and no `atuin login` |
| Undo | n/a | remove 1 line | remove lines + Atuin database |

I chose B: one program, no database, easy to remove. B then C is an easy upgrade later:
Atuin takes Ctrl-R, fzf keeps Ctrl-T and Alt-C.

I also rejected: mcfly (asks for co-maintainers; Atuin does the same), separate zsh fzf history
plugins (fzf's own widget now has multi-line entries, dedup and multi-select), and
zsh-history-substring-search (overlaps with oh-my-zsh's Up-arrow prefix search).

## What the file does

1. `source <(fzf --zsh)`: fzf's own Ctrl-R, Ctrl-T, Alt-C and `**` completion.
2. Its own Ctrl-R widget. It first runs `[[ -o share_history ]] || fc -RI`.
   `fc -RI` reads `$HISTFILE` and adds only the events that are not already in zsh's internal
   history list (zsh manual, `zshbuiltins`, `fc`: "If the -I option is added to -R, only those
   events that are not already contained within the internal history list are added.").
   Then it does what fzf's `fzf-history-widget` does, with the same fzf options, but it sorts
   the list by time (see "Sorted by time" below).
3. `FZF_CTRL_R_OPTS` with a Ctrl-Y binding that copies the selected command.
4. A `preexec` hook that saves the folder of each command, for Ctrl-O in the Ctrl-R list
   (see "Only this folder" below).
5. All of it inside `if (( $+commands[fzf] ))`, so a Mac without fzf starts normally.

## Problems that I found (and the tests that catch them)

| Problem | Fix | Test in `tests/verify.py` |
|---|---|---|
| The fzf README's Ctrl-Y example uses `echo -n {2..}`. In zsh, `echo` changes `\n` and `\t` in a command into real newlines and tabs. | Use `printf %s`. | "Ctrl-Y keeps literal backslash escapes" |
| fzf adds a tab after each newline of a multi-line entry, for its display. | `perl` removes `\n\t` back to `\n`. | "Ctrl-Y copies multi-line command exactly" |
| fzf trims the spaces at the ends of `{2..}`. zsh keeps them in history. | Copy `{}` (the whole line); `perl` removes the `<number><tab>` prefix. | "Ctrl-Y keeps trailing spaces" |
| `fc -RI` with `share_history` on adds duplicate entries. | Run `fc -RI` only when `share_history` is off. | "share_history on: no duplicate history entries" |
| An unguarded `source <(fzf --zsh)` prints `command not found` on a Mac without fzf. | `if (( $+commands[fzf] ))` | "without fzf: no startup errors" |
| fzf's Ctrl-R sorts by match when you type, and lists by event number. `fc -RI` gives old commands from other tabs new event numbers. | Own widget: sort by time, `--no-sort`. | "Ctrl-R lists newest first by time, also while you type", "old command from other tab is not listed as newest" |
| The time is in the line, so a query like `2026-09-29` would match every command of that day. | `--delimiter='\t\| │ ' --nth=3..`: search only the command. | "Ctrl-R search looks only at the command, not the time" |
| On macOS, `fc -l -t` in a subshell is very slow (11 s for 50,000 commands): `localtime()` reads the time zone file on each call. | `export TZ=` in the subshell. | "Ctrl-R list with 20,000 commands shows in less than 2 s" |
| zsh history has no folder, so a Ctrl-R list for "this folder" has nothing to filter on. | `preexec` saves `<time>\t<folder>\t<command>\0` to `${HISTFILE}_dirs`. | "Ctrl-O: a command from a subfolder is listed", "Ctrl-O: a command from another folder (same name prefix) is not listed" |
| A line that zsh keeps out of `$HISTFILE` (leading space, also from an alias; `HISTORY_IGNORE`; a `zshaddhistory` hook that returns 1 or 2; no `HISTFILE`; `SAVEHIST=0`) looks normal in `$history` in `preexec`. Saving it would save secrets. | Save a line only if zsh wrote it to `$HISTFILE` for this command: read only the bytes added since the prompt. | "folder file: no line with a leading space", "... of an alias with a leading space", "... that matches HISTORY_IGNORE", "... that a zshaddhistory hook drops (return 1 or 2)", "... nothing is saved without $HISTFILE", "... nothing is saved with SAVEHIST=0", "... a line that a hook drops is not saved, also when the same text is in $HISTFILE", "... HISTORY_IGNORE ..., also when the same text is in $HISTFILE" |
| zsh writes a newline as `\<newline>` and the bytes 0x83 to 0xa2 (in many UTF-8 characters, for example `↳`) as 0x83 + byte XOR 32 in `$HISTFILE`. A plain text compare does not find those lines. | Change the text the same way before the compare. | "folder file: commands with UTF-8 and with a newline are saved" |
| zsh writes a space after a `\` at the end of a command (also when spaces follow the `\`), so that the line does not continue. Without `extended_history` it writes `\:` for a command that starts with `:` (zsh 5.9, `Src/hist.c`, `savehistfile`). | Change the text the same way before the compare. | "folder file: a command that ends in a backslash is saved", "... without extended_history, a command that starts with ':' or ends in '\' + spaces is saved" |
| `inc_append_history_time` writes a line after the command ends, not before `preexec`. | The line waits in `_zfh_dirs_wait`; `precmd` saves it (zsh writes the line before `precmd`) with the same check. | "Ctrl-O with inc_append_history_time: ...", "... is saved after it ran", "... other tabs write 4 KB during the command: still saved", "... inc_append_history_time: no leading-space, HISTORY_IGNORE or hook-dropped line" |
| zsh expands aliases when it reads a function, so an alias such as `rm=trash` made before this file loads would change the cleanup (`trash -f` fails, and the lists with all of `$history` stay). A shell function such as `rm() { trash "$@" }` does the same at run time, because zsh runs a function before a program with the same name. | `setopt no_aliases` before the `if` block of the file (zsh reads that block as one unit), and `aliases` on again after it. The functions call `command rm`, `command rmdir`, `command mktemp` and `command perl`. | the minimal test config makes functions and aliases for `rm`, `rmdir`, `mktemp` and `perl` before it loads the file; the temp folder and Ctrl-O checks fail without the fix |
| With `share_history` or `inc_append_history`, a line that is not in the file at `preexec` is not written for this command. A waiting line would only make the time window longer: the dropped command itself (or another tab) could write the same text while it runs. | Wait only when `inc_append_history_time` is the only one of the three options that is on. | "folder file: a dropped line is not saved when the same text is written while it runs", "... share_history: a dropped line ..." |
| fzf-tmux gives fzf only its options and `TERM`, not other environment variables. | The temp path is written into the options (only `[[:alnum:]/._-]`, else `/tmp`). | "FZF_TMUX=1: Ctrl-O lists only this folder and removes its temp folder" (runs in its own `tmux -L` server) |
| A folder name can hold `)`, `+`, `$(...)` and backticks. In `change-prompt(...)` a `)` in the name would end the action, and the rest would run as fzf actions. | The toggle script prints the name with `printf %s` after `change-prompt:` (the colon form takes the rest of the string as the prompt). | "Ctrl-O: a folder name with fzf actions and $(...) is only text" |
| `${(D)PWD}` quotes the path after `~` (the zsh manual: "The remainder of the path ... is then quoted"), so the prompt would show `~/My\ Project`. | `${(%):-%~}`: prompt expansion, the same `~` form, not quoted (also with `prompt_subst` and a `%` in the name). | "Ctrl-O: a folder name with fzf actions and $(...) is only text" (checks the prompt text) |
| fzf's own widget (the fallback when perl is missing or `mktemp` fails) also reads `FZF_CTRL_R_OPTS`, but has no Ctrl-O. | `FZF_CTRL_R_OPTS` names only Ctrl-Y in the header; the widget adds a header with Ctrl-O after it. | "header names Ctrl-O only when Ctrl-O works" |
| The temp lists hold all of `$history`. A tab that closes while the list is open would leave them. | `zshexit` hook deletes them (it runs also on SIGHUP while the widget waits). | "tab closed while the Ctrl-R list is open: temp folder removed" |
| A SIGINT while perl makes the lists (for example Ctrl-C before fzf has the terminal) stops the widget before its last line, so the cleanup there does not run. A Ctrl-C after fzf starts goes to fzf as a key: fzf ends, and the widget ends normally when perl is done. | The widget body is in `{ ... } always { _zfh_tmp_clean }`. | "SIGINT while perl makes the lists: temp folder removed" (the test sends SIGINT to the shell and its children), "Ctrl-C while the Ctrl-R list loads: temp folder removed" |
| `setopt nounset` or `ksh_arrays` in the user's shell. With `ksh_arrays`, `$+commands[fzf]` without braces is an error ("bad output format specification"). | `emulate -L zsh` in the hooks; the widget sets `no_nounset no_ksharrays` as its first line (before its `$+commands[perl]` check); `${+commands[fzf]}` with braces when the file loads. | "folder file: works with setopt nounset", "... ksh_arrays", "Ctrl-R and Ctrl-O work with setopt ksh_arrays"; the minimal test config loads the file with `ksh_arrays nounset` on |
| A `precmd` hook that fails (for example a prompt theme that reads an unset variable with `nounset`) makes zsh skip the hooks after it. Then the mark stayed from an older prompt, and every line written since then counted as new: a line that a hook drops in one folder was saved if the same text was written earlier in the session. | `preexec` clears the mark (it is good for one command; a waiting line keeps its own copy), so with no new mark nothing is saved. Our `precmd` hook goes first in `precmd_functions`. | "folder file: when a precmd hook before ours fails, an old mark does not count", "... loading the file puts its precmd hook first" |
| `/work/app` is a prefix of `/work/app-old`. | Match the folder itself or `folder/` + more. | "Ctrl-O: a command from another folder (same name prefix) is not listed" |
| The folder file shows where you work and what you ran. | Create it with `umask 077` (mode 600), as zsh does for `$HISTFILE`. | "folder file can be read only by you (600)" |
| An exported `FZF_CTRL_R_OPTS` from an older version would keep the old Ctrl-Y pattern. | Set `FZF_CTRL_R_OPTS` each time the file loads. | the Ctrl-Y checks (the test starts zsh with a stale value) |

## Sorted by time

fzf's widget gives fzf `$history` in event order and lets fzf sort by match score when you type.
That order is not time order:

- `fc -RI` gives commands from other tabs event numbers after the commands of this tab, also
  when they ran earlier.
- When you type, the best match comes first, also when it is years old.

The widget in this file makes one line per command, `<event>\t<YYYY-MM-DD HH:MM> │ <command>`:

1. `fc -l -t %s 1` gives the time of each event as a Unix time. `fc -l` prints one line per
   event (a newline in a command shows as `\n`), so the event number and the time are easy to
   read. The command text comes from `$history`, which has the exact text.
2. perl sorts by time, newest first. When two events have the same time, the higher event
   number comes first, so history without timestamps keeps its event order.
3. perl keeps only the newest copy of each command (fzf's widget does the same by event number).
   After each newline of a multi-line command it adds `<tab><16 spaces> │ `, so the next line
   starts under the command.
   After the time comes ` │ `, not a tab: the time ends on a tab stop, so a tab would add 8
   empty columns. The command starts at column 27 (with a tab: 32). A command without a time
   gets 16 spaces in place of the time.
4. fzf gets `--no-sort` (Ctrl-R in the list sorts by match), `--delimiter='\t| │ ' --nth=3..` (search only the
   command, not the time) and fzf's own options (`--scheme=history`, `--multi`, `--wrap-sign`, ...).
5. On Enter, the event number at the start of each selected line gives the command from `$history`,
   the same as fzf's widget.

`fc -l` must run in a subshell (`<(export TZ=; fc -l -t '%s' 1)`). In the widget itself zsh
refuses it ("no interactive history within ZLE"). The subshell is a fork without exec. On macOS,
`localtime()` in such a child reads the time zone file again for each call: 50,000 commands
took 11 s. With `TZ` set to an empty value in the child, this does not occur. `TZ=UTC` or a zone
name is still slow, and `TZ= fc ...` has no effect because `fc` is a builtin, so the file uses
`export TZ=`. The `%s` output is a Unix time, so `TZ` does not change it (checked: the same
output as in the main shell, also with `TZ=America/New_York` and `TZ=Asia/Kolkata`). perl
formats the time in the time zone of your shell.

Cost with 50,000 commands (Apple silicon, zsh 5.9, fzf 0.74.4, load 5 to 7), from Ctrl-R until
the newest line shows, best of 3:

| Widget | Time |
|---|---|
| fzf's own widget | 0.59 s |
| this widget before Ctrl-O | 0.57 s |
| this widget, empty folder file | 0.57 s |
| this widget, 50,000 folder lines, all in `$PWD` | 0.75 s |

fzf starts in the same pipeline as perl, so its start-up (about 0.5 s here) and the sort run at
the same time. A first Ctrl-O version started fzf only after perl had written its files
(`fzf < all`): 1.04 s with an empty folder file. With a full folder file, perl alone needs
0.51 s instead of 0.26 s; most of the extra time is the time format (`strftime`) for the second
list.

Ctrl-Y removes `<event><tab><time> │ ` from the start and `<tab><16 spaces> │ ` after each
newline. In fzf's own widget (the fallback) a line is `<event><tab><command>` and a newline gets
only a tab, so the time part of the pattern is optional. The time part matches only this
widget's exact forms (`\d\d\d\d-\d\d-\d\d \d\d:\d\d` or 16 spaces), so a command with ` │ ` in it
keeps its text in both formats. The pattern has no `{n}` count: fzf would read `{16}` or `{2}`
in a bind as a field placeholder, so it uses `\d\d` and 16 real spaces. The file sets `FZF_CTRL_R_OPTS` each
time it loads, so an exported value from an older version (with the old one-field Ctrl-Y
pattern) does not stay in new shells. The test starts zsh with such a stale value.

If perl, `zsh/parameter` or fzf's helper functions are missing, the widget falls back to fzf's
own widget (event order, no time).

With `share_history` on, zsh imports lines from other tabs only when this tab next writes history
(after you run a command). That is zsh's own timing, and this file does not change it.

## Only this folder

Ctrl-O in the Ctrl-R list shows only the commands that ran in `$PWD` or a subfolder.
zsh does not save the folder of a command (not in `$HISTFILE`, not with `extended_history`), so
the file saves it itself. I compared:

| | Own folder file (chosen) | Atuin | A folder in the history line |
|---|---|---|---|
| New programs | 0 | 1 (+ SQLite database) | 0 |
| Old commands get a folder | no | no (import has no folder) | no |
| Change to `$HISTFILE` | none | none | yes: other tools can no longer read it |
| Keeps Ctrl-Y, time sort, other tabs | yes | no, Atuin has its own list | yes |

**Saving.** `preexec` or `precmd` appends `<Unix time>\t<$PWD>\t<command>\0` to
`${HISTFILE}_dirs`, but only for a line that zsh wrote to `$HISTFILE` for this command.

- The command text comes from `$history[$HISTCMD]`, not from the typed line. With
  `hist_reduce_blanks` the two are different, and the Ctrl-R list uses the `$history` text.
- NUL at the end, because a command can have newlines and tabs. The command is the last field,
  so a tab in it is no problem. A folder with a tab in its name is not saved.
- `>>|` appends also with `noclobber`. `umask 077` in a subshell, only when the file is new.
- In `preexec`, a line that zsh will not save looks the same as a kept line: it is in
  `$history` as the current event. A line with a leading space or one that a `zshaddhistory`
  hook drops with 1 stays there until the next command, which then gets its event number; a
  `HISTORY_IGNORE` match or a line that a hook drops with 2 stays in `$history` (checked with
  zsh 5.9).
  Checking each reason by hand missed cases (an alias with a leading space, a hook that returns 2,
  `unset HISTFILE`). So there is one rule: **save a line only if zsh wrote it to `$HISTFILE`
  for this command.**
- **Only new bytes count.** At each prompt, `precmd` saves the file name, inode and size of
  `$HISTFILE` in `_zfh_dirs_mark` (`zstat` from `zsh/stat`, no fork). `_zfh_dirs_saved` reads
  only the bytes after that size (`sysopen`, `sysseek`, `sysread` from `zsh/system`). An older
  line with the same text does not count. A first version read the last 4 KB of the file; then
  `git status` in a folder that a `zshaddhistory` hook hides was saved, because `git status`
  from another folder was in those 4 KB. The line is not saved if the inode changed (zsh
  replaced the file), the file became smaller (zsh rewrote it), `$HISTFILE` names another file
  (`fc -p`), or more than 4 MB was added since the prompt. `preexec` clears the mark, so a mark
  is good for one command only; a line that waits for `precmd` keeps its own copy.
- It looks for a full line: `\n<command>\n`, or `\n: <digits>:<digits>;<command>\n` with
  `extended_history`, or `\n\<command>\n` without it when the command starts with `:`. Before
  the compare it writes the command as zsh does in the file: a
  newline as `\<newline>`, and a byte 0x83 to 0xa2 as 0x83 + (byte XOR 32). 0x83 goes first,
  and no replacement makes a byte in that range again, so no byte is changed twice. 32
  replacements take 4 ms for a 10 KB command; an ASCII command needs none.
- When zsh writes the line (checked with zsh 5.9: the line is in the file before `precmd`):

  | Option | Line in `$HISTFILE` at `preexec` | This file saves the folder |
  |---|---|---|
  | `share_history`, `inc_append_history` | yes | in `preexec`, at once |
  | `inc_append_history_time` (and not one of the two above) | no, when the command ends | in `precmd` (the line waits in `_zfh_dirs_wait`) |
  | none | no, at shell exit | never (`preexec` does not find it and does not wait for it) |

- Before the compare, a `\` at the end of the command (also with spaces after it) gets one
  more space, because zsh writes it like that (else the next line would continue the command).
- Limits: a line that zsh did not write, but whose same text another writer (another tab, or
  the command itself) adds to `$HISTFILE` in the time window, is saved. The window starts at the
  prompt. With `share_history` or `inc_append_history` it ends when you press Enter; with only
  `inc_append_history_time` it ends when the command is done. With `hist_ignore_dups`, a
  command that is the same as the one before is not written again, so it gets no new folder
  line (none at all when it is the first time in this folder). With `share_history` this also
  happens when another tab wrote the same command just before: zsh reads that line first, and
  then yours is a duplicate ("share_history + hist_ignore_dups, ...: no folder"). zsh sets the
  new time only in this tab's memory (the file keeps the old time), so in this tab the full list
  can show a newer time than the Ctrl-O list for that command. When a `precmd` hook that runs
  before ours fails, zsh skips ours, so there is no mark and the next command is not saved. The
  file puts its hook first when it loads, but a hook that is added in front of it later can
  still do this.
- Each hook function starts with `emulate -L zsh`, so options in your `~/.zshrc` (`nounset`,
  `ksh_arrays`, `sh_word_split`, ...) do not change it. The check reads only the history
  options (`inc_append_history_time` and the two others), and `emulate` does not reset those.

**Listing.** perl reads the folder file and keeps, per command text, the
newest time in `$PWD` or below (`$p eq $here || index($p, "$here/") == 0`). It writes two files to
a temp folder (`mktemp -d`): `all`, the list from "Sorted by time", and `here`: the lines of `all`
whose command is in the folder file, with the time in this folder, sorted by that time. It
writes each file as `<name>.tmp` and renames it when it is complete. Then it sends `all` to fzf,
which runs in the same pipeline (so fzf starts at once; see the cost table in "Sorted by
time"). So:

- A command that is no longer in `$history` (deleted, or older than `HISTSIZE`) is not in `here`.
  Enter always gets the text from `$history`, the same as in `all`.
- Commands from other tabs are in `here` when their text is in `$history`: at once with
  `share_history` off (`fc -RI` reads it), and with `share_history` on after this tab runs a
  command (zsh's own timing, the same as the full list).

**The key.** fzf starts with `all`. `ctrl-o:transform:sh <tmp>/toggle` runs a small
script. If `all` or `here` does not exist yet (perl is not done, and the list is still empty),
it prints nothing, so Ctrl-O does nothing. When the first line shows, both files are complete.
With no `on` file, it saves `$FZF_PROMPT`, creates `on` and prints
`reload(cat <tmp>/here)+change-prompt:<~folder> <prompt>`; with `on`, it goes back.
The temp path is in the options and the script as it is. An environment variable would be
simpler, but `fzf-tmux` (`FZF_TMUX=1`) gives fzf only its options, `TERM` and the
`FZF_DEFAULT_*` variables (the test "FZF_TMUX=1: ..." runs this in tmux). So the path may only have `[[:alnum:]/._-]`; if `$TMPDIR` has other
characters, the widget uses `/tmp`. `mktemp -d` makes the folder with mode 700.
Ctrl-O is free in fzf (Ctrl-D, Ctrl-F and Ctrl-G have jobs there). The header line
`CTRL-O: only this folder` comes from the widget's own options, not from `FZF_CTRL_R_OPTS`:
fzf's own widget, the fallback, reads that variable too and has no Ctrl-O.

**Cleanup.** The lists hold all of `$history`. `_zfh_tmp_clean` deletes the known files and
the folder (`rm -f` on each name, then `rmdir`: no `rm -r` on a path from a variable) when fzf
exits. The widget body after `mktemp` is in `{ ... } always { _zfh_tmp_clean }`, so a SIGINT
while perl or fzf runs also cleans up (a Ctrl-C key after fzf starts goes to fzf, and the
widget ends normally). A `zshexit` hook runs it too: when the tab closes while the list is
open, zsh gets SIGHUP and runs `zshexit` (checked with zsh 5.9).

If `mktemp` fails, or the widget cannot write `here.name` or `toggle`, it falls back to fzf's
own widget, the same as when perl is missing. If perl fails, the list is empty (the same as in
the version before Ctrl-O); Esc closes it.

Cost: the folder file is read at each Ctrl-R (see the cost table in "Sorted by time"). The check at each
command reads only the bytes that were added since the prompt, so it does not get slower as
`$HISTFILE` grows.

## How the test works

`tests/verify.py` starts `zsh -i` in a pseudo-terminal with its own `ZDOTDIR`, a made-up
`$HISTFILE` and a fake `pbcopy` on `PATH`. It sends real key codes (Ctrl-R, text, Enter, Ctrl-Y)
and reads the prompt buffer through a helper widget on Ctrl-X Ctrl-D. To act as "another tab", it
appends a line to the history file while the shell is open.

The pseudo-terminal is 40 rows by 120 columns: in a 0x0 terminal fzf draws no list lines, and
the check "Ctrl-R list shows the date and time of each command" reads the screen.

Control runs. Each one breaks one part of `fzf.zsh`, and at least one check must fail. The
first four are from before Ctrl-O (27 checks then); the rest use the 66 checks of now.

- A `fzf.zsh` that has only `source <(fzf --zsh)`: 9 of the 27 checks fail (the guard, Ctrl-Y,
  the other-tab checks and the time-order checks).
- The version before time sorting: 3 of the 27 checks fail ("Ctrl-R lists newest first by time,
  also while you type", "Ctrl-R list shows the date and time of each command",
  "old command from other tab is not listed as newest").
- This version without `export TZ=`: 1 of the 27 checks fails ("Ctrl-R list with 20,000
  commands shows in less than 2 s": 4.2 s).
- This version with `--nth=1..` (the time is searched too): 1 of the 27 checks fails
  ("Ctrl-R search looks only at the command, not the time").

| Control (what is removed) | Checks that fail (of 66) |
|---|---|
| The `$HISTFILE` check (`_zfh_dirs_saved` always true) | 6: leading space, alias, `HISTORY_IGNORE`, hook, and the two "same text is in $HISTFILE" checks |
| The mark (read the whole file, not only the new bytes) | 2: the two "same text is in $HISTFILE" checks |
| Read at most 4 KB after the mark | 1: "other tabs write 4 KB during the command" |
| The waiting line (`inc_append_history_time`) | 3: the three `inc_append_history_time` checks |
| The UTF-8 byte change (0x83 to 0xa2) | 2: "commands with UTF-8 and with a newline are saved", "Ctrl-O: a command with UTF-8 is listed" |
| The `\<newline>` change | 1: "commands with UTF-8 and with a newline are saved" |
| `emulate -L zsh` in the hooks | 1: "works with setopt ksh_arrays" |
| The `/` after the folder (`/work/app` matches `/work/app-old`) | 2: "another folder (same name prefix)", "sorted by the last time in this folder" |
| `umask 077` | 1: "folder file can be read only by you (600)" |
| The cleanup after fzf | 2: both temp folder checks |
| The `zshexit` cleanup | 1: "tab closed while the Ctrl-R list is open: temp folder removed" |

A full run takes about 5 minutes (each check waits for real key presses).

Minimum fzf version: `fzf --zsh` needs 0.48, but marking more than one command in the zsh Ctrl-R list needs
0.68 (fzf CHANGELOG 0.68.0: "zsh: Handle multi-line history selection (#4595)"). The test
"Shift-Tab / Tab in the list marks more than one command" checks this.
