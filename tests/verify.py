#!/usr/bin/env python3
"""Test fzf.zsh by driving a real interactive zsh in a pseudo-terminal.

Usage:
  python3 tests/verify.py                 # minimal zsh config that sources ../fzf.zsh
  python3 tests/verify.py --zshrc FILE    # your full config (FILE must source fzf.zsh)

Safe: uses a made-up history file, a fake pbcopy and a temp dir, so your real
history and clipboard are not touched. Slow Mac? Set ZFH_TEST_SLOW=2.
"""
import fcntl, os, pty, select, shutil, signal, struct, sys, tempfile, termios, time

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
DIRS = HIST + "_dirs"  # the folder of each command, next to $HISTFILE
COMP_DIR = f"{W}/comp/unique-dir-XYZ"
T_NEW = int(time.time()) - 50  # time of "echo q-z-x-new" in the test history


def setup(no_fzf=False):
    for d in ("zdot", "shim", "brewbin", "tmp"):
        shutil.rmtree(f"{W}/{d}", ignore_errors=True)
    for f in (HIST, DIRS, BUF, CLIP, f"{W}/ready", f"{W}/bind.out", f"{W}/dup.out", f"{W}/has.out"):
        os.path.exists(f) and os.remove(f)
    os.makedirs(f"{W}/zdot"); os.makedirs(f"{W}/shim"); os.makedirs(f"{W}/tmp"); os.makedirs(COMP_DIR, exist_ok=True)
    t = int(time.time()) - 100
    with open(HIST, "w") as f:
        f.write(f": {t}:0;echo line1-ML \\\necho line2-ML\n")  # one multi-line entry
        f.write(f": {t+1}:0;touch {W}/EXECUTED-marker\n")       # must never run
        f.write(f": {t+2}:0;printf 'BS-test a\\tb\\n'\n")        # literal backslashes
        f.write(f": {t+3}:0;echo TRAIL-test   \n")               # trailing spaces
        f.write(f": {t+4}:0;echo MULTI-a\n: {t+5}:0;echo MULTI-b\n")  # for multi-select
        # File order is not time order, and the older command matches "qzx" better.
        # fzf's own widget would show qzx-old first (higher event, better match).
        f.write(f": {T_NEW}:0;echo q-z-x-new\n: {t+6}:0;echo qzx-old\n")
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
        body = (f"HISTFILE={HIST}; HISTSIZE=30000; SAVEHIST=30000\n"
                "setopt extended_history inc_append_history\nbindkey -e\n"
                # Functions and aliases with these names must not change what fzf.zsh runs
                # (zsh runs a function before a program with the same name).
                "function rm rmdir { print -r -- FUNC; }; function mktemp perl { return 1; }\n"
                "alias rm='echo ALIASED' rmdir='echo ALIASED' mktemp=false perl=false\n"
                # Options set when the file loads must not break it.
                f"{hide}setopt ksh_arrays nounset\nsource {FZF_ZSH}\nunsetopt ksh_arrays nounset\n")
    with open(f"{W}/zdot/.zshrc", "w") as f:
        f.write(body +
                f"path=({W}/shim $path)\n"
                f"_dump() {{ print -rn -- \"$BUFFER\" >| {BUF}; BUFFER=''; }}\n"
                "zle -N _dump; bindkey '^X^D' _dump\n"
                # cd without a history line, so that it is not a command of the folder
                "_zcd() { builtin cd -- $BUFFER; BUFFER=''; zle reset-prompt; }\n"
                "zle -N _zcd; bindkey '^X^G' _zcd\n"
                "setopt ignore_eof\n"
                f"_zfh_ready() {{ : >| {W}/ready; }}; precmd_functions+=(_zfh_ready)\n"
                f"_rb() {{ local k; for k in '^R' '^T' '\\ec' '^I' '^[[A'; do "
                f"print -r -- ${{${{(z)$(bindkey \"$k\")}}[2]}}; done >| {W}/bind.out; }}\n"
                f"_dups() {{ print -r -- $(fc -l 1 | grep -c 'echo own-cmd-111') "
                f"$(fc -l 1 | grep -c 'echo from-other-tab-XYZ') >| {W}/dup.out; }}\n")


