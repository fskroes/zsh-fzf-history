#!/usr/bin/env python3
"""Test fzf.zsh by driving a real interactive zsh in a pseudo-terminal.

Usage:
  python3 tests/verify.py                 # minimal zsh config that sources ../fzf.zsh
  python3 tests/verify.py --zshrc FILE    # your full config (FILE must source fzf.zsh)

Safe: uses a made-up history file, a fake pbcopy and a temp dir, so your real
history and clipboard are not touched. Slow Mac? Set ZFH_TEST_SLOW=2.
"""
import os, pty, select, shutil, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
FZF_ZSH = os.path.join(os.path.dirname(HERE), "fzf.zsh")
USER_ZSHRC = None
if len(sys.argv) == 3 and sys.argv[1] == "--zshrc":
    USER_ZSHRC = os.path.abspath(os.path.expanduser(sys.argv[2]))
elif len(sys.argv) != 1:
    sys.exit(__doc__)
SLOW = float(os.environ.get("ZFH_TEST_SLOW", "1"))
FZF = shutil.which("fzf")
if not FZF:
    sys.exit("fzf is not installed. Run: brew install fzf")

W = tempfile.mkdtemp(prefix="zsh-fzf-history-test.")
HIST, BUF, CLIP = f"{W}/hist", f"{W}/buf.out", f"{W}/clip.out"
COMP_DIR = f"{W}/comp/unique-dir-XYZ"


def setup(no_fzf=False):
    for d in ("zdot", "shim", "brewbin"):
        shutil.rmtree(f"{W}/{d}", ignore_errors=True)
    for f in (HIST, BUF, CLIP, f"{W}/ready", f"{W}/bind.out", f"{W}/dup.out", f"{W}/has.out"):
        os.path.exists(f) and os.remove(f)
    os.makedirs(f"{W}/zdot"); os.makedirs(f"{W}/shim"); os.makedirs(COMP_DIR, exist_ok=True)
    t = int(time.time()) - 100
    with open(HIST, "w") as f:
        f.write(f": {t}:0;echo line1-ML \\\necho line2-ML\n")  # one multi-line entry
        f.write(f": {t+1}:0;touch {W}/EXECUTED-marker\n")       # must never run
        f.write(f": {t+2}:0;printf 'BS-test a\\tb\\n'\n")        # literal backslashes
        f.write(f": {t+3}:0;echo TRAIL-test   \n")               # trailing spaces
        f.write(f": {t+4}:0;echo MULTI-a\n: {t+5}:0;echo MULTI-b\n")  # for multi-select
    with open(f"{W}/shim/pbcopy", "w") as f:
        f.write(f"#!/bin/sh\ncat > {CLIP}\n")
    os.chmod(f"{W}/shim/pbcopy", 0o755)
    hide = ""
    if no_fzf:  # same PATH, but the fzf directory is replaced by a copy without fzf
        fzf_dir = os.path.dirname(FZF)
        os.makedirs(f"{W}/brewbin")
        for n in os.listdir(fzf_dir):
            if n != "fzf":
                os.symlink(f"{fzf_dir}/{n}", f"{W}/brewbin/{n}")
        hide = f"_d={fzf_dir}; _m={W}/brewbin; path=(\"${{(@)path/#%$_d/$_m}}\"); hash -r\n"
    if USER_ZSHRC:
        body = f"export HISTFILE={HIST}\n{hide}source {USER_ZSHRC}\nexport HISTFILE={HIST}\n"
    else:
        body = (f"HISTFILE={HIST}; HISTSIZE=1000; SAVEHIST=1000\n"
                "setopt extended_history inc_append_history\nbindkey -e\n"
                f"{hide}source {FZF_ZSH}\n")
    with open(f"{W}/zdot/.zshrc", "w") as f:
        f.write(body +
                f"path=({W}/shim $path)\n"
                f"_dump() {{ print -rn -- \"$BUFFER\" >| {BUF}; BUFFER=''; }}\n"
                "zle -N _dump; bindkey '^X^D' _dump\n"
                "setopt ignore_eof\n"
                f"_zfh_ready() {{ : >| {W}/ready; }}; precmd_functions+=(_zfh_ready)\n"
                f"_rb() {{ local k; for k in '^R' '^T' '\\ec' '^I' '^[[A'; do "
                f"print -r -- ${{${{(z)$(bindkey \"$k\")}}[2]}}; done >| {W}/bind.out; }}\n"
                f"_dups() {{ print -r -- $(fc -l 1 | grep -c 'echo own-cmd-111') "
                f"$(fc -l 1 | grep -c 'echo from-other-tab-XYZ') >| {W}/dup.out; }}\n")


