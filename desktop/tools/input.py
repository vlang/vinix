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

X and Y are pixels on a display whose size is given by --size (default
1024x768). The VM must have been started with a QMP socket:

    VINIX_QEMU_EXTRA="-qmp unix:/tmp/vinix-qmp,server,nowait" ./run-aarch64.sh
"""

import argparse
import json
import os
import socket
import sys
import time

ABS_MAX = 32767


class Monitor:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.stream = self.sock.makefile("rw", encoding="utf-8", newline="\n")
        self.stream.readline()  # greeting
        self.command("qmp_capabilities")

    def command(self, name, **arguments):
        request = {"execute": name}
        if arguments:
            request["arguments"] = arguments
        self.stream.write(json.dumps(request) + "\n")
        self.stream.flush()
        # Events can arrive between the request and its reply.
        while True:
            line = self.stream.readline()
            if not line:
                raise RuntimeError("QMP closed the connection")
            message = json.loads(line)
            if "return" in message or "error" in message:
                if "error" in message:
                    raise RuntimeError(message["error"])
                return message["return"]

    def send_input(self, events):
        self.command("input-send-event", events=events)


def absolute(value, extent):
    scaled = int(round(value * ABS_MAX / max(extent - 1, 1)))
    return max(0, min(ABS_MAX, scaled))


def move_events(x, y, width, height):
    return [
        {"type": "abs", "data": {"axis": "x", "value": absolute(x, width)}},
        {"type": "abs", "data": {"axis": "y", "value": absolute(y, height)}},
    ]


def button_events(down):
    return [{"type": "btn", "data": {"down": down, "button": "left"}}]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["move", "click", "drag"])
    parser.add_argument("coordinates", type=int, nargs="+")
    parser.add_argument("--socket", default=os.environ.get("VINIX_QMP_SOCKET",
                                                           "/tmp/vinix-qmp"))
    parser.add_argument("--size", default="1024x768")
    parser.add_argument("--settle", type=float, default=0.25,
                        help="seconds to let the compositor redraw between steps")
    args = parser.parse_args()

    width, height = (int(part) for part in args.size.split("x"))
    monitor = Monitor(args.socket)
    coordinates = args.coordinates

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