class Shell:
    def __init__(self):
        # A stale value, as an older fzf.zsh exported it: fzf.zsh must replace it,
        # or the Ctrl-Y checks fail.
        env = dict(os.environ, ZDOTDIR=f"{W}/zdot", TERM="xterm-256color", TMPDIR=f"{W}/tmp",
                   FZF_CTRL_R_OPTS="--bind 'ctrl-y:abort'")
        for k in list(env):
            if k.startswith("OTTY_"):
                env.pop(k)
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execvpe("zsh", ["zsh", "-i"], env)
        # A real window size: in a 0x0 pty fzf draws no list lines.
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
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


def other_tab_writes(cmd, when=None):
    with open(HIST, "a") as f:
        f.write(f": {when or int(time.time())}:0;{cmd}\n")


def cd(sh, path):
    sh.keys(path.encode() + b"\x18\x07", 0.5)


def wait_out(sh, pat, start, timeout):
    """Pump until pat is in the output after start, or timeout seconds pass."""
    end = time.time() + timeout * SLOW
    while pat not in sh.out[start:] and time.time() < end:
        sh.pump(0.05)
    return pat in sh.out[start:]


def lists_ready(sh, tmp_dirs=None, timeout=10):
    """Pump until a zfh.* temp folder has both lists (then Ctrl-O works). Returns the folder."""
    global last_ready
    end = time.time() + timeout * SLOW
    while True:  # scan at least once, also with timeout=0
        for d in tmp_dirs or [f"{W}/tmp"]:
            for n in os.listdir(d) if os.path.isdir(d) else []:
                z = os.path.join(d, n)
                if n.startswith("zfh.") and os.path.exists(f"{z}/all") and os.path.exists(f"{z}/here"):
                    last_ready = z
                    return z
        if time.time() >= end:
            last_ready = None
            return None
        sh.pump(0.05)


last_ready = None  # the temp folder that the last lists_ready() found


def ctrl_r_here(sh, query, toggles=1, tmp_dirs=None):
    """Ctrl-R, Ctrl-O `toggles` times, type query, Enter. Returns the prompt buffer."""
    start = len(sh.out)
    sh.keys(b"\x12", 0.3)
    wait_out(sh, b"CTRL-O: only this folder", start, 10)  # the list is open
    lists_ready(sh, tmp_dirs)  # fzf starts before perl is done
    sh.pump(0.5)
    for _ in range(toggles):
        sh.keys(b"\x0f", 1.0)
    sh.keys(query.encode(), 1.2); sh.keys(b"\r", 0.8)
    return sh.buffer()


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

# 3b. Sorted on time, newest first, also while you type; Ctrl-R in the list sorts by match
start = len(sh.out)
buf = ctrl_r_pick(sh, "qzx")
check("Ctrl-R lists newest first by time, also while you type", buf == "echo q-z-x-new", repr(buf))
stamp = time.strftime("%Y-%m-%d %H:%M", time.localtime(T_NEW)).encode()
check("Ctrl-R list shows the date and time of each command", stamp in sh.out[start:], stamp.decode())
sh.keys(b"\x12", 1.5); sh.keys(b"qzx", 1.2); sh.keys(b"\x12", 0.8); sh.keys(b"\r", 0.8)
buf = sh.buffer()
check("Ctrl-R in the list sorts by match", buf == "echo qzx-old", repr(buf))
# Exact-match query for the date of T_NEW: if the time were searched, Enter would insert a command.
sh.keys(b"\x12", 1.5); sh.keys(b"'" + stamp[:10], 1.2); sh.keys(b"\r", 0.8)
buf = sh.buffer()
check("Ctrl-R search looks only at the command, not the time", buf == "", repr(buf))

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
    if mode != "share_history on":
        # fc -RI gives an old command from another tab the highest event number.
        other_tab_writes("echo old-other-tab-QQ", int(time.time()) - 3600)
        buf = ctrl_r_pick(sh, "")
        check(f"{mode}: old command from other tab is not listed as newest", buf == "echo own-cmd-111", repr(buf))
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

# 7. Ctrl-O: only the commands that ran in this folder and its subfolders
setup()
P, SUB, OTHER = f"{W}/proj", f"{W}/proj/sub", f"{W}/proj-other"  # proj-other: same prefix, other folder
for d in (SUB, OTHER):
    os.makedirs(d, exist_ok=True)
