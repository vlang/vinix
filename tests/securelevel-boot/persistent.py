#!/usr/bin/env python3
"""Run the security, shared alias and append suite on a persistent ext2 volume."""
import argparse
import importlib.util
import os
from pathlib import Path
import platform
import runpy
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kernel-dir', type=Path, default=ROOT / 'kernel')
    parser.add_argument('--state-dir', type=Path)
    args = parser.parse_args()
    state = (args.state_dir or Path(tempfile.mkdtemp(prefix='vinix-securelevel-ext2-'))).resolve()
    state.mkdir(parents=True, exist_ok=True)
    if (state / 'root.ext2').exists():
        parser.error('Use a fresh state directory for the ext2 checks')
    sysroot = Path(os.environ.get('VINIX_AARCH64_SYSROOT', str(ROOT / 'build-aarch64-userland/sysroot')))
    serial = runpy.run_path(str(ROOT / 'tests/kernel-gaps/compile-v-fixture.py'))['compile_serial'](
        state / 'serial.o', 'aarch64', [os.environ.get('CC', 'clang'), '--target=aarch64-linux-musl',
                                      f'--sysroot={sysroot}', '-O2', '-Wall', '-Wextra', '-Werror'])
    subprocess.run([os.environ.get('CC', 'clang'), '--target=aarch64-linux-musl', f'--sysroot={sysroot}',
                    '-static', '-pthread', '-O2', '-fno-stack-protector', '-Wall', '-Wextra', '-Werror',
                    '-DTEST_DIR="/root"', '-DSECURELEVEL_EXT2',
                    str(Path(__file__).with_name('guest.c')), str(serial),
                    f'-L{sysroot / "lib"}', '-fuse-ld=lld', '-o', str(state / 'init')], check=True)
    rootfs = state / 'rootfs'
    for directory in ('root', 'sbin', 'tmp'):
        (rootfs / directory).mkdir(parents=True, exist_ok=True)
    with tarfile.open(state / 'initramfs.tar', 'w', format=tarfile.USTAR_FORMAT) as archive:
        archive.add(rootfs, arcname='.')
    environment = os.environ.copy()
    environment.update(VINIX_KERNEL_DIR=str(args.kernel_dir.resolve()), VINIX_INITRAMFS=str(state / 'initramfs.tar'),
                       VINIX_BOOT_DISK=str(state / 'boot.img'), VINIX_EFIVARS=str(state / 'efivars.fd'),
                       VINIX_QEMU_PACKAGE_STORE=str(state / 'packages.tar'), VINIX_QEMU_HOST_SOURCE='0',
                       VINIX_QEMU_PERSIST_DISK=str(state / 'root.ext2'), VINIX_QEMU_PERSIST_SIZE_MB='64',
                       VINIX_QEMU_AUDIO='off', VINIX_CMDLINE='vinix.securelevel=1',
                       VINIX_QEMU_EXTRA=f'-qmp unix:{state / "qmp.sock"},server=on,wait=off')
    environment.pop('VINIX_QEMU_PERSIST', None)
    if platform.system() != 'Darwin':
        environment.setdefault('USE_TCG', '1')
    spec = importlib.util.spec_from_file_location('guest', ROOT / 'tests/kernel-gaps/run.py')
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    print(f'Guest artifacts: {state}', flush=True)
    command = [str(ROOT / 'scripts/run-aarch64.sh'), '--no-build', '--serial', '--mem=1024', f'--guest-init={state / "init"}']
    result = helper.boot(command, environment, state, ['SECURELEVEL ALL PASS'],
                         ['SECURELEVEL FAIL:', 'KERNEL PANIC', 'FATAL EXCEPTION'], 240)
    if result:
        raise SystemExit('Native ext2 security test failed')
    e2fsck = os.environ.get('E2FSCK', shutil.which('e2fsck') or '/opt/homebrew/opt/e2fsprogs/sbin/e2fsck')
    debugfs = os.environ.get('DEBUGFS', shutil.which('debugfs') or '/opt/homebrew/opt/e2fsprogs/sbin/debugfs')
    subprocess.run([e2fsck, '-fn', str(state / 'root.ext2')], check=True)
    for path, flags in (('/sealed', '0x10'), ('/append', '0x20'), ('/mapped-seal', '0x10')):
        inode = subprocess.check_output([debugfs, '-R', f'stat {path}', str(state / 'root.ext2')], text=True)
        print(inode)
        if f'Flags: {flags}' not in inode:
            raise SystemExit(f'Host ext2 inspection found incorrect persisted protection flags: {path}')
    print('SECURELEVEL EXT2 PASS: native enforcement, append positions/limits and persisted flags')


if __name__ == '__main__':
    main()
