#!/usr/bin/env python3
"""Run an Android APK on Vinix, check a calculator or observe its real window."""
from __future__ import annotations

import argparse
import errno
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import pty
import select
import shlex
import shutil
import signal
import socket
import subprocess
import struct
import sys
import tarfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
CALCULATOR_SHA256 = "1928e65ced8cbe78be2ff3cb4c321e9e75d138e8e30ea1368fbb772a86827d1d"
FAILURES = (b"ANDROID-FAIL", b"KERNEL PANIC", b"FATAL EXCEPTION",
            b"JNI DETECTED ERROR IN APPLICATION", b"Fatal signal ")


def copy_layer(source: Path, destination: Path, inodes: dict | None = None) -> None:
    if inodes is None:
        inodes = {}
    destination.mkdir(parents=True, exist_ok=True)
    for entry in source.iterdir():
        target = destination / entry.name
        if entry.is_symlink():
            if target.exists() or target.is_symlink():
                target.unlink()
            target.symlink_to(os.readlink(entry))
        elif entry.is_dir():
            copy_layer(entry, target, inodes)
        else:
            stat = entry.stat()
            key = (stat.st_dev, stat.st_ino)
            if target.exists() or target.is_symlink():
                target.unlink()
            if stat.st_nlink > 1 and key in inodes:
                os.link(inodes[key], target)
            else:
                shutil.copy2(entry, target)
                if stat.st_nlink > 1:
                    inodes[key] = target


def needed_libraries(path: Path) -> list[str]:
    """Read DT_NEEDED from a little-endian ELF64 without executing the file."""
    with path.open("rb") as file:
        header = file.read(64)
        if len(header) < 64 or header[:6] != b"\x7fELF\x02\x01":
            return []
        phoff = struct.unpack_from("<Q", header, 32)[0]
        phsize, phcount = struct.unpack_from("<HH", header, 54)
        file.seek(phoff)
        raw = file.read(phsize * phcount)
        segments = [struct.unpack_from("<IIQQQQQQ", raw, i * phsize) for i in range(phcount)]
        dynamic = next((s for s in segments if s[0] == 2), None)
        if dynamic is None:
            return []
        file.seek(dynamic[2])
        table = file.read(dynamic[5])
        values = [struct.unpack_from("<QQ", table, i) for i in range(0, len(table) - 15, 16)]
        string_address = next((value for tag, value in values if tag == 5), None)
        string_size = next((value for tag, value in values if tag == 10), 0)
        if string_address is None:
            return []
        segment = next(s for s in segments if s[0] == 1 and s[3] <= string_address < s[3] + s[5])
        file.seek(segment[2] + string_address - segment[3])
        strings = file.read(string_size)
        return [strings[value:].split(b"\0", 1)[0].decode("ascii") for tag, value in values if tag == 1]


def supply_host_libraries(repo: Path, root: Path, base_libraries: set[str] | None = None) -> None:
    # Supply the X11 layer's inherited dependency closure, without copying the
    # developer toolchain and unrelated multi-hundred-MiB LLVM libraries.
    search = [root / "lib", root / "usr/lib", root / "usr/lib/xorg/legacy-glx"]
    sources = [repo / "build-aarch64-userland/staging/lib",
               repo / "build-aarch64-userland/staging/usr/lib",
               repo / "build-aarch64-x11/sysroot/lib", repo / "build-aarch64-x11/sysroot/usr/lib"]
    pending = [p for directory in (root / "usr/bin", root / "usr/lib", root / "opt/android-test")
               if directory.exists() for p in directory.rglob("*") if p.is_file()]
    visited = set()
    base_libraries = base_libraries or set()
    while pending:
        path = pending.pop()
        if path in visited:
            continue
        visited.add(path)
        for name in needed_libraries(path):
            if name in base_libraries:
                continue
            found = next((directory / name for directory in search if (directory / name).is_file()), None)
            if found:
                pending.append(found)
                continue
            source = next((directory / name for directory in sources if (directory / name).is_file()), None)
            if source is None:
                # Some Xorg modules deliberately share dependencies with their
                # server; the loader resolves those when the module is opened.
                continue
            target = root / "usr/lib" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            pending.append(target)


