#!/usr/bin/env python3
"""Local QEMU IPv6 socket/packet checks, using the shared isolated runner."""
import importlib.util
from pathlib import Path
import socket
import threading
import struct
import os
import sys
import shutil

path = Path(__file__).resolve().parents[1] / "openbsd-security" / "run_vm.py"
spec = importlib.util.spec_from_file_location("vinix_security_vm", path)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
runner.TEST_LABEL = "IPv6 multicast"
runner.PASS_MARKER = b"VINIX IPV6: PASS"
runner.FAIL_MARKERS = (b"VINIX IPV6: FAIL", b"KERNEL PANIC", b"FATAL EXCEPTION")
runner.FEATURE_MARKERS = (
 b"IPV6 PASS: TCP and UDP loopback, names and tcp6",
 b"IPV6 PASS: mapped addresses and V6ONLY",
 b"IPV6 PASS: IGMP multicast interface=1",
 b"IPV6 PASS: MLD multicast interface=1",
 b"IPV6 PASS: IGMP multicast interface=2",
 b"IPV6 PASS: MLD multicast interface=2",
 b"IPV6 PASS: physical TCP/UDP and SLAAC",
 b"IPV6 PASS: link-local interface scopes",
 b"IPV6 PASS: repeated memberships and close stay flat",
)
runner.REPORT_MARKER = b""

original_command_for = runner.command_for
def command_for(arguments, root):
    selected = Path(os.environ.get("VINIX_QEMU_RUNNER_ROOT", str(root)))
    return original_command_for(arguments, selected)
runner.command_for = command_for

def echo(kind):
    endpoint = socket.socket(socket.AF_INET6, kind)
    endpoint.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    endpoint.bind(("::1", 39066))
    if kind == socket.SOCK_STREAM: endpoint.listen(4)
    def serve():
        while True:
            if kind == socket.SOCK_DGRAM:
                data, peer = endpoint.recvfrom(65536); endpoint.sendto(data, peer)
            else:
                connection, _ = endpoint.accept()
                with connection:
                    data = connection.recv(65536)
                    connection.sendall(data)
    threading.Thread(target=serve, daemon=True).start()
    return endpoint

def check_capture(path):
    frames=runner.capture_frames(path)
    outgoing={}; incoming={}; protocols=set()
    for frame in frames:
        if len(frame)<14: continue
        if frame[12:14] == b"\x86\xdd" and len(frame)>=54:
            packet=frame[14:]; kind=packet[6]; at=40
            if kind == 0 and len(packet)>=48: kind=packet[40]; at=48
            if kind == 58 and len(packet)>at:
                counts=outgoing if frame[6:12] == runner.GUEST_MAC else incoming
                counts[packet[at]]=counts.get(packet[at],0)+1
            if frame[6:12] == runner.GUEST_MAC and kind in (6,17): protocols.add(kind)
        elif len(frame)>=34 and frame[12:14] == b"\x08\x00" and frame[23] == 2: outgoing[2]=outgoing.get(2,0)+1
    print(f"==> IPv6 packet checks: outbound ICMPv6/IGMP={outgoing}, inbound ICMPv6={incoming}, protocols={protocols}")
    problems=[]
    for kind,name in ((133,"router solicitation"),(135,"neighbor solicitation"),(131,"MLD report"),(2,"IGMP report")):
        if not outgoing.get(kind): problems.append("no outbound "+name)
    for kind,name in ((134,"router advertisement"),(136,"neighbor advertisement")):
        if not incoming.get(kind): problems.append("no inbound "+name)
    if protocols != {6,17}: problems.append("missing physical IPv6 TCP or UDP")
    return problems
runner.check_capture = check_capture
if __name__ == "__main__":
    listeners=[echo(socket.SOCK_STREAM),echo(socket.SOCK_DGRAM)]
    result=runner.main()
    capture=Path(sys.argv[sys.argv.index("--capture")+1])
    if capture.exists():
        problems=check_capture(capture)
        if os.environ.get("VINIX_TEST_CAPTURE"):
            shutil.copyfile(capture, os.environ["VINIX_TEST_CAPTURE"])
        if result == 0 and problems:
            print("Packet failures: " + "; ".join(problems)); result=1
    raise SystemExit(result)
