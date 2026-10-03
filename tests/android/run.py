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
    if args.launcher == "roblox":
        spec = importlib.util.spec_from_file_location("vinix_roblox_builder", ROOT / "build-support/roblox/build.py")
        assert spec and spec.loader
        roblox = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(roblox)
        roblox.validate_stage(args.roblox_staging, args.runtime)
        copy_layer(args.roblox_staging, overlay)
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
    subprocess.run([observer_compiler, "-O2", "-Wall", "-Wextra", "-Werror",
                    str(ROOT / "tests/android/runtime-stack-probe.c"), "-pthread",
                    "-o", str(test / "runtime-stack-probe")], check=True)
    subprocess.run([observer_compiler, "-O2", "-Wall", "-Wextra", "-Werror",
                    str(ROOT / "tests/android/memory-probe.c"),
                    "-o", str(test / "runtime-memory-probe")], check=True)
    if args.runtime_arch == "aarch64":
        subprocess.run([compiler, "-O2", "-Wall", "-Wextra", "-Werror",
                        str(ROOT / "tests/android/atfork-test.c"), "-ldl", "-pthread",
                        "-o", str(test / "runtime-atfork-probe")], check=True)
    if args.runtime_arch == "aarch64":
        subprocess.run([compiler, "-O2", "-Wall", "-Wextra", "-Werror",
                        str(ROOT / "tests/android/fortify-test.c"), "-ldl",
                        "-o", str(test / "runtime-fortify-probe")], check=True)
        subprocess.run([compiler, "-O2", "-Wall", "-Wextra", "-Werror",
                        "-I" + str(ROOT / "build-support/android"),
                        str(ROOT / "tests/android/mallinfo-test.c"), "-ldl", "-pthread",
                        "-o", str(test / "runtime-mallinfo-probe")], check=True)
    if args.runtime_arch == "aarch64":
        subprocess.run([compiler, "-O2", "-Wall", "-Wextra", "-Werror",
                        "-I" + str(ROOT / "build-support/android"),
                        str(ROOT / "tests/android/netdb-test.c"), "-ldl",
                        "-o", str(test / "runtime-netdb-probe")], check=True)
    if args.loader_probe:
        loader_test = test / "loader"
        loader_test.mkdir()
        args.loader_probe_sha256 = {}
        for name in ("loader-test", "packed-relocation-probe.so"):
            shutil.copy2(args.loader_probe / name, loader_test / name)
            args.loader_probe_sha256[name] = hashlib.sha256((loader_test / name).read_bytes()).hexdigest()
    subprocess.run([compiler, "-O2", "-Wall", "-Wextra", "-Werror", "-static",
                    str(ROOT / "tests/android/memory-probe.c"),
                    "-o", str(test / "memory-probe")], check=True)
    # Test the input bridge built with the compositor under test.
    subprocess.run([compiler, "-O2", "-w", "-D__vinix__", f"-I{x11}/usr/include",
                    str(ROOT / "build-support/xorg-server/vinix-wine-host.c"),
                    f"-L{x11}/usr/lib", f"-L{x11}/lib", "-Wl,--allow-shlib-undefined",
                    "-lXtst", "-lXdamage", "-lX11", "-lXext", "-lxcb",
                    "-o", str(overlay / "usr/bin/vinix-wine-host")], check=True)
    shutil.copy2(args.desktop, overlay / "usr/bin/vinix-desktop")
    app = overlay / "usr/bin" / ("vinix-roblox" if args.launcher == "roblox" else "vinix-android-calculator")
    if app.exists() or app.is_symlink():
        app.unlink()
    app.symlink_to("vinix-desktop")
    icons = overlay / "usr/share/vinix/icons"
    icons.mkdir(parents=True, exist_ok=True)
    for icon in (args.repo / "desktop/assets").glob("*.qoi"):
        shutil.copy2(icon, icons / icon.name)
    apk = overlay / "opt/android-test/application.apk"
    shutil.copy2(args.apk, apk)
    if args.layout_probe:
        shutil.copy2(args.layout_probe, test / "android-layout-focus-probe.jar")
        args.layout_probe_sha256 = hashlib.sha256((test / "android-layout-focus-probe.jar").read_bytes()).hexdigest()
    if args.pointer_probe:
        shutil.copy2(args.pointer_probe, test / "android-pointer-capture-probe.jar")
        args.pointer_probe_sha256 = hashlib.sha256((test / "android-pointer-capture-probe.jar").read_bytes()).hexdigest()
    if args.lifecycle_probe:
        shutil.copy2(args.lifecycle_probe, test / "android-activity-lifecycle-probe.apk")
        args.lifecycle_probe_sha256 = hashlib.sha256((test / "android-activity-lifecycle-probe.apk").read_bytes()).hexdigest()
    if args.cookie_probe:
        shutil.copy2(args.cookie_probe, test / "android-cookie-probe.apk")
        args.cookie_probe_sha256 = hashlib.sha256((test / "android-cookie-probe.apk").read_bytes()).hexdigest()
    if args.egl_probe:
        shutil.copy2(args.egl_probe, test / "egl-interop-test")
        (test / "egl-interop-test").chmod(0o755)
        args.egl_probe_sha256 = hashlib.sha256((test / "egl-interop-test").read_bytes()).hexdigest()
    if args.tls_probe:
        shutil.copy2(args.tls_probe, test / "android-tls-probe.jar")
        args.tls_probe_sha256 = hashlib.sha256((test / "android-tls-probe.jar").read_bytes()).hexdigest()
    if args.boot_probe:
        shutil.copy2(args.boot_probe, test / "art-boot-probe.jar")
        args.boot_probe_sha256 = hashlib.sha256((test / "art-boot-probe.jar").read_bytes()).hexdigest()
    configuration = {
        "TEST_APK": "/opt/android-test/application.apk", "TEST_MODE": args.mode,
        "TEST_DESKTOP_APP": "Roblox" if args.launcher == "roblox" else "Android Calculator",
        "TEST_HOSTED_NAME": "roblox" if args.launcher == "roblox" and args.mode == "desktop" else "android",
        "TEST_GEOMETRY": "1280x720x24" if args.launcher == "roblox" else "480x640x24",
        "VINIX_ROBLOX_APK": "/opt/android-test/application.apk",
        "VINIX_ANDROID_LINKER_DIAGNOSTICS": "1" if args.linker_diagnostics else "0",
        "TEST_BIONIC_LOADER_PROBE": "/opt/android-test/loader" if args.loader_probe else "",
        "TEST_LAYOUT_PROBE": "/opt/android-test/android-layout-focus-probe.jar" if args.layout_probe else "",
        "TEST_POINTER_PROBE": "/opt/android-test/android-pointer-capture-probe.jar" if args.pointer_probe else "",
        "TEST_LIFECYCLE_PROBE": "/opt/android-test/android-activity-lifecycle-probe.apk" if args.lifecycle_probe else "",
        "TEST_COOKIE_PROBE": "/opt/android-test/android-cookie-probe.apk" if args.cookie_probe else "",
        "TEST_EGL_PROBE": "/opt/android-test/egl-interop-test" if args.egl_probe else "",
        "TEST_TLS_PROBE": "/opt/android-test/android-tls-probe.jar" if args.tls_probe else "",
        "TEST_ART_BOOT_PROBE": "/opt/android-test/art-boot-probe.jar" if args.boot_probe else "",
        "TEST_INPUT": args.input, "TEST_KEYS": args.keys, "TEST_TITLE": args.title,
        "TEST_TIMEOUT": str(args.startup_timeout), "VINIX_ANDROID_EXPECTED_RESULT": args.expect,
        "TEST_RUNTIME_ARCH": args.runtime_arch, "TEST_STRACE": "1" if args.strace else "0",
        "TEST_FOCUS_X": str(args.focus[0]), "TEST_FOCUS_Y": str(args.focus[1]),
        "TEST_WAIT_FOR_RESUME": "1" if hashlib.sha256(args.apk.read_bytes()).hexdigest() == CALCULATOR_SHA256 else "0",
        "TEST_OBSERVE": "1" if args.observe else "0",
        "TEST_INTERACTIVE": "1" if args.interactive else "0",
        "TEST_OBSERVATION_SECONDS": str(args.observation_seconds),
    }
    (test / "config.sh").write_text("".join(f"{key}={shlex.quote(value)}\n" for key, value in configuration.items()))
    if args.lifecycle_probe:
        (test / "lifecycle-launch").write_text(
            "#!/bin/sh\n. /opt/android-test/config.sh\n"
            '/usr/bin/run-android "$TEST_LIFECYCLE_PROBE" '
            "-l 'android/app/AndroidActivityLifecycleProbe$BootstrapActivity' -w 128 -h 128 "
            '-X "-Djava.class.path=/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar:'
            '/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk:$TEST_LIFECYCLE_PROBE"\n'
            'lifecycle_status=$?\nprintf \'%s\\n\' "$lifecycle_status" >/tmp/android-lifecycle-status\n'
            'exit "$lifecycle_status"\n')
        (test / "lifecycle-launch").chmod(0o755)
    if args.cookie_probe:
        for phase, activity in (("cookie", "BootstrapActivity"), ("cookie-reload", "PersistenceActivity")):
            launcher = test / f"{phase}-launch"
            launcher.write_text(
                "#!/bin/sh\n. /opt/android-test/config.sh\n"
                '/usr/bin/run-android "$TEST_COOKIE_PROBE" '
                f"-l 'org/vinix/tests/AndroidCookieProbe${activity}' -w 128 -h 128\n"
                f'cookie_status=$?\nprintf \'%s\\n\' "$cookie_status" >/tmp/android-{phase}-status\n'
                'exit "$cookie_status"\n')
            launcher.chmod(0o755)
    (test / "launch").write_text(
        "#!/bin/sh\n. /opt/android-test/config.sh\n"
        "export VINIX_ANDROID_EXPECTED_RESULT\n"
        "[ \"$TEST_STRACE\" = 0 ] || export QEMU_STRACE=1\n"
        + ("export VINIX_ANDROID_TEST_PRELOAD=/opt/android-test/text-observer.so\n" if not args.observe else "")
        + ("export LD_PRELOAD=\"$VINIX_ANDROID_TEST_PRELOAD\"\n" if args.runtime_arch == "aarch64" and not args.observe else "")
        +
        (f'exec /usr/bin/run-android "$TEST_APK" -l {shlex.quote(args.activity)} -w 480 -h 640'
         if args.launcher == "android" else 'exec /usr/bin/run-roblox "$TEST_APK"')
        + "".join(" " + shlex.quote(argument) for argument in args.runtime_arg) + "\n")
    (test / "launch").chmod(0o755)
    if args.launcher == "android":
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
    elif args.interactive:
        environment["QEMU_DISPLAY_BACKEND"] = "cocoa"
    command = [str(args.repo / "run-aarch64.sh"), "--no-build", "--no-persist",
               f"--mem={args.memory}", f"--guest-init={ROOT / 'tests/android/guest-init.sh'}"]
    if not args.interactive:
        command.append("--serial")
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
    deadline = float("inf") if args.interactive else time.monotonic() + args.timeout

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
                failure = "VM exited before observing a window" if args.interactive else "VM exited before passing"
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
                if args.interactive:
                    observed = False
                else:
                    # Allow the diagnostic tail to reach the serial transcript.
                    deadline = min(deadline, time.monotonic() + 4)
            if args.interactive and b"ANDROID-READY" in recent and not observed and not guest_failed:
                observed = True
                print("Interactive APK window ready; application functionality is unchecked. "
                      "Use the QEMU window locally; Ctrl-C stops the session.", flush=True)
            if not args.interactive and b"ANDROID-PASS" in recent and not guest_failed:
                passed = True
                time.sleep(2)
                break
            if not args.interactive and b"ANDROID-OBSERVED" in recent and args.observe and not guest_failed:
                observed = True
                time.sleep(2)
                break
        if input_thread:
            input_thread.join(timeout=25)
            if input_thread.is_alive() or input_errors:
                passed = False
                failure = f"keyboard input failed: {input_errors[0] if input_errors else 'timeout'}"
    except KeyboardInterrupt:
        if not args.interactive:
            raise
        if not observed and not guest_failed:
            failure = "interactive session stopped before observing a window"
    finally:
        try:
            if args.interactive:
                # Login and account screens belong to the local user. Capture
                # only through an explicit external QMP request, never here.
                pass
            elif socket_path.exists():
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
    boot_probe_passed = None
    loader_probe_passed = None
    tls_probe_passed = None
    layout_probe_passed = None
    pointer_probe_passed = None
    lifecycle_probe_passed = None
    cookie_probe_passed = None
    egl_probe_passed = None
    guest_failures = [line.split(b"ANDROID-FAIL ", 1)[1].strip().decode(errors="replace")
                      for line in bytes(transcript).replace(b"\r", b"").splitlines()
                      if b"ANDROID-FAIL " in line]
    if guest_failures and not passed and not observed:
        failure = guest_failures[0]
    if args.boot_probe:
        boot_probe_passed = any(line == b"ANDROID-BOOTCLASSPATH-VERIFIED"
                                for line in bytes(transcript).replace(b"\r", b"").splitlines())
        if not boot_probe_passed:
            if passed or observed:
                failure = "native Java bootclasspath probe did not pass"
            passed = observed = False
    if args.loader_probe:
        loader_probe_passed = b"ANDROID-BIONIC-LOADER-VERIFIED" in transcript
        if not loader_probe_passed:
            if passed or observed:
                failure = "native Bionic nested loader probe did not pass"
            passed = observed = False
    if args.tls_probe:
        tls_probe_passed = b"ANDROID-TLS-VERIFIED" in transcript
        if not tls_probe_passed:
            if passed or observed:
                failure = "native Java HTTPS trust probe did not pass"
            passed = observed = False
    if args.layout_probe:
        layout_probe_passed = b"ANDROID-LAYOUT-FOCUS-VERIFIED" in transcript
        if not layout_probe_passed:
            if passed or observed:
                failure = "native framework layout focus probe did not pass"
            passed = observed = False
    if args.pointer_probe:
        pointer_probe_passed = b"ANDROID-POINTER-CAPTURE-VERIFIED" in transcript
        if not pointer_probe_passed:
            if passed or observed:
                failure = "native framework pointer capture probe did not pass"
            passed = observed = False
    if args.lifecycle_probe:
        lifecycle_probe_passed = b"ANDROID-ACTIVITY-LIFECYCLE-VERIFIED" in transcript
        if not lifecycle_probe_passed:
            if passed or observed:
                failure = "native framework activity lifecycle probe did not pass"
            passed = observed = False
    if args.egl_probe:
        egl_probe_passed = b"ANDROID-EGL-VERIFIED" in transcript
        if not egl_probe_passed:
            if passed or observed:
                failure = "native EGL and GTK texture probe did not pass"
            passed = observed = False
    if args.cookie_probe:
        cookie_probe_passed = b"ANDROID-COOKIE-VERIFIED" in transcript
        if not cookie_probe_passed:
            if passed or observed:
                failure = "native framework cookie probe did not pass"
            passed = observed = False
    result = {"passed": None if args.interactive or (args.observe and observed) else passed,
              "observed": observed,
              "check": ("interactive-observation" if args.interactive else
                        "window-observation" if args.observe else "calculator"),
              "failure": None if passed or observed else failure,
              "mode": args.mode, "launcher": args.launcher, "apk": str(args.apk),
              "apk_sha256": hashlib.sha256(args.apk.read_bytes()).hexdigest(),
              "initramfs": str(args.initramfs), "runtime_arch": args.runtime_arch,
              "memory_mb": args.memory, "desktop": str(args.desktop), "kernel_dir": str(args.kernel_dir),
              "keys": None if args.observe else args.keys,
              "expected": None if args.observe else args.expect,
              "screenshot": None if args.interactive else str(args.screenshot),
              "key_retries": input_retries[0] if input_retries else None,
              "runtime_arguments": args.runtime_arg,
              "layout_probe": str(args.layout_probe) if args.layout_probe else None,
              "layout_probe_sha256": args.layout_probe_sha256 if args.layout_probe else None,
              "layout_probe_passed": layout_probe_passed,
              "pointer_probe": str(args.pointer_probe) if args.pointer_probe else None,
              "pointer_probe_sha256": args.pointer_probe_sha256 if args.pointer_probe else None,
              "pointer_probe_passed": pointer_probe_passed,
              "lifecycle_probe": str(args.lifecycle_probe) if args.lifecycle_probe else None,
              "lifecycle_probe_sha256": args.lifecycle_probe_sha256 if args.lifecycle_probe else None,
              "lifecycle_probe_passed": lifecycle_probe_passed,
              "cookie_probe": str(args.cookie_probe) if args.cookie_probe else None,
              "cookie_probe_sha256": args.cookie_probe_sha256 if args.cookie_probe else None,
              "cookie_probe_passed": cookie_probe_passed,
              "egl_probe": str(args.egl_probe) if args.egl_probe else None,
              "egl_probe_sha256": args.egl_probe_sha256 if args.egl_probe else None,
              "egl_probe_passed": egl_probe_passed,
              "tls_probe": str(args.tls_probe) if args.tls_probe else None,
              "tls_probe_sha256": args.tls_probe_sha256 if args.tls_probe else None,
              "tls_probe_passed": tls_probe_passed,
              "linker_diagnostics": args.linker_diagnostics,
              "loader_probe": str(args.loader_probe) if args.loader_probe else None,
              "loader_probe_sha256": args.loader_probe_sha256 if args.loader_probe else None,
              "loader_probe_passed": loader_probe_passed,
              "netdb_probe_passed": (b"ANDROID-NETDB-PASS " in transcript
                                       if args.runtime_arch == "aarch64" else None),
              "boot_probe": str(args.boot_probe) if args.boot_probe else None,
              "boot_probe_sha256": args.boot_probe_sha256 if args.boot_probe else None,
              "boot_probe_passed": boot_probe_passed,
              "configuration_probe_passed": (b"ATL-CONFIGURATION-PASS " in transcript
                                               if args.runtime_arch == "aarch64" else None),
              "fortify_probe_passed": (b"ANDROID-FORTIFY-PASS " in transcript
                                         if args.runtime_arch == "aarch64" else None),
              "mallinfo_probe_passed": (b"ANDROID-MALLINFO-PASS " in transcript
                                          if args.runtime_arch == "aarch64" else None),
              "serial_log": str(state / "serial.log")}
    if args.interactive:
        result["functionality"] = "unchecked"
    (state / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    if args.interactive:
        print(f"Interactive Android session ended; application functionality is unchecked. "
              f"Status: {state / 'result.json'}")
        return 0 if observed and not guest_failed else 1
    if not passed and not observed:
        print(f"Android smoke test failed ({failure}); inspect {state / 'serial.log'}", file=sys.stderr)
        return 1
    if observed:
        print(f"Observed the APK's X11 window; application functionality was not checked. Screenshot: {args.screenshot}")
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
    parser.add_argument("--boot-probe", type=Path,
                        help="DEX JAR containing ArtBootProbe; require native Java preflight before the APK")
    parser.add_argument("--layout-probe", type=Path,
                        help="DEX JAR containing android.view.AndroidLayoutFocusProbe; require real inflater focus assertions")
    parser.add_argument("--pointer-probe", type=Path,
                        help="DEX JAR containing android.view.AndroidPointerCaptureProbe; require real event dispatch and snapshot assertions")
    parser.add_argument("--lifecycle-probe", type=Path,
                        help="lifecycle fixture APK; require production activity and fragment ordering assertions through ATL's real application bootstrap")
    parser.add_argument("--cookie-probe", type=Path,
                        help="cookie fixture APK; require production cookie storage and caller-Looper callback assertions")
    parser.add_argument("--egl-probe", type=Path,
                        help="native ARM64 egl-interop-test executable; require GLES2 readback and EGLImage sharing with GTK")
    parser.add_argument("--tls-probe", type=Path,
                        help="DEX JAR containing AndroidTlsProbe; require public HTTPS and untrusted local rejection")
    parser.add_argument("--loader-probe", type=Path,
                        help="directory with native loader-test and packed-relocation-probe.so fixtures")
    parser.add_argument("--linker-diagnostics", action="store_true",
                        help="enable bounded native Bionic linker diagnostics")
    parser.add_argument("--launcher", choices=("android", "roblox"), default="android",
                        help="exercise run-android or the production native Roblox launcher")
    parser.add_argument("--roblox-staging", type=Path,
                        help="verified Roblox launcher stage, used with --launcher roblox")
    parser.add_argument("--activity", default="calculator/Calculator")
    parser.add_argument("--runtime-arg", action="append", default=[],
                        help="extra ATL argument, repeatable; use = for values beginning with -")
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
    parser.add_argument("--interactive", action="store_true",
                        help="keep the desktop QEMU window open until Ctrl-C, without automatic screenshots or application-log export")
    parser.add_argument("--observation-seconds", type=int, default=30,
                        help="seconds a generic APK's painted window must remain visible (default: 30)")
    args = parser.parse_args()
    if args.observation_seconds < 1:
        parser.error("--observation-seconds must be positive")
    if args.interactive:
        if not args.observe or args.mode != "desktop":
            parser.error("--interactive requires --observe and --mode desktop")
        if args.screenshot is not None:
            parser.error("--interactive disables automatic screenshots; capture explicitly through QMP")
    if not args.prepare_only and not args.interactive:
        try:
            import PIL
        except ImportError:
            raise SystemExit("Python Pillow is required to save the APK screenshot")
    args.repo = args.repo.resolve()
    args.state_dir = args.state_dir.resolve()
    args.runtime = (args.runtime or args.repo / "build-aarch64-android/aarch64/staging").resolve()
    if args.runtime_arch is None:
        architectures = {marker.read_text().strip() for marker in args.runtime.glob("opt/vinix-android*/architecture")}
        args.runtime_arch = "x86_64" if "x86_64" in architectures else "aarch64"
    if args.boot_probe and args.runtime_arch != "aarch64":
        parser.error("--boot-probe requires a native aarch64 runtime")
    if args.layout_probe and args.runtime_arch != "aarch64":
        parser.error("--layout-probe requires a native aarch64 runtime")
    if args.pointer_probe and args.runtime_arch != "aarch64":
        parser.error("--pointer-probe requires a native aarch64 runtime")
    if args.lifecycle_probe and args.runtime_arch != "aarch64":
        parser.error("--lifecycle-probe requires a native aarch64 runtime")
    if args.cookie_probe and args.runtime_arch != "aarch64":
        parser.error("--cookie-probe requires a native aarch64 runtime")
    if args.egl_probe and args.runtime_arch != "aarch64":
        parser.error("--egl-probe requires a native aarch64 runtime")
    if args.tls_probe and args.runtime_arch != "aarch64":
        parser.error("--tls-probe requires a native aarch64 runtime")
    if args.loader_probe and args.runtime_arch != "aarch64":
        parser.error("--loader-probe requires a native aarch64 runtime")
    if args.launcher == "roblox":
        if args.runtime_arch != "aarch64" or not args.observe or args.apk is None:
            parser.error("--launcher roblox requires --runtime-arch aarch64, --observe and --apk")
        if args.strace:
            parser.error("--strace applies to translated runtime diagnostics")
        if args.mode == "desktop" and args.runtime_arg:
            parser.error("--runtime-arg is supported by the Roblox launcher in --mode direct")
        args.roblox_staging = (args.roblox_staging or args.repo / "build-aarch64-roblox/aarch64/staging").resolve()
    args.desktop = (args.desktop or args.repo / "build/vinix-desktop").resolve()
    args.kernel_dir = (args.kernel_dir or args.repo / "kernel").resolve()
    args.initramfs = args.initramfs.resolve() if args.initramfs else None
    args.apk = (args.apk or args.runtime / "usr/share/vinix/android/Arity-1.1.apk").resolve()
    args.boot_probe = args.boot_probe.resolve() if args.boot_probe else None
    args.layout_probe = args.layout_probe.resolve() if args.layout_probe else None
    args.pointer_probe = args.pointer_probe.resolve() if args.pointer_probe else None
    args.lifecycle_probe = args.lifecycle_probe.resolve() if args.lifecycle_probe else None
    args.cookie_probe = args.cookie_probe.resolve() if args.cookie_probe else None
    args.egl_probe = args.egl_probe.resolve() if args.egl_probe else None
    args.tls_probe = args.tls_probe.resolve() if args.tls_probe else None
    args.loader_probe = args.loader_probe.resolve() if args.loader_probe else None
    args.screenshot = (args.screenshot or args.state_dir / ("application.png" if args.observe else "calculator.png")).resolve()
    args.input = args.input or ("xtest" if args.mode == "direct" else "qmp")
    base = args.initramfs or args.repo / "build-aarch64-userland/downloads/alpine-minirootfs-3.21.7-aarch64.tar.gz"
    for path in (args.runtime / "usr/bin/run-android", args.desktop, args.kernel_dir / "bin/vinix", base, args.apk):
        if not path.is_file():
            raise SystemExit(f"Missing Android smoke test input: {path}")
    if args.boot_probe and not args.boot_probe.is_file():
        raise SystemExit(f"Missing native Java bootclasspath probe: {args.boot_probe}")
    if args.layout_probe and not args.layout_probe.is_file():
        raise SystemExit(f"Missing native framework layout focus probe: {args.layout_probe}")
    if args.pointer_probe and not args.pointer_probe.is_file():
        raise SystemExit(f"Missing native framework pointer capture probe: {args.pointer_probe}")
    if args.lifecycle_probe and not args.lifecycle_probe.is_file():
        raise SystemExit(f"Missing native framework activity lifecycle probe: {args.lifecycle_probe}")
    if args.cookie_probe and not args.cookie_probe.is_file():
        raise SystemExit(f"Missing native framework cookie probe: {args.cookie_probe}")
    if args.egl_probe and not args.egl_probe.is_file():
        raise SystemExit(f"Missing native EGL and GTK texture probe: {args.egl_probe}")
    if args.tls_probe and not args.tls_probe.is_file():
        raise SystemExit(f"Missing native Java HTTPS trust probe: {args.tls_probe}")
    if args.loader_probe:
        for name in ("loader-test", "packed-relocation-probe.so"):
            if not (args.loader_probe / name).is_file():
                raise SystemExit(f"Missing native Bionic loader probe: {args.loader_probe / name}")
    args.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700 if args.interactive else 0o777)
    if args.interactive:
        args.state_dir.chmod(0o700)
    if not args.interactive:
        args.screenshot.parent.mkdir(parents=True, exist_ok=True)
    overlay = prepare(args)
    if args.prepare_only:
        print(f"Prepared Android smoke image: {args.initramfs or overlay}")
        return 0
    return run(args, overlay)


if __name__ == "__main__":
    raise SystemExit(main())
