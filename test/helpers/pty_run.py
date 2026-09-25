#!/usr/bin/env python3
"""Run a shell command inside a pseudo-terminal, for tests that need real fzf.

Usage: pty_run.py "<command>"
Environment:
  KEYS     keys to type once the UI is drawn (Python escapes, e.g. "\\r", "\\x1b[3~");
           "<pause>" splits them into chunks. Each chunk is typed only after the
           screen has been quiet for a moment, so slow machines don't lose keys.
  TIMEOUT  seconds before the command is killed (default 10)
  PTY_LOG  optional file that receives everything written to the terminal
  WAIT_FOR optional text (e.g. a prompt) that also counts as interactive once printed

Answers fzf's cursor position queries so it can render. The first chunk of keys
is typed once fzf is interactive (it has enabled mouse reporting) and the screen
is quiet. Exits with the command's exit code, or 99 on timeout.
"""
import fcntl
import os
import pty
import select
import struct
import sys
import termios
import time

command = sys.argv[1]
chunks = [
    chunk.encode().decode("unicode_escape").encode("latin1")
    for chunk in os.environ.get("KEYS", "").split("<pause>")
    if chunk
]
timeout = float(os.environ.get("TIMEOUT", "10"))
wait_for = os.environ.get("WAIT_FOR", "").encode()
seen = b""

pid, fd = pty.fork()
if pid == 0:
    os.execvp("sh", ["sh", "-c", command])

fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 160, 0, 0))
start = time.time()
last_output = None   # time of the last screen output
interactive = False  # fzf has started reading keys
last_send = start
QUIET = 0.7          # seconds without output before typing the next chunk
while time.time() - start < timeout:
    readable, _, _ = select.select([fd], [], [], 0.1)
    if readable:
        try:
            data = os.read(fd, 65536)
        except OSError:
            data = b""
        if not data:
            break
        # Answer every cursor position query (fzf may send several at once)
        for _ in range(data.count(b"\x1b[6n")):
            os.write(fd, b"\x1b[1;1R")
        if b"\x1b[?1000h" in data:
            interactive = True
        if wait_for and not interactive:
            seen += data
            interactive = wait_for in seen
        last_output = time.time()
        if os.environ.get("PTY_LOG"):
            with open(os.environ["PTY_LOG"], "ab") as log:
                log.write(data)
    now = time.time()
    if (chunks and interactive and last_output is not None
            and now - last_output >= QUIET and now - last_send >= QUIET):
        chunk = chunks.pop(0)
        os.write(fd, chunk)
        last_send = now
        if os.environ.get("PTY_LOG"):
            with open(os.environ["PTY_LOG"], "ab") as log:
                log.write(b"\n<<<SENT %r>>>\n" % chunk)
    done, status = os.waitpid(pid, os.WNOHANG)
    if done:
        sys.exit(os.waitstatus_to_exitcode(status))

done, status = os.waitpid(pid, os.WNOHANG)
if done:
    sys.exit(os.waitstatus_to_exitcode(status))
if time.time() - start >= timeout:
    os.kill(pid, 9)
    print("TIMEOUT", file=sys.stderr)
    sys.exit(99)
_, status = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(status))
