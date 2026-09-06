#!/bin/bash
# Capture the QEMU guest screen.
#
#   ./desktop/tools/screenshot.sh out.png
#
# Requires the VM to have been started with a QMP socket, which
# run-desktop-aarch64.sh --monitor sets up.
#
# This talks QMP rather than the human monitor. The human monitor is a
# `server,nowait` socket that serves one client at a time, and a client that
# does not disconnect cleanly leaves it unable to accept another — which looks
# exactly like a hung guest, and twice sent me hunting for a bug in a VM that
# was running perfectly well. QMP tolerates the same treatment.
set -e

OUT="${1:-/tmp/vinix-screen.png}"
SOCKET="${VINIX_QMP_SOCKET:-/tmp/vinix-qmp}"

if [ ! -S "$SOCKET" ]; then
    echo "ERROR: no QMP socket at $SOCKET" >&2
    echo "Start the VM with ./run-desktop-aarch64.sh --monitor" >&2
    exit 1
fi

python3 - "$SOCKET" "$OUT" <<'PY'
import json
import os
import socket
import sys
import tempfile

from PIL import Image

socket_path, out_path = sys.argv[1], sys.argv[2]

connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
connection.settimeout(30)
connection.connect(socket_path)
stream = connection.makefile("rw", encoding="utf-8", newline="\n")
stream.readline()  # greeting


def command(name, **arguments):
    request = {"execute": name}
    if arguments:
        request["arguments"] = arguments
    stream.write(json.dumps(request) + "\n")
    stream.flush()
    while True:
        message = json.loads(stream.readline())
        # Events can arrive between a request and its reply.
        if "return" in message:
            return message["return"]
        if "error" in message:
            sys.exit("QMP error: %s" % message["error"])


command("qmp_capabilities")
# screendump always writes PPM; the guest never sees this happen.
ppm = tempfile.mktemp(prefix="vinix-screen-", suffix=".ppm")
command("screendump", filename=ppm)

if not os.path.exists(ppm) or os.path.getsize(ppm) == 0:
    sys.exit("screendump produced nothing")

Image.open(ppm).save(out_path)
os.remove(ppm)
print(out_path)
PY
