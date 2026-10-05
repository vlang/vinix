#!/usr/bin/python3
"""Replace QEMU's DNS proxy only when it cannot answer a real query.

Some QEMU user-network hosts advertise 10.0.2.3 through DHCP but do not
answer DNS there. Native UDP traffic to public resolvers still works. Limit
this workaround to that QEMU address; a hardware installation keeps its DHCP
resolver untouched.
"""

import os
from pathlib import Path
import socket
import time


RESOLV_CONF = Path(os.environ.get("VINIX_STEAM_RESOLV_CONF", "/etc/resolv.conf"))
QUERY = (b"\x56\x4e\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00"
         b"\x07example\x03com\x00\x00\x01\x00\x01")
PUBLIC_SERVERS = ("1.1.1.1", "8.8.8.8")


def answers(server, timeout=1):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as connection:
        connection.settimeout(timeout)
        try:
            connection.sendto(QUERY, (server, 53))
            reply, _ = connection.recvfrom(512)
        except OSError:
            return False
    return len(reply) >= 12 and reply[:2] == QUERY[:2] and reply[2] & 0x80 != 0


def main():
    try:
        lines = RESOLV_CONF.read_text().splitlines(keepends=True)
    except OSError:
        return 0
    if not any(line.split() == ["nameserver", "10.0.2.3"] for line in lines):
        return 0

    # A disk-root VM can carry yesterday's resolv.conf across a reboot. Its
    # DHCP lease may not be ready when the desktop or smoke test starts Steam.
    working_server = None
    for attempt in range(15):
        for server in PUBLIC_SERVERS:
            if answers(server):
                working_server = server
                break
        if working_server:
            break
        time.sleep(1)
    if not working_server or answers("10.0.2.3", timeout=2):
        return 0

    replacement = [line for line in lines
                   if line.split() != ["nameserver", "10.0.2.3"]]
    replacement.extend(f"nameserver {server}\n" for server in PUBLIC_SERVERS)
    temporary = RESOLV_CONF.with_name(RESOLV_CONF.name + ".steam-tmp")
    try:
        temporary.write_text("".join(replacement))
        os.replace(temporary, RESOLV_CONF)
    except OSError as error:
        print(f"steam: could not update QEMU's unresponsive DNS: {error}", flush=True)
        try:
            temporary.unlink()
        except OSError:
            pass
        return 1
    print(f"steam: QEMU DNS at 10.0.2.3 is unresponsive; using {working_server}",
          flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
