#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Run the original C fixtures against native V and unmodified lwIP."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
root = Path(__file__).resolve().parents[2]
suite, fixture = sys.argv[1:]
compiler = os.environ.get('CC', 'clang')
with tempfile.TemporaryDirectory(prefix='vinix-' + suite + '-') as directory:
    work = Path(directory)
    (work / 'arch').mkdir()
    options = (root / 'kernel/c/lwipopts.h').read_text()
    if suite in ('network-ipv6', 'network-tcp-lifetime'):
        options = options.replace('#define LWIP_STATS 0', '#define LWIP_STATS 1')
    (work / 'lwipopts.h').write_text(options)
    shutil.copyfile(root / 'kernel/c/arch/cc.h', work / 'arch/cc.h')
    lwip = root / 'kernel/c/lwip'
    generated, obj = work / 'core.c', work / 'core.o'
    subprocess.run([sys.executable, str(root / 'tests/network-options/compile-v-core.py'), str(generated)], check=True)
    flags = ['-O2', '-g', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-Wno-macro-redefined',
             '-I' + str(work), '-I' + str(lwip / 'include')]
    subprocess.run([compiler, *flags, '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
                    '-ffreestanding', '-fno-builtin', '-fno-strict-aliasing', '-DVINIX_V_RUNTIME',
                    '-I' + str(root / 'kernel/c'), '-c', str(generated), '-o', str(obj)], check=True)
    imports = subprocess.check_output(['nm', '-u', str(obj)], text=True)
    if re.search(r'\b_?(?:malloc|calloc|realloc|memdup|new_array\w*|array_new\w*)\b', imports):
        raise RuntimeError('implicit V allocator import: ' + imports)
    print('Network: production V core has no implicit allocator imports', flush=True)
    sources = sorted((lwip / 'core').rglob('*.c')) + [lwip / 'netif/ethernet.c']
    subprocess.run([compiler, *flags, str(root / 'tests' / suite / fixture), str(obj),
                    *map(str, sources), '-o', str(work / 'test')], check=True)
    subprocess.run([str(work / 'test')], check=True, timeout=60)
