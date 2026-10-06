#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compare the fixed-size VNC viewer with frozen C using a native V Xlib/RFB model."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
REFERENCE = '8f7239d1fd4c593746279699f6ff25df5f4dd7bd'
CALLS = ('XOpenDisplay', 'XCreateSimpleWindow', 'XSelectInput', 'XStoreName',
         'XMapWindow', 'XCreateGC', 'calloc', 'XCreateImage', 'socket', 'connect',
         'close', 'usleep', 'recv', 'send', 'select', 'XPutImage', 'XFlush',
         'XPending', 'XNextEvent', 'XLookupKeysym', 'XFreeGC', 'XDestroyWindow',
         'XCloseDisplay')
REMAP = ['-Dmain=vnf_viewer'] + [f'-D{name}=vnf_{name}' for name in CALLS]
WARNINGS = ['-std=c11', '-D_DEFAULT_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror',
            '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter']


def generate(work, arch='amd64', guest=False):
    core, fixture, api = work / (arch + '-core.c'), work / (arch + '-fixture.c'), work / (arch + '-api.h')
    helper = ROOT / 'build-support/compile-v-module.py'
    subprocess.run(['python3', helper, ROOT / 'build-support/qemu-system/vnccore',
                    core, '--arch', arch, '--header', api], check=True)
    api.write_text(api.read_text().replace(' main(', ' vnf_viewer('))
    subprocess.run(['python3', helper, ROOT / 'build-support/qemu-system/tests/vncfixture',
                    fixture, '--arch', arch] + (['-d', 'vnc_guest'] if guest else []), check=True)
    return core, fixture, api


def host(work, headers):
    core, fixture, api = generate(work)
    original = work / 'frozen-viewer.c'
    original.write_bytes(subprocess.check_output(['git', 'show', REFERENCE +
                          ':build-support/qemu-system/vinix-vnc-window.c'], cwd=ROOT))
    flags = [os.environ.get('CC', 'clang')] + WARNINGS + ['-g',
             '-fsanitize=address,undefined', '-fsanitize-address-use-after-return=always',
             '-fno-omit-frame-pointer', '-idirafter', str(headers)]
    model = work / 'fixture.o'
    subprocess.run(flags + ['-include', api, '-c', fixture, '-o', model], check=True)
    results = []
    env = {**os.environ, 'ASAN_OPTIONS': 'detect_leaks=0:halt_on_error=1',
           'UBSAN_OPTIONS': 'halt_on_error=1:print_stacktrace=1'}
    for kind, source in (('c', original), ('v', core)):
        obj, binary = work / (kind + '-viewer.o'), work / (kind + '-viewer')
        subprocess.run(flags + REMAP + ['-c', source, '-o', obj], check=True)
        subprocess.run(flags + [model, obj, '-o', binary], check=True)
        run = subprocess.run([binary], capture_output=True, env=env)
        (work / (kind + '.stdout')).write_bytes(run.stdout)
        (work / (kind + '.stderr')).write_bytes(run.stderr)
        if run.returncode:
            raise RuntimeError(f'{kind} model failed: {run.stdout.decode()}\n{run.stderr.decode()}')
        results.append((run.stdout, run.stderr))
    assert results[0] == results[1], 'Frozen C and V protocol/lifetime traces differ'
    assert results[1][0].count(b'CASE ') == 34
    assert results[1][0].endswith(b'VNC MODEL PASS\n')
    imports = subprocess.check_output(['nm', '-u', work / 'v-viewer.o'], text=True)
    assert not re.search(r'\b_?(?:malloc|realloc|free|memdup|new_array\w*)\b', imports), imports
    assert re.search(r'\b_?vnf_calloc\b', imports), imports
    print(results[1][0].decode(), end='')
    print('VNC viewer: 34 exact C/V protocol, pixel, Xlib and ownership traces; ASan/UBSan PASS')


def native(work, headers, arch):
    v_arch = 'arm64' if arch == 'aarch64' else 'amd64'
    core, fixture, api = generate(work, v_arch, guest=True)
    compiler = os.environ.get('CC_ARM64' if arch == 'aarch64' else 'CC_AMD64',
                              arch + '-linux-musl-gcc')
    flags = [compiler] + WARNINGS + ['-idirafter', str(headers)]
    obj, model = work / (arch + '-core.o'), work / (arch + '-fixture.o')
    subprocess.run(flags + REMAP + ['-c', core, '-o', obj], check=True)
    subprocess.run(flags + ['-include', api, '-c', fixture, '-o', model], check=True)
    binary = work / (arch + '-viewer')
    subprocess.run([compiler, '-static', model, obj, '-o', binary], check=True)
    print(f'Native {arch} V model: {binary}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--headers', type=Path, default=ROOT / 'build-aarch64-userland/staging/usr/include')
    parser.add_argument('--state-dir', type=Path)
    parser.add_argument('--native', choices=('aarch64', 'x86_64'))
    args = parser.parse_args()
    if args.native and not args.state_dir:
        parser.error('--native requires --state-dir to retain the guest ELF')
    if args.state_dir:
        work = args.state_dir.resolve()
        if work == ROOT or ROOT in work.parents:
            parser.error('Frozen C and generated artifacts must remain outside the checkout')
        work.mkdir(parents=True, exist_ok=True)
        host(work, args.headers)
        if args.native:
            native(work, args.headers, args.native)
    else:
        with tempfile.TemporaryDirectory(prefix='vinix-vnc-model-') as directory:
            host(Path(directory), args.headers)


if __name__ == '__main__':
    main()
