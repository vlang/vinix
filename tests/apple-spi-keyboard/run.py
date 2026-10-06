#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compare frozen SPI packet/PIO goldens and run both native model ABIs."""
import argparse
from contextlib import nullcontext
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ORIGINAL = 'fb74d12ab3ac2510500fbd3393f3374864d23967'
PORTS = {'keyboard': HERE / 'keyboardfixture',
         'touchpad': ROOT / 'tests/apple-spi-touchpad/touchpadfixture'}
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--state-dir', type=Path)
p.add_argument('--suite', choices=('keyboard', 'touchpad', 'both'), default='both')
p.add_argument('--host-arch', choices=('arm64', 'amd64'), default='arm64' if os.uname().machine in ('arm64', 'aarch64') else 'amd64')
p.add_argument('--arch', choices=('aarch64', 'x86_64'))
p.add_argument('--build-only', action='store_true')
p.add_argument('--kernel-dir', type=Path)
p.add_argument('--guest-state-dir', type=Path)
a = p.parse_args()
if a.arch and (not a.kernel_dir or not a.guest_state_dir):
    p.error('--arch requires --kernel-dir and --guest-state-dir')
if a.arch and (a.suite == 'both' or a.suite not in PORTS):
    p.error('native checks require one migrated --suite')
if a.state_dir:
    a.state_dir.mkdir(parents=True, exist_ok=False)
context = nullcontext(str(a.state_dir.resolve())) if a.state_dir else tempfile.TemporaryDirectory(prefix='vinix-spi-', dir='/tmp')
generate = runpy.run_path(str(ROOT / 'build-support/compile-v-module.py'))['generate']
provider = runpy.run_path(str(HERE / 'provider.py'))['copy_provider']
quiet = ['-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label', '-Wno-unused-variable', '-fwrapv', '-fno-strict-aliasing']
quotes = ['-iquote', str(HERE), '-iquote', str(ROOT / 'kernel/c'), '-iquote', str(ROOT / 'tests/apple-ans'), '-iquote', str(ROOT / 'tests/apple-spi-touchpad')]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(path, nm='nm'):
    imports = subprocess.check_output([nm, '-u', str(path)], text=True)
    assert not re.search(r'\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*|v_malloc)\b', imports), imports
    return imports.splitlines()


def fixture(kind, output, arch, *features):
    subprocess.run(['python3', str(HERE / 'compile-fixture.py'), '--kind', kind, '--arch', arch, '--entry', *features, str(output)], check=True)


