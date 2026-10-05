#!/usr/bin/env python3
# SPDX-License-Identifier: ISC
"""Cross-build the production V CLI and run all device fixtures in QEMU."""
from pathlib import Path
import argparse, os, platform, runpy, shutil, subprocess, tarfile
root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--arch',choices=('aarch64','x86_64'),required=True)
parser.add_argument('--kernel-dir',type=Path,required=True)
parser.add_argument('--state-dir',type=Path,required=True)
parser.add_argument('--timeout',type=int,default=300)
args=parser.parse_args();state=args.state_dir.resolve();state.mkdir(parents=True,exist_ok=False)
source=state/'core.c';obj=state/'core.o';fixture=state/'init'
subprocess.run(['python3',str(root/'tools/m1-wifi/compile-v.py'),str(source),'--arch','arm64' if args.arch=='aarch64' else 'amd64'],check=True)
common=['-std=gnu11','-O2','-fwrapv','-fno-strict-aliasing','-fno-stack-protector','-Wall','-Wextra','-Werror','-I'+str(root/'tools/m1-wifi'),'-iquote',str(root/'kernel/c')]
if args.arch=='aarch64':
    llvm=Path(os.environ.get('LLVM_BIN','/opt/homebrew/opt/llvm/bin'))
    sysroot=Path(os.environ.get('VINIX_AARCH64_SYSROOT',str(root/'build-aarch64-userland/staging')))
    gcc=next((sysroot/'usr/lib/gcc/aarch64-alpine-linux-musl').glob('*'))
    cc=[str(llvm/'clang'),'--target=aarch64-linux-musl','-nostdinc','-isystem',str(root/'build-support/aarch64-cc-shim'),'-isystem',str(gcc/'include'),'-isystem',str(sysroot/'usr/include')]
    start=['-static','-nostdlib',str(sysroot/'usr/lib/crt1.o'),str(sysroot/'usr/lib/crti.o'),str(gcc/'crtbeginT.o')]
    end=['-L'+str(sysroot/'usr/lib'),'-L'+str(gcc),'-lc','-lgcc',str(gcc/'crtend.o'),str(sysroot/'usr/lib/crtn.o'),'-fuse-ld=lld','-B'+str(llvm)]
else:
    cc=[os.environ.get('CC_AMD64','/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc')]
    start=['-static'];end=[]
hooks=['open','close','read','tcgetattr','tcsetattr','nanosleep','ioctl']
subprocess.run(cc+common+['-Dmain=test_program_main',*['-D'+h+'=test_'+h for h in hooks],'-c',str(source),'-o',str(obj)],check=True)
subprocess.run(cc+common+start+[str(root/'tests/kernel-gaps/serial.c'),str(root/'tests/m1-wifi/ctl_guest.c'),str(obj)]+end+['-o',str(fixture)],check=True)
rootfs=state/'rootfs'
for directory in ('sbin','dev','proc','sys','tmp','root'):(rootfs/directory).mkdir(parents=True,exist_ok=True)
shutil.copy2(fixture,rootfs/'sbin/init')
archive=state/'initramfs.tar'
with tarfile.open(archive,'w',format=tarfile.USTAR_FORMAT) as tar:tar.add(rootfs,arcname='.')
env=os.environ.copy();harness=runpy.run_path(str(root/'tests/kernel-gaps/run.py'))
if args.arch=='aarch64':
    env.update(VINIX_KERNEL_DIR=str(args.kernel_dir.resolve()),VINIX_INITRAMFS=str(archive),VINIX_BOOT_DISK=str(state/'boot.img'),VINIX_EFIVARS=str(state/'efivars.fd'),VINIX_QEMU_HOST_SOURCE='0',VINIX_QEMU_PACKAGE_STORE=str(state/'packages.tar'),VINIX_QEMU_AUDIO='off',VINIX_QEMU_NETWORK='0',VINIX_QEMU_EXTRA=f'-qmp unix:{state / "qmp.sock"},server=on,wait=off')
    if platform.system()!='Darwin':env.setdefault('USE_TCG','1')
    command=[str(root/'scripts/run-aarch64.sh'),'--no-build','--serial','--no-persist','--mem=1024',f'--guest-init={fixture}']
else:
    iso=state/'test.iso';build=state/'iso-build';cache=root/'build-amd64-iso/limine'
    if cache.is_dir():build.mkdir();shutil.copytree(cache,build/'limine')
    env.update(VINIX_AMD64_KERNEL=str(args.kernel_dir.resolve()/'bin/vinix'),VINIX_AMD64_INITRAMFS=str(archive),VINIX_AMD64_ISO=str(iso),VINIX_AMD64_ISO_BUILD_DIR=str(build))
    subprocess.run([str(root/'build-support/build-amd64-iso.sh')],env=env,check=True)
    qemu=shutil.which(os.environ.get('VINIX_QEMU_X86_64','qemu-system-x86_64'))
    if not qemu:raise SystemExit('qemu-system-x86_64 is required')
    firmware=Path(os.environ.get('VINIX_OVMF_CODE',str(Path(qemu).parent.parent/'share/qemu/edk2-x86_64-code.fd')))
    command=[qemu,'-machine','q35,smm=off','-accel','tcg','-cpu','max','-m','1024','-smp','2','-drive',f'if=pflash,format=raw,unit=0,readonly=on,file={firmware}','-cdrom',str(iso),'-display','none','-monitor','none','-qmp',f'unix:{state / "qmp.sock"},server=on,wait=off','-serial','mon:stdio','-no-reboot','-nic','none']
raise SystemExit(harness['boot'](command,env,state,['VINIX_WIFI_CTL_VM_PASS'],['KERNEL PANIC','FATAL EXCEPTION','FAIL:','Assertion'],args.timeout))