def archive_root(root: Path, destination: Path) -> None:
    # Runtime package aliases can be materialized regular files. Retain one
    # data payload per identical library; Vinix understands USTAR hardlinks.
    identities = {}
    with tarfile.open(destination, "w", format=tarfile.USTAR_FORMAT) as archive:
        for path in sorted(root.rglob("*"), key=lambda p: (len(str(p.relative_to(root))), str(p))):
            name = "./" + str(path.relative_to(root))
            info = archive.gettarinfo(str(path), arcname=name)
            if info.isreg():
                identity = None
                if info.size >= 4096 and len(name) <= 100:
                    with path.open("rb") as file:
                        digest = hashlib.sha256()
                        while chunk := file.read(1024 * 1024):
                            digest.update(chunk)
                    identity = (info.size, info.mode, digest.digest())
                if identity in identities:
                    info.type = tarfile.LNKTYPE
                    info.linkname = identities[identity]
                    info.size = 0
                    archive.addfile(info)
                else:
                    with path.open("rb") as file:
                        archive.addfile(info, file)
                    if identity is not None:
                        identities[identity] = name
            else:
                archive.addfile(info)


def prepare(args: argparse.Namespace) -> Path | None:
    overlay = args.state_dir / "overlay"
    if overlay.exists():
        shutil.rmtree(overlay)
    base_libraries = set()
    if args.initramfs is None:
        minirootfs = args.repo / "build-aarch64-userland/downloads/alpine-minirootfs-3.21.7-aarch64.tar.gz"
        overlay.mkdir(parents=True)
        with tarfile.open(minirootfs, "r:gz") as archive:
            archive.extractall(overlay)
        copy_layer(args.repo / "build-aarch64-x11/staging", overlay)
    else:
        # Exercise the base image's X11 and library combination unchanged.
        # Only dependencies absent from it may be supplied for test helpers.
        with tarfile.open(args.initramfs, "r:*") as archive:
            for member in archive:
                path = Path(member.name.lstrip("./"))
                if str(path.parent) in ("lib", "usr/lib", "usr/lib/xorg/legacy-glx"):
                    base_libraries.add(path.name)
    copy_layer(args.runtime, overlay)
    test = overlay / "opt/android-test"
    test.mkdir(parents=True, exist_ok=True)
    x11 = args.repo / "build-aarch64-x11/sysroot"
    compiler = shutil.which("aarch64-linux-musl-gcc")
    if not compiler:
        raise SystemExit("aarch64-linux-musl-gcc is required for the test helpers")
    subprocess.run([compiler, "-O2", "-Wall", "-Wextra", "-Werror", "-isystem", str(x11 / "usr/include"),
                    str(ROOT / "tests/android/x11-probe.c"), f"-L{x11}/usr/lib", f"-L{x11}/lib",
                    "-Wl,--allow-shlib-undefined", "-lXtst", "-lX11", "-lxcb",
                    "-o", str(test / "x11-probe")], check=True)
    observer_compiler = compiler
    if args.runtime_arch == "x86_64":
        observer_compiler = shutil.which("x86_64-linux-musl-gcc")
        if not observer_compiler:
            raise SystemExit("x86_64-linux-musl-gcc is required for the translated runtime observer")
    if not args.observe:
        subprocess.run([observer_compiler, "-O2", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
                        str(ROOT / "tests/android/text-observer.c"), "-ldl",
                        "-o", str(test / "text-observer.so")], check=True)
    if args.runtime_arch == "x86_64":
        subprocess.run([observer_compiler, "-O2", "-Wall", "-Wextra", "-Werror",
                        str(ROOT / "tests/android/runtime-stack-probe.c"), "-pthread",
                        "-o", str(test / "runtime-stack-probe")], check=True)
        subprocess.run([observer_compiler, "-O2", "-Wall", "-Wextra", "-Werror",
                        str(ROOT / "tests/android/memory-probe.c"),
                        "-o", str(test / "runtime-memory-probe")], check=True)
    subprocess.run([compiler, "-O2", "-Wall", "-Wextra", "-Werror", "-static",
                    str(ROOT / "tests/android/memory-probe.c"),
                    "-o", str(test / "memory-probe")], check=True)
    # Test the input bridge built with the compositor under test.
    subprocess.run([compiler, "-O2", "-w", "-D__vinix__", f"-I{x11}/usr/include",
                    str(args.repo / "build-support/xorg-server/vinix-wine-host.c"),
                    f"-L{x11}/usr/lib", f"-L{x11}/lib", "-Wl,--allow-shlib-undefined",
                    "-lXtst", "-lXdamage", "-lX11", "-lXext", "-lxcb",
                    "-o", str(overlay / "usr/bin/vinix-wine-host")], check=True)
    shutil.copy2(args.desktop, overlay / "usr/bin/vinix-desktop")
    app = overlay / "usr/bin/vinix-android-calculator"
    if app.exists() or app.is_symlink():
        app.unlink()
    app.symlink_to("vinix-desktop")
    icons = overlay / "usr/share/vinix/icons"
    icons.mkdir(parents=True, exist_ok=True)
    for icon in (args.repo / "desktop/assets").glob("*.qoi"):
        shutil.copy2(icon, icons / icon.name)
    apk = overlay / "opt/android-test/application.apk"
    shutil.copy2(args.apk, apk)
    configuration = {
        "TEST_APK": "/opt/android-test/application.apk", "TEST_MODE": args.mode,
        "TEST_INPUT": args.input, "TEST_KEYS": args.keys, "TEST_TITLE": args.title,
        "TEST_TIMEOUT": str(args.startup_timeout), "VINIX_ANDROID_EXPECTED_RESULT": args.expect,
        "TEST_RUNTIME_ARCH": args.runtime_arch, "TEST_STRACE": "1" if args.strace else "0",
        "TEST_FOCUS_X": str(args.focus[0]), "TEST_FOCUS_Y": str(args.focus[1]),
        "TEST_WAIT_FOR_RESUME": "1" if hashlib.sha256(args.apk.read_bytes()).hexdigest() == CALCULATOR_SHA256 else "0",
        "TEST_OBSERVE": "1" if args.observe else "0",
        "TEST_OBSERVATION_SECONDS": str(args.observation_seconds),
    }
    (test / "config.sh").write_text("".join(f"{key}={shlex.quote(value)}\n" for key, value in configuration.items()))
    (test / "launch").write_text(
        "#!/bin/sh\n. /opt/android-test/config.sh\n"
        "export VINIX_ANDROID_EXPECTED_RESULT\n"
        "[ \"$TEST_STRACE\" = 0 ] || export QEMU_STRACE=1\n"
        + ("export VINIX_ANDROID_TEST_PRELOAD=/opt/android-test/text-observer.so\n" if not args.observe else "")
        + ("export LD_PRELOAD=\"$VINIX_ANDROID_TEST_PRELOAD\"\n" if args.runtime_arch == "aarch64" and not args.observe else "")
        +
        f"exec /usr/bin/run-android \"$TEST_APK\" -l {shlex.quote(args.activity)} -w 480 -h 640\n")
    (test / "launch").chmod(0o755)
    launcher = overlay / "usr/bin/run-android-calculator"
    if launcher.exists() or launcher.is_symlink():
        launcher.unlink()
    # A later initramfs module can replace a regular base file with another
    # regular file, but a symlink entry leaves the base launcher in place.
    launcher.write_text("#!/bin/sh\nexec /opt/android-test/launch \"$@\"\n")
    launcher.chmod(0o755)
    supply_host_libraries(args.repo, overlay, base_libraries)
    if args.initramfs is None:
        for directory in ("sbin", "proc", "dev", "sys", "tmp", "root", "run"):
            (overlay / directory).mkdir(parents=True, exist_ok=True)
        init = overlay / "sbin/init"
        if init.exists() or init.is_symlink():
            init.unlink()
        shutil.copy2(ROOT / "tests/android/guest-init.sh", init)
        args.initramfs = args.state_dir / "initramfs.tar"
        archive_root(overlay, args.initramfs)
        return None
    return overlay