sh = Shell(); sh.cmd("unsetopt share_history; setopt inc_append_history")
cd(sh, P); sh.cmd("echo SHARED-x"); sh.cmd("echo LATER-y")
cd(sh, SUB); sh.cmd("echo IN-SUB-z")
cd(sh, OTHER); sh.cmd("echo SHARED-x"); sh.cmd("echo ONLY-other")
cd(sh, P)
buf = ctrl_r_here(sh, "ONLY-other")
check("Ctrl-O: a command from another folder (same name prefix) is not listed", buf == "", repr(buf))
buf = ctrl_r_here(sh, "IN-SUB")
check("Ctrl-O: a command from a subfolder is listed", buf == "echo IN-SUB-z", repr(buf))
buf = ctrl_r_pick(sh, "SHARED | LATER")
here = ctrl_r_here(sh, "SHARED | LATER")
check("Ctrl-O: sorted by the last time in this folder",
      buf == "echo SHARED-x" and here == "echo LATER-y", f"all={buf!r} here={here!r}")
start = len(sh.out)
buf = ctrl_r_here(sh, "ONLY-other", toggles=2)
check("Ctrl-O again: all commands", buf == "echo ONLY-other", repr(buf))
# fzf draws the last space of the prompt after a color code.
check("Ctrl-O: the prompt shows the folder", f"{P} >".encode() in sh.out[start:], f"{P} >")
sh.keys(b"\x12", 0.3); lists_ready(sh); sh.pump(0.5)
sh.keys(b"\x0f", 1.0); sh.keys(b"LATER-y", 1.2); sh.keys(b"\x19", 2.0)
clip = read(CLIP)
check("Ctrl-O: Ctrl-Y copies the command", clip == "echo LATER-y", repr(clip))
sh.buffer()
# zsh writes some UTF-8 bytes to $HISTFILE in another form (0x83, byte XOR 32) and a newline as "\<newline>".
for c in ["echo 'caf\u00e9 \u21b3 \u4e2d\u6587 UTF'", "echo 'ML-first", "ML-second'"]:
    sh.keys(c.encode() + b"\r", 0.5)
sh.cmd("true")
data = open(DIRS, "rb").read()
check("folder file: commands with UTF-8 and with a newline are saved",
      f"\t{P}\techo 'caf\u00e9 \u21b3 \u4e2d\u6587 UTF'\0".encode() in data and
      f"\t{P}\techo 'ML-first\nML-second'\0".encode() in data)
buf = ctrl_r_here(sh, "\u21b3 UTF")
check("Ctrl-O: a command with UTF-8 is listed", buf == "echo 'caf\u00e9 \u21b3 \u4e2d\u6587 UTF'", repr(buf))
with open(DIRS, "ab") as f:  # another open tab runs a command in this folder
    f.write(f"{int(time.time())}\t{P}\techo TAB2-here\0".encode())
other_tab_writes("echo TAB2-here")
buf = ctrl_r_here(sh, "TAB2-here")
check("Ctrl-O: a command from another tab in this folder shows at once", buf == "echo TAB2-here", repr(buf))
perm = oct(os.stat(DIRS).st_mode & 0o777) if os.path.exists(DIRS) else None
check("folder file can be read only by you (600)", perm == "0o600", perm)

