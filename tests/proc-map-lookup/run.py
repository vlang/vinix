#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build and compare the independent procfs map fixture with its immutable C oracle."""
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
ORIGINAL = '47db8e1ce160c2829ad9df9fde6e1f1345d1f80c'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--arch', choices=('aarch64', 'x86_64'), required=True)
parser.add_argument('--kernel-dir', type=Path, required=True)
parser.add_argument('--state-dir', type=Path, required=True)
parser.add_argument('--guest-state-dir', type=Path, required=True)
parser.add_argument('--build-only', action='store_true')
args = parser.parse_args()
args.state_dir.mkdir(parents=True, exist_ok=False)
work = args.state_dir.resolve()
raw = subprocess.check_output(['git', 'show', ORIGINAL + ':tests/proc-map-lookup/test.c'], cwd=ROOT)
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
fixture = helper['compile_module'](HERE / 'mapfixture', work / 'fixture.o', args.arch, flags + ['-D_GNU_SOURCE'])
serial = helper['compile_serial'](work / 'serial.o', args.arch, flags)
subprocess.run(flags + ['-c', str(work / 'original.c'), '-o', str(work / 'original.o')], check=True)
imports = subprocess.check_output(['/opt/homebrew/opt/llvm/bin/llvm-nm', '-u', str(fixture)], text=True)
assert not re.search(r'\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*|v_malloc)\b', imports), imports
receipt = {'original_revision': ORIGINAL, 'original_lines': len(raw.splitlines()),
           'original_sha256': hashlib.sha256(raw).hexdigest(), 'arch': args.arch,
           'compiler_flags': flags,
           'qemu_cpus': int(os.environ.get('VINIX_QEMU_SMP', '4')) if args.arch == 'aarch64' else 2,
           'fixture_alarm_seconds': 600, 'harness_timeout_seconds': 1800,
           'source_hashes': {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted((HERE / 'mapfixture').iterdir())},
           'kernel_sha256': hashlib.sha256((args.kernel_dir / 'bin/vinix').read_bytes()).hexdigest(),
           'fixture_imports': imports.splitlines(), 'variants': {}}
for variant, object_file in (('original', work / 'original.o'), ('v', fixture)):
    program = work / (variant + '-init')
    subprocess.run(compiler + (['-fuse-ld=lld'] if args.arch == 'aarch64' else []) +
                   ['-static', '-pthread', str(object_file), str(serial), '-o', str(program)], check=True)
    state = Path(str(args.guest_state_dir) + '-' + variant)
    command = ['python3', str(ROOT / 'tests/kernel-gaps/run.py'), '--no-network', '--arch', args.arch,
               '--kernel-dir', str(args.kernel_dir), '--state-dir', str(state), '--prebuilt-init', str(program),
               '--timeout', '1800', '--expect', 'VINIX PROC MAP LOOKUP: PASS', '--fail', 'FAIL: proc map lookup:']
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
        rows = re.findall(r'PROC-MAP-RETENTION class=(\d+) live=([+-]?\d+) pages=([+-]?\d+)', serial_text)
        large = re.findall(r'PROC-MAP-RETENTION large=([+-]?\d+) uaf=([+-]?\d+)', serial_text)
        cohorts = re.findall(r'proc map lookup: completed growth cohort (\d+) children=(\d+)', serial_text)
        progress = re.findall(r'proc map lookup: (\d+) lookups, (\d+) directory snapshots', serial_text)
        assert len(rows) == (18 if args.arch == 'aarch64' else 14) and all(int(live) == int(pages) == 0 for _, live, pages in rows), rows
        assert large == [('0', '0')] and cohorts == [('1', '12'), ('2', '12'), ('3', '12'), ('4', '12')], (large, cohorts)
        assert len(progress) == 1 and all(int(value) >= 100 for value in progress[0]), progress
        item.update(passed=True, class_rows=rows, large_rows=large, cohort_rows=cohorts,
                    progress=progress, serial_sha256=hashlib.sha256((state / 'serial.log').read_bytes()).hexdigest())
        print('PASS proc-map-lookup ' + variant + ' ' + args.arch + ': all retained classes and pages exactly flat', flush=True)
if not args.build_only:
    assert receipt['variants']['original']['class_rows'] == receipt['variants']['v']['class_rows']
    assert receipt['variants']['original']['large_rows'] == receipt['variants']['v']['large_rows']
    receipt['original_V_retention_equal'] = True
(work / 'validation.json').write_text(json.dumps(receipt, indent=2) + '\n')