class Shell:
    def __init__(self):
        env = dict(os.environ, ZDOTDIR=f"{W}/zdot", TERM="xterm-256color")
        for k in list(env):
            if k.startswith("OTTY_"):
                env.pop(k)
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execvpe("zsh", ["zsh", "-i"], env)
        self.out = b""
        wait_file(f"{W}/ready", 30, self)  # first prompt drawn
        self.pump(0.5)

    def pump(self, t):
        end = time.time() + t * SLOW
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.05)
            if r:
                try: self.out += os.read(self.fd, 65536)
                except OSError: return

    def keys(self, b, wait=0.8):
        os.write(self.fd, b); self.pump(wait)

    def cmd(self, s, wait=1.0):
        self.keys(s.encode() + b"\r", wait)

    def buffer(self):
        os.path.exists(BUF) and os.remove(BUF)
        self.keys(b"\x18\x04", 0.3)
        return wait_file(BUF, 3, self)

    def bindings(self):
        self.cmd("_rb", 0.3)
        return (wait_file(f"{W}/bind.out", 10, self) or "? ? ? ? ?").split()

    def close(self):
        try: self.keys(b"\x03exit\r", 0.6)
        except OSError: pass
        try: os.kill(self.pid, 9)
        except OSError: pass
        os.waitpid(self.pid, 0)


def wait_file(path, timeout, sh):
    """Return the file's text once it exists, or None after timeout seconds."""
    end = time.time() + timeout * SLOW
    while time.time() < end:
        if os.path.exists(path):
            sh.pump(0.1)
            return open(path).read()
        sh.pump(0.1)
    return None


def other_tab_writes(cmd):
    with open(HIST, "a") as f:
        f.write(f": {int(time.time())}:0;{cmd}\n")


def ctrl_r_pick(sh, query):
    sh.keys(b"\x12", 1.5); sh.keys(query.encode(), 1.2); sh.keys(b"\r", 0.8)
    return sh.buffer()


def read(path):
    return open(path).read() if os.path.exists(path) else None


results = []
def check(name, ok, detail=""):
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))


print(f"fzf: {FZF}\nconfig: {USER_ZSHRC or 'minimal + ' + FZF_ZSH}\n")

# 1. Without fzf: no errors, zsh keeps its own Ctrl-R. Also record the Up key.
setup(no_fzf=True); sh = Shell()
b0 = sh.bindings()
sh.cmd(f"print -r -- $+commands[fzf] >| {W}/has.out", 0.3)
hidden = (wait_file(f"{W}/has.out", 10, sh) or "").strip() == "0"
if hidden:
    err = [s for s in (b"command not found", b"no such file", b"parse error") if s in sh.out]
    check("without fzf: no startup errors", not err, repr(err))
    check("without fzf: Ctrl-R is not an fzf widget", not b0[0].startswith("fzf"), b0[0])
else:
    print("SKIP  without fzf: your zshrc puts fzf back on PATH, so this test cannot hide it")
sh.close()

# 2. Key bindings with fzf
setup(); sh = Shell()
b = sh.bindings()
check("Ctrl-R -> fzf-history-widget-all-tabs", b[0] == "fzf-history-widget-all-tabs", b[0])
check("Ctrl-T -> fzf-file-widget", b[1] == "fzf-file-widget", b[1])
check("Alt-C -> fzf-cd-widget", b[2] == "fzf-cd-widget", b[2])
check("Tab -> fzf-completion (falls back to normal completion)", b[3] == "fzf-completion", b[3])
check("Up arrow not changed by fzf", b[4] == b0[4], f"{b0[4]} -> {b[4]}")

