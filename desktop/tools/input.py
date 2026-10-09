#!/usr/bin/env python3
"""Drive the guest's pointer over QMP, to exercise the desktop from a script.

QEMU's virtio tablet takes absolute coordinates on a fixed 0..32767 axis, so a
screen position is sent as a fraction of the display rather than as a delta —
which means a click lands where it is aimed with no need to know where the
cursor was.

Usage:
    input.py move X Y
    input.py click X Y
    input.py drag X0 Y0 X1 Y1
    input.py switch [TABS] [--hold SECONDS]

`switch` is Cmd-Tab: Cmd held down, Tab tapped TABS times, and Cmd let go
--hold seconds later. The desktop shows its switcher panel only once Cmd has
been held past its own delay, so --hold is what tells a tap from a hold.

X and Y are pixels on a display whose size is given by --size (default
1024x768). The VM must have been started with a QMP socket:

    VINIX_QEMU_EXTRA="-qmp unix:/tmp/vinix-qmp,server,nowait" ./scripts/run-aarch64.sh
"""

import argparse
import json
import os
import socket
import sys
import time

ABS_MAX = 32767


def _native(operation, *arguments):
    import importlib.util
    from pathlib import Path
    spec = importlib.util.spec_from_file_location('qmp_input_native', Path(__file__).with_name('_input_native.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    globals()['_native'] = lambda operation, *arguments: module.call(operation, globals(), *arguments)
    return _native(operation, *arguments)


class Monitor:
    def __init__(self, path):
        return _native('__init__', self, path)

    def command(self, name, **arguments):
        return _native('command', self, name, arguments)

    def send_input(self, events):
        return _native('send_input', self, events)

    def hold_command_tab(self, taps, hold, settle):
        """Cmd-Tab, with Cmd held across every tap and let go at the end.

        The whole point of the gesture is that it is one press of Cmd with
        several of Tab inside it, so this cannot be spelled with type_text:
        the modifier has to stay down between them.
        """
        return _native('hold_command_tab', self, taps, hold, settle)

    def type_text(self, text):
        """Send a string as key presses, one character at a time.

        A guest reading its keyboard through a driver that polls, as Vinix
        does, drops characters sent faster than it looks; the pause between
        them is what makes a typed line arrive whole.
        """
        return _native('type_text', self, text)


def absolute(value, extent):
    return _native('absolute', value, extent)


# QMP names keys rather than taking characters, so a string has to be spelled
# out. Only what a shell command needs is here; anything else is skipped rather
# than guessed at.
KEY_NAMES = {
    " ": "spc", "-": "minus", "=": "equal", "[": "bracket_left",
    "]": "bracket_right", ";": "semicolon", "'": "apostrophe", "`": "grave_accent",
    "\\": "backslash", ",": "comma", ".": "dot", "/": "slash",
    "\n": "ret", "\t": "tab",
}
SHIFTED = {
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7",
    "*": "8", "(": "9", ")": "0", "_": "minus", "+": "equal", "{": "bracket_left",
    "}": "bracket_right", ":": "semicolon", '"': "apostrophe", "~": "grave_accent",
    "|": "backslash", "<": "comma", ">": "dot", "?": "slash",
}


def key_events(character):
    """The QMP key event(s) for one character, or None if it has no name."""
    return _native('key_events', character)


def move_events(x, y, width, height):
    return _native('move_events', x, y, width, height)


def button_events(down):
    return _native('button_events', down)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action",
                        choices=["move", "click", "drag", "type", "switch"])
    parser.add_argument("coordinates", nargs="*")
    parser.add_argument("--socket", default=os.environ.get("VINIX_QMP_SOCKET",
                                                           "/tmp/vinix-qmp"))
    parser.add_argument("--size", default="1024x768")
    parser.add_argument("--settle", type=float, default=0.25,
                        help="seconds to let the compositor redraw between steps")
    parser.add_argument("--hold", type=float, default=0.0,
                        help="seconds to keep Cmd down after the last Tab")
    args = parser.parse_args()

    width, height = (int(part) for part in args.size.split("x"))
    monitor = Monitor(args.socket)

    if args.action == "switch":
        taps = int(args.coordinates[0]) if args.coordinates else 1
        monitor.hold_command_tab(taps, args.hold, args.settle)
        time.sleep(args.settle)
        return

    if args.action == "type":
        # Everything after the verb is the text, rejoined so a command with
        # spaces survives the shell that invoked this.
        monitor.type_text(" ".join(args.coordinates))
        time.sleep(args.settle)
        return

    coordinates = [int(part) for part in args.coordinates]

    if args.action == "move":
        x, y = coordinates[0], coordinates[1]
        monitor.send_input(move_events(x, y, width, height))
    elif args.action == "click":
        x, y = coordinates[0], coordinates[1]
        monitor.send_input(move_events(x, y, width, height))
        time.sleep(args.settle)
        monitor.send_input(button_events(True))
        time.sleep(args.settle)
        monitor.send_input(button_events(False))
    else:
        x0, y0, x1, y1 = coordinates[:4]
        monitor.send_input(move_events(x0, y0, width, height))
        time.sleep(args.settle)
        monitor.send_input(button_events(True))
        time.sleep(args.settle)
        # Several steps, so the compositor sees a drag rather than a jump.
        steps = 12
        for step in range(1, steps + 1):
            x = x0 + (x1 - x0) * step // steps
            y = y0 + (y1 - y0) * step // steps
            monitor.send_input(move_events(x, y, width, height))
            time.sleep(0.05)
        time.sleep(args.settle)
        monitor.send_input(button_events(False))

    time.sleep(args.settle)


if __name__ == "__main__":
    sys.exit(main())
