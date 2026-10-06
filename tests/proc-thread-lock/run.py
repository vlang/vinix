#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build and compare the independent process inspection fixture with its immutable C oracle."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ORIGINAL = '8ca75d10e8b804cf26705ba9c04614965da81690'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--arch', choices=('aarch64', 'x86_64'), required=True)
parser.add_argument('--kernel-dir', type=Path, required=True)
parser.add_argument('--state-dir', type=Path, required=True)
parser.add_argument('--guest-state-dir', type=Path, required=True)
parser.add_argument('--build-only', action='store_true')
args = parser.parse_args()
args.state_dir.mkdir(parents=True, exist_ok=False)
work = args.state_dir.resolve()
raw = subprocess.check_output(['git', 'show', ORIGINAL + ':tests/proc-thread-lock/test.c'], cwd=ROOT)
(work / 'original.c').write_bytes(raw)
if args.arch == 'aarch64':
    sysroot = ROOT / 'build-aarch64-userland/sysroot'
    gcc = sorted((ROOT / 'build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl').iterdir())[-1]
    compiler = [os.environ.get('CC_AARCH64', '/opt/homebrew/opt/llvm/bin/clang'), '--target=aarch64-linux-musl',
                '--sysroot=' + str(sysroot), '--gcc-install-dir=' + str(gcc)]
else:
    compiler = [os.environ.get('CC_AMD64', '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc')]
flags = compiler + ['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fno-strict-aliasing', '-pthread']
helper = runpy.run_path(str(ROOT / 'tests/kernel-gaps/compile-v-fixture.py'))
fixture = helper['compile_module'](HERE / 'lockfixture', work / 'fixture.o', args.arch, flags + ['-D_GNU_SOURCE'])
serial = helper['compile_serial'](work / 'serial.o', args.arch, flags)
subprocess.run(flags + ['-c', str(work / 'original.c'), '-o', str(work / 'original.o')], check=True)
imports = subprocess.check_output(['/opt/homebrew/opt/llvm/bin/llvm-nm', '-u', str(fixture)], text=True)
assert not re.search(r'\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*|v_malloc)\b', imports), imports
receipt = {'original_revision': ORIGINAL, 'original_lines': len(raw.splitlines()),
           'original_sha256': hashlib.sha256(raw).hexdigest(), 'arch': args.arch,
           'compiler_flags': flags,
           'qemu_cpus': int(os.environ.get('VINIX_QEMU_SMP', '4')) if args.arch == 'aarch64' else 2,
           'fixture_alarm_seconds': 120, 'harness_timeout_seconds': 180,
           'source_hashes': {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted((HERE / 'lockfixture').iterdir())},
           'kernel_sha256': hashlib.sha256((args.kernel_dir / 'bin/vinix').read_bytes()).hexdigest(),
           'fixture_imports': imports.splitlines(), 'variants': {}}
for variant, object_file in (('original', work / 'original.o'), ('v', fixture)):
    program = work / (variant + '-init')
    subprocess.run(compiler + (['-fuse-ld=lld'] if args.arch == 'aarch64' else []) +
                   ['-static', '-pthread', str(object_file), str(serial), '-o', str(program)], check=True)
    state = Path(str(args.guest_state_dir) + '-' + variant)
    command = ['python3', str(ROOT / 'tests/kernel-gaps/run.py'), '--no-network', '--arch', args.arch,
               '--kernel-dir', str(args.kernel_dir), '--state-dir', str(state), '--prebuilt-init', str(program),
               '--timeout', '180', '--expect', 'VINIX PROC THREAD LOCK: PASS', '--fail', 'FAIL: proc thread lock:']
    item = {'program_sha256': hashlib.sha256(program.read_bytes()).hexdigest(), 'command': command}
    receipt['variants'][variant] = item
    (work / 'validation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if not args.build_only:
        with (work / (variant + '-run.log')).open('w') as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
        item['harness_exit'] = result.returncode
        (work / 'validation.json').write_text(json.dumps(receipt, indent=2) + '\n')
        if result.returncode:
            raise SystemExit(result.returncode)
        serial_text = (state / 'serial.log').read_text(errors='replace')
        progress = re.findall(r'proc thread lock: (\d+) snapshots, (\d+) process CPU clocks', serial_text)
        assert len(progress) == 1 and int(progress[0][0]) >= 100 and int(progress[0][1]) >= 10, progress
        assert serial_text.count('PASS: process inspection completes during sibling thread churn') == 1
        assert serial_text.count('VINIX PROC THREAD LOCK: PASS') == 1
        item.update(passed=True, progress=progress,
                    serial_sha256=hashlib.sha256((state / 'serial.log').read_bytes()).hexdigest())
        print('PASS proc-thread-lock ' + variant + ' ' + args.arch + ': thread/fork/exec inspection and clock progress', flush=True)
(work / 'validation.json').write_text(json.dumps(receipt, indent=2) + '\n')
