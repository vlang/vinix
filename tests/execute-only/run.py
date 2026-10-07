#!/usr/bin/env python3
"""Compile the execute-only permission test and boot it through an isolated existing VM driver."""
from pathlib import Path
import argparse
import contextlib
import hashlib
import importlib.util
import json
import os
import runpy
import shutil
import subprocess
import struct
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FEATURES = (b'EXECUTE ONLY PASS: permissions and checked copies', b'EXECUTE ONLY PASS: fork split remap and demand paging')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", choices=("aarch64", "amd64"), default="aarch64")
    parser.add_argument("--expect-readable", action="store_true", help="verify the fallback when enhanced PAN is unavailable or disabled")
    parser.add_argument("--source", type=Path, help="compile an explicit original C control instead of the V fixture")
    parser.add_argument("--state-dir", type=Path, help="retain build inputs and guest artifacts in a new directory")
    parser.add_argument("--kernel-dir", type=Path, help="use an already-built isolated kernel")
    arguments = parser.parse_args()
    if arguments.source is not None and not arguments.source.is_file():
        parser.error("--source must name an existing C control")
    if arguments.state_dir is not None:
        arguments.state_dir = arguments.state_dir.resolve()
        arguments.state_dir.mkdir(parents=True, exist_ok=False)
    if arguments.kernel_dir is not None:
        kernel_dir = arguments.kernel_dir.resolve()
        if not (kernel_dir / "bin/vinix").is_file():
            parser.error("--kernel-dir must contain bin/vinix")
        if struct.unpack_from("<H", (kernel_dir / "bin/vinix").read_bytes(), 18)[0] != {"aarch64": 183, "amd64": 62}[arguments.arch]:
            parser.error("kernel architecture must match --arch")
        os.environ["VINIX_KERNEL_DIR"] = str(kernel_dir)
        os.environ["VINIX_AMD64_KERNEL"] = str(kernel_dir / "bin/vinix")
        os.environ["VINIX_QEMU_RT_NO_BUILD"] = "1"
    runner_root = Path(os.environ.get("VINIX_VM_RUNNER_ROOT", ROOT))
    runner_path = runner_root / ("tests/realtime/run_vm.py" if arguments.arch == "aarch64"
                                 else "tests/openbsd-security/run_vm.py")
    spec = importlib.util.spec_from_file_location("execute-only_vm", runner_path)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.PASS_MARKER = b"EXECUTE ONLY GUEST: PASS"
    runner.FAIL_MARKERS = (b"EXECUTE ONLY FAIL", b"FATAL EXCEPTION", b"KERNEL PANIC")
    runner.FEATURE_MARKERS = FEATURES
    helper = runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))
    context = (contextlib.nullcontext(arguments.state_dir) if arguments.state_dir is not None
               else tempfile.TemporaryDirectory(prefix="vinix-execute-only-vm-"))
    with context as directory:
        work = Path(directory)
        if arguments.arch == "aarch64":
            sysroot = Path(os.environ.get("VINIX_AARCH64_SYSROOT", ROOT / "build-aarch64-userland/sysroot"))
            command = [os.environ.get("CC", "clang"), "--target=aarch64-linux-musl",
                f"--sysroot={sysroot}", "-static", "-O2", "-fno-stack-protector", "-Wall", "-Wextra", "-Werror",
                f"-L{sysroot / 'lib'}", "-fuse-ld=lld",
                "-o", str(work / "init")]
        else:
            command = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc"), "-static", "-O2",
                "-Wall", "-Wextra", "-Werror",
                "-o", str(work / "init")]
        if arguments.expect_readable:
            command.insert(1, "-DEXECUTE_ONLY_EXPECT_READABLE")
        source = arguments.source or helper["compile_module"](
            ROOT / "tests/execute-only/execfixture", work / "fixture.o",
            "aarch64" if arguments.arch == "aarch64" else "x86_64", command[:-2])
        command.insert(-2, str(source))
        subprocess.run(command, check=True)
        for name in ("root", "sbin", "proc", "sys", "dev", "tmp"):
            (work / "rootfs" / name).mkdir(parents=True)
        if arguments.arch == "amd64":
            shutil.copy2(work / "init", work / "rootfs/sbin/init")
        subprocess.run(["tar", "--format=ustar", "-cf", str(work / "initramfs.tar"),
            "-C", str(work / "rootfs"), "."], env={**os.environ, "COPYFILE_DISABLE": "1"}, check=True)
        timeout = int(os.environ.get("VINIX_QEMU_TIMEOUT", "300"))
        module = ROOT / "tests/execute-only/execfixture"
        evidence = {
            "arch": arguments.arch, "expect_readable": arguments.expect_readable,
            "timeout": timeout, "independent_C_control": arguments.source is not None,
            "source_sha256": hashlib.sha256(arguments.source.read_bytes()).hexdigest() if arguments.source else
                {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(module.iterdir()) if path.is_file()},
            "fixture_elf_sha256": hashlib.sha256((work / "init").read_bytes()).hexdigest(),
            "native_link_command": command,
            "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        }
        if arguments.kernel_dir is not None:
            evidence["selected_kernel_sha256"] = hashlib.sha256((kernel_dir / "bin/vinix").read_bytes()).hexdigest()
            evidence["kernel_rebuilt_by_runner"] = False
        (work / "inputs.json").write_text(json.dumps(evidence, indent=2) + "\n")
        if arguments.arch == "aarch64":
            return runner.run_vm(runner_root, work / "init", work / "initramfs.tar", work / "vm", timeout)
        environment = {**os.environ,
            "VINIX_AMD64_KERNEL": os.environ.get("VINIX_AMD64_KERNEL", str(ROOT / "kernel/bin/vinix")),
            "VINIX_AMD64_INITRAMFS": str(work / "initramfs.tar"),
            "VINIX_AMD64_ISO": str(work / "test.iso"),
            "VINIX_AMD64_ISO_BUILD_DIR": str(work / "iso"),
        }
        subprocess.run([str(runner_root / "build-support/build-amd64-iso.sh")], env=environment, check=True)
        qemu = Path(shutil.which(os.environ.get("VINIX_QEMU_X86_64", "qemu-system-x86_64")))
        firmware = os.environ.get("VINIX_OVMF_CODE_AMD64", str(qemu.parent.parent / "share/qemu/edk2-x86_64-code.fd"))
        runner.REPORT_MARKER = b""  # This test does not provoke pledge violations.
        sys.argv = [str(runner_path), "--arch", "amd64", "--iso", str(work / "test.iso"),
            "--qemu", str(qemu), "--firmware", firmware, "--capture", str(work / "unused.pcap"),
            "--timeout", str(timeout)]
        return runner.main()


if __name__ == "__main__":
    raise SystemExit(main())