# Lines that zsh does not save to $HISTFILE are not saved with their folder either.
sh.cmd("setopt hist_ignore_space"); sh.cmd(" echo SECRET-space")
sh.cmd("alias hide=' echo'"); sh.cmd("hide ALIAS-secret")
sh.cmd("HISTORY_IGNORE='echo IGN-*'"); sh.cmd("echo IGN-pat-1")
sh.cmd("zshaddhistory() { [[ $1 == *HOOK''-drop* ]] && return 1; [[ $1 == *HOOK''-keep2* ]] && return 2; return 0 }")
sh.cmd("echo HOOK-drop"); sh.cmd("echo HOOK-keep2"); sh.cmd("echo AFTER-hook")
# The same text is already in $HISTFILE from another folder: that old line does not count.
# Each command also appends a line to $HISTFILE, as another tab does while it runs.
TAB = "; print -r -- ': 1:0;echo from another tab' >> $HISTFILE"
SAME, AGAIN = "echo SAME-text" + TAB, "echo AGAIN-1" + TAB
sh.cmd(SAME); cd(sh, OTHER)
sh.cmd("zshaddhistory() { [[ $PWD == *-other ]] && return 1; return 0 }"); sh.cmd(SAME)
cd(sh, P)
# A dropped line that the command itself then writes to $HISTFILE (as another tab could).
sh.cmd("zshaddhistory() { [[ $1 == *DROP''-ME* ]] && return 1; return 0 }")
sh.cmd("echo DROP-ME; print -r -- \": 1:0;$history[$HISTCMD]\" >> $HISTFILE")
sh.cmd("unfunction zshaddhistory"); sh.cmd(AGAIN); sh.cmd("HISTORY_IGNORE='echo AGAIN-*'")
sh.cmd(AGAIN); sh.cmd("unset HISTORY_IGNORE")
start = len(sh.out)
sh.cmd("setopt nounset"); sh.cmd("echo NOUNSET-ok"); sh.cmd("unsetopt nounset")
# Errors from this file fail the check. When another hook (for example a prompt theme) fails
# with nounset, zsh skips the hooks after it, so then the line cannot be saved.
errs = [l for l in sh.out[start:].split(b"\n") if b"not set" in l]
nounset_err = [l for l in errs if b"_zfh" in l]
other_err = [l for l in errs if b"_zfh" not in l]
sh.cmd("setopt ksh_arrays"); sh.cmd("echo KSH-ok"); sh.cmd("echo KSH-ok2"); sh.cmd("unsetopt ksh_arrays")
# inc_append_history_time writes a line when it ends: precmd saves it before the next prompt.
sh.cmd("unsetopt inc_append_history; setopt inc_append_history_time"); sh.cmd("echo TIME-wait")
buf = ctrl_r_here(sh, "TIME-wait")
check("Ctrl-O with inc_append_history_time: the last command shows at once", buf == "echo TIME-wait", repr(buf))
sh.cmd("echo TRAIL-bs\\\\")  # zsh writes "echo TRAIL-bs\\ " (a space after the last backslash)
# Another tab writes more than 4 KB to $HISTFILE while the command runs.
LONG = "echo LONG-A; repeat 100 print -r -- ': 1:0;echo filler line from another tab 0123456789 0123456789' >> $HISTFILE"
sh.cmd(LONG)
# The same privacy rules when the line waits for precmd (only inc_append_history_time).
sh.cmd(" echo IAHT-space"); sh.cmd("HISTORY_IGNORE='echo IAHT-ign*'"); sh.cmd("echo IAHT-ign")
sh.cmd("unset HISTORY_IGNORE")
sh.cmd("zshaddhistory() { [[ $1 == *IAHT''-hook* ]] && return 1; return 0 }"); sh.cmd("echo IAHT-hook")
sh.cmd("unfunction zshaddhistory")
# Without extended_history zsh writes "\\:" for a first ":" and a space after "\\" + spaces at the end.
sh.cmd("unsetopt extended_history"); sh.cmd(": COLON-cmd"); sh.cmd("echo TRAIL-sp\\  ")
sh.cmd("setopt extended_history")
sh.cmd("true")
data = open(DIRS, "rb").read() if os.path.exists(DIRS) else b""
rec = lambda c: f"\t{P}\t{c}\0".encode()
check("folder file: no line with a leading space (hist_ignore_space)", b"SECRET-space" not in data)
check("folder file: no line of an alias with a leading space", b"ALIAS-secret" not in data)
check("folder file: no line that matches HISTORY_IGNORE", rec("echo IGN-pat-1") not in data)
check("folder file: no line that a zshaddhistory hook drops (return 1 or 2)",
      rec("echo HOOK-drop") not in data and rec("echo HOOK-keep2") not in data and rec("echo AFTER-hook") in data,
      f"drop={rec('echo HOOK-drop') in data} keep2={rec('echo HOOK-keep2') in data} after={rec('echo AFTER-hook') in data}")
check("folder file: a line that a hook drops is not saved, also when the same text is in $HISTFILE",
      f"\t{OTHER}\t{SAME}\0".encode() not in data and rec(SAME) in data)
check("folder file: a line that matches HISTORY_IGNORE is not saved, also when the same text is in $HISTFILE",
      data.count(rec(AGAIN)) == 1, f"count={data.count(rec(AGAIN))}")
check("folder file: a dropped line is not saved when the same text is written while it runs",
      b"DROP-ME" not in data)
check("folder file: a command that ends in a backslash is saved", rec("echo TRAIL-bs\\\\") in data)
check("folder file: without extended_history, a command that starts with ':' or ends in '\\' + spaces is saved",
      rec(": COLON-cmd") in data and rec("echo TRAIL-sp\\  ") in data)
check("folder file: inc_append_history_time: no leading-space, HISTORY_IGNORE or hook-dropped line",
      b"IAHT-space" not in data and rec("echo IAHT-ign") not in data and rec("echo IAHT-hook") not in data
      and rec("echo TIME-wait") in data)
