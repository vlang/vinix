#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Boot each production ARM init policy with small independent native programs."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
INIT=ROOT/'build-support/init-aarch64'
def run(command): subprocess.run([str(value) for value in command],check=True)
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kernel-dir',type=Path,required=True)
    parser.add_argument('--state-dir',type=Path,required=True)
    parser.add_argument('--timeout',type=int,default=600)
    args=parser.parse_args()
    spec=importlib.util.spec_from_file_location('kernel_gap_runner',ROOT/'tests/kernel-gaps/run.py')
    runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
    sysroot=Path(os.environ.get('VINIX_AARCH64_SYSROOT',ROOT/'build-aarch64-userland/sysroot'))
    args.state_dir.mkdir(parents=True,exist_ok=True)
    for policy in ('shell','full','desktop'):
        state=(args.state_dir/policy).resolve();state.mkdir()
        core=state/'init.c';obj=state/'init.o';binary=state/'policy-init';abi=state/'init-abi.o'
        run(['python3',INIT/'compile-v.py',policy,core])
        run(['clang','--target=aarch64-linux-none','-nostdlib','-ffreestanding','-O2','-fno-stack-protector','-fno-builtin','-ffunction-sections','-fdata-sections','-I'+str(INIT),'-c',core,'-o',obj])
        linker=os.environ.get('LD_AARCH64','/opt/homebrew/bin/ld.lld' if Path('/opt/homebrew/bin/ld.lld').exists() else 'ld.lld')
        run(['clang','--target=aarch64-linux-none','-c',INIT/'syscall_abi.S','-o',abi])
        run([linker,'-m','aarch64elf','--nostdlib','-static','--gc-sections','-o',binary,obj,abi])
        fixture=state/'native-program'
        defines={'shell':'INIT_SHELL_DRIVER','full':'INIT_FULL_PROGRAM','desktop':'INIT_DESKTOP_PROGRAM'}
        run(['clang','--target=aarch64-linux-musl','--sysroot='+str(sysroot),'-static','-O2','-fno-stack-protector','-Wall','-Wextra','-Werror','-D'+defines[policy],HERE/'guest.c','-L'+str(sysroot/'lib'),'-fuse-ld=lld','-o',fixture])
        rootfs=state/'rootfs'
        for name in ('sbin','bin','usr/bin','dev','proc','sys','tmp','root','run'): (rootfs/name).mkdir(parents=True,exist_ok=True)
        if policy=='shell':
            shutil.copy2(fixture,rootfs/'sbin/init');shutil.copy2(binary,rootfs/'shell-init')
        else:
            shutil.copy2(binary,rootfs/'sbin/init')
            shutil.copy2(fixture,rootfs/('bin/busybox' if policy=='full' else 'usr/bin/vinix-desktop'))
        archive=state/'initramfs.tar'
        with tarfile.open(archive,'w',format=tarfile.USTAR_FORMAT) as tar: tar.add(rootfs,arcname='.')
        environment=os.environ.copy()
        environment.update(VINIX_KERNEL_DIR=str(args.kernel_dir.resolve()),VINIX_INITRAMFS=str(archive),VINIX_BOOT_DISK=str(state/'boot.img'),VINIX_EFIVARS=str(state/'efivars.fd'),VINIX_QEMU_HOST_SOURCE='0',VINIX_QEMU_PACKAGE_STORE=str(state/'packages.tar'),VINIX_QEMU_AUDIO='off',VINIX_QEMU_NETWORK='0',VINIX_QEMU_EXTRA='-qmp unix:'+str(state/'qmp.sock')+',server=on,wait=off')
        command=[str(ROOT/'scripts/run-aarch64.sh'),'--no-build','--serial','--no-persist','--mem=1024']
        expected={'shell':['Hello from userland!','Vinix 0.1.0 aarch64','SHELL INIT GUEST: PASS'],'full':['FULL INIT GUEST: PASS'],'desktop':['DESKTOP RELOAD FORWARDED: PASS','DESKTOP RESTART: PASS','DESKTOP INIT GUEST: PASS']}[policy]
        print('Init policy guest artifacts: '+str(state),flush=True)
        if runner.boot(command,environment,state,expected,['INIT GUEST FAIL:','KERNEL PANIC','FATAL EXCEPTION'],args.timeout): return 1
    print('ALL INIT POLICY GUESTS: PASS')
    return 0
if __name__=='__main__': raise SystemExit(main())
