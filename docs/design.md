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
2. A wrapper widget on Ctrl-R: `[[ -o share_history ]] || fc -RI`, then fzf's widget.
   `fc -RI` reads `$HISTFILE` and adds only the events that are not already in zsh's internal
   history list (zsh manual, `zshbuiltins`, `fc`: "If the -I option is added to -R, only those
   events that are not already contained within the internal history list are added.").
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

With `share_history` on, zsh imports lines from other tabs only when this tab next writes history
(after you run a command). That is zsh's own timing, and this file does not change it.

## How the test works

`tests/verify.py` starts `zsh -i` in a pseudo-terminal with its own `ZDOTDIR`, a made-up
`$HISTFILE` and a fake `pbcopy` on `PATH`. It sends real key codes (Ctrl-R, text, Enter, Ctrl-Y)
and reads the prompt buffer through a helper widget on Ctrl-X Ctrl-D. To act as "another tab", it
appends a line to the history file while the shell is open.

Control run: with a `fzf.zsh` that has only `source <(fzf --zsh)`, 10 of the 21 checks fail
(the guard, Ctrl-Y and the other-tab checks).

Minimum fzf version: `fzf --zsh` needs 0.48, but marking more than one command in the zsh Ctrl-R list needs
0.68 (fzf CHANGELOG 0.68.0: "zsh: Handle multi-line history selection (#4595)"). The test
"Shift-Tab / Tab in the list marks more than one command" checks this.
