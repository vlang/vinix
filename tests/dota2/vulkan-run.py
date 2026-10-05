#!/usr/bin/env python3
"""Boot actual ARM64 Vinix and exercise translated glibc lavapipe/X11."""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import tarfile
import time

REPO = Path(__file__).resolve().parents[2]
BASE64_LINE = 76


def decode_capture(transcript: bytes) -> bytes:
    """Reassemble the guest's two numbered base64 copies of one snapshot.

    Interleaved kernel output lengthens or splits a line, so only complete
    numbered lines are kept; the guest's hash checks the reassembled image.
    """
    capture = transcript.split(b"VINIX-DOTA2-VULKAN-SHOT-BEGIN\n", 1)[1]
    capture = capture.split(b"VINIX-DOTA2-VULKAN-SHOT-END", 1)[0]
    hashes = set(re.findall(rb"^VINIX-DOTA2-VULKAN-SHOT-SHA256: ([0-9a-f]{64})$", capture, re.M))
    lines: dict[int, set[bytes]] = {}
    for match in re.finditer(rb"^S([1-9][0-9]*) ([A-Za-z0-9+/]+={0,2})$", capture, re.M):
        lines.setdefault(int(match[1]), set()).add(match[2])
    if len(hashes) != 1 or not lines:
        raise SystemExit("the guest capture has no intact hash or image lines")
    last = max(lines)
    chosen = []
    for index in range(1, last):
        candidates = {line for line in lines.get(index, ()) if len(line) == BASE64_LINE}
        if len(candidates) != 1:
            raise SystemExit(f"capture line {index} is missing or corrupt in both copies")
        chosen.append(candidates.pop())
    # The final line is shorter; the hash picks its intact copy.
    for final in sorted(lines[last], key=len):
        try:
            contents = base64.b64decode(b"".join(chosen) + final, validate=True)
        except ValueError:
            continue
        if hashlib.sha256(contents).hexdigest().encode() in hashes:
            return contents
    raise SystemExit("the reassembled capture does not match the guest's hash")


def copy_layer(source: Path, target: Path) -> None:
    target.mkdir(parents=True, exist_ok=True)
    for entry in source.iterdir():
        destination = target / entry.name
        if entry.is_symlink():
            if destination.exists() or destination.is_symlink():
                if destination.is_dir() and not destination.is_symlink():
                    continue
                destination.unlink()
            destination.symlink_to(os.readlink(entry))
        elif entry.is_dir():
            copy_layer(entry, destination)
        else:
            if destination.is_symlink():
                destination.unlink()
            shutil.copy2(entry, destination)


def complete_native_closure(root: Path) -> None:
    userland = REPO / "build-aarch64-userland/staging"
    queue = [root / "usr/bin/Xvfb", root / "usr/bin/xkbcomp",
             root / "usr/bin/qemu-x86_64"]
    seen = set()
    while queue:
        binary = queue.pop()
        if binary in seen or not binary.exists():
            continue
        seen.add(binary)
        output = subprocess.check_output(["aarch64-linux-musl-readelf", "-d", str(binary)], text=True)
        for name in re.findall(r"\(NEEDED\).*\[([^]]+)\]", output):
            library = next((root / directory / name for directory in ("usr/lib", "lib")
                            if (root / directory / name).exists()), None)
            if library is None:
                source = next((userland / directory / name for directory in ("usr/lib", "lib")
                               if (userland / directory / name).exists()), None)
                if source is None:
                    raise SystemExit(f"native probe dependency is missing: {name}")
                library = root / "usr/lib" / name
                if library.is_symlink():
                    library.unlink()
                shutil.copy2(source, library)
            queue.append(library)


def install_native_translator(staging: Path, root: Path) -> None:
    binary = staging / "usr/bin/qemu-x86_64"
    with binary.open("rb") as stream:
        header = stream.read(20)
    if (header[:7] != b"\x7fELF\x02\x01\x01" or
            header[16:18] not in (b"\x02\x00", b"\x03\x00") or
            header[18:20] != b"\xb7\x00" or not os.access(binary, os.X_OK)):
        raise SystemExit(f"Expected an executable native AArch64 translator: {binary}")
    for directory in ("usr/lib", "lib"):
        if (staging / directory).is_dir():
            copy_layer(staging / directory, root / directory)
    (root / "usr/bin").mkdir(parents=True, exist_ok=True)
    target = root / "usr/bin/qemu-x86_64"
    if target.is_symlink():
        target.unlink()
    shutil.copy2(binary, target)


