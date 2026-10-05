#!/usr/bin/env python3
"""Check boot floors, default compatibility, and fail-closed boot parsing."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--arch', choices=('aarch64', 'x86_64'), required=True)
parser.add_argument('--kernel-dir', type=Path, default=root / 'kernel')
parser.add_argument('--state-dir', type=Path)
args = parser.parse_args()
state = args.state_dir or Path(tempfile.mkdtemp(prefix='vinix-securelevel-boots-'))
state.mkdir(parents=True, exist_ok=True)
cases = [('', True), ('vinix.securelevel=-1', True), ('vinix.securelevel=0', True), ('vinix.securelevel=1', True),
         ('vinix.securelevel=2', True), ('vinix.securelevel=invalid', False),
         ('vinix.securelevel=1 vinix.securelevel=2', False), ('vinix.securelevel', False)]
for index, (policy, valid) in enumerate(cases):
    target = state / str(index)
    environment = os.environ.copy()
    environment['VINIX_CMDLINE'] = policy
    expected = 'SECURELEVEL ALL PASS' if valid else 'security: invalid or duplicate vinix.securelevel boot policy'
    command = ['python3', str(root/'tests/kernel-gaps/run.py'), '--arch', args.arch,
               '--kernel-dir', str(args.kernel_dir.resolve()), '--source', str(Path(__file__).with_name('guest.c')),
               '--expect', expected, '--fail', 'SECURELEVEL FAIL:', '--timeout', '240', '--state-dir', str(target)]
    if not valid:
        command += ['--expect-panic', '--fail', 'SECURELEVEL BOOT TEST ENTERED']
    print(f'Boot {index}: {policy or "default"}', flush=True)
    with (state/f'{index}.log').open('w') as log:
        result = subprocess.run(command, cwd=root, env=environment, stdout=log, stderr=subprocess.STDOUT)
    serial_path = target/'serial.log'
    serial = serial_path.read_text(errors='replace') if serial_path.exists() else ''
    if valid:
        if result.returncode or 'SECURELEVEL ALL PASS' not in serial:
            raise SystemExit(f'Valid policy failed; inspect {target} and {state/f"{index}.log"}')
    elif not (result.returncode == 0 and expected in serial and 'KERNEL PANIC' in serial
              and 'SECURELEVEL BOOT TEST ENTERED' not in serial):
        raise SystemExit(f'Malformed policy did not stop before userspace; inspect {state/f"{index}.log"}')
print(f'SECURELEVEL BOOT SUITE PASS: {args.arch}; artifacts {state}')