check("folder file: works with setopt nounset",
      not nounset_err and (rec("echo NOUNSET-ok") in data or bool(other_err)),
      repr(nounset_err[:1]) if nounset_err else ("another hook failed first, not saved" if other_err else ""))
check("folder file: works with setopt ksh_arrays", rec("echo KSH-ok") in data and rec("echo KSH-ok2") in data)
check("folder file: a line saved by inc_append_history_time is saved after it ran", rec("echo TIME-wait") in data)
check("folder file: inc_append_history_time, other tabs write 4 KB during the command: still saved", rec(LONG) in data)
# No $HISTFILE: zsh saves nothing, so the folder file gets nothing (also not a default file).
sh.cmd(f"HOME={W}/fakehome; unset HISTFILE"); sh.cmd("echo NOHIST-secret")
after = open(DIRS, "rb").read() if os.path.exists(DIRS) else b""
check("folder file: nothing is saved without $HISTFILE",
      b"NOHIST-secret" not in after and not os.path.exists(f"{W}/fakehome/.zsh_history_dirs"))
left = [n for n in os.listdir(f"{W}/tmp") if n.startswith("zfh.")]
check("Ctrl-R removes its temp folder", not left, repr(left))
# Ctrl-C while the list loads (a slow perl): the temp folder is removed too. The key goes
# to fzf (it has the terminal); fzf ends and the widget ends normally after perl.
os.makedirs(f"{W}/slowbin", exist_ok=True)
with open(f"{W}/slowbin/perl", "w") as f:
    f.write(f"#!/bin/sh\nsleep 1.5\nexec {shutil.which('perl')} \"$@\"\n")
os.chmod(f"{W}/slowbin/perl", 0o755)
sh.cmd(f"path=({W}/slowbin $path)")
sh.keys(b"\x12", 0.6)
opened = [n for n in os.listdir(f"{W}/tmp") if n.startswith("zfh.")]
sh.keys(b"\x03", 2.5)
left = [n for n in os.listdir(f"{W}/tmp") if n.startswith("zfh.")]
check("Ctrl-C while the Ctrl-R list loads: temp folder removed", opened and not left, f"open={opened} left={left}")
# SIGINT to the shell and its children while perl makes the lists: the widget stops before
# its last line, so only "always" can clean up.
sh.buffer()
sh.keys(b"\x12", 0.6)
opened = [n for n in os.listdir(f"{W}/tmp") if n.startswith("zfh.")]
os.killpg(os.getpgid(sh.pid), signal.SIGINT); sh.pump(2.5)
left = [n for n in os.listdir(f"{W}/tmp") if n.startswith("zfh.")]
check("SIGINT while perl makes the lists: temp folder removed", opened and not left, f"open={opened} left={left}")
sh.keys(b"\x03", 0.5)
sh.cmd("path=(${path:#*/slowbin})")
# The tab closes while the list is open: zshexit deletes the lists (they hold all of $history).
sh.keys(b"\x12", 1.5)
opened = [n for n in os.listdir(f"{W}/tmp") if n.startswith("zfh.")]
os.kill(sh.pid, signal.SIGHUP); sh.pump(1.0)
left = [n for n in os.listdir(f"{W}/tmp") if n.startswith("zfh.")]
check("tab closed while the Ctrl-R list is open: temp folder removed", opened and not left, f"open={opened} left={left}")
sh.close()

