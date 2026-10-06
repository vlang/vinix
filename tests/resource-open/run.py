#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Run unchanged resource-open and retained-object assertions as a native V fixture."""
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
ORIGINAL = '22c5d6ee193d107102888f359bfade8e34b592d2'
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--arch', choices=('aarch64', 'x86_64'), required=True)
p.add_argument('--state-dir', type=Path, required=True)
p.add_argument('--kernel-dir', type=Path, required=True)
p.add_argument('--guest-state-dir', type=Path, required=True)
p.add_argument('--build-only', action='store_true')
a = p.parse_args()
a.state_dir.mkdir(parents=True, exist_ok=False)
work = a.state_dir.resolve()
raw = subprocess.check_output(['git', 'show', ORIGINAL + ':tests/resource-open/test.c'], cwd=ROOT)
(work / 'original.c').write_bytes(raw)
if a.arch == 'aarch64':
    sysroot = ROOT / 'build-aarch64-userland/sysroot'
    gcc = sorted((ROOT / 'build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl').iterdir())[-1]
    cc = [os.environ.get('CC_AARCH64', '/opt/homebrew/opt/llvm/bin/clang'), '--target=aarch64-linux-musl', '--sysroot=' + str(sysroot), '--gcc-install-dir=' + str(gcc)]
else:
    cc = [os.environ.get('CC_AMD64', '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc')]
flags = cc + ['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fno-strict-aliasing']
helper = runpy.run_path(str(ROOT / 'tests/kernel-gaps/compile-v-fixture.py'))
fixture = helper['compile_module'](HERE / 'resourcefixture', work / 'fixture.o', a.arch, flags + ['-D_GNU_SOURCE'])
serial = helper['compile_serial'](work / 'serial.o', a.arch, flags)
nm = '/opt/homebrew/opt/llvm/bin/llvm-nm'
imports = subprocess.check_output([nm, '-u', str(fixture)], text=True)
assert not re.search(r'\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*|v_malloc)\b', imports), imports
subprocess.run(flags + ['-c', str(work / 'original.c'), '-o', str(work / 'original.o')], check=True)
receipt = {'original_revision': ORIGINAL, 'original_lines': len(raw.splitlines()), 'original_sha256': hashlib.sha256(raw).hexdigest(),
           'arch': a.arch, 'fixture_imports': imports.splitlines(), 'source_hashes': {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted((HERE / 'resourcefixture').iterdir())},
           'kernel_sha256': hashlib.sha256((a.kernel_dir / 'bin/vinix').read_bytes()).hexdigest(), 'variants': {}}
for variant, object_file in (('original', work / 'original.o'), ('v', fixture)):
    program = work / (variant + '-init')
    subprocess.run(cc + (['-fuse-ld=lld'] if a.arch == 'aarch64' else []) + ['-static', str(object_file), str(serial), '-o', str(program)], check=True)
    state = Path(str(a.guest_state_dir) + '-' + variant)
    command = ['python3', str(ROOT / 'tests/kernel-gaps/run.py'), '--arch', a.arch, '--no-network', '--prebuilt-init', str(program), '--kernel-dir', str(a.kernel_dir), '--state-dir', str(state), '--expect', 'RESOURCE OPEN semantics PASS', '--expect', 'RESOURCE OPEN: PASS', '--fail', 'FAIL: resource open']
    receipt['variants'][variant] = {'program_sha256': hashlib.sha256(program.read_bytes()).hexdigest(), 'command': command}
    (work / 'validation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if not a.build_only:
        with (work / (variant + '-run.log')).open('w') as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
        serial_text = (state / 'serial.log').read_text(errors='replace')
        rows = re.findall(r'RESOURCE-OPEN window=(\d+) class=(\d+) objects=([+-]?\d+)', serial_text)
        large = re.findall(r'RESOURCE-OPEN window=(\d+) large_pages=([+-]?\d+) written_after_free=(\d+) flat=(\d+)', serial_text)
        classes = 18 if a.arch == 'aarch64' else 14
        assert len(rows) == 2 * classes and all(int(delta) == 0 for _, _, delta in rows), rows
        assert len(large) == 2 and all((int(pages), int(frees), int(flat)) == (0, 0, 1) for _, pages, frees, flat in large), large
        receipt['variants'][variant].update({'class_rows': rows, 'large_rows': large, 'passed': True})
        print('PASS resource-open ' + variant + ' ' + a.arch + ': all ' + str(classes) + ' classes flat in both 200-pair windows', flush=True)
if not a.build_only:
    assert receipt['variants']['original']['class_rows'] == receipt['variants']['v']['class_rows']
    assert receipt['variants']['original']['large_rows'] == receipt['variants']['v']['large_rows']
    receipt['original_V_retention_equal'] = True
(work / 'validation.json').write_text(json.dumps(receipt, indent=2) + '\n')
