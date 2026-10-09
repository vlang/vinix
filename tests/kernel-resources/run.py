#!/usr/bin/env python3
"""Boot the kernel-resource exhaustion fixture with the existing VM harness."""
import argparse
import os
from pathlib import Path
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--arch', choices=('aarch64', 'x86_64'), required=True)
parser.add_argument('--kernel-dir', type=Path, default=ROOT / 'kernel')
parser.add_argument('--state-dir', type=Path, required=True)
parser.add_argument('--timeout', type=int, default=480)
args = parser.parse_args()
args.state_dir.mkdir(parents=True, exist_ok=False)
state = args.state_dir.resolve()
if args.arch == 'aarch64':
    sysroot = ROOT / 'build-aarch64-userland/sysroot'
    cc = [os.environ.get('CC', 'clang'), '--target=aarch64-linux-musl', '--sysroot=' + str(sysroot),
          '-L' + str(sysroot / 'lib'), '-fuse-ld=lld', '-fno-stack-protector']
else:
    cc = [os.environ.get('CC_AMD64', 'x86_64-linux-musl-gcc')]
flags = cc + ['-static', '-pthread', '-O2', '-Wall', '-Wextra', '-Werror']
serial = state / 'serial.o'
runpy.run_path(str(ROOT / 'tests/kernel-gaps/compile-v-fixture.py'))['compile_serial'](serial, args.arch, flags)
init = state / 'init'
subprocess.run(flags + [str(serial), str(Path(__file__).with_name('guest.c')), '-o', str(init)], check=True)
subprocess.run(['python3', str(ROOT / 'tests/kernel-gaps/run.py'), '--arch', args.arch,
                '--kernel-dir', str(args.kernel_dir.resolve()), '--state-dir', str(state / 'guest'),
                '--prebuilt-init', str(init), '--no-network', '--timeout', str(args.timeout),
                '--expect', 'KRES PASS', '--fail', 'KRES FAIL'], check=True)
