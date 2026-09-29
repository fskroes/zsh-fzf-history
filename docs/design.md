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
| "What did I run in this folder" | no | no | yes |
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
4. All of it inside `if (( $+commands[fzf] ))`, so a Mac without fzf starts normally.

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

Cost with 50,000 commands (Apple silicon, zsh 5.9, fzf 0.74.4), until the list is ready:
this widget 0.42 s, fzf's own widget 0.05 s (it streams to fzf and does not sort).
For a history of a few thousand commands the difference is not visible.

Ctrl-Y removes `<event><tab><time> │ ` from the start and `<tab><spaces>│ ` after each newline.
The pattern has no `{16}`: fzf would read `{16}` in a bind as a field placeholder. The file sets `FZF_CTRL_R_OPTS` each
time it loads, so an exported value from an older version (with the old one-field Ctrl-Y
pattern) does not stay in new shells. The test starts zsh with such a stale value.

If perl, `zsh/parameter` or fzf's helper functions are missing, the widget falls back to fzf's
own widget (event order, no time).

With `share_history` on, zsh imports lines from other tabs only when this tab next writes history
(after you run a command). That is zsh's own timing, and this file does not change it.

## How the test works

`tests/verify.py` starts `zsh -i` in a pseudo-terminal with its own `ZDOTDIR`, a made-up
`$HISTFILE` and a fake `pbcopy` on `PATH`. It sends real key codes (Ctrl-R, text, Enter, Ctrl-Y)
and reads the prompt buffer through a helper widget on Ctrl-X Ctrl-D. To act as "another tab", it
appends a line to the history file while the shell is open.

The pseudo-terminal is 40 rows by 120 columns: in a 0x0 terminal fzf draws no list lines, and
the check "Ctrl-R list shows the date and time of each command" reads the screen.

Control runs:

- A `fzf.zsh` that has only `source <(fzf --zsh)`: 9 of the 27 checks fail (the guard, Ctrl-Y,
  the other-tab checks and the time-order checks).
- The version before time sorting: 3 of the 27 checks fail ("Ctrl-R lists newest first by time,
  also while you type", "Ctrl-R list shows the date and time of each command",
  "old command from other tab is not listed as newest").
- This version without `export TZ=`: 1 of the 27 checks fails ("Ctrl-R list with 20,000
  commands shows in less than 2 s": 4.2 s).
- This version with `--nth=1..` (the time is searched too): 1 of the 27 checks fails
  ("Ctrl-R search looks only at the command, not the time").

Minimum fzf version: `fzf --zsh` needs 0.48, but marking more than one command in the zsh Ctrl-R list needs
0.68 (fzf CHANGELOG 0.68.0: "zsh: Handle multi-line history selection (#4595)"). The test
"Shift-Tab / Tab in the list marks more than one command" checks this.
