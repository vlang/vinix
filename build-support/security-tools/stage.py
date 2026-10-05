#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build and install Vinix security utilities into a target userland tree."""
import argparse
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def install(source: Path, destination: Path, mode: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".security-tool-", dir=destination.parent)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(source.read_bytes())
        os.chmod(temporary, mode)
        os.replace(temporary, destination)
    finally:
        Path(temporary).unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
    parser.add_argument("--staging", type=Path, required=True)
    parser.add_argument("--cc", help="target musl C compiler command")
    args = parser.parse_args()
    staging = args.staging.resolve()
    if staging == Path("/") or not staging.is_dir():
        parser.error("staging must be an existing target filesystem, not /")
    cc = shlex.split(args.cc or os.environ.get(f"VINIX_SECURITY_CC_{args.arch.upper()}")
                    or os.environ.get(f"VINIX_MUSL_CC_{args.arch.upper()}")
                    or f"{args.arch}-linux-musl-gcc")
    if not cc or not shutil.which(cc[0]):
        parser.error("target musl compiler is missing")
    machine = subprocess.check_output(cc + ["-dumpmachine"], text=True).strip()
    if not machine.startswith(args.arch + "-") or "linux" not in machine:
        parser.error(f"compiler target does not match --arch: {machine}")
    with tempfile.TemporaryDirectory(prefix="vinix-security-tools-") as directory:
        for source, destination in (
                ("tools/sandbox/vinix-sandbox.c", "usr/bin/vinix-sandbox"),
                ("tools/security-mac/mac.c", "usr/sbin/vinix-mac"),
                ("tools/security-audit/collector.c", "usr/sbin/vinix-security-audit")):
            binary = Path(directory) / Path(destination).name
            subprocess.run(cc + ["-static", "-std=c11", "-O2", "-Wall", "-Wextra",
                                 "-Werror", str(ROOT / source), "-o", str(binary)], check=True)
            header = binary.read_bytes()[:64]
            expected = 183 if args.arch == "aarch64" else 62
            if header[:6] != b"\x7fELF\x02\x01" or int.from_bytes(header[18:20], "little") != expected:
                raise RuntimeError("compiler produced a wrong-architecture ELF executable")
            install(binary, staging / destination, 0o755)
    install(ROOT / "build-support/security-audit/run-collector",
            staging / "usr/libexec/vinix-security-audit-supervise", 0o755)
    log = staging / "var/log/vinix-audit"
    if log.is_symlink():
        raise RuntimeError("audit log staging directory cannot be a symlink")
    log.mkdir(parents=True, exist_ok=True)
    log.chmod(0o700)
    print(f"Staged Vinix sandbox, mandatory policy and audit utilities ({args.arch}).")


if __name__ == "__main__":
    main()
