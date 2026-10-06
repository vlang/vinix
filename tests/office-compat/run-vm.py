#!/usr/bin/env python3
"""Execute actual Windows64 C/V licensing goldens in staged Wine on Vinix."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--state-dir", type=Path, required=True)
p.add_argument("--kernel-dir", type=Path, required=True)
p.add_argument("--fixtures", type=Path, required=True)
p.add_argument("--timeout", type=int, default=900)
a = p.parse_args()
work = a.state_dir.resolve()
work.mkdir(parents=True, exist_ok=False)
root = work / "root"
stage = ROOT / "build-aarch64-x86-translation/staging"
runtime = stage / "usr/libexec/vinix-x86_64/root"
native = ROOT / "build-aarch64-userland/staging"
files = {"bin/busybox": native / "bin/busybox", "lib/ld-musl-aarch64.so.1": native / "lib/ld-musl-aarch64.so.1",
         "usr/bin/qemu-x86_64": stage / "usr/bin/qemu-x86_64", "usr/bin/run-x86-64": ROOT / "build-support/x86-translation/run-x86-64",
         "usr/bin/wineserver": ROOT / "build-support/x86-translation/run-wine-x86-64",
         "runtime/usr/bin/wine": runtime / "usr/bin/wine", "runtime/usr/bin/wineserver": runtime / "usr/bin/wineserver",
         "runtime/lib/ld-musl-x86_64.so.1": runtime / "lib/ld-musl-x86_64.so.1"}
for variant in ("c", "v"):
    files["test-" + variant + ".exe"] = a.fixtures / ("fixture-" + variant + ".exe")
for source in (runtime / "usr/share/wine").rglob("*"):
    if source.is_file():
        files["runtime/usr/share/wine/" + str(source.relative_to(runtime / "usr/share/wine"))] = source
for source in (runtime / "usr/lib/wine/x86_64-windows").iterdir():
    if source.is_file(): files["runtime/usr/lib/wine/x86_64-windows/" + source.name] = source
pending = []
for source in (runtime / "usr/lib/wine/x86_64-unix").iterdir():
    if source.is_file():
        files["runtime/usr/lib/wine/x86_64-unix/" + source.name] = source
        if source.name in ("ntdll.so", "win32u.so"):
            pending.append(source)
pending += [runtime / "usr/bin/wine", runtime / "usr/bin/wineserver"]
seen = set()
while pending:
    source = pending.pop()
    dynamic = subprocess.check_output(["aarch64-linux-musl-readelf", "-d", str(source)], text=True)
    for name in re.findall(r"Shared library: \[([^]]+)\]", dynamic):
        if name in seen: continue
        seen.add(name)
        dependency = next((directory / name for directory in (runtime / "lib", runtime / "usr/lib", runtime / "usr/lib/wine/x86_64-unix") if (directory / name).is_file()), None)
        if dependency is None: raise RuntimeError("Missing staged Wine dependency: " + name)
        files["runtime/lib/" + name] = dependency
        pending.append(dependency)
for name, source in files.items():
    target = root / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
for directory in ("sbin", "dev", "proc", "sys", "tmp", "root/.wine/drive_c/windows/system32", "root/.wine/dosdevices", "etc"):
    (root / directory).mkdir(parents=True, exist_ok=True)
(root / "tmp").chmod(0o1777)
for name in ("sh", "sleep", "mount", "mkdir"):
    (root / "bin" / name).symlink_to("busybox")
# The loader's flat ELF dependency path may resolve ntdll.so in runtime/lib.
# Keep Wine's corresponding relative share lookup attached to the original data.
(root / "runtime/share").mkdir(exist_ok=True)
(root / "runtime/share/wine").symlink_to("../usr/share/wine")
(root / "etc/passwd").write_text("root:x:0:0:root:/root:/bin/sh\n")
(root / "etc/group").write_text("root:x:0:\n")
(root / "root/.wine/.update-timestamp").write_text("disable\n")
(root / "root/.wine/dosdevices/c:").symlink_to("../drive_c")
(root / "root/.wine/dosdevices/z:").symlink_to("/")
for source in (root / "runtime/usr/lib/wine/x86_64-windows").iterdir():
    (root / "root/.wine/drive_c/windows/system32" / source.name).symlink_to("/runtime/usr/lib/wine/x86_64-windows/" + source.name)
script = "#!/bin/sh\nset -eu\nexport PATH=/bin:/usr/bin HOME=/root USER=root VINIX_ALLOW_WX=1\n"
script += "export VINIX_X86_64_ROOT=/runtime WINEPREFIX=/root/.wine WINEARCH=win64 WINEDEBUG=+seh\n"
script += "export WINEDLLPATH=/runtime/usr/lib/wine/x86_64-unix:/runtime/usr/lib/wine/x86_64-windows\n"
script += "export WINELOADERNOEXEC=1 WINESERVER=/usr/bin/wineserver WINEDLLOVERRIDES=winemenubuilder.exe=d\n"
script += "mount -t proc proc /proc 2>/dev/null || true\nulimit -s 32768\n"
for variant in ("c", "v"):
    script += "echo OFFICE-NATIVE-BEGIN:" + variant + "\nset +e\n/usr/bin/run-x86-64 /runtime/usr/bin/wine /test-" + variant + ".exe\nresult=$?\nset -e\n"
    script += 'if [ "$result" -ne 73 ]; then echo "OFFICE-NATIVE-ERROR:' + variant + ':exit=$result"; exit 1; fi\n'
    script += "echo OFFICE-NATIVE-PASS:" + variant + "\n"
script += "echo OFFICE-NATIVE-GUEST-PASS\nwhile :; do sleep 60; done\n"
(root / "sbin/init").write_text(script)
(root / "sbin/init").chmod(0o755)
archive = work / "initramfs.tar.gz"
with tarfile.open(archive, "w:gz", format=tarfile.USTAR_FORMAT) as tar: tar.add(root, arcname=".")
kernel = work / "kernel/bin/vinix"
kernel.parent.mkdir(parents=True)
shutil.copy2(a.kernel_dir / "bin/vinix", kernel)
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
inputs = {"kernel_sha256": digest(kernel), "archive_sha256": digest(archive), "files": {name: digest(root / name) for name in files}}
(work / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
env = {**os.environ, "VINIX_KERNEL_DIR": str(kernel.parent.parent), "VINIX_INITRAMFS": str(archive), "VINIX_INITRAMFS_COMPRESSED": "1",
       "VINIX_QEMU_ROOT_DISK": "0", "VINIX_BOOT_DISK": str(work / "boot.img"), "VINIX_EFIVARS": str(work / "efivars.fd"),
       "VINIX_BOOT_DISK_SIZE_MB": "128", "VINIX_QEMU_PACKAGE_STORE": str(work / "packages.tar"), "VINIX_QEMU_PACKAGE_PERSIST": "0",
       "VINIX_QEMU_HOST_SOURCE": "0", "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_SMP": "2", "VINIX_QEMU_NETWORK": "0",
       "VINIX_QEMU_EXTRA": f"-qmp unix:{work / 'qmp.sock'},server=on,wait=off"}
for name in ("VINIX_QEMU_PERSIST_DISK", "VINIX_QEMU_GUEST_INIT", "VINIX_QEMU_OVERLAY", "VINIX_QEMU_MODULE_ISO", "VINIX_QEMU_BASE_ARCHIVE", "VINIX_QEMU_MODULE_MANIFEST", "VINIX_QEMU_EXTRA_MODULES", "VINIX_BOOT_HYPRLAND", "VINIX_UI2_SOURCE"):
    env.pop(name, None)
spec = importlib.util.spec_from_file_location("office_native_guest", ROOT / "tests/kernel-gaps/run.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
expected = ["OFFICE-NATIVE-PASS:c", "OFFICE-NATIVE-PASS:v", "OFFICE-NATIVE-GUEST-PASS"]
result = runner.boot([str(ROOT / "scripts/run-aarch64.sh"), "--no-build", "--serial", "--no-persist", "--mem=1024"], env, work, expected, ["KERNEL PANIC", "Office ABI assertion", "OFFICE-NATIVE-ERROR:"], a.timeout)
(work / "results.json").write_text(json.dumps({**inputs, "exit_code": result, "expected_markers": expected, "fixture_success_exit": 73}, indent=2) + "\n")
raise SystemExit(result)
