#!/usr/bin/env python3
"""Compare frozen C/V configuration goldens against actual ATL/androidfw objects."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--state-dir", type=Path, required=True)
p.add_argument("--kernel-dir", type=Path, required=True)
p.add_argument("--linux-host", help="Optional Lima ARM Linux host for an independent native run")
p.add_argument("--baseline-rev", default="8f7239d1")
a = p.parse_args()
state = a.state_dir.resolve()
state.mkdir(parents=True, exist_ok=False)
support = ROOT / "build-support/android"
art = ROOT / "build-aarch64-android/aarch64/art-runtime"
native = ROOT / "build-aarch64-userland/staging"
directories = [art / "usr/lib/art", ROOT / "build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib",
               native / "lib", native / "usr/lib", ROOT / "build-aarch64-x11/staging/usr/lib"]
provider = state / "src/libandroid/configuration.c"
provider.parent.mkdir(parents=True)
original_provider = ROOT / "build-aarch64-android/source/atl/src/libandroid/configuration.c"
shutil.copy2(original_provider, provider)
# Apply precisely the selected library's configuration hunk, leaving all
# unrelated ATL source and Java/UI patches outside this bounded fixture.
patch = (support / "atl-configuration.patch").read_text().split("\n--- a/", 1)[0] + "\n"
assert patch.startswith("--- a/src/libandroid/configuration.c\n")
(state / "configuration.patch").write_text(patch)
subprocess.run(["patch", "--batch", "--fuzz=0", "-p1", "-i", str(state / "configuration.patch")], cwd=state, check=True)
sysroot = ROOT / "build-aarch64-userland/sysroot"
gcc = sorted((native / "usr/lib/gcc/aarch64-alpine-linux-musl").iterdir())[-1]
cc = [os.environ.get("CC", "/opt/homebrew/opt/llvm/bin/clang"), "--target=aarch64-linux-musl", "--sysroot=" + str(sysroot), "--gcc-install-dir=" + str(gcc)]
flags = ["-O2", "-Wall", "-Wextra", "-Werror", "-I" + str(art / "usr/include")]
provider_object = state / "configuration.o"
subprocess.run([*cc, *flags, "-D_LARGEFILE64_SOURCE", "-c", str(provider), "-o", str(provider_object)], check=True)
baseline = state / "baseline.c"
baseline.write_bytes(subprocess.check_output(["git", "show", a.baseline_rev + ":build-support/android/atl-configuration-test.c"], cwd=ROOT))
generated = state / "probe.c"
subprocess.run(["python3", str(support / "compile-v-atl-configuration.py"), str(generated)], check=True)
# The actual second Linux ABI must compile strictly even though the coherent
# ATL builder and selected native provider are ARM-only.
x86_generated = state / "probe-x86.c"
subprocess.run(["python3", str(support / "compile-v-atl-configuration.py"), str(x86_generated), "--arch", "amd64"], check=True)
subprocess.run([os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc"), *flags, "-Wno-unused-function", "-Wno-unused-parameter",
                "-I" + str(support), "-c", str(x86_generated), "-o", str(state / "probe-x86.o")], check=True)
probes = {}
for tag, source in (("c", baseline), ("v", generated)):
    program = state / ("probe-" + tag)
    library_flags = [flag for directory in directories for flag in ("-L" + str(directory), "-Wl,-rpath-link," + str(directory))]
    subprocess.run([*cc, *flags, "-Wno-unused-function", "-Wno-unused-parameter", "-I" + str(support), str(source),
                    str(provider_object), *library_flags, "-landroidfw", "-lpng", "-fuse-ld=lld", "-Wl,-z,max-page-size=65536",
                    "-o", str(program)], check=True)
    probes[tag] = program
golden = "ATL-CONFIGURATION-PASS snapshot=asset-manager owned-copy=verified matching=androidfw\n"
if a.linux_host:
    for tag, program in probes.items():
        output = subprocess.check_output(["limactl", "shell", a.linux_host, str(native / "lib/ld-musl-aarch64.so.1"),
                                          "--library-path", ":".join(map(str, directories)), str(program)], text=True)
        assert output == golden, repr(output)
        (state / ("linux-" + tag + ".log")).write_text(output)
root = state / "root"
files = {"bin/busybox": native / "bin/busybox", "lib/ld-musl-aarch64.so.1": native / "lib/ld-musl-aarch64.so.1"}
pending = []
for tag, program in probes.items():
    files["probe-" + tag] = program
    pending.append(program)
seen = set()
while pending:
    source = pending.pop()
    dynamic = subprocess.check_output(["aarch64-linux-musl-readelf", "-d", str(source)], text=True)
    for name in re.findall(r"Shared library: \[([^]]+)\]", dynamic):
        if name in seen:
            continue
        seen.add(name)
        dependency = next((directory / name for directory in directories if (directory / name).is_file()), None)
        if dependency is None:
            raise RuntimeError("Missing selected native provider dependency: " + name)
        files["lib/" + name] = dependency
        pending.append(dependency)
for name, source in files.items():
    target = root / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
for directory in ("sbin", "dev", "proc", "sys", "tmp", "root"):
    (root / directory).mkdir(parents=True, exist_ok=True)
for name in ("sh", "mount", "sleep"):
    (root / "bin" / name).symlink_to("busybox")
script = "#!/bin/sh\nset -eu\nexport PATH=/bin LD_LIBRARY_PATH=/lib\nmount -t proc proc /proc 2>/dev/null || true\n"
for tag in probes:
    script += "/probe-" + tag + "\necho ATL-NATIVE-PASS:" + tag + "\n"
script += "echo ATL-NATIVE-GUEST-PASS\nwhile :; do sleep 60; done\n"
(root / "sbin/init").write_text(script)
(root / "sbin/init").chmod(0o755)
archive = state / "initramfs.tar.gz"
with tarfile.open(archive, "w:gz", format=tarfile.USTAR_FORMAT) as tar:
    tar.add(root, arcname=".")
env = {**os.environ, "VINIX_KERNEL_DIR": str(a.kernel_dir.resolve()), "VINIX_INITRAMFS": str(archive),
       "VINIX_INITRAMFS_COMPRESSED": "1", "VINIX_BOOT_DISK": str(state / "boot.img"), "VINIX_BOOT_DISK_SIZE_MB": "128",
       "VINIX_EFIVARS": str(state / "efivars.fd"), "VINIX_QEMU_HOST_SOURCE": "0", "VINIX_QEMU_ROOT_DISK": "0",
       "VINIX_QEMU_PACKAGE_STORE": str(state / "packages.tar"), "VINIX_QEMU_PACKAGE_PERSIST": "0",
       "VINIX_QEMU_AUDIO": "off", "VINIX_QEMU_NETWORK": "0", "VINIX_QEMU_SMP": "2",
       "VINIX_QEMU_EXTRA": "-qmp unix:" + str(state / "qmp.sock") + ",server=on,wait=off"}
for name in ("VINIX_QEMU_GUEST_INIT", "VINIX_QEMU_OVERLAY", "VINIX_QEMU_MODULE_ISO", "VINIX_QEMU_BASE_ARCHIVE", "VINIX_QEMU_MODULE_MANIFEST", "VINIX_QEMU_EXTRA_MODULES"):
    env.pop(name, None)
expected = [golden.rstrip(), "ATL-NATIVE-PASS:c", "ATL-NATIVE-PASS:v", "ATL-NATIVE-GUEST-PASS"]
result = runpy.run_path(str(ROOT / "tests/kernel-gaps/run.py"))["boot"](
    [str(ROOT / "scripts/run-aarch64.sh"), "--no-build", "--serial", "--no-persist", "--mem=1024"],
    env, state, expected, ["KERNEL PANIC", "Assertion failed"], 300)
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
metadata = {"baseline_revision": a.baseline_rev, "result": result, "expected_markers": expected,
            "configuration_probe_digest": runpy.run_path(str(support / "art-runtime.py"))["configuration_probe_digest"](),
            "provider_source_sha256": digest(original_provider), "provider_patch_sha256": digest(state / "configuration.patch"),
            "provider_header_sha256": digest(art / "usr/include/androidfw/androidfw_c_api.h"),
            "provider_library_sha256": digest(art / "usr/lib/art/libandroidfw.so"),
            "kernel_sha256": digest(a.kernel_dir / "bin/vinix"), "files": {name: digest(source) for name, source in files.items()}}
(state / "validation.json").write_text(json.dumps(metadata, indent=2) + "\n")
raise SystemExit(result)