# 3. Ctrl-R inserts, does not run; multi-line entries come back whole
buf = ctrl_r_pick(sh, "EXECUTED-marker")
check("Ctrl-R inserts selection into prompt", buf == f"touch {W}/EXECUTED-marker", repr(buf))
check("Ctrl-R did not run the command", not os.path.exists(f"{W}/EXECUTED-marker"))
buf = ctrl_r_pick(sh, "line1-ML")
check("multi-line entry inserted whole", buf == "echo line1-ML \necho line2-ML", repr(buf))
# Shift-Tab marks and moves to the next match in fzf's default layout; Tab does in --layout=reverse.
for mark in (b"\x1b[Z", b"\t"):
    sh.keys(b"\x12", 1.5); sh.keys(b"MULTI-", 1.2); sh.keys(mark, 0.5); sh.keys(mark, 0.5); sh.keys(b"\r", 0.8)
    buf = sh.buffer()
    if buf is not None and sorted(buf.split("\n")) == ["echo MULTI-a", "echo MULTI-b"]:
        break
check("Shift-Tab / Tab in the list marks more than one command",
      buf is not None and sorted(buf.split("\n")) == ["echo MULTI-a", "echo MULTI-b"], repr(buf))

# 4. Ctrl-Y copies the exact command and does not change the prompt
sh.keys(b"\x12", 1.5); sh.keys(b"line2-ML", 1.2); sh.keys(b"\x19", 2.0)
clip = read(CLIP)
check("Ctrl-Y copies multi-line command exactly", clip == "echo line1-ML \necho line2-ML", repr(clip))
buf = sh.buffer()
check("Ctrl-Y leaves an empty prompt empty", buf == "", repr(buf))
os.path.exists(CLIP) and os.remove(CLIP)
sh.keys(b"\x12", 1.5); sh.keys(b"BS-test", 1.2); sh.keys(b"\x19", 2.0)
clip = read(CLIP)
check("Ctrl-Y keeps literal backslash escapes", clip == "printf 'BS-test a\\tb\\n'", repr(clip))
sh.buffer()
os.path.exists(CLIP) and os.remove(CLIP)
sh.keys(b"TRAIL-test", 0.6); sh.keys(b"\x12", 1.5); sh.keys(b"\x19", 2.0)
clip = read(CLIP)
check("Ctrl-Y keeps trailing spaces", clip == "echo TRAIL-test   ", repr(clip))
buf = sh.buffer()
check("Ctrl-Y leaves typed text unchanged", buf == "TRAIL-test", repr(buf))

# 5. Normal Tab completion still works
sh.keys(f"ls {W}/comp/unique-d".encode() + b"\t", 1.5)
buf = sh.buffer()
check("Tab completion still works", buf is not None and buf.endswith("/comp/unique-dir-XYZ/"), repr(buf))
sh.close()

# 6. Another open tab writes a command: found, no duplicates, in both history modes
for mode, opts in (("share_history off (Otty per-pane)", "unsetopt share_history; setopt inc_append_history"),
                   ("share_history on", "setopt share_history")):
    setup(); sh = Shell(); sh.cmd(opts)
    sh.cmd("echo own-cmd-111")
    other_tab_writes("echo from-other-tab-XYZ")
    if mode == "share_history on":  # zsh imports shared lines when this shell next writes history
        sh.cmd("true")
    buf = ctrl_r_pick(sh, "from-other-tab-XYZ")
    when = "at once" if mode != "share_history on" else "after next command (zsh native)"
    check(f"{mode}: other tab's command found {when}", buf == "echo from-other-tab-XYZ", repr(buf))
    for _ in range(2):
        sh.keys(b"\x12", 1.2); sh.keys(b"\x1b", 0.8)  # open and cancel Ctrl-R twice more
    sh.cmd("_dups", 0.3)
    own, other = ((wait_file(f"{W}/dup.out", 10, sh) or "? ?").split() + ["?", "?"])[:2]
    check(f"{mode}: no duplicate history entries", own == "1" and other == "1", f"own={own} other={other}")
    sh.close()

shutil.rmtree(W, ignore_errors=True)
print(f"\n{sum(results)}/{len(results)} passed")
sys.exit(0 if all(results) else 1)
