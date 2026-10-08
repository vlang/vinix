# SPDX-License-Identifier: GPL-2.0-or-later
"""Stdlib process/filesystem primitives for the native guest workflow."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tarfile
import threading

_binding_path = Path(__file__).resolve().parents[1] / "agx-fake-g17/_native.py"
_spec = importlib.util.spec_from_file_location("vinix_guest_primitives", _binding_path)
_binding = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_binding)


def wire(value):
    return os.fsencode(value).hex()


def text(value):
    return os.fsdecode(bytes.fromhex(value))


def workflow(root, args, namespace):
    errors = []
    log = process = None
    retired = False
    pending_interrupt = False
    previous = None

    def mask():
        nonlocal previous
        if previous is None and threading.current_thread() is threading.main_thread():
            previous = signal.signal(signal.SIGINT, signal.SIG_IGN)

    def primitive(method, row):
        nonlocal log, process, retired
        if method == "metadata": return {name: namespace[name] for name in ("MARKERS", "MMAP_LEASE_MARKER", "TOPOLOGY_MARKER")}
        if method == "path": return wire(Path(text(row["path"])))
        if method == "join": return wire(Path(text(row["base"])) / row["name"])
        if method == "resolve": return wire(Path(text(row["path"])).resolve())
        if method == "parent_parent": return wire(Path(text(row["path"])).parent.parent)
        if method == "mkdir": return Path(text(row["path"])).mkdir(parents=row["parents"], exist_ok=row["exist_ok"])
        if method == "contains": return row["needle"] in row["haystack"]
        if method == "which": return shutil.which(row["name"])
        if method == "exists": return Path(text(row["path"])).exists()
        if method == "read_text": return Path(text(row["path"])).read_text(errors="replace")
        if method == "copytree":
            shutil.copytree(Path(text(row["source"])), Path(text(row["destination"])))
            return None
        if method == "archive":
            with tarfile.open(Path(text(row["path"])), "w", format=tarfile.USTAR_FORMAT) as archive:
                archive.add(Path(text(row["rootfs"])), arcname=".")
            return None
        if method == "run":
            environment = None if row["environment"] is None else {text(k): text(v) for k, v in row["environment"]}
            subprocess.run([text(item) for item in row["argv"]], env=environment, check=True,
                           stdout=subprocess.DEVNULL if row["quiet"] else None)
            return None
        if method == "start":
            log = Path(text(row["log"])).open("wb")
            process = subprocess.Popen([text(item) for item in row["argv"]], stdout=log, stderr=log)
            return None
        if method == "poll":
            result = process.poll()
            if result is not None: retired = True
            return result
        if method == "terminate": return process.terminate()
        if method == "kill": return process.kill()
        if method == "wait":
            result = process.wait(timeout=row["timeout"])
            retired = True
            return result
        if method == "retiring":
            mask()
            return None
        if method == "print":
            for line in row["lines"]: print(text(line))
            return None
        raise RuntimeError("unknown guest primitive: " + method)

    fields = {"root": wire(root), "python": wire(sys.executable),
              "environment": b"\0".join(os.fsencode(k) + b"=" + os.fsencode(v) for k, v in os.environ.items()).hex(),
              "timeout_text": str(args.timeout)}
    for name in ("kernel", "state_dir", "firmware", "limine_dir"):
        value = getattr(args, name)
        fields[name] = wire(value) if value is not None else None
    for name in ("qemu", "cc", "cpu", "no_linuxkpi", "mmap_lease_test", "pci_topology_test"):
        fields[name] = getattr(args, name)
    child = subprocess.Popen([str(_binding.controller()), "--linux-guest-callback"],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=os.environ)
    try:
        child.stdin.write(json.dumps(fields) + "\n")
        child.stdin.flush()
        while True:
            try:
                line = child.stdout.readline()
            except KeyboardInterrupt:
                pending_interrupt = True
                mask()
                continue
            if not line:
                raise RuntimeError("native guest workflow ended before returning a result")
            value = json.loads(line)
            if "callback" not in value:
                if pending_interrupt: raise KeyboardInterrupt()
                if "error" not in value: return value["value"]
                error = value["error"]
                if "binding_error" in error: raise errors[error["binding_error"]]
                raise RuntimeError(text(error["message_hex"]))
            try:
                if pending_interrupt:
                    pending_interrupt = False
                    raise KeyboardInterrupt()
                reply = {"value": primitive(value["callback"], value["arguments"])}
            except BaseException as error:
                if isinstance(error, KeyboardInterrupt): mask()
                errors.append(error)
                reply = {"error": {"binding_error": len(errors) - 1, "binding_kind": type(error).__name__}}
            child.stdin.write(json.dumps(reply) + "\n")
            child.stdin.flush()
    finally:
        mask()
        try:
            try:
                child.stdin.close()
            finally:
                try:
                    try:
                        child.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait()
                    except BaseException:
                        child.kill()
                        child.wait()
                        raise
                finally:
                    child.stdout.close()
        finally:
            try:
                # Emergency ownership recovery if the controller itself exits.
                if process is not None and not retired and process.poll() is None:
                    process.kill()
                    process.wait()
            finally:
                try:
                    if log is not None: log.close()
                finally:
                    if previous is not None: signal.signal(signal.SIGINT, previous)
