#!/usr/bin/env python3
"""Compile the native V volume utility into a target userland tree."""
import argparse
import os
from pathlib import Path
import runpy
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--arch', choices=('aarch64', 'x86_64'), required=True)
    p.add_argument('--staging', type=Path, required=True)
    p.add_argument('--cc')
    a = p.parse_args()
    staging = a.staging.resolve()
    if staging == Path('/') or not staging.is_dir(): p.error('staging must be an existing target filesystem')
    cc = shlex.split(a.cc or os.environ.get(f'VINIX_MUSL_CC_{a.arch.upper()}') or f'{a.arch}-linux-musl-gcc')
    machine = subprocess.check_output(cc + ['-dumpmachine'], text=True).strip()
    if not machine.startswith(a.arch + '-') or 'linux' not in machine: p.error('compiler architecture mismatch')
    generate = runpy.run_path(str(ROOT / 'build-support/compile-v-module.py'))['generate']
    with tempfile.TemporaryDirectory(prefix='vinix-volume-tool-') as directory:
        work = Path(directory)
        source = work / 'volume.c'
        generate(ROOT / 'tools/volumes/volumecli', source, 'arm64' if a.arch == 'aarch64' else 'amd64')
        source.write_text(source.read_text() + '\n_Static_assert(sizeof(volumecli__Request)==32, "V request ABI");\n_Static_assert(sizeof(volumecli__Status)==128, "V status ABI");\n')
        binary = work / 'vinix-volume'
        subprocess.run(cc + ['-static', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
                             '-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label',
                             '-D_GNU_SOURCE', '-DVINIX_V_RUNTIME', '-I', str(ROOT / 'tools/volumes/volumecli'),
                             str(source), '-o', str(binary)], check=True)
        data = binary.read_bytes()
        expected = 183 if a.arch == 'aarch64' else 62
        if data[:6] != b'\x7fELF\x02\x01' or int.from_bytes(data[18:20], 'little') != expected:
            raise RuntimeError('volume utility ELF architecture mismatch')
        destination = staging / 'usr/sbin/vinix-volume'
        destination.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix='.vinix-volume-', dir=destination.parent)
        try:
            with os.fdopen(fd, 'wb') as out: out.write(binary.read_bytes())
            os.chmod(temporary, 0o755)
            os.replace(temporary, destination)
        finally:
            Path(temporary).unlink(missing_ok=True)
    print(f'Staged vinix-volume ({a.arch}).')


if __name__ == '__main__': main()