def qmp(socket_path: Path, name: str, **arguments):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(20)
        connection.connect(str(socket_path))
        with connection.makefile("rw", encoding="utf-8") as stream:
            stream.readline()
            for command in ({"execute": "qmp_capabilities"}, {"execute": name, "arguments": arguments}):
                stream.write(json.dumps(command) + "\n")
                stream.flush()
                while True:
                    line = stream.readline()
                    if not line:
                        raise RuntimeError("QMP disconnected")
                    reply = json.loads(line)
                    if "error" in reply:
                        raise RuntimeError(reply["error"])
                    if "return" in reply:
                        break
            return reply["return"]


def keyboard(socket_path: Path, text: str, observed_input) -> int:
    spec = importlib.util.spec_from_file_location("vinix_input", ROOT / "desktop/tools/input.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    retries = 0
    for index, character in enumerate(text):
        events = module.key_events(character)
        if events is None:
            raise ValueError(f"QMP cannot type {character!r}")
        previous, expected = text[:index], text[:index + 1]
        for attempt in range(3):
            if attempt:
                retries += 1
            # Finish every down/up edge before observing or retrying a key.
            for event in events:
                qmp(socket_path, "input-send-event", events=[event])
                time.sleep(0.35)
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                actual = observed_input()
                if actual == expected:
                    break
                if actual != previous:
                    raise RuntimeError(f"APK input became {actual!r}; expected {expected!r}")
                time.sleep(0.1)
            if actual == expected:
                break
            if attempt == 2:
                raise RuntimeError(f"APK did not acknowledge {character!r}; input remains {actual!r}")
    return retries


def click(socket_path: Path, x: int, y: int) -> None:
    # The isolated desktop uses the runner's standard 1024x768 ramfb.
    events = [{"type": "abs", "data": {"axis": axis, "value": round(value * 32767 / extent)}}
              for axis, value, extent in (("x", x, 1023), ("y", y, 767))]
    qmp(socket_path, "input-send-event", events=events)
    time.sleep(0.2)
    for down in (True, False):
        qmp(socket_path, "input-send-event", events=[{"type": "btn", "data": {"down": down, "button": "left"}}])
        time.sleep(0.35)
    time.sleep(3)


def screenshot(socket_path: Path, destination: Path) -> None:
    from PIL import Image
    ppm = destination.with_suffix(".ppm")
    qmp(socket_path, "screendump", filename=str(ppm))
    with Image.open(ppm) as image:
        image.save(destination)
    ppm.unlink()


def stop_vm(pid: int, master: int) -> None:
    try:
        os.write(master, b"\x01x")
    except OSError:
        pass
    for sig, duration in ((None, 3), (signal.SIGTERM, 3), (signal.SIGKILL, 1)):
        if sig is not None:
            try:
                os.killpg(pid, sig)
            except (ProcessLookupError, PermissionError):
                try:
                    os.kill(pid, sig)
                except (ProcessLookupError, PermissionError):
                    pass
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            try:
                if os.waitpid(pid, os.WNOHANG)[0] == pid:
                    return
            except ChildProcessError:
                return
            time.sleep(0.1)


def run(args: argparse.Namespace, overlay: Path | None) -> int:
    state = args.state_dir
    socket_path = state / "qmp.sock"
    if socket_path.exists():
        raise SystemExit(f"QMP socket already exists: {socket_path}; choose another --state-dir")
    # A private snapshot also keeps concurrent kernel rebuilds out of this boot.
    snapshot = state / "kernel/bin"
    snapshot.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.kernel_dir / "bin/vinix", snapshot / "vinix")
    boot_payload = args.initramfs.stat().st_size
    if overlay is not None:
        boot_payload += sum(path.stat().st_size for path in overlay.rglob("*")
                            if path.is_file() and not path.is_symlink())
    # The runner materializes overlay hardlinks. Leave space for its tar,
    # the kernel and EFI files even when testing a complete desktop image.
    boot_size_mb = max(4096, ((boot_payload // (1024 * 1024) + 256 + 511) // 512) * 512)
    environment = os.environ.copy()
    environment.update({
        "VINIX_KERNEL_DIR": str(snapshot.parent), "VINIX_INITRAMFS": str(args.initramfs),
        "VINIX_INITRAMFS_COMPRESSED": "1" if args.initramfs.suffix == ".gz" else "0",
        "VINIX_QEMU_ROOT_DISK": "0",
        "VINIX_BOOT_DISK": str(state / "boot.img"), "VINIX_EFIVARS": str(state / "efivars.fd"),
        "VINIX_BOOT_DISK_SIZE_MB": str(boot_size_mb), "VINIX_QEMU_PACKAGE_STORE": str(state / "packages.tar"),
        "VINIX_QEMU_PACKAGE_PERSIST": "0", "VINIX_QEMU_HOST_SOURCE": "0",
        "VINIX_KEEP_TEMP_BOOT_DISK": "1", "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": str(args.cpus),
        "VINIX_QEMU_EXTRA": f"-qmp unix:{socket_path},server=on,wait=off",
    })
    if overlay is not None:
        environment["VINIX_QEMU_OVERLAY"] = str(overlay)
    else:
        environment.pop("VINIX_QEMU_OVERLAY", None)
    if platform.system() != "Darwin":
        environment["USE_TCG"] = "1"
    command = [str(args.repo / "run-aarch64.sh"), "--no-build", "--no-persist", "--serial",
               f"--mem={args.memory}", f"--guest-init={ROOT / 'tests/android/guest-init.sh'}"]
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(args.repo)
        os.execve(command[0], command, environment)
    transcript = bytearray()
    passed = False
    observed = False
    guest_failed = False
    typed = False
    input_thread = None
    input_errors = []
    input_retries = []
    serial_errors = []
    reader_stop = threading.Event()
    failure = "timeout"
    deadline = time.monotonic() + args.timeout

    def read_serial() -> None:
        try:
            with (state / "serial.log").open("wb") as log:
                while not reader_stop.is_set():
                    if not select.select([master], [], [], 0.1)[0]:
                        continue
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
                    if not chunk:
                        break
                    transcript.extend(chunk)
                    log.write(chunk)
                    log.flush()
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.buffer.flush()
        except OSError as error:
            serial_errors.append(str(error))

    def send_input() -> None:
        try:
            time.sleep(3)
            screenshot(socket_path, state / "ready.png")
            click(socket_path, *args.click)
            def observed_input() -> str:
                lines = bytes(transcript[-262144:]).replace(b"\r", b"").split(b"\n")[:-1]
                for line in reversed(lines):
                    if line.startswith(b"ANDROID-INPUT "):
                        return line[len(b"ANDROID-INPUT "):].decode("utf-8")
                return ""
            input_retries.append(keyboard(socket_path, args.keys, observed_input))
        except Exception as error:
            input_errors.append(str(error))

    # Serial must remain readable during QMP calls, settling and shutdown:
    # a full pipe blocks QEMU's monitor as well as its console output.
    reader = threading.Thread(target=read_serial, daemon=True)
    reader.start()
    try:
        while time.monotonic() < deadline:
            if os.waitpid(pid, os.WNOHANG)[0] == pid:
                failure = "VM exited before passing"
                break
            time.sleep(0.1)
            recent = bytes(transcript[-262144:])
            if b"ANDROID-READY" in recent and args.input == "qmp" and not args.observe and not typed:
                typed = True
                input_thread = threading.Thread(target=send_input, daemon=True)
                input_thread.start()
            if input_errors or serial_errors:
                guest_failed = True
                failure = f"host I/O failed: {(input_errors or serial_errors)[0]}"
                break
            if any(marker in recent for marker in FAILURES):
                guest_failed = True
                failure = "guest reported a failure"
                # Allow the diagnostic tail to reach the serial transcript.
                deadline = min(deadline, time.monotonic() + 4)
            if b"ANDROID-PASS" in recent and not guest_failed:
                passed = True
                time.sleep(2)
                break
            if b"ANDROID-OBSERVED" in recent and args.observe and not guest_failed:
                observed = True
                time.sleep(2)
                break
        if input_thread:
            input_thread.join(timeout=25)
            if input_thread.is_alive() or input_errors:
                passed = False
                failure = f"keyboard input failed: {input_errors[0] if input_errors else 'timeout'}"
    finally:
        try:
            if socket_path.exists():
                try:
                    screenshot(socket_path, args.screenshot)
                except (OSError, RuntimeError, ImportError) as error:
                    print(f"Screenshot failed: {error}", file=sys.stderr)
                    passed = False
                    observed = False
                    failure = "screenshot failed"
            else:
                passed = False
                observed = False
                failure = "VM did not expose QMP"
        finally:
            stop_vm(pid, master)
            reader_stop.set()
            reader.join(timeout=2)
            os.close(master)
            socket_path.unlink(missing_ok=True)
    result = {"passed": None if args.observe and observed else passed,
              "observed": observed, "check": "window-observation" if args.observe else "calculator",
              "failure": None if passed or observed else failure,
              "mode": args.mode, "apk": str(args.apk),
              "apk_sha256": hashlib.sha256(args.apk.read_bytes()).hexdigest(),
              "initramfs": str(args.initramfs), "runtime_arch": args.runtime_arch,
              "memory_mb": args.memory, "desktop": str(args.desktop), "kernel_dir": str(args.kernel_dir),
              "keys": None if args.observe else args.keys,
              "expected": None if args.observe else args.expect, "screenshot": str(args.screenshot),
              "key_retries": input_retries[0] if input_retries else None,
              "serial_log": str(state / "serial.log")}
    (state / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    if not passed and not observed:
        print(f"Android smoke test failed ({failure}); inspect {state / 'serial.log'}", file=sys.stderr)
        return 1
    if observed:
        print(f"Observed the APK's painted window; application functionality was not checked. Screenshot: {args.screenshot}")
    else:
        print(f"Android calculator displayed {args.expect}; screenshot: {args.screenshot}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--runtime-arch", choices=("aarch64", "x86_64"), help="defaults to the staged runtime's architecture marker")
    parser.add_argument("--desktop", type=Path)
    parser.add_argument("--kernel-dir", type=Path)
    parser.add_argument("--initramfs", type=Path)
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--activity", default="calculator/Calculator")
    parser.add_argument("--title", default="", help="optional substring of the real X11 APK window title")
    parser.add_argument("--mode", choices=("desktop", "direct"), default="desktop")
    parser.add_argument("--input", choices=("qmp", "xtest"))
    parser.add_argument("--keys", default="123+456")
    parser.add_argument("--click", type=int, nargs=2, default=(360, 202), metavar=("X", "Y"),
                        help="desktop screen point to click in the APK input field")
    parser.add_argument("--focus", type=int, nargs=2, default=(240, 120), metavar=("X", "Y"),
                        help="APK window point clicked by the direct XTEST input")
    parser.add_argument("--expect", default="579")
    parser.add_argument("--state-dir", type=Path, default=ROOT / "build/android-smoke")
    parser.add_argument("--screenshot", type=Path)
    parser.add_argument("--memory", type=int, default=8192)
    parser.add_argument("--cpus", type=int, default=4)
    parser.add_argument("--startup-timeout", type=int, default=240)
    parser.add_argument("--timeout", type=int, default=420)
    parser.add_argument("--prepare-only", action="store_true", help="assemble and cross-build the test image without booting")
    parser.add_argument("--strace", action="store_true", help="trace translated runtime syscalls for bring-up diagnostics")
    parser.add_argument("--observe", action="store_true",
                        help="capture a generic APK window and logs without input or a functional pass claim")
    parser.add_argument("--observation-seconds", type=int, default=30,
                        help="seconds a generic APK's painted window must remain visible (default: 30)")
    args = parser.parse_args()
    if args.observation_seconds < 1:
        parser.error("--observation-seconds must be positive")
    if not args.prepare_only:
        try:
            import PIL
        except ImportError:
            raise SystemExit("Python Pillow is required to save the APK screenshot")
    args.repo = args.repo.resolve()
    args.state_dir = args.state_dir.resolve()
    args.runtime = (args.runtime or args.repo / "build-aarch64-android/x86_64/staging").resolve()
    if args.runtime_arch is None:
        architectures = {marker.read_text().strip() for marker in args.runtime.glob("opt/vinix-android*/architecture")}
        args.runtime_arch = "x86_64" if "x86_64" in architectures else "aarch64"
    args.desktop = (args.desktop or args.repo / "build/vinix-desktop").resolve()
    args.kernel_dir = (args.kernel_dir or args.repo / "kernel").resolve()
    args.initramfs = args.initramfs.resolve() if args.initramfs else None
    args.apk = (args.apk or args.runtime / "usr/share/vinix/android/Arity-1.1.apk").resolve()
    args.screenshot = (args.screenshot or args.state_dir / ("application.png" if args.observe else "calculator.png")).resolve()
    args.input = args.input or ("xtest" if args.mode == "direct" else "qmp")
    base = args.initramfs or args.repo / "build-aarch64-userland/downloads/alpine-minirootfs-3.21.7-aarch64.tar.gz"
    for path in (args.runtime / "usr/bin/run-android", args.desktop, args.kernel_dir / "bin/vinix", base, args.apk):
        if not path.is_file():
            raise SystemExit(f"Missing Android smoke test input: {path}")
    args.state_dir.mkdir(parents=True, exist_ok=True)
    args.screenshot.parent.mkdir(parents=True, exist_ok=True)
    overlay = prepare(args)
    if args.prepare_only:
        print(f"Prepared Android smoke image: {args.initramfs or overlay}")
        return 0
    return run(args, overlay)


if __name__ == "__main__":
    raise SystemExit(main())
