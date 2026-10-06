#!/usr/bin/env python3
"""Exercise the exact CPUID/MSR policy with an independent V oracle."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def build(work, arch, flags, original=None, guest=False):
    work.mkdir(parents=True, exist_ok=False)
    helper = runpy.run_path(str(ROOT / 'tests/kernel-gaps/compile-v-fixture.py'))
    generate = runpy.run_path(str(ROOT / 'build-support/compile-v-module.py'))['generate']
    production = work / 'speculationpolicy'
    production.mkdir()
    hashes = {}
    for source, target in (('speculation.v', 'policy.v'), ('speculation_amd64.v', 'ports.v')):
        path = ROOT / 'kernel/lib' / source
        text = path.read_text()
        hashes[str(path.relative_to(ROOT))] = hashlib.sha256(text.encode()).hexdigest()
        (production / target).write_text(text.replace('module lib', 'module speculationpolicy', 1))
    source = work / 'policy.c'
    generate(production, source, 'arm64' if arch == 'aarch64' else 'amd64', ('nofloat', 'speculation_test'))
    compile_flags = [f for f in flags if not f.startswith(('-L', '-l', '-fuse-ld='))]
    core = work / 'policy.o'
    subprocess.run(compile_flags + ['-Wno-unused-function', '-Wno-unused-parameter', '-ffreestanding',
                   '-fno-builtin', '-fno-strict-aliasing', '-c', str(source), '-o', str(core)], check=True)
    shutil.copyfile(ROOT / 'kernel/c/speculation.h', work / 'speculation.h')
    fixture_flags = flags + ['-I', str(work)] + (['-Dmain=speculation_native_main'] if guest else [])
    fixture = work / 'fixture.o'
    if original:
        (work / 'fixture.c').write_bytes(original.read_bytes())
        fixture_cc = [f for f in fixture_flags if not f.startswith(('-L', '-l', '-fuse-ld='))]
        subprocess.run(fixture_cc + ['-c', str(work / 'fixture.c'), '-o', str(fixture)], check=True)
    else:
        helper['compile_module'](HERE / 'fixture', fixture, arch, fixture_flags)
    objects = [core, fixture]
    imports = subprocess.check_output([os.environ.get('NM', 'nm'), '-u', *map(str, objects)], text=True)
    assert not re.search(r'\b_?(?:malloc|calloc|realloc|free|aligned_alloc|posix_memalign|memdup|new_array\w*|v_malloc)\b', imports), imports
    if guest:
        entry = work / 'entry'
        entry.mkdir()
        (entry / 'entry-native-abi.h').write_text('#include <stdio.h>\n#include <unistd.h>\nint speculation_native_main(void);\n')
        (entry / 'core.v').write_text("""module entry
#include <entry-native-abi.h>
fn C.speculation_native_main() i32
fn C.fflush(voidptr) i32
fn C.pause() i32
@[export: 'main']
pub fn run() i32 {
    result := C.speculation_native_main()
    unsafe { C.fflush(nil) }
    if result == 0 { for { C.pause() } }
    return result
}
""")
        objects.append(helper['compile_module'](entry, work / 'entry.o', arch, flags))
        objects.append(helper['compile_serial'](work / 'serial.o', arch, flags))
    executable = work / 'test'
    subprocess.run(flags + (['-static'] if guest else []) + list(map(str, objects)) + ['-o', str(executable)], check=True)
    manifest = {'arch': arch, 'original': str(original) if original else None, 'guest': guest,
                'compiler_flags': flags, 'production_sources': hashes,
                'generated_policy_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                'fixture_source_sha256': hashlib.sha256((work / 'fixture.c').read_bytes()).hexdigest(),
                'executable_sha256': hashlib.sha256(executable.read_bytes()).hexdigest(), 'imports': imports.splitlines()}
    (work / 'inputs.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return executable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', choices=('aarch64', 'x86_64'))
    parser.add_argument('--host-arch', choices=('arm64', 'amd64'), default='arm64' if os.uname().machine in ('arm64', 'aarch64') else 'amd64')
    parser.add_argument('--state-dir', type=Path)
    parser.add_argument('--original-reference', type=Path)
    parser.add_argument('--kernel-dir', type=Path)
    parser.add_argument('--guest-state-dir', type=Path)
    args = parser.parse_args()
    if args.arch and (not args.kernel_dir or not args.guest_state_dir or not args.state_dir):
        parser.error('native run needs --state-dir, --kernel-dir and --guest-state-dir')
    with tempfile.TemporaryDirectory(prefix='vinix-speculation-policy-') as directory:
        work = args.state_dir.resolve() if args.state_dir else Path(directory)
        if args.state_dir:
            work.mkdir(parents=True, exist_ok=False)
        arch = args.arch or ('aarch64' if args.host_arch == 'arm64' else 'x86_64')
        if args.arch == 'aarch64':
            sdk = Path(os.environ.get('VINIX_AARCH64_SYSROOT', ROOT / 'build-aarch64-userland/sysroot'))
            cc = [os.environ.get('CC_AARCH64', 'clang'), '--target=aarch64-linux-musl', f'--sysroot={sdk}', '-fuse-ld=lld', f'-L{sdk}/lib']
        elif args.arch:
            cc = [os.environ.get('CC_AMD64', 'x86_64-linux-musl-gcc')]
        else:
            cc = [os.environ.get('CC', 'clang')]
            if os.uname().sysname == 'Darwin':
                cc += ['-arch', 'arm64' if arch == 'aarch64' else 'x86_64']
        flags = cc + ['-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror']
        if not args.arch:
            flags += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
        if args.arch:
            binary = build(work / 'native', arch, flags, args.original_reference, True)
            return subprocess.call(['python3', str(ROOT / 'tests/kernel-gaps/run.py'), '--arch', arch,
                '--no-network', '--kernel-dir', str(args.kernel_dir), '--prebuilt-init', str(binary),
                '--state-dir', str(args.guest_state_dir), '--expect', 'SPECULATION POLICY PASS (6144 cases)',
                '--fail', 'Assertion', '--timeout', '3600'])
        translated = build(work / 'v', arch, flags)
        environment = {**os.environ, 'ASAN_OPTIONS': 'detect_leaks=1', 'UBSAN_OPTIONS': 'halt_on_error=1'}
        v = subprocess.run([str(translated)], capture_output=True, env=environment, timeout=180)
        assert v.returncode == 0 and v.stdout == b'SPECULATION POLICY PASS (6144 cases)\n', (v.returncode, v.stdout, v.stderr)
        assert not re.search(rb'runtime error|AddressSanitizer|LeakSanitizer', v.stderr)
        if args.original_reference:
            original = build(work / 'c', arch, flags, args.original_reference)
            c = subprocess.run([str(original)], capture_output=True, env=environment, timeout=180)
            assert (v.returncode, v.stdout, v.stderr) == (c.returncode, c.stdout, c.stderr), (c, v)
        (work / 'stdout').write_bytes(v.stdout)
        (work / 'stderr').write_bytes(v.stderr)
        print(v.stdout.decode(), end='')
        return 0


if __name__ == '__main__':
    raise SystemExit(main())
