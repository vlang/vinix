from pathlib import Path
import socket, time, os
state = Path(__file__).resolve().parent
(state / "control.pid").write_text(str(os.getpid()) + "\n")
s = socket.socket(socket.AF_UNIX)
s.settimeout(0.2)
for attempt in range(100):
    try:
        s.connect(str(state / "serial.sock"))
        break
    except ConnectionRefusedError:
        time.sleep(0.1)
cursor = int((state / "control.cursor").read_text()) if (state / "control.cursor").exists() else 0
with (state / "console.log").open("ab", buffering=0) as log:
    while True:
        queue = state / "commands.txt"
        if queue.exists():
            with queue.open("rb") as commands:
                commands.seek(cursor)
                pending = commands.read()
            if pending:
                s.sendall(pending)
                cursor += len(pending)
                (state / "control.cursor").write_text(str(cursor) + "\n")
        try:
            data = s.recv(65536)
        except socket.timeout:
            continue
        if not data:
            break
        log.write(data)