# 7b. share_history, SAVEHIST=0, folder names with special characters, fzf-tmux, fallback header.
os.remove(f"{W}/ready")
sh = Shell()
N = "inj')+execute(touch PWNED1)+abort($(touch PWNED2))`touch PWNED3`"
INJ = f"{W}/{N}"
os.makedirs(INJ, exist_ok=True)
cd(sh, P)
# share_history writes at once, so a line that is not in $HISTFILE at preexec must not wait.
sh.cmd("unsetopt inc_append_history; setopt share_history inc_append_history_time")
sh.cmd("echo SHARE-kept")
sh.cmd("zshaddhistory() { [[ $1 == *SHDROP''-ME* ]] && return 1; return 0 }")
sh.cmd("echo SHDROP-ME; print -r -- \": 1:0;$history[$HISTCMD]\" >> $HISTFILE")
sh.cmd("unfunction zshaddhistory")
sh.cmd("SAVEHIST=0"); sh.cmd("echo SAVEHIST0-secret"); sh.cmd("SAVEHIST=30000")
# A precmd hook before ours fails, so zsh skips ours: the old mark must not count.
sh.cmd("_zfh_bad() { : ${ZFH_BAD:?} }; precmd_functions=(_zfh_bad $precmd_functions)")
sh.cmd("echo STALE-x"); cd(sh, OTHER)
sh.cmd("zshaddhistory() { [[ $PWD == *-other ]] && return 1; return 0 }"); sh.cmd("echo STALE-x")
sh.cmd("unfunction zshaddhistory"); cd(sh, P)
sh.cmd(f"source {FZF_ZSH}")  # loading the file again puts its precmd hook first
sh.cmd("echo ORDER-ok"); sh.cmd("precmd_functions=(${precmd_functions:#_zfh_bad})")
# share_history + hist_ignore_dups: zsh reads the line of another tab first, and then does
# not write the same command again. So it gets no folder (the documented limit).
sh.cmd("setopt hist_ignore_dups; print -r -- ': 1:0;echo DUPSH-x' >> $HISTFILE")
sh.cmd("echo DUPSH-x"); sh.cmd("unsetopt hist_ignore_dups")
sh.cmd(f"hash -d w={W}")  # the prompt shows ~w/<name>: the full path is wider than the pty
cd(sh, INJ); sh.cmd("echo INJ-cmd"); sh.cmd("true")
data = open(DIRS, "rb").read()
check("folder file: share_history: a command is saved with its folder", rec("echo SHARE-kept") in data)
check("folder file: share_history: a dropped line is not saved when the same text is written while it runs",
      b"SHDROP-ME" not in data)
check("folder file: nothing is saved with SAVEHIST=0", b"SAVEHIST0-secret" not in data)
check("folder file: when a precmd hook before ours fails, an old mark does not count",
      f"\t{OTHER}\techo STALE-x\0".encode() not in data)
check("folder file: loading the file puts its precmd hook first", rec("echo ORDER-ok") in data)
check("folder file: share_history + hist_ignore_dups, same command as another tab just wrote: no folder (documented)",
      rec("echo DUPSH-x") not in data)
cd(sh, P)  # ORDER-ok ran in P
start = len(sh.out)
sh.cmd("setopt ksh_arrays"); buf = ctrl_r_here(sh, "ORDER-ok"); sh.cmd("unsetopt ksh_arrays")
check("Ctrl-R and Ctrl-O work with setopt ksh_arrays",
      buf == "echo ORDER-ok" and b"bad output format" not in sh.out[start:], repr(buf))
cd(sh, INJ)
start = len(sh.out)
buf = ctrl_r_here(sh, "INJ-cmd")
prompt = f"~w/{N} >".encode() in sh.out[start:]
other = ctrl_r_here(sh, "ONLY-other")  # Ctrl-O really filters in this folder
pwned = [os.path.join(d, f) for d, _, fs in os.walk(W) for f in fs if f.startswith("PWNED")]
check("Ctrl-O: a folder name with fzf actions and $(...) is only text",
      buf == "echo INJ-cmd" and other == "" and prompt and not pwned,
      f"buf={buf!r} other={other!r} prompt={prompt} pwned={pwned}")
# Fallback (mktemp fails): fzf's own widget has no Ctrl-O, so its header must not name it.
for c in ["echo 'FB-first", "FB-second'"]:
    sh.keys(c.encode() + b"\r", 0.5)
sh.pump(0.5)
start = len(sh.out)
sh.keys(b"\x12", 1.5)
full = b"CTRL-O: only this folder" in sh.out[start:]
sh.keys(b"\x1b", 0.8)
sh.cmd("TMPDIR=/nonexistent-zfh-dir")
start = len(sh.out)
sh.keys(b"\x12", 1.5)
fb = sh.out[start:]
sh.keys(b"\x1b", 0.8)
sh.cmd("unfunction perl")  # the test's perl function empties fzf's own list (it calls plain perl)
os.path.exists(CLIP) and os.remove(CLIP)
sh.keys(b"\x12", 1.5); sh.keys(b"SHARE-kept", 1.2); sh.keys(b"\x19", 2.0)
clip1 = read(CLIP)
os.path.exists(CLIP) and os.remove(CLIP)
sh.keys(b"\x12", 1.5); sh.keys(b"FB-first", 1.2); sh.keys(b"\x19", 2.0)
clip2 = read(CLIP)
sh.buffer()
sh.cmd(f"TMPDIR={W}/tmp"); sh.cmd("function perl { return 1; }")
check("fallback (fzf's own widget): Ctrl-Y copies only the command, also a multi-line one",
      clip1 == "echo SHARE-kept" and clip2 == "echo 'FB-first\nFB-second'", f"{clip1!r} {clip2!r}")
