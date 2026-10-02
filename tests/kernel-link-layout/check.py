#!/usr/bin/env python3
"""Relink actual kernel objects to verify shuffled and reproducible layouts."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--kernel', type=Path, required=True)
parser.add_argument('--arch', choices=('aarch64', 'x86_64'), required=True)
args = parser.parse_args()
root = args.kernel.resolve()
linker = os.environ.get('LD', shutil.which('ld.lld'))
nm = os.environ.get('NM', shutil.which('llvm-nm'))
if not linker or not nm:
    raise SystemExit('ld.lld and llvm-nm are required')
objects = sorted((root / 'obj/c').rglob('*.o')) + sorted((root / 'obj/asm').rglob('*.o'))
script = 'linker-aarch64.ld' if args.arch == 'aarch64' else 'linker.ld'
emulation = 'aarch64elf' if args.arch == 'aarch64' else 'elf_x86_64'
page = '0x4000' if args.arch == 'aarch64' else '0x1000'
base = [linker, '-m', emulation, '--build-id=none', '--nostdlib', '--static',
        '-z', 'max-page-size=' + page, '--gc-sections', '-T', str(root / script),
        str(root / 'obj/blob.c.o'), *map(str, objects),
        str(root / f'cc-runtime-{args.arch}/cc-runtime.a')]
with tempfile.TemporaryDirectory(prefix='vinix-link-layout-') as directory:
    work = Path(directory)
    images = []
    symbols = []
    for index, seed in enumerate((12345, 12345, 67890, 0, 0)):
        image = work / str(index)
        subprocess.run([*base, f'--shuffle-sections=.text.*={seed}', '-o', str(image)], check=True)
        images.append(image.read_bytes())
        rows = subprocess.check_output([nm, '-n', str(image)], text=True).splitlines()
        symbols.append([row.split()[-1] for row in rows if len(row.split()) == 3 and row.split()[1] in ('t', 'T')])
    assert images[0] == images[1], 'fixed seed must reproduce the identical ELF'
    assert symbols[0] != symbols[2], 'different seeds must alter function order'
    assert symbols[3] != symbols[4], 'fresh links must choose different layouts'
    assert all('main__kmain' in rows for rows in symbols), 'kernel entry must be retained'
    print(f'Kernel link layout {args.arch}: PASS (fixed seed reproducible; distinct/random seeds differ)')
