"""Read host text on demand for the loopback QEMU service."""

import os
import shutil
import subprocess
import sys

MAX_CLIPBOARD_BYTES = 64 * 1024


class ClipboardError(Exception):
    pass


def clipboard_command():
    if sys.platform == "darwin":
        return ["/usr/bin/pbpaste", "-Prefer", "txt"]
    if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-paste"):
        return ["wl-paste", "--no-newline", "--type", "text"]
    if os.environ.get("DISPLAY"):
        if shutil.which("xclip"):
            return ["xclip", "-selection", "clipboard", "-out"]
        if shutil.which("xsel"):
            return ["xsel", "--clipboard", "--output"]
    raise ClipboardError("no host text clipboard available")


def read_clipboard():
    try:
        result = subprocess.run(
            clipboard_command(), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            timeout=2, check=True,
            env={**os.environ, "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"},
        )
        text = result.stdout.decode("utf-8")
    except (OSError, subprocess.SubprocessError, UnicodeError) as error:
        raise ClipboardError("cannot read host text clipboard") from error
    if len(result.stdout) > MAX_CLIPBOARD_BYTES:
        raise ClipboardError("host clipboard exceeds 64 KiB")
    return text.encode("utf-8")
