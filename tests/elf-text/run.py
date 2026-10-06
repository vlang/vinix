#!/usr/bin/env python3
"""Boot the real ELF loader with textrel fixtures and a dynamically linked PIE."""
import argparse
import importlib.util
import os
import runpy
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', choices=('aarch64', 'x86_64'), required=True)
    parser.add_argument('--kernel-dir', type=Path, required=True)
    parser.add_argument('--state-dir', type=Path)
    args = parser.parse_args()
    runner_root = Path(os.environ.get('VINIX_VM_RUNNER_ROOT', ROOT))
    state = args.state_dir or Path(tempfile.mkdtemp(prefix='vinix-elf-text-vm-'))
    state = state.resolve()
    rootfs = state / 'rootfs'
    for name in ('sbin', 'lib', 'tmp', 'dev', 'proc', 'sys', 'root'):
        (rootfs / name).mkdir(parents=True, exist_ok=True)
    source = ROOT / 'tests/elf-text/guest.c'
    compile_serial = runpy.run_path(str(runner_root / 'tests/kernel-gaps/compile-v-fixture.py'))['compile_serial']
    flags = ['-O2', '-Wall', '-Wextra', '-Werror']
    if args.arch == 'aarch64':
        sysroot = Path(os.environ.get('VINIX_AARCH64_SYSROOT', runner_root / 'build-aarch64-userland/sysroot'))
        loader = Path(os.environ.get('VINIX_AARCH64_LOADER', runner_root / 'build-aarch64-userland/staging/lib/ld-musl-aarch64.so.1'))
        cc = [os.environ.get('CC', 'clang'), '--target=aarch64-linux-musl', f'--sysroot={sysroot}', '-fuse-ld=lld', '-fno-stack-protector']
        serial = compile_serial(state / 'serial.o', args.arch, cc + flags)
        subprocess.run(cc + flags + ['-static', str(serial), str(source), f'-L{sysroot / "lib"}', '-o', str(rootfs / 'sbin/init')], check=True)
        # The build sysroot contains static libc; use the real Alpine loader
        # as the shared libc instead of silently producing a static PIE.
        subprocess.run(cc + flags + ['-fPIE', '-pie', '-nostdlib', str(sysroot / 'lib/Scrt1.o'), str(sysroot / 'lib/crti.o'), str(serial), str(source), str(loader), str(sysroot / 'lib/crtn.o'), '-Wl,--dynamic-linker=/lib/ld-musl-aarch64.so.1', '-o', str(rootfs / 'elf-pie')], check=True)
        loader_name = 'ld-musl-aarch64.so.1'
    else:
        cc = [os.environ.get('CC_AMD64', 'x86_64-linux-musl-gcc')]
        serial = compile_serial(state / 'serial.o', args.arch, cc + flags)
        subprocess.run(cc + flags + ['-static', str(serial), str(source), '-o', str(rootfs / 'sbin/init')], check=True)
        subprocess.run(cc + flags + ['-fPIE', '-pie', str(serial), str(source), '-o', str(rootfs / 'elf-pie')], check=True)
        loader = Path(subprocess.check_output(cc + ['-print-file-name=libc.so'], text=True).strip())
        loader_name = 'ld-musl-x86_64.so.1'
    shutil.copy2(loader, rootfs / 'lib' / loader_name)
    (rootfs / 'lib/libc.so').symlink_to(loader_name)
    archive = state / 'initramfs.tar'
    with tarfile.open(archive, 'w', format=tarfile.USTAR_FORMAT) as tar:
        tar.add(rootfs, arcname='.')
    spec = importlib.util.spec_from_file_location('elf_vm', runner_root / 'tests/kernel-gaps/run.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    environment = {**os.environ, 'VINIX_CMDLINE': 'vinix.user_access=strict'}
    kernel = args.kernel_dir.resolve() / 'bin/vinix'
    if args.arch == 'aarch64':
        environment.update(VINIX_KERNEL_DIR=str(args.kernel_dir.resolve()), VINIX_INITRAMFS=str(archive), VINIX_BOOT_DISK=str(state / 'boot.img'), VINIX_EFIVARS=str(state / 'efivars.fd'), VINIX_QEMU_HOST_SOURCE='0', VINIX_QEMU_AUDIO='off', VINIX_QEMU_NETWORK='0', VINIX_QEMU_PACKAGE_STORE=str(state / 'packages.tar'), VINIX_QEMU_EXTRA=f'-qmp unix:{state / "qmp.sock"},server=on,wait=off')
        launcher = runner_root / 'scripts/run-aarch64.sh'
        if not launcher.is_file():
            launcher = runner_root / 'run-aarch64.sh'
        command = [str(launcher), '--no-build', '--serial', '--no-persist', '--mem=1024', f'--guest-init={rootfs / "sbin/init"}']
    else:
        iso = state / 'test.iso'
        environment.update(VINIX_AMD64_KERNEL=str(kernel), VINIX_AMD64_INITRAMFS=str(archive), VINIX_AMD64_ISO=str(iso), VINIX_AMD64_ISO_BUILD_DIR=str(state / 'iso'))
        subprocess.run([str(runner_root / 'build-support/build-amd64-iso.sh')], env=environment, check=True)
        qemu = shutil.which(os.environ.get('VINIX_QEMU_X86_64', 'qemu-system-x86_64'))
        firmware = os.environ.get('VINIX_OVMF_CODE', str(Path(qemu).parent.parent / 'share/qemu/edk2-x86_64-code.fd'))
        command = [qemu, '-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-m', '1024', '-smp', '2', '-drive', f'if=pflash,format=raw,unit=0,readonly=on,file={firmware}', '-cdrom', str(iso), '-display', 'none', '-monitor', 'none', '-qmp', f'unix:{state / "qmp.sock"},server=on,wait=off', '-serial', 'mon:stdio', '-no-reboot', '-nic', 'none']
    return runner.boot(command, environment, state,
        ['ELF TEXT PASS: ordinary and both textrel encodings', 'ELF TEXT PASS: PIE and interpreter boot'],
        ['ELF TEXT FAIL', 'FATAL EXCEPTION', 'KERNEL PANIC'], 240)


if __name__ == '__main__':
    raise SystemExit(main())
