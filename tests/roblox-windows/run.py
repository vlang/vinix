#!/usr/bin/env python3
"""Start Roblox's Windows Player on Vinix through Wine and record how far it gets.

The client is fetched from Roblox's own deployment CDN, the way its installer
does, and laid out in a Wine prefix. Vinix then boots under QEMU/HVF with a
test init that starts RobloxPlayerBeta.exe on a private Xvfb display. The
serial transcript, Wine's log, Roblox's own logs and the frames the guest
uploads are kept below --work.

Requires scripts/build-x86-translation-aarch64.sh, the X11 and userland layers and a
kernel. Nothing proprietary is stored in the repository.
"""
from __future__ import annotations

import argparse
import hashlib
import http.server
import json
import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import signal
import struct
import tarfile
import threading
import time
import urllib.request
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[2]
VERSION_URL = "https://clientsettingscdn.roblox.com/v2/client-version/WindowsPlayer"
CDN = "https://setup.rbxcdn.com"
# Where the installer unpacks each deployment package below the version
# directory. A package it does not know is refused rather than guessed at.
PACKAGES = {
    "RobloxApp.zip": "",
    "WebView2.zip": "",
    "shaders.zip": "shaders",
    "ssl.zip": "ssl",
    "content-avatar.zip": "content/avatar",
    "content-configs.zip": "content/configs",
    "content-fonts.zip": "content/fonts",
    "content-models.zip": "content/models",
    "content-sky.zip": "content/sky",
    "content-sounds.zip": "content/sounds",
    "content-textures2.zip": "content/textures",
    "content-textures3.zip": "PlatformContent/pc/textures",
    "content-terrain.zip": "PlatformContent/pc/terrain",
    "content-platform-fonts.zip": "PlatformContent/pc/fonts",
    "content-platform-dictionaries.zip": "PlatformContent/pc/shared_compression_dictionaries",
    "extracontent-places.zip": "ExtraContent/places",
    "extracontent-luapackages.zip": "ExtraContent/LuaPackages",
    "extracontent-translations.zip": "ExtraContent/translations",
    "extracontent-models.zip": "ExtraContent/models",
    "extracontent-textures.zip": "ExtraContent/textures",
}
# The Edge runtime installer and the bootstrapper are not part of the client.
SKIPPED = ("WebView2RuntimeInstaller.zip", "RobloxPlayerInstaller.exe")
APP_SETTINGS = """<?xml version="1.0" encoding="UTF-8"?>
<Settings>
\t<ContentFolder>content</ContentFolder>
\t<BaseUrl>http://www.roblox.com</BaseUrl>
</Settings>
"""
TOOLS = ("sh", "cat", "mkdir", "chmod", "sleep", "uname", "grep", "ps", "tail", "head", "ls",
         "wget", "kill", "rm", "ln", "find", "sed", "cut", "wc", "tr", "date", "cp", "mv", "env")
# Layers of the translation stage this test has no use for.
UNUSED = ("root/.wine-word2013-x86_64", "root/.wine-office2010-x86_64", "root/word2013-media",
          "root/office2010-media", "root/.wine-x86_32", "usr/libexec/vinix-i386")
FAILURES = (b"KERNEL PANIC", b"ROBLOX-WINDOWS-FAIL")


def download(url: str, target: Path) -> None:
    partial = target.with_name(target.name + ".partial")
    with urllib.request.urlopen(url, timeout=120) as response, partial.open("wb") as output:
        shutil.copyfileobj(response, output, 1024 * 1024)
    partial.rename(target)


def md5(path: Path) -> str:
    digest = hashlib.md5()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch(work: Path, version: str | None) -> tuple[str, Path]:
    """Download one deployment's packages, checking each against its manifest."""
    if version is None:
        with urllib.request.urlopen(VERSION_URL, timeout=60) as response:
            version = json.load(response)["clientVersionUpload"]
    if not version.startswith("version-") or not version[8:].isalnum():
        raise SystemExit(f"Not a Roblox deployment name: {version}")
    downloads = work / "downloads" / version
    downloads.mkdir(parents=True, exist_ok=True)
    manifest = downloads / "rbxPkgManifest.txt"
    if not manifest.exists():
        download(f"{CDN}/{version}-rbxPkgManifest.txt", manifest)
    lines = manifest.read_text().split()
    if lines[0] != "v0" or (len(lines) - 1) % 4:
        raise SystemExit(f"Unknown package manifest format in {manifest}")
    for index in range(1, len(lines), 4):
        name, checksum = lines[index], lines[index + 1]
        if name in SKIPPED:
            continue
        if name not in PACKAGES:
            raise SystemExit(f"Deployment {version} has a package this test cannot place: {name}")
        package = downloads / name
        if not package.exists():
            print(f"Downloading {name}", flush=True)
            download(f"{CDN}/{version}-{name}", package)
        if md5(package) != checksum:
            package.unlink()
            raise SystemExit(f"{name} does not match its manifest checksum; run again to refetch it")
    return version, downloads


