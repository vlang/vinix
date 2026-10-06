#!/usr/bin/env python3
"""Boot one 2-core/2-thread x86 guest with each SMT policy."""
import importlib.util
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RUNNER_ROOT = Path(os.environ.get('VINIX_VM_RUNNER_ROOT', ROOT))
runner_path = RUNNER_ROOT / 'tests/openbsd-security/run_vm.py'
spec = importlib.util.spec_from_file_location('smt_vm', runner_path)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
original_command = runner.command_for


def smt_command(arguments, root):
    command, environment = original_command(arguments, root)
    command[command.index('-smp') + 1] = '4,sockets=1,cores=2,threads=2'
    return command, environment


runner.command_for = smt_command
runner.PASS_MARKER = b'SMT POLICY: PASS'
runner.FAIL_MARKERS = (b'SMT POLICY: FAIL', b'KERNEL PANIC', b'FATAL EXCEPTION')
runner.FEATURE_MARKERS = (b'SMT POLICY: PASS',)
runner.REPORT_MARKER = b''
runner.TEST_LABEL = 'SMT policy'
with tempfile.TemporaryDirectory(prefix='vinix-smt-') as directory:
    work = Path(directory)
    for name in ('sbin', 'dev', 'sys', 'proc', 'root'):
        (work / 'rootfs' / name).mkdir(parents=True)
    compiler = os.environ.get('CC_AMD64', 'x86_64-linux-musl-gcc')
    fixture = work / 'fixture.o'
    compile_module = runpy.run_path(str(ROOT / 'tests/kernel-gaps/compile-v-fixture.py'))['compile_module']
    compile_module(ROOT / 'tests/smt-policy/guestfixture', fixture, 'x86_64',
                   [compiler, '-O2', '-Wall', '-Wextra', '-Werror', '-D_GNU_SOURCE',
                    '-fno-strict-aliasing'])
    subprocess.run([compiler, '-static', '-O2', '-Wall', '-Wextra', '-Werror', str(fixture),
                    '-o', str(work / 'rootfs/sbin/init')], check=True)
    qemu = Path(shutil.which(os.environ.get('VINIX_QEMU_X86_64', 'qemu-system-x86_64')))
    firmware = os.environ.get('VINIX_OVMF_CODE', str(qemu.parent.parent / 'share/qemu/edk2-x86_64-code.fd'))
    for enabled in (False, True):
        (work / 'rootfs/smt-request').write_text('1' if enabled else '0')
        subprocess.run(['tar', '--format=ustar', '-cf', str(work / 'initramfs.tar'),
                        '-C', str(work / 'rootfs'), '.'],
                       env={**os.environ, 'COPYFILE_DISABLE': '1'}, check=True)
        environment = {**os.environ,
            'VINIX_AMD64_KERNEL': os.environ.get('VINIX_AMD64_KERNEL', str(ROOT / 'build-amd64-kernel/bin/vinix')),
            'VINIX_AMD64_INITRAMFS': str(work / 'initramfs.tar'),
            'VINIX_AMD64_ISO': str(work / 'test.iso'),
            'VINIX_AMD64_ISO_BUILD_DIR': str(work / 'iso'),
            'VINIX_CMDLINE': 'vinix.smt=' + ('1' if enabled else '0')}
        subprocess.run([str(RUNNER_ROOT / 'build-support/build-amd64-iso.sh')],
                       env=environment, stdout=subprocess.DEVNULL, check=True)
        sys.argv = [str(runner_path), '--arch', 'amd64', '--iso', str(work / 'test.iso'),
                    '--qemu', str(qemu), '--firmware', firmware, '--capture', str(work / 'unused.pcap'),
                    '--timeout', os.environ.get('VINIX_QEMU_TIMEOUT', '180')]
        if runner.main():
            raise SystemExit(1)