def retain_software_gl(source: Path, guest: Path) -> None:
    relative = "usr/lib/x86_64-linux-gnu/dri"
    destination = guest / relative
    destination.mkdir(parents=True, exist_ok=True)
    keep = {"swrast_dri.so", "kms_swrast_dri.so"}
    for name in keep:
        library = source / relative / name
        if library.is_file():
            target = destination / name
            if target.is_symlink():
                target.unlink()
            shutil.copy2(library, target)
    for entry in destination.iterdir():
        if entry.name not in keep:
            if entry.is_dir() and not entry.is_symlink():
                shutil.rmtree(entry)
            else:
                entry.unlink()


def prepare(args, work: Path) -> Path:
    root = work / "root"
    staged_translator = (args.staging / "usr/bin/qemu-x86_64").exists()
    if not (root / ".prepared").exists():
        copy_layer(REPO / "build-aarch64-x11/staging", root)
        if not staged_translator:
            install_native_translator(REPO / "build-aarch64-x86-translation/staging", root)
        (root / "bin").mkdir(exist_ok=True)
        userland = REPO / "build-aarch64-userland/staging"
        shutil.copy2(userland / "bin/busybox", root / "bin/busybox")
        loader = root / "lib/ld-musl-aarch64.so.1"
        if loader.is_symlink():
            loader.unlink()
        shutil.copy2(userland / "lib/ld-musl-aarch64.so.1", loader)
        for name in ("sh", "cat", "mkdir", "chmod", "sleep", "kill", "base64", "uname", "grep"):
            target = root / "bin" / name
            if target.exists() or target.is_symlink():
                target.unlink()
            target.symlink_to("busybox")
        for directory in ("sbin", "proc", "dev", "sys", "tmp", "root", "run", "etc"):
            (root / directory).mkdir(parents=True, exist_ok=True)
        (root / "etc/passwd").write_text("root:x:0:0:root:/root:/bin/sh\n")
        (root / "etc/group").write_text("root:x:0:root\n")
        (root / ".prepared").touch()
    # The foreign runtime stamp cannot identify a changed native translator.
    # Refresh the Dota binary and its native libraries even for a prepared root.
    if staged_translator:
        install_native_translator(args.staging, root)
    source = args.staging / "usr/libexec/vinix-dota2/root"
    generation = (source / ".vinix-dota2-vulkan-generation").read_text()
    marker = root / ".vulkan-runtime-generation"
    guest = root / "usr/libexec/vinix-dota2/root"
    if not marker.exists() or marker.read_text() != generation or not guest.exists():
        if guest.exists():
            shutil.rmtree(guest)
        guest.parent.mkdir(parents=True, exist_ok=True)
        if sys.platform == "darwin":
            subprocess.run(["/bin/cp", "-cRp", str(source), str(guest)], check=True)
        else:
            shutil.copytree(source, guest, symlinks=True)
        marker.write_text(generation)
    shutil.copy2(Path(__file__).with_name("vulkan-init.sh"), root / "sbin/init")
    (root / "sbin/init").chmod(0o755)
    complete_native_closure(root)
    # This root also supplies the real game probe. Steam's gldriverquery needs
    # software GL even when the game itself renders through Vulkan.
    retain_software_gl(source, guest)
    for path in (guest / "usr/lib/i386-linux-gnu", guest / "lib/i386-linux-gnu",
                 guest / "usr/share/doc", guest / "usr/share/man", guest / "usr/share/locale"):
        if path.exists():
            shutil.rmtree(path)
    return root


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staging", type=Path, default=REPO / "build/dota2-vulkan/staging")
    parser.add_argument("--work", type=Path, default=REPO / "build/dota2-vulkan/test")
    parser.add_argument("--kernel-dir", type=Path, default=REPO / "kernel")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--venus", action="store_true",
                        help="boot on KekVM's GPU and render with the staged x86-64 Venus driver")
    args = parser.parse_args()
    args.staging = args.staging.resolve()
    args.kernel_dir = args.kernel_dir.resolve()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    root = prepare(args, work)
    driver = "venus" if args.venus else "lavapipe"
    (root / "etc/vinix-dota2-vulkan-driver").write_text(driver + "\n")
    archive = work / "initramfs.tar.gz"
    with tarfile.open(archive, "w:gz", compresslevel=1, format=tarfile.USTAR_FORMAT) as tar:
        tar.add(root, arcname=".")
    pinned_kernel = work / "kernel/bin"
    pinned_kernel.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.kernel_dir / "bin/vinix", pinned_kernel / "vinix")
    socket_path = work / "qmp.sock"
    if socket_path.exists():
        socket_path.unlink()
    environment = {**os.environ,
        "VINIX_KERNEL_DIR": str(pinned_kernel.parent), "VINIX_INITRAMFS": str(archive),
        "VINIX_INITRAMFS_COMPRESSED": "1", "VINIX_QEMU_ROOT_DISK": "0",
        "VINIX_BOOT_DISK": str(work / "boot.img"), "VINIX_EFIVARS": str(work / "efivars.fd"),
        "VINIX_BOOT_DISK_SIZE_MB": "2048", "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"),
        "VINIX_QEMU_PACKAGE_PERSIST": "0", "VINIX_QEMU_HOST_SOURCE": "0",
        "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": "4", "VINIX_KEEP_TEMP_BOOT_DISK": "1",
        "VINIX_QEMU_EXTRA": f"-qmp unix:{socket_path},server=on,wait=off",
    }
    firmware = REPO / "boot-image/edk2-aarch64-code-2048x1536.fd"
    if args.venus and firmware.exists():
        # Vinix's own firmware build, as for OpenGothic's Venus boots; the
        # stock firmware stopped at its splash with the Venus GPU attached.
        environment.update({"VINIX_QEMU_RESOLUTION": "2048x1536x32", "VINIX_OVMF_CODE": str(firmware)})
    # Accelerated QEMU needs a GL display; its serial console still uses stdio.
    command = [str(REPO / "run-aarch64.sh"), "--no-build", "--no-persist", "--mem=8192",
               *(["--venus"] if args.venus else ["--serial"])]
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(REPO)
        os.execvpe(command[0], command, environment)
    transcript = bytearray()
    deadline = time.monotonic() + args.timeout
    try:
        with (work / "vinix.log").open("wb") as log:
            while time.monotonic() < deadline:
                if not select.select([master], [], [], 1)[0]:
                    continue
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                transcript.extend(data)
                log.write(data)
                log.flush()
                # Keep binary capture data out of the host's progress output.
                if any(marker in transcript for marker in
                       (b"VINIX-DOTA2-VULKAN-PASS", b"VINIX-DOTA2-VULKAN-FAIL", b"KERNEL PANIC")):
                    break
    finally:
        try:
            os.write(master, b"\x01x")
            os.killpg(pid, signal.SIGTERM)
        except (OSError, ProcessLookupError):
            pass
        stop = time.monotonic() + 5
        while time.monotonic() < stop:
            if os.waitpid(pid, os.WNOHANG)[0] == pid:
                break
            time.sleep(0.1)
        else:
            try:
                os.killpg(pid, signal.SIGKILL)
            except OSError:
                try:
                    os.kill(pid, signal.SIGKILL)
                except OSError:
                    pass
            os.waitpid(pid, os.WNOHANG)
        os.close(master)
    normalized = bytes(transcript).replace(b"\r", b"")
    passed = b"VINIX-DOTA2-VULKAN-PASS" in normalized
    colors = 0
    if b"VINIX-DOTA2-VULKAN-SHOT-END" in normalized:
        xwd = work / "vkcube.xwd"
        contents = decode_capture(normalized)
        xwd.write_bytes(contents)
        header = struct.unpack(">25I", contents[:100])
        if header[1] != 7 or header[11] != 32:
            raise SystemExit("unexpected Xvfb XWD format")
        begin = header[0] + header[19] * 12
        pixels = contents[begin:begin + header[12] * header[5]]
        colors = len({pixels[i:i + 4] for i in range(0, len(pixels), 4)})
        # A cleared Xvfb root can survive after a successful cube exits.
        # Require an actual rendered scene in the captured surface too.
        if shutil.which("ffmpeg"):
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(xwd),
                            "-frames:v", "1", str(work / "vkcube.png")], check=True)
    passed = passed and colors > 8
    report = {"passed": passed, "requested_frames": 3000, "cpu": "Haswell",
        "kernel_sha256": hashlib.sha256((pinned_kernel / "vinix").read_bytes()).hexdigest(),
        "translator_sha256": hashlib.sha256((root / "usr/bin/qemu-x86_64").read_bytes()).hexdigest(),
        "driver": driver,
        "icd_sha256": hashlib.sha256((root / "usr/libexec/vinix-dota2/root/usr/lib/x86_64-linux-gnu" /
                                      ("libvulkan_virtio.so" if args.venus else "libvulkan_lvp.so")).read_bytes()).hexdigest(),
        "enumerated": b"VINIX-DOTA2-VULKAN-ENUMERATE-PASS" in normalized,
        "captured_colors": colors,
        "log": str(work / "vinix.log")}
    (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if not passed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