def stage(downloads: Path, client: Path) -> None:
    """Unpack the packages into the layout the Windows installer produces."""
    if (client / ".staged").exists():
        return
    if client.exists():
        shutil.rmtree(client)
    for name, directory in PACKAGES.items():
        package = downloads / name
        if not package.exists():
            continue
        with zipfile.ZipFile(package) as archive:
            for entry in archive.infolist():
                # The archives are written on Windows with its separator.
                relative = Path(directory, *[part for part in entry.filename.replace("\\", "/").split("/") if part])
                if ".." in relative.parts:
                    raise SystemExit(f"{name} has an entry outside its directory: {entry.filename}")
                target = client / relative
                if entry.filename.endswith(("/", "\\")):
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(entry) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output, 1024 * 1024)
    (client / "AppSettings.xml").write_text(APP_SETTINGS)
    (client / ".staged").touch()


def copy_layer(source: Path, dest: Path, skip: tuple[str, ...] = (), base: Path | None = None) -> None:
    base = base or source
    dest.mkdir(parents=True, exist_ok=True)
    for entry in source.iterdir():
        if str(entry.relative_to(base)) in skip:
            continue
        target = dest / entry.name
        if entry.is_symlink():
            if target.exists() or target.is_symlink():
                target.unlink()
            target.symlink_to(os.readlink(entry))
        elif entry.is_dir():
            copy_layer(entry, target, skip, base)
        else:
            if target.exists() or target.is_symlink():
                target.unlink()
            shutil.copy2(entry, target)


def prepare(args, work: Path, client: Path, version: str) -> Path:
    root = work / "root"
    if not (root / ".prepared").exists():
        if root.exists():
            shutil.rmtree(root)
        # Xvfb and its libraries, musl and a shell, then Wine and its translator.
        copy_layer(args.repo / "build-aarch64-x11/staging", root)
        userland = args.repo / "build-aarch64-userland/staging"
        for directory in ("lib", "usr/lib"):
            for library in (userland / directory).glob("*.so*"):
                target = root / directory / library.name
                if not target.exists() and not target.is_symlink():
                    if library.is_symlink():
                        target.symlink_to(os.readlink(library))
                    else:
                        shutil.copy2(library, target)
        (root / "bin").mkdir(exist_ok=True)
        shutil.copy2(userland / "bin/busybox", root / "bin/busybox")
        for name in TOOLS:
            (root / "bin" / name).symlink_to("busybox")
        for directory in ("sbin", "proc", "dev", "sys", "tmp", "root", "run", "etc"):
            (root / directory).mkdir(parents=True, exist_ok=True)
        (root / "etc/passwd").write_text("root:x:0:0:root:/root:/bin/sh\n")
        (root / "etc/group").write_text("root:x:0:root\n")
        copy_layer(args.translation, root, UNUSED)
        (root / ".prepared").touch()
    for launcher in ("run-wine-x86-64", "run-x86-64", "run-x86-32"):
        shutil.copy2(ROOT / "build-support/x86-translation" / launcher, root / "usr/bin" / launcher)
    prefix = root / "root/.wine-x86_64"
    installed = prefix / "drive_c/Roblox"
    if installed.exists():
        shutil.rmtree(installed)
    copy_layer(client, installed / "Versions" / version)
    test = root / "opt/roblox-test"
    test.mkdir(parents=True, exist_ok=True)
    configuration = {
        "TEST_EXECUTABLE": f"C:\\Roblox\\Versions\\{version}\\RobloxPlayerBeta.exe",
        "TEST_WINEDEBUG": args.winedebug, "TEST_UPLOAD": f"http://10.0.2.2:{args.port}",
        "TEST_SECONDS": str(args.seconds), "TEST_GEOMETRY": "1280x720x24",
        "TEST_ARGUMENTS": args.arguments, "TEST_SHELL": "1" if args.shell else "0",
        "TEST_STRACE": "1" if args.strace else "0",
    }
    (test / "config.sh").write_text("".join(f"{key}={shlex.quote(value)}\n" for key, value in configuration.items()))
    shutil.copy2(Path(__file__).with_name("guest-init.sh"), root / "sbin/init")
    (root / "sbin/init").chmod(0o755)
    return root


