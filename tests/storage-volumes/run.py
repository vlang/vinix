#!/usr/bin/env python3
"""Qualify production logical volumes on disposable VirtIO/AHCI disks."""
import argparse
import importlib.util
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from contextlib import nullcontext

ROOT = Path(__file__).resolve().parents[2]

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result); return result

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--arch', choices=('aarch64', 'amd64'), default='aarch64')
    p.add_argument('--state-dir', type=Path)
    a = p.parse_args()
    sys.stdout.reconfigure(line_buffering=True)
    if a.state_dir:
        a.state_dir = a.state_dir.resolve()
        if a.state_dir.exists() and any(a.state_dir.iterdir()): p.error('state directory must be empty')
        a.state_dir.mkdir(parents=True, exist_ok=True)
    runner = Path(os.environ.get('VINIX_VM_RUNNER_ROOT', ROOT))
    helper = load('volume_boot', runner / 'tests/disk-no-sync/run_vm.py')
    mapped = load('volume_monitor', runner / 'tests/mapped-writeback/run.py')
    helper.START_MARKER = b'VOLUME START'
    helper.DONE_RE = re.compile(rb'VOLUME DONE (\w+) ino=(\d+)\r*\n')
    helper.FAIL_MARKERS = (b'FAIL END', b'FATAL EXCEPTION', b'KERNEL PANIC')
    context = nullcontext(str(a.state_dir)) if a.state_dir else tempfile.TemporaryDirectory(prefix='vinix-volume-')
    with context as directory:
        work = Path(directory)
        if a.arch == 'aarch64':
            sysroot = Path(os.environ.get('VINIX_AARCH64_SYSROOT', ROOT / 'build-aarch64-userland/sysroot'))
            cc = [os.environ.get('CC', 'clang'), '--target=aarch64-linux-musl', f'--sysroot={sysroot}', f'-L{sysroot / "lib"}', '-fuse-ld=lld']
        else: cc = [os.environ.get('CC_AMD64', 'x86_64-linux-musl-gcc')]
        subprocess.run(cc + ['-static', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-stack-protector', '-pthread', str(ROOT / 'tests/storage-volumes/guest.c'), '-o', str(work / 'init')], check=True)
        seed = work / 'seed'
        for name in ('dev', 'proc', 'tmp', 'run', 'sbin', 'root'): (seed / name).mkdir(parents=True, exist_ok=True)
        shutil.copyfile(work / 'init', seed / 'sbin/init'); (seed / 'sbin/init').chmod(0o755)
        subprocess.run([sys.executable, str(ROOT / 'build-support/storage-tools/stage.py'), '--arch', 'aarch64' if a.arch == 'aarch64' else 'x86_64', '--staging', str(seed), '--cc', ' '.join(cc)], check=True)
        archive = work / 'initramfs.tar'
        with tarfile.open(archive, 'w', format=tarfile.USTAR_FORMAT) as f:
            for name in sorted(seed.iterdir()): f.add(name, name.name)
        disk = work / 'volume.raw'
        with disk.open('wb') as f: f.truncate(16 * 1024 * 1024)
        # Sentinels immediately before and after the full management test area.
        with disk.open('r+b') as f:
            f.seek(1024 * 1024 - 512); f.write(bytes([0xA1]) * 512)
            f.seek(1536 * 1024); f.write(bytes([0xA2]) * 512)
        env = {**os.environ, 'VINIX_INITRAMFS': str(archive), 'VINIX_BOOT_DISK': str(work / 'boot.img'),
               'VINIX_EFIVARS': str(work / 'efivars.fd'), 'VINIX_QEMU_PACKAGE_STORE': str(work / 'packages.tar'),
               'VINIX_QEMU_PERSIST_DISK': str(disk), 'VINIX_QEMU_PERSIST_SIZE_MB': '16',
               'VINIX_KEEP_TEMP_BOOT_DISK': '1', 'VINIX_QEMU_PACKAGE_STORE_PORT': helper.available_port(), 'VINIX_QEMU_NETWORK': '0'}
        env['VINIX_QEMU_PERSIST'] = '0'
        if platform.system() != 'Darwin': env.setdefault('USE_TCG', '1')
        if a.arch == 'aarch64':
            command = [str(runner / 'scripts/run-aarch64.sh'), '--no-build', '--serial', '--mem=1024', '--no-persist', '--no-disk-root', f'--guest-init={work / "init"}']
        else:
            iso = work / 'iso'; iso.mkdir()
            (iso / 'limine').symlink_to(ROOT / 'build-amd64-iso/limine')
            isoenv = {**env, 'VINIX_AMD64_INITRAMFS': str(archive), 'VINIX_AMD64_ISO': str(work / 'test.iso'), 'VINIX_AMD64_ISO_BUILD_DIR': str(iso)}
            subprocess.run([str(runner / 'build-support/build-amd64-iso.sh')], env=isoenv, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            qemu = shutil.which(os.environ.get('VINIX_QEMU_X86_64', 'qemu-system-x86_64'))
            firmware = os.environ.get('VINIX_OVMF_CODE_AMD64', str(Path(qemu).parent.parent / 'share/qemu/edk2-x86_64-code.fd'))
            command = [qemu, '-machine', 'q35,smm=off', '-accel', os.environ.get('VINIX_QEMU_ACCEL', 'tcg'), '-cpu', 'max', '-m', '1024', '-smp', '2',
                       '-drive', f'if=pflash,format=raw,unit=0,readonly=on,file={firmware}', '-cdrom', str(work / 'test.iso'),
                       '-drive', f'if=ide,format=raw,file={disk},cache=writeback', '-display', 'none', '-monitor', 'none', '-serial', 'stdio', '-nic', 'none', '-no-reboot']
        with tempfile.TemporaryDirectory(prefix='vinix-volume-drive-', dir='/tmp') as drive_directory:
            if a.arch == 'aarch64':
                drive = Path(drive_directory) / 'disk.raw'; drive.symlink_to(disk.resolve())
                env['VINIX_QEMU_EXTRA'] = f'-drive if=none,format=raw,file={drive},id=volume-test -device virtio-blk-device,drive=volume-test'
            if not mapped.boot_guest(command, env, helper, int(os.environ.get('VINIX_QEMU_TIMEOUT', '300')), 'full'):
                raise RuntimeError('volume guest qualification failed')
        with disk.open('rb') as f:
            for offset, value in ((1024 * 1024 - 512, 0xA1), (1536 * 1024, 0xA2)):
                f.seek(offset)
                if f.read(512) != bytes([value]) * 512: raise RuntimeError('out-of-volume sentinel changed')
            f.seek(1024 * 1024)
            if f.read(512) != bytes([0x73]) * 512: raise RuntimeError('mapped physical data missing')
        print(f'PASS {a.arch}: volumes, CLI, alias/bounds, growth, removal races, 200-cycle retention and physical sentinels')
    return 0
if __name__ == '__main__': raise SystemExit(main())
