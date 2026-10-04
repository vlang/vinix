#!/usr/bin/env python3
"""Exercise genuine dynamic-musl ARM64 signal return in an isolated QEMU VM."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kernel-dir', type=Path, default=ROOT / 'kernel')
    parser.add_argument('--state-dir', type=Path, required=True)
    parser.add_argument('--runner-root', type=Path, default=ROOT,
                        help='repository containing run-aarch64.sh and its boot dependencies')
    parser.add_argument('--musl', type=Path,
                        default=ROOT / 'build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/lib/ld-musl-aarch64.so.1',
                        help='genuine ARM64 musl loader/libc image to exercise dynamically')
    parser.add_argument('--cc', default=os.environ.get('VINIX_AARCH64_CC', 'aarch64-linux-musl-gcc'))
    parser.add_argument('--timeout', type=int, default=90)
    parser.add_argument('--build-only', action='store_true')
    args = parser.parse_args()
    state = args.state_dir.resolve()
    if state.exists():
        parser.error('Use a fresh state directory to preserve prior evidence')
    kernel = args.kernel_dir.resolve() / 'bin/vinix'
    loader = args.musl.resolve()
    runner = args.runner_root.resolve()
    boot_helper = runner / 'tests/kernel-gaps/run.py'
    script = runner / 'run-aarch64.sh'
    if not all(p.is_file() for p in (kernel, loader, boot_helper, script)) or args.timeout <= 0:
        parser.error('Built kernel, musl image, repository runner, and positive timeout required')
    cc = shutil.which(args.cc)
    if not cc:
        parser.error(f'ARM64 musl compiler unavailable: {args.cc}')
    state.mkdir(parents=True)
    flags = ['-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fno-stack-protector',
             '-Wl,-z,max-page-size=65536']
    commands = [[cc, *flags, str(HERE / 'probe.c'), '-ldl', '-o', str(state / 'signal-return-probe')],
                [cc, *flags, '-static', str(HERE / 'init.c'), '-o', str(state / 'init')]]
    for command in commands:
        subprocess.run(command, check=True)
    (state / 'sources').mkdir()
    for name in ('probe.c', 'init.c', 'run.py'):
        shutil.copy2(HERE / name, state / 'sources' / name)
    rootfs = state / 'rootfs'
    for name in ('sbin', 'bin', 'lib', 'dev', 'proc', 'sys', 'tmp', 'root'):
        (rootfs / name).mkdir(parents=True)
    shutil.copy2(state / 'init', rootfs / 'sbin/init')
    shutil.copy2(state / 'signal-return-probe', rootfs / 'bin/signal-return-probe')
    shutil.copy2(loader, rootfs / 'lib/ld-musl-aarch64.so.1')
    (rootfs / 'lib/libc.musl-aarch64.so.1').symlink_to('ld-musl-aarch64.so.1')
    snapshot = state / 'kernel/bin/vinix'
    snapshot.parent.mkdir(parents=True)
    shutil.copy2(kernel, snapshot)
    archive = state / 'initramfs.tar'
    with tarfile.open(archive, 'w', format=tarfile.USTAR_FORMAT) as tar:
        tar.add(rootfs, arcname='.')
    receipt = {
        'kind': 'genuine-dynamic-musl-signal-return', 'commands': commands,
        'inputs': {str(p): sha(p) for p in
                   (HERE / 'probe.c', HERE / 'init.c', HERE / 'run.py', loader, kernel, script, boot_helper)},
        'outputs': {str(p.relative_to(state)): sha(p) for p in
                    (state / 'signal-return-probe', state / 'init', snapshot, archive)},
    }
    (state / 'build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if args.build_only:
        return 0
    spec = importlib.util.spec_from_file_location('kernel_gaps_boot', boot_helper)
    harness = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(harness)
    env = os.environ.copy()
    env.update(VINIX_KERNEL_DIR=str(state / 'kernel'), VINIX_INITRAMFS=str(archive),
               VINIX_BOOT_DISK=str(state / 'boot.img'), VINIX_EFIVARS=str(state / 'efivars.fd'),
               VINIX_QEMU_HOST_SOURCE='0', VINIX_QEMU_PACKAGE_STORE=str(state / 'packages.tar'),
               VINIX_QEMU_AUDIO='off', VINIX_QEMU_NETWORK='0',
               VINIX_QEMU_EXTRA=f'-qmp unix:{state / "qmp.sock"},server=on,wait=off')
    command = [str(script), '--no-build', '--serial', '--no-persist', '--mem=1024',
               f'--guest-init={state / "init"}']
    expected = ['SIGNAL-RETURN-PASS signals=', 'SIGNAL-RETURN-CHILD-EXIT status=0']
    failures = ['KERNEL PANIC', 'FATAL EXCEPTION', 'FAIL:']
    verdict = harness.boot(command, env, state, expected, failures, args.timeout)
    serial = (state / 'serial.log').read_text(errors='replace')
    result = {
        'verdict': verdict, 'command': command, 'expected': expected,
        'failures': [marker for marker in failures if marker in serial],
        'build_sha256': sha(state / 'build.json'), 'serial_sha256': sha(state / 'serial.log'),
        'kernel_sha256': sha(snapshot), 'probe_sha256': sha(state / 'signal-return-probe'),
    }
    (state / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return verdict


if __name__ == '__main__':
    raise SystemExit(main())