def xwd_to_png(source: Path, target: Path) -> bool:
    """Convert Xvfb's 24-bit framebuffer dump; report whether anything is drawn."""
    data = source.read_bytes()
    if len(data) < 100:
        return False
    header = struct.unpack(">25I", data[:100])
    header_size, width, height = header[0], header[4], header[5]
    bits_per_pixel, bytes_per_line, colours = header[11], header[12], header[19]
    least_significant_first = header[7] == 0
    start = header_size + colours * 12
    if bits_per_pixel != 32 or len(data) < start + bytes_per_line * height:
        return False
    rows, drawn = bytearray(), False
    for y in range(height):
        line = data[start + y * bytes_per_line:start + y * bytes_per_line + width * 4]
        if least_significant_first:
            red, green, blue = line[2::4], line[1::4], line[0::4]
        else:
            red, green, blue = line[1::4], line[2::4], line[3::4]
        row = bytearray(width * 3)
        row[0::3], row[1::3], row[2::3] = red, green, blue
        drawn = drawn or any(row)
        rows += b"\0" + row

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    target.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                       + chunk(b"IDAT", zlib.compress(bytes(rows), 6)) + chunk(b"IEND", b""))
    return drawn


def serve_uploads(directory: Path, port: int) -> http.server.ThreadingHTTPServer:
    """Take what the guest posts: its framebuffer and Roblox's log files."""
    directory.mkdir(parents=True, exist_ok=True)

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            name = Path(self.path).name or "upload"
            (directory / name).write_bytes(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()

        def log_message(self, *_):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def stop(pid: int, master: int) -> None:
    try:
        os.write(master, b"\x01x")
        time.sleep(1)
        os.killpg(pid, signal.SIGTERM)
    except (OSError, ProcessLookupError):
        pass
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if os.waitpid(pid, os.WNOHANG)[0] == pid:
            break
        time.sleep(0.1)
    else:
        try:
            os.killpg(pid, signal.SIGKILL)
        except OSError:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        # macOS can leave an exiting HVF process unreapable for a while.
        os.waitpid(pid, os.WNOHANG)
    os.close(master)


def run_guest(args, work: Path, root: Path) -> bytes:
    archive = work / "initramfs.tar"
    with tarfile.open(archive, "w", format=tarfile.USTAR_FORMAT) as tar:
        tar.add(root, arcname=".")
    environment = os.environ.copy()
    environment.update({
        "VINIX_KERNEL_DIR": str(args.kernel_dir), "VINIX_INITRAMFS": str(archive),
        "VINIX_INITRAMFS_COMPRESSED": "0", "VINIX_QEMU_ROOT_DISK": "0",
        "VINIX_BOOT_DISK": str(work / "boot.img"), "VINIX_EFIVARS": str(work / "efivars.fd"),
        "VINIX_BOOT_DISK_SIZE_MB": "4096", "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
        "VINIX_QEMU_PACKAGE_PERSIST": "0", "VINIX_QEMU_HOST_SOURCE": "0",
        "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": str(args.cpus), "VINIX_KEEP_TEMP_BOOT_DISK": "1",
    })
    command = [str(args.repo / "scripts/run-aarch64.sh"), "--no-build", "--no-persist", f"--mem={args.mem}", "--serial"]
    print("Booting Vinix with the Windows Player", flush=True)
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(args.repo)
        os.execvpe(command[0], command, environment)
    transcript = bytearray()
    deadline = time.monotonic() + args.timeout
    # --shell: what is written to this pipe is typed at the guest's console.
    pipe = work / "shell.in"
    typed = -1
    if args.shell:
        if pipe.exists():
            pipe.unlink()
        os.mkfifo(pipe)
        typed = os.open(pipe, os.O_RDWR | os.O_NONBLOCK)
        print(f"Guest shell: write commands to {pipe}, read {work}/vinix.log; 'poweroff-test' ends it", flush=True)
    try:
        with (work / "vinix.log").open("wb") as log:
            while time.monotonic() < deadline:
                if typed >= 0 and select.select([typed], [], [], 0)[0]:
                    command = os.read(typed, 65536)
                    if b"poweroff-test" in command:
                        break
                    os.write(master, command)
                if select.select([master], [], [], 0.2 if args.shell else 1)[0]:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    transcript.extend(chunk)
                    log.write(chunk)
                    log.flush()
                if not args.shell and (b"ROBLOX-WINDOWS-DONE" in transcript
                                       or any(marker in transcript for marker in FAILURES)):
                    break
    finally:
        stop(pid, master)
        if typed >= 0:
            os.close(typed)
            pipe.unlink()
        # Both are written again by the next run, and together they are 6 GiB.
        for scratch in (archive, work / "boot.img"):
            scratch.unlink(missing_ok=True)
    return bytes(transcript)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", type=Path, default=ROOT, help="checkout holding the layers and scripts/run-aarch64.sh")
    parser.add_argument("--kernel-dir", type=Path, help="kernel directory holding bin/vinix")
    parser.add_argument("--translation", type=Path,
                        help="stage of scripts/build-x86-translation-aarch64.sh; the checkout's otherwise")
    parser.add_argument("--work", type=Path, default=ROOT / "build/roblox-windows")
    parser.add_argument("--version", help="deployment to test, e.g. version-02c37bc51a384b8f; the current one otherwise")
    parser.add_argument("--winedebug", default="fixme-all,err+all", help="WINEDEBUG for the client")
    parser.add_argument("--arguments", default="", help="arguments for RobloxPlayerBeta.exe")
    parser.add_argument("--seconds", type=int, default=300, help="how long the guest watches the client")
    parser.add_argument("--timeout", type=int, default=1500, help="host limit for the whole boot")
    parser.add_argument("--strace", action="store_true",
                        help="report the system calls the translator could not serve, not Wine's log")
    parser.add_argument("--shell", action="store_true",
                        help="give the guest a shell on its console instead of starting the client")
    parser.add_argument("--mem", type=int, default=12288)
    parser.add_argument("--cpus", type=int, default=4)
    parser.add_argument("--port", type=int, default=18791, help="host port the guest uploads to")
    args = parser.parse_args()
    args.kernel_dir = args.kernel_dir or args.repo / "kernel"
    args.translation = args.translation or args.repo / "build-aarch64-x86-translation/staging"
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)

    version, downloads = fetch(work, args.version)
    client = work / "client" / version
    stage(downloads, client)
    root = prepare(args, work, client, version)
    uploads = work / "uploads"
    if uploads.exists():
        shutil.rmtree(uploads)
    server = serve_uploads(uploads, args.port)
    try:
        transcript = run_guest(args, work, root)
    finally:
        server.shutdown()

    if args.shell:
        return
    drawn = False
    for frame in sorted(uploads.glob("*.xwd")):
        drawn = xwd_to_png(frame, frame.with_suffix(".png")) or drawn
    if b"KERNEL PANIC" in transcript:
        raise SystemExit(f"The kernel panicked; inspect {work}/vinix.log")
    if b"ROBLOX-WINDOWS-FAIL" in transcript:
        raise SystemExit(f"Wine did not run in the guest, so the client was never started; inspect {work}/vinix.log")
    if b"ROBLOX-WINDOWS-DONE" not in transcript:
        raise SystemExit(f"The guest never finished its observation; inspect {work}/vinix.log")
    report = uploads / "wine.log"
    lines = report.read_text(errors="replace").splitlines() if report.exists() else []
    if args.strace:
        numbers = [line.rsplit(" ", 1)[1] for line in lines]
        print(f"The client made {len(numbers)} system calls of its own that Linux does not have"
              + (f", first {', '.join(numbers[:4])}" if numbers else ""))
    else:
        for line in lines[-12:]:
            print("  " + line)
    alive = b"ROBLOX-WINDOWS-ALIVE" in transcript.rsplit(b"ROBLOX-WINDOWS-TICK", 1)[-1]
    print(f"Deployment {version}: client {'still running' if alive else 'gone'} at the end of the observation, "
          f"{'a drawn' if drawn else 'an empty'} display. Transcript: {work}/vinix.log, uploads: {uploads}")
    if not alive or not drawn:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
