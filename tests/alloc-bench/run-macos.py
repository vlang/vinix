#!/usr/bin/env python3
"""Compile with real GCC inside a macOS QEMU guest and save benchmark records."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
FLAGS = ["-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-fno-builtin"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--identity", required=True, type=Path)
    parser.add_argument("--gcc", default="/opt/local/bin/gcc-mp-14")
    parser.add_argument("--guest-sdk", help="guest SDK root for GCC assembly output when CLT is absent")
    parser.add_argument("--host-sdk", type=Path,
                        help="host Apple SDK used to assemble/link guest GCC output; requires --guest-sdk")
    parser.add_argument("--vm-config", type=Path, required=True,
                        help="recorded QEMU configuration of the target VM")
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--iterations", type=int, default=20000)
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    if not 1 <= args.iterations <= 1000000000 or not 5 <= args.samples <= 31 or args.timeout <= 0:
        parser.error("iterations must be 1..1000000000, samples 5..31, timeout positive")
    if bool(args.guest_sdk) != bool(args.host_sdk):
        parser.error("--guest-sdk and --host-sdk must be supplied together")
    config = json.loads(args.vm_config.read_text())
    for key in ["qemu_version", "machine", "accelerator", "cpu", "smp", "memory_mb"]:
        if key not in config:
            parser.error(f"VM configuration lacks {key}")
    source = ROOT / "tests/alloc-bench/bench.c"
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=False)
    staged_source = state / "bench.c"
    staged_source.write_bytes(source.read_bytes())
    source_hash = hashlib.sha256(staged_source.read_bytes()).hexdigest()
    config.update(source_sha256=source_hash, compile_flags=FLAGS,
                  iterations=args.iterations, samples=args.samples)
    config["build_method"] = ("guest GCC C-to-assembly; host Apple assembler/linker"
                              if args.guest_sdk else "guest GCC driver")
    (state / "config.json").write_text(json.dumps(config, indent=2) + "\n")
    destination = f"{args.user}@{args.host}"
    host_key_options = ["-o", f"UserKnownHostsFile={state / 'known_hosts'}",
                        "-o", "StrictHostKeyChecking=accept-new"]
    ssh = ["ssh", "-i", str(args.identity.resolve()), "-p", str(args.port),
           "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", *host_key_options, destination]
    remote_dir = f"/tmp/vinix-alloc-bench-{time.time_ns()}"
    subprocess.run(ssh + ["mkdir -m 700 " + shlex.quote(remote_dir)], check=True, timeout=30)
    scp = ["scp", "-i", str(args.identity.resolve()), "-P", str(args.port),
           "-o", "BatchMode=yes", *host_key_options, str(staged_source), f"{destination}:{remote_dir}/bench.c"]
    subprocess.run(scp, check=True, timeout=60)
    gcc = shlex.quote(args.gcc)
    prefix = f"""set -e
cd {shlex.quote(remote_dir)}
test "$(/usr/bin/shasum -a 256 bench.c | /usr/bin/awk '{{print $1}}')" = {source_hash}
echo ALLOC-COMPILE-BEGIN
{gcc} --version | head -n 1
if {gcc} -dM -E - </dev/null | grep __clang__; then
    echo ALLOC-FAIL stage=compiler-is-clang
    exit 1
fi
"""
    binary = shlex.quote(remote_dir + "/alloc-bench")
    run = f"echo $$ > run.pid\nexec {binary} --label macos --iterations {args.iterations} --samples {args.samples}"
    with (state / "serial.log").open("wb") as log:
        if args.guest_sdk:
            includes = subprocess.check_output(ssh + [f"{gcc} -print-file-name=include"],
                                               text=True, timeout=30).strip()
            codegen = (f"{gcc} {shlex.join(FLAGS)} -mmacosx-version-min=10.15 "
                       f"-isysroot {shlex.quote(args.guest_sdk)} -nostdinc "
                       f"-isystem {shlex.quote(includes)} "
                       f"-isystem {shlex.quote(args.guest_sdk + '/usr/include')} "
                       "-S bench.c -o bench.s")
            config["guest_compile_command"] = codegen
            subprocess.run(ssh + [prefix + codegen], stdout=log, stderr=subprocess.STDOUT,
                           check=True, timeout=args.timeout)
            transfer = ["scp", "-i", str(args.identity.resolve()), "-P", str(args.port),
                        "-o", "BatchMode=yes", *host_key_options]
            subprocess.run(transfer + [f"{destination}:{remote_dir}/bench.s", str(state / "bench.s")],
                           check=True, timeout=60)
            link = ["xcrun", "clang", "-target", "x86_64-apple-macos10.15", "-isysroot",
                    str(args.host_sdk.resolve()), str(state / "bench.s"), "-o", str(state / "alloc-bench")]
            config["host_link_command"] = link
            subprocess.run(link, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=60)
            subprocess.run(transfer + [str(state / "alloc-bench"), f"{destination}:{remote_dir}/alloc-bench"],
                           check=True, timeout=60)
            command = f"cd {shlex.quote(remote_dir)} && chmod 755 alloc-bench && echo ALLOC-COMPILE-DONE && {run}"
        else:
            codegen = f"{gcc} {shlex.join(FLAGS)} bench.c -o alloc-bench"
            config["guest_compile_command"] = codegen
            command = prefix + codegen + "\necho ALLOC-COMPILE-DONE\n" + run
        (state / "config.json").write_text(json.dumps(config, indent=2) + "\n")
        try:
            subprocess.run(ssh + [command], stdout=log, stderr=subprocess.STDOUT, check=True, timeout=args.timeout)
        except BaseException:
            # A lost SSH client need not terminate its remote child. Before
            # retrying, kill only the PID still executing this unique binary.
            cleanup = f"""cd {shlex.quote(remote_dir)} || exit 0
test -f run.pid || exit 0
bench_pid=$(cat run.pid)
case "$bench_pid" in ''|*[!0-9]*) exit 1;; esac
case "$(ps -p "$bench_pid" -o command=)" in
    {binary}' '*) kill "$bench_pid";;
esac
"""
            try:
                subprocess.run(ssh + [cleanup], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, check=True, timeout=30)
            except (OSError, subprocess.SubprocessError):
                print(f"Remote cleanup failed; check {remote_dir}/run.pid before retrying.", file=sys.stderr)
            raise
    output = (state / "serial.log").read_text(errors="replace")
    if "ALLOC-DONE" not in output or "ALLOC-ERROR" in output or "ALLOC-FAIL" in output:
        raise RuntimeError(f"benchmark incomplete; see {state / 'serial.log'}")
    print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
