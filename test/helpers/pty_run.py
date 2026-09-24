#!/usr/bin/env python3
"""Run a shell command inside a pseudo-terminal, for tests that need real fzf.

Usage: pty_run.py "<command>"
Environment:
  KEYS     keys to type after the UI has started (Python escapes, e.g. "\\r", "\\x1b[3~");
           "<pause>" splits them into chunks typed one second apart
  TIMEOUT  seconds before the command is killed (default 10)

Answers fzf's cursor position query so it can render. Exits with the command's
exit code, or 99 on timeout.
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

pid, fd = pty.fork()
if pid == 0:
    os.execvp("sh", ["sh", "-c", command])

fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 160, 0, 0))
start = time.time()
next_send = start + 1.0
while time.time() - start < timeout:
    readable, _, _ = select.select([fd], [], [], 0.1)
    if readable:
        try:
            data = os.read(fd, 65536)
        except OSError:
            data = b""
        if not data:
            break
        if b"\x1b[6n" in data:
            os.write(fd, b"\x1b[1;1R")
    if chunks and time.time() >= next_send:
        os.write(fd, chunks.pop(0))
        next_send = time.time() + 1.0
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
