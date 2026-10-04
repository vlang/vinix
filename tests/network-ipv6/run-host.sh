#!/bin/sh
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-network-ipv6.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/arch"
cp "$repo/kernel/c/lwipopts.h" "$work/"
cp "$repo/kernel/c/arch/cc.h" "$work/arch/"
python3 - "$repo" "$work" "${CC:-clang}" <<'PY'
from pathlib import Path
import subprocess
import sys
root, temporary, compiler = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
options = temporary / 'lwipopts.h'
options.write_text(options.read_text().replace('#define LWIP_STATS 0', '#define LWIP_STATS 1'))
lwip = root / 'kernel/c/lwip'
sources = sorted((lwip / 'core').rglob('*.c')) + [lwip / 'netif/ethernet.c']
subprocess.run([compiler, '-O1', '-g', '-fsanitize=address,undefined',
    '-fno-omit-frame-pointer', '-Wno-macro-redefined', '-I' + str(temporary), '-I' + str(lwip / 'include'),
    str(root / 'tests/network-ipv6/host.c'), *map(str, sources),
    '-o', str(temporary / 'test')], check=True)
subprocess.run([str(temporary / 'test')], check=True)
PY