with context as directory:
    work = Path(directory)
    reference = work / 'original'
    receipt = {'original_revision': ORIGINAL, 'originals': {}, 'host_arch': a.host_arch, 'source_hashes': {}}
    # Preserve immutable bytes and their original relative include paths.
    for name in ('tests/apple-spi-keyboard/test.c', 'tests/apple-spi-touchpad/test.c', 'tests/apple-spi-keyboard/core_fixture.h', 'kernel/c/apple_spi_keyboard.h'):
        raw = subprocess.check_output(['git', 'show', ORIGINAL + ':' + name], cwd=ROOT)
        path = reference / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
        receipt['originals'][name] = {'sha256': digest(path), 'lines': len(raw.splitlines())}
    suites = ('keyboard', 'touchpad') if a.suite == 'both' else (a.suite,)
    for kind in PORTS:
        for path in sorted(PORTS[kind].glob('*.v')):
            receipt['source_hashes'][str(path.relative_to(ROOT))] = digest(path)
        header = PORTS[kind].parent / (kind + '-native-abi.h')
        receipt['source_hashes'][str(header.relative_to(ROOT))] = digest(header)
    receipt['host_provider'] = provider(ROOT, work / 'spicore', hardware=a.host_arch == 'arm64')
    generate(work / 'spicore', work / 'core.c', a.host_arch, ('nofloat',))
    subprocess.run(['python3', str(ROOT / 'tests/apple-ans/compile-fixture.py'), '--kind', 'platform', '--arch', a.host_arch, str(work / 'platform.c')], check=True)
    target = ['-arch', 'arm64' if a.host_arch == 'arm64' else 'x86_64'] if os.uname().sysname == 'Darwin' else []
    common = [os.environ.get('CC', 'clang'), *target, '-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
    for name in ('core', 'platform'):
        subprocess.run(common + quiet + quotes + ['-ffreestanding', '-fno-builtin'] + (['-DVINIX_V_RUNTIME'] if name == 'core' else []) + ['-c', str(work / (name + '.c')), '-o', str(work / (name + '.o'))], check=True)
        receipt[name + '_imports'] = audit(work / (name + '.o'))
    for kind in suites:
        original = reference / 'tests' / ('apple-spi-' + kind) / 'test.c'
        subprocess.run(common + quotes + [str(original), str(work / 'core.o'), str(work / 'platform.o'), '-o', str(work / (kind + '-original-host'))], check=True)
        expected = subprocess.check_output([str(work / (kind + '-original-host'))])
        (work / (kind + '-original.stdout')).write_bytes(expected)
        if kind in PORTS:
            fixture(kind, work / (kind + '.c'), a.host_arch)
            subprocess.run(common + quiet + quotes + ['-ffreestanding', '-fno-builtin', '-c', str(work / (kind + '.c')), '-o', str(work / (kind + '.o'))], check=True)
            receipt[kind + '_imports'] = audit(work / (kind + '.o'))
            subprocess.run(common + [str(work / (kind + '.o')), str(work / 'core.o'), str(work / 'platform.o'), '-o', str(work / (kind + '-v-host'))], check=True)
            actual = subprocess.check_output([str(work / (kind + '-v-host'))])
            (work / (kind + '-v.stdout')).write_bytes(actual)
            assert actual == expected, (actual, expected)
            receipt[kind + '_generated_sha256'] = digest(work / (kind + '.c'))
        groups = 21 if kind == 'keyboard' else 19
        assert len(expected.decode().splitlines()) == groups + 1, expected
        receipt[kind + '_golden'] = expected.decode().splitlines()
        print(expected.decode(), end='', flush=True)
    (work / 'validation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('PASS frozen original/V SPI goldens, native callbacks, ASan/UBSan and no allocator imports', flush=True)
    if a.arch:
        arch = 'arm64' if a.arch == 'aarch64' else 'amd64'
        receipt['native_provider'] = provider(ROOT, work / 'native/spicore', hardware=a.arch == 'aarch64')
        called = sorted(set(re.findall(r'\b(\w+)\s*\(', original.read_text())))
        omitted = runpy.run_path(str(HERE / 'provider.py'))['HARDWARE_ONLY']
        assert not (set(called) & set(omitted)), called
        receipt['native_provider']['original_fixture_calls'] = called
        (work / 'native-provider.json').write_text(json.dumps(receipt['native_provider'], indent=2) + '\n')
        generate(work / 'native/spicore', work / 'core-native.c', arch, ('nofloat',))
        fixture(a.suite, work / 'fixture-native.c', arch, '--guest')
        fixture(a.suite, work / 'reference-entry.c', arch, '--guest', '--reference')
        subprocess.run(['python3', str(ROOT / 'tests/apple-ans/compile-fixture.py'), '--kind', 'platform', '--arch', arch, str(work / 'platform-native.c')], check=True)
        if a.arch == 'aarch64':
            sysroot = ROOT / 'build-aarch64-userland/sysroot'
            gcc = sorted((ROOT / 'build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl').iterdir())[-1]
            cc = [os.environ.get('CC_AARCH64', '/opt/homebrew/opt/llvm/bin/clang'), '--target=aarch64-linux-musl', '--sysroot=' + str(sysroot), '--gcc-install-dir=' + str(gcc)]
        else:
            cc = [os.environ.get('CC_AMD64', '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc')]
        flags = ['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', *quotes]
        imports = {}
        for name in ('core-native', 'fixture-native', 'reference-entry', 'platform-native'):
            extra = ['-DVINIX_V_RUNTIME', '-ffreestanding', '-fno-builtin'] if name == 'core-native' else []
            if name == 'core-native' and a.arch == 'x86_64':
                extra.append('-Wno-array-parameter')
            subprocess.run(cc + flags + quiet + extra + ['-c', str(work / (name + '.c')), '-o', str(work / (name + '.o'))], check=True)
            imports[name] = audit(work / (name + '.o'), '/opt/homebrew/opt/llvm/bin/llvm-nm')
        subprocess.run(cc + flags + ['-Dmain=vsf_reference_entry', '-c', str(original), '-o', str(work / 'original-native.o')], check=True)
        serial = work / 'serial.o'
        runpy.run_path(str(ROOT / 'tests/kernel-gaps/compile-v-fixture.py'))['compile_serial'](serial, a.arch, cc + flags)
        for variant in ('original', 'v'):
            init = work / (variant + '-native-init')
            objects = [work / 'original-native.o', work / 'reference-entry.o'] if variant == 'original' else [work / 'fixture-native.o']
            objects += [work / 'core-native.o', work / 'platform-native.o', serial]
            subprocess.run(cc + (['-fuse-ld=lld'] if a.arch == 'aarch64' else []) + ['-static', *map(str, objects), '-o', str(init)], check=True)
            command = ['python3', str(ROOT / 'tests/kernel-gaps/run.py'), '--arch', a.arch, '--prebuilt-init', str(init), '--kernel-dir', str(a.kernel_dir), '--state-dir', str(a.guest_state_dir) + '-' + variant, '--no-network', '--timeout', '3600', '--fail', 'SPI FIXTURE FAIL']
            for marker in expected.decode().splitlines():
                command += ['--expect', marker]
            (work / (variant + '-native-inputs.json')).write_text(json.dumps({'arch': a.arch, 'provider': receipt['native_provider'], 'imports': imports, 'init_sha256': digest(init), 'kernel_sha256': digest(a.kernel_dir / 'bin/vinix'), 'command': command}, indent=2) + '\n')
            if not a.build_only:
                subprocess.run(command, check=True)
                print('PASS complete native SPI ' + a.suite + ' ' + variant + ' ' + a.arch, flush=True)