check("header names Ctrl-O only when Ctrl-O works",
      full and b"CTRL-Y: copy to clipboard" in fb and b"CTRL-O" not in fb, f"full={full} fallback={b'CTRL-O' in fb}")
# FZF_TMUX=1: fzf-tmux gives fzf only its options and TERM. Ctrl-O must still work.
if shutil.which("tmux") and shutil.which("fzf-tmux"):
    os.makedirs(f"{W}/tmuxbin", exist_ok=True)
    with open(f"{W}/tmuxbin/fzf-tmux", "w") as f:
        f.write(f"#!/bin/sh\necho used >> {W}/fzf-tmux.log\nexec {shutil.which('fzf-tmux')} \"$@\"\n")
    os.chmod(f"{W}/tmuxbin/fzf-tmux", 0o755)
    cd(sh, P)
    os.remove(f"{W}/ready")
    sh.cmd(f"tmux -L zfh-test -f /dev/null new-session zsh -i", 0.3)
    wait_file(f"{W}/ready", 15, sh); sh.pump(0.5)  # the first prompt in tmux
    sh.cmd(f"path=({W}/tmuxbin $path); export FZF_TMUX=1", 1.0)
    cd(sh, P)
    buf = ctrl_r_here(sh, "SHARE-kept")
    buf2 = ctrl_r_here(sh, "ONLY-other")
    used = os.path.exists(f"{W}/fzf-tmux.log")
    left = [n for n in os.listdir(f"{W}/tmp") if n.startswith("zfh.")]
    check("FZF_TMUX=1: Ctrl-O lists only this folder and removes its temp folder",
          used and buf == "echo SHARE-kept" and buf2 == "" and not left,
          f"fzf-tmux used={used} here={buf!r} other={buf2!r} left={left}")
    sh.cmd("exit", 1.5)
    os.system("tmux -L zfh-test kill-server 2>/dev/null")
else:
    print("SKIP  FZF_TMUX=1 check (tmux or fzf-tmux not installed)")
sh.close()

# 7c. More limits of the folder file, TMPDIR, and Ctrl-O while perl still runs.
os.remove(f"{W}/ready")
sh = Shell()
cd(sh, P)
sh.cmd("unsetopt share_history; setopt inc_append_history")
# hist_reduce_blanks: the saved text is the one in $history, so Ctrl-O finds it.
sh.cmd("setopt hist_reduce_blanks"); sh.cmd("echo   RB-a     b"); sh.cmd("unsetopt hist_reduce_blanks")
buf = ctrl_r_here(sh, "RB-a")
data = open(DIRS, "rb").read()
check("hist_reduce_blanks: the folder file has the short form and Ctrl-O lists it",
      rec("echo RB-a b") in data and buf == "echo RB-a b", repr(buf))
# A folder with a tab in its name is not saved (the file uses tabs between the fields).
TABD = f"{W}/tab\tdir"
os.makedirs(TABD, exist_ok=True)
sh.cmd(f"cd $'{W}/tab\\tdir'"); sh.cmd("echo TABDIR-x"); cd(sh, P)
data = open(DIRS, "rb").read()
check("folder file: a command in a folder with a tab in its name is not saved", b"TABDIR-x" not in data)
# The line is not saved when $HISTFILE changes while the command runs. With only
# inc_append_history_time, zsh writes the line when the command ends, so the command itself
# can change the file. A second history file keeps the test history as it is.
H2 = f"{W}/hist2"
sh.cmd("unsetopt inc_append_history; setopt inc_append_history_time")
sh.cmd(f"HISTFILE={H2}; echo HF-switch")
for i in range(4):
    sh.cmd(f"echo H2-fill-{i}")
sh.cmd(f"fc -p {W}/hist3; echo FCP-x"); sh.cmd("fc -P")
sh.cmd("echo INODE-x; cp $HISTFILE $HISTFILE.n && mv -f $HISTFILE.n $HISTFILE")
sh.cmd("echo SMALL-x; : >| $HISTFILE")
sh.cmd("echo BIG-x; head -c 4200000 /dev/zero | tr '\\0' '#' >> $HISTFILE; print >> $HISTFILE", 3.0)
sh.cmd("echo H2-after")
sh.cmd(f"HISTFILE={HIST}"); sh.cmd("unsetopt inc_append_history_time; setopt inc_append_history")
d2 = b"".join(open(f, "rb").read() for f in (DIRS, H2 + "_dirs", f"{W}/hist3_dirs") if os.path.exists(f))
h2 = open(H2 + "_dirs", "rb").read() if os.path.exists(H2 + "_dirs") else b""
check("folder file: saved again in the new $HISTFILE (the checks below are not always false)",
      f"\t{P}\techo H2-fill-3\0".encode() in h2 and f"\t{P}\techo H2-after\0".encode() in h2)
