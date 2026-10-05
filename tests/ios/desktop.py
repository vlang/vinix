#!/usr/bin/env python3
"""Boot a minimal Vinix desktop, click the iOS binary's buttons, save its screen."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


class QMP:
    def __init__(self, path):
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.settimeout(10)
        self.socket.connect(str(path))
        self.file = self.socket.makefile('rb')
        json.loads(self.file.readline())
        self.call('qmp_capabilities')

    def call(self, command, arguments=None):
        self.socket.sendall((json.dumps(dict(execute=command, arguments=arguments or {}))+'\n').encode())
        while True:
            reply = json.loads(self.file.readline())
            if 'error' in reply:
                raise RuntimeError(reply)
            if 'return' in reply:
                return reply['return']

    def click(self, x, y):
        self.call('input-send-event', {'events': [
            {'type': 'abs', 'data': {'axis': 'x', 'value': round(x*32767/2048)}},
            {'type': 'abs', 'data': {'axis': 'y', 'value': round(y*32767/1536)}},
            {'type': 'btn', 'data': {'button': 'left', 'down': True}}]})
        time.sleep(.15)
        self.call('input-send-event', {'events': [
            {'type': 'btn', 'data': {'button': 'left', 'down': False}}]})
        time.sleep(.4)

    def swipe(self, x0, y0, x1, y1):
        def move(x, y):
            self.call('input-send-event', {'events': [
                {'type': 'abs', 'data': {'axis': 'x', 'value': round(x*32767/2048)}},
                {'type': 'abs', 'data': {'axis': 'y', 'value': round(y*32767/1536)}}]})
        move(x0,y0)
        self.call('input-send-event', {'events': [{'type': 'btn', 'data': {'button': 'left', 'down': True}}]})
        time.sleep(.1)
        for i in range(1,7):
            move(x0+(x1-x0)*i/6, y0+(y1-y0)*i/6)
            time.sleep(.04)
        self.call('input-send-event', {'events': [{'type': 'btn', 'data': {'button': 'left', 'down': False}}]})
        time.sleep(.4)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--desktop', type=Path, default=ROOT/'build/vinix-desktop')
    parser.add_argument('--timeout', type=int, default=120)
    parser.add_argument('--app', choices=['calculator', '2048'], default='calculator')
    args = parser.parse_args()
    build = ROOT/'build/ios'
    if not args.desktop.is_file():
        parser.error('build the desktop with ./scripts/build-desktop-aarch64.sh first')
    qmp_path = Path(f'/tmp/vinix-ios-{os.getpid()}.qmp')
    with tempfile.TemporaryDirectory(prefix='vinix-ios-desktop-') as directory:
        work = Path(directory)
        rootfs = work/'rootfs'
        for name in ['run', 'root', 'sbin', 'usr/bin', 'usr/share/vinix/icons', 'dev', 'tmp', 'proc', 'sys']:
            (rootfs/name).mkdir(parents=True, exist_ok=True)
        shutil.copy2(args.desktop, rootfs/'usr/bin/vinix-desktop')
        shutil.copytree(build/'staging/usr', rootfs/'usr', dirs_exist_ok=True, symlinks=True)
        shutil.copy2(ROOT/'desktop/assets/calculator.qoi', rootfs/'usr/share/vinix/icons/calculator.qoi')
        sysroot = ROOT/'build-aarch64-userland/sysroot'
        subprocess.run(['clang', '--target=aarch64-linux-musl', f'--sysroot={sysroot}',
            '-static', '-O2', '-fno-stack-protector', '-Wall', '-Wextra', '-Werror',
            '-DIOS_TEST_APP="'+('iOS 2048' if args.app == '2048' else 'iOS Calculator')+'"',
            str(ROOT/'tests/ios/desktop-init.c'), f'-L{sysroot}/lib', '-fuse-ld=lld',
            '-o', str(work/'init')], check=True)
        subprocess.run(['tar', '--format=ustar', '-cf', str(work/'rootfs.tar'), '-C', str(rootfs), '.'],
            env={**os.environ, 'COPYFILE_DISABLE': '1'}, check=True)
        environment = {**os.environ, 'VINIX_INITRAMFS': str(work/'rootfs.tar'),
            'VINIX_BOOT_DISK': str(work/'boot.img'), 'VINIX_EFIVARS': str(work/'efivars.fd'),
            'VINIX_QEMU_PACKAGE_STORE': str(work/'packages.tar'),
            'VINIX_QEMU_PERSIST_DISK': str(work/'root.ext2'), 'VINIX_QEMU_PERSIST_SIZE_MB': '64',
            'VINIX_QEMU_HOST_SOURCE': '0', 'VINIX_QEMU_NETWORK': '0', 'VINIX_QEMU_AUDIO': 'off',
            'VINIX_QEMU_CLIPBOARD': '0', 'VINIX_KEEP_TEMP_BOOT_DISK': '1',
            'VINIX_OVMF_CODE': str(ROOT/'boot-image/edk2-aarch64-code-2048x1536.fd'),
            'VINIX_QEMU_RESOLUTION': '2048x1536x32',
            'VINIX_QEMU_EXTRA': f'-qmp unix:{qmp_path},server,nowait'}
        environment.pop('VINIX_QEMU_PERSIST', None)
        environment.pop('VINIX_QEMU_OVERLAY', None)
        environment.pop('VINIX_QEMU_ROOT_DISK', None)
        name = '2048' if args.app == '2048' else 'calculator'
        log_path = build/('2048-desktop.log' if args.app == '2048' else 'desktop.log')
        with log_path.open('wb') as log:
            process = subprocess.Popen([str(ROOT/'scripts/run-aarch64.sh'), '--no-build', '--serial',
                '--mem=2048', f'--guest-init={work}/init'], env=environment,
                stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                deadline = time.monotonic()+args.timeout
                while time.monotonic() < deadline:
                    transcript = log_path.read_bytes()
                    if b'FAIL:' in transcript or b'KERNEL PANIC' in transcript or process.poll() is not None:
                        raise RuntimeError('desktop boot failed; see '+str(log_path))
                    if b'vinix-desktop: ready' in transcript:
                        break
                    time.sleep(.2)
                else:
                    raise RuntimeError('desktop startup timed out; see '+str(log_path))
                qmp = QMP(qmp_path)
                time.sleep(1)
                qmp.call('screendump', {'filename': str(build/(name+'-before.ppm'))})
                # The single window opens at (120,60), with a 34-pixel title.
                # These centers come from the app's own 390x680 layout.
                if args.app == '2048':
                    qmp.click(120+160, 94+284) # Upstream storyboard's Play Game.
                    for i in range(16):
                        x0,y0,x1,y1 = [(420,434,220,434), (315,534,315,334),
                                      (220,434,420,434), (315,334,315,534)][i%4]
                        qmp.swipe(x0,y0,x1,y1)
                else:
                    for x, y in [(177.75,441.75), (452.25,624.75), (269.25,533.25), (452.25,716.25)]:
                        qmp.click(x, y)
                time.sleep(1)
                qmp.call('screendump', {'filename': str(build/(name+'.ppm'))})
                transcript = log_path.read_bytes()
                if args.app == '2048':
                    import re
                    scores = [int(v) for v in re.findall(rb'iOS UILabel: SCORE: (\d+)', transcript)]
                    if not scores or max(scores) < 4:
                        raise RuntimeError('real desktop swipes did not merge tiles; see '+str(log_path))
                    print('Vinix desktop: upstream iOS-2048 launched; pointer swipes reached score', max(scores))
                elif b'iOS UILabel: 12' not in transcript:
                    raise RuntimeError('real desktop clicks did not calculate 12; see '+str(log_path))
                qmp.call('quit')
                process.wait(timeout=10)
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=10)
                qmp_path.unlink(missing_ok=True)
    if args.app == 'calculator':
        print('Vinix desktop: unmodified iOS Mach-O launched; real clicks calculated 7+5=12')
    print('Screenshot:', build/(name+'.ppm'))


if __name__ == '__main__':
    main()
