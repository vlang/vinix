#!/usr/bin/env python3
"""Check exact greeting output and boot the allocation-free maintained V bodies."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", choices=("aarch64", "x86_64"), required=True)
parser.add_argument("--kernel-dir", type=Path, required=True)
parser.add_argument("--state-dir", type=Path, required=True)
args = parser.parse_args()
state = args.state_dir.resolve()
state.mkdir(parents=True, exist_ok=False)
module = state / "fixture"
module.mkdir()
shutil.copy2(ROOT / "tests/userland-demo/fixture/core.v", module / "core.v")
sources = {
    "world": ROOT / "base-files/root/hello.v",
    "arm": ROOT / "build-support/userland-demo/hello-aarch64.v",
    "x86": ROOT / "build-support/userland-demo/hello-amd64.v",
}
for name, source in sources.items():
    text = source.read_text()
    assert text.count("fn main()") == 1 and text.count("module main") == 1
    # Only the entry/module names change in scratch. Test the exact maintained
    # function bodies without duplicating them in a fixture implementation.
    (module / (name + ".v")).write_text(text.replace("module main", "module fixture").replace("fn main()", "fn greet_" + name + "()"))
compiler = runpy.run_path(str(ROOT / "build-support/compile-v-module.py"))
host = state / "host.c"
compiler["generate"](module, host, "arm64", ("nofloat", "hello_host"))
host_program = state / "host"
common = ["-O2", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function", "-Wno-unused-parameter", "-fno-strict-aliasing"]
subprocess.run(["clang", *common, "-fsanitize=address,undefined", str(host), "-o", str(host_program)], check=True)
expected = ("Hello world\nHello from Alpine GCC on Vinix!\nHello from Alpine GCC on Vinix/amd64!\nUSERLAND DEMO V PASS\n")
result = subprocess.check_output([str(host_program)], text=True)
assert result == expected, repr(result)
generated = state / "native.c"
compiler["generate"](module, generated, "arm64" if args.arch == "aarch64" else "amd64", ("nofloat",))
if args.arch == "aarch64":
    sysroot = ROOT / "build-aarch64-userland/sysroot"
    gcc = sorted((ROOT / "build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl").iterdir())[-1]
    cc = [os.environ.get("CC", "/opt/homebrew/opt/llvm/bin/clang"), "--target=aarch64-linux-musl", "--sysroot=" + str(sysroot), "--gcc-install-dir=" + str(gcc), "-fuse-ld=lld"]
else:
    cc = [os.environ.get("CC_AMD64", "x86_64-linux-musl-gcc")]
serial = state / "serial.o"
runpy.run_path(str(ROOT / "tests/kernel-gaps/compile-v-fixture.py"))["compile_serial"](serial, args.arch, [*cc, *common])
init = state / "init"
subprocess.run([*cc, *common, "-static", str(generated), str(serial), "-o", str(init)], check=True)
metadata = {"arch": args.arch, "expected_stdout": expected, "sources": {str(source.relative_to(ROOT)): hashlib.sha256(source.read_bytes()).hexdigest() for source in sources.values()}, "fixture_sha256": hashlib.sha256(init.read_bytes()).hexdigest(), "kernel_sha256": hashlib.sha256((args.kernel_dir / "bin/vinix").read_bytes()).hexdigest(), "host_sanitizers": ["address", "undefined"]}
(state / "inputs.json").write_text(json.dumps(metadata, indent=2) + "\n")
command = ["python3", str(ROOT / "tests/kernel-gaps/run.py"), "--arch", args.arch, "--prebuilt-init", str(init), "--kernel-dir", str(args.kernel_dir), "--state-dir", str(state / "guest"), "--no-network", "--timeout", "300"]
for marker in expected.splitlines(): command += ["--expect", marker]
subprocess.run(command, check=True)
print("USERLAND DEMO HOST AND NATIVE PASS: " + args.arch)