check("folder file: not saved when $HISTFILE names another file at the end of the command",
      b"HF-switch" not in d2 and b"FCP-x" not in d2)
check("folder file: not saved when $HISTFILE was replaced during the command (new inode)", b"INODE-x" not in d2)
check("folder file: not saved when $HISTFILE got smaller during the command", b"SMALL-x" not in d2)
check("folder file: not saved when more than 4 MB was added during the command", b"BIG-x" not in d2)
# TMPDIR with a character that the widget does not write into the fzf options: /tmp is used.
SPC = f"{W}/tmp dir"
os.makedirs(SPC, exist_ok=True)
sh.cmd(f"TMPDIR='{SPC}'")
before = {n for n in os.listdir("/tmp") if n.startswith("zfh.")}
buf = ctrl_r_here(sh, "RB-a", tmp_dirs=["/tmp"])
z1 = last_ready
other = ctrl_r_here(sh, "ONLY-other", tmp_dirs=["/tmp"])  # only in "all": Ctrl-O must hide it
z2 = last_ready
sh.cmd(f"TMPDIR={W}/tmp")
new = {n for n in os.listdir("/tmp") if n.startswith("zfh.")} - before
in_tmp = all(z and z.startswith("/tmp/zfh.") for z in (z1, z2))
check("TMPDIR with a space: Ctrl-O works, the temp folder is in /tmp and is removed",
      in_tmp and buf == "echo RB-a b" and other == "" and not new and not os.listdir(SPC),
      f"lists={z1},{z2} buf={buf!r} other={other!r} left={sorted(new)}")
# fzf starts at once, before perl is done. Ctrl-O before the lists are ready does nothing.
os.makedirs(f"{W}/slowbin", exist_ok=True)
sh.cmd(f"path=({W}/slowbin $path)")
start = len(sh.out); t = time.time()
sh.keys(b"\x12", 0)
shown = wait_out(sh, b"CTRL-O: only this folder", start, 1.2)
early = time.time() - t
zs = [f"{W}/tmp/{n}" for n in os.listdir(f"{W}/tmp") if n.startswith("zfh.")]
shown = bool(shown and zs) and not any(os.path.exists(f"{z}/all") for z in zs)
sh.keys(b"\x0f", 0.2)  # perl still sleeps: the lists do not exist yet
ready = lists_ready(sh, timeout=10)
sh.pump(0.5); sh.keys(b"ONLY-other", 1.2); sh.keys(b"\r", 0.8)
buf = sh.buffer()
sh.cmd("path=(${path:#*/slowbin})")
check("Ctrl-R: fzf shows before perl is done", shown, f"{early:.2f} s, folders={zs}")
check("Ctrl-O before the lists are ready does nothing (the full list stays)",
      bool(ready) and buf == "echo ONLY-other", repr(buf))
sh.close()

# 8. Speed with a large history. In a subshell on macOS, `fc -l -t` is slow unless TZ is
# empty (see fzf.zsh): the list would need about 4 s here instead of about 0.2 s.
setup()
with open(HIST, "a") as f:
    t0 = int(time.time()) - 10**7
    for i in range(20000):
        f.write(f": {t0 + i * 60}:0;echo speed-{i}\n")
    f.write(f": {int(time.time()) - 10}:0;echo SPEED-newest\n")
with open(DIRS, "wb") as f:  # and 20,000 commands with their folder
    f.write(b"".join(f"{t0 + i * 60}\t{os.getcwd()}\techo speed-{i}\0".encode() for i in range(20000)))
sh = Shell()
start = len(sh.out); t = time.time()
sh.keys(b"\x12", 0)
while b"SPEED-newest" not in sh.out[start:] and time.time() - t < 20 * SLOW:
    sh.pump(0.02)
took = time.time() - t
check("Ctrl-R list with 20,000 commands shows in less than 2 s", took < 2 * SLOW, f"{took:.2f} s")
sh.keys(b"\x1b", 0.5)
sh.close()

shutil.rmtree(W, ignore_errors=True)
print(f"\n{sum(results)}/{len(results)} passed")
sys.exit(0 if all(results) else 1)
