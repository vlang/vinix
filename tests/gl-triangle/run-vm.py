#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build native V and an exact Mesa runtime, then run the original guest checks."""
from pathlib import Path
import argparse, hashlib, json, os, re, runpy, shlex, shutil, subprocess, tarfile
root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--kernel-dir',type=Path,required=True)
parser.add_argument('--state-dir',type=Path,required=True)
parser.add_argument('--timeout',type=int,default=1800)
args=parser.parse_args();state=args.state_dir.resolve();state.mkdir(parents=True,exist_ok=False)
llvm=Path(os.environ.get('LLVM_BIN','/opt/homebrew/opt/llvm/bin'))
sysroot=Path(os.environ.get('VINIX_AARCH64_SYSROOT',str(root/'build-aarch64-userland/staging')))
gpu_sysroot=Path(os.environ.get('VINIX_GPU_SYSROOT',str(root/'build-aarch64-x11/sysroot')))
gpu=Path(os.environ.get('VINIX_ASAHI_STAGING',str(root/'build-aarch64-asahi/staging')))
gcc=next((sysroot/'usr/lib/gcc/aarch64-alpine-linux-musl').glob('*'))
cc=str(llvm/'clang');shim=root/'build-support/aarch64-cc-shim'
examples=state/'examples'
subprocess.run(['python3',str(root/'gl-triangle/stage.py'),str(examples),'--arch','arm64'],check=True)
native=state/'native/usr/bin';native.mkdir(parents=True)
(state/'native/usr/lib').symlink_to(gpu/'usr/lib',target_is_directory=True)
binary=native/'gl-triangle-agx'
subprocess.run([cc,'--target=aarch64-linux-musl','--sysroot='+str(gpu_sysroot),'--gcc-install-dir='+str(gcc),'-static-libgcc','-isystem',str(shim),'-fuse-ld=lld','-O2','-Wall','-Wextra','-Werror','-D__vinix__','-fwrapv','-fno-strict-aliasing','-I'+str(gpu/'usr/include'),str(examples/'egl_triangle.c'),'-L'+str(gpu/'usr/lib'),'-Wl,-rpath-link,'+str(gpu/'usr/lib'),'-Wl,-dynamic-linker,/lib/ld-musl-aarch64.so.1','-o',str(binary),'-lEGL','-lGLESv2','-Wl,--no-as-needed','-lvinix-agx-fault','-Wl,--as-needed','-ldl','-lpthread','-lm'],check=True)
stage=state/'rootfs'
for directory in ('sbin','bin','dev','proc','sys','tmp','root','lib','usr/bin','usr/lib/dri'):(stage/directory).mkdir(parents=True,exist_ok=True)
subprocess.run([cc,'--target=aarch64-linux-musl','-static','-nostdinc','-nostdlib','-isystem',str(shim),'-isystem',str(gcc/'include'),'-isystem',str(sysroot/'usr/include'),'-O2',str(sysroot/'usr/lib/crt1.o'),str(sysroot/'usr/lib/crti.o'),str(gcc/'crtbeginT.o'),str(root/'tests/gl-triangle/guest_init.c'),'-L'+str(sysroot/'usr/lib'),'-L'+str(gcc),'-lc','-lgcc',str(gcc/'crtend.o'),str(sysroot/'usr/lib/crtn.o'),'-fuse-ld=lld','-B'+str(llvm),'-o',str(stage/'sbin/init')],check=True)
shutil.copy2(sysroot/'bin/busybox',stage/'bin/busybox')
for name in ('sh','env'):(stage/'bin'/name).symlink_to('busybox')
shutil.copy2(binary,stage/'usr/bin/gl-triangle-agx')
shutil.copy2(root/'gl-triangle/run-gl-triangle-agx',stage/'usr/bin/run-gl-triangle-agx')
shutil.copy2(gpu/'lib/ld-musl-aarch64.so.1',stage/'lib/ld-musl-aarch64.so.1')
(stage/'usr/lib/libc.musl-aarch64.so.1').symlink_to('../../lib/ld-musl-aarch64.so.1')
search=[gpu/'usr/lib',gpu/'lib',gpu_sysroot/'usr/lib',gpu_sysroot/'lib',sysroot/'usr/lib',sysroot/'lib']
queue=[stage/'bin/busybox',stage/'usr/bin/gl-triangle-agx'];seen=set()
for source,destination in ((gpu/'usr/lib/libgallium-25.0.5.so',stage/'usr/lib/libgallium-25.0.5.so'),(gpu/'usr/lib/dri/libdril_dri.so',stage/'usr/lib/dri/libdril_dri.so')):
    shutil.copy2(source,destination);queue.append(destination)
(stage/'usr/lib/dri/asahi_dri.so').symlink_to('libdril_dri.so')
while queue:
    file=queue.pop()
    if file in seen:continue
    seen.add(file)
    dynamic=subprocess.check_output([str(llvm/'llvm-readelf'),'-d',str(file)],text=True)
    for name in re.findall(r'Shared library: \[([^]]+)\]',dynamic):
        destination=stage/'usr/lib'/name
        if destination.exists():continue
        source=next((directory/name for directory in search if (directory/name).is_file()),None)
        if source is None:raise SystemExit('Missing exact Mesa dependency: '+name)
        shutil.copy2(source,destination);queue.append(destination)
archive=state/'initramfs.tar'
with tarfile.open(archive,'w',format=tarfile.USTAR_FORMAT) as tar:tar.add(stage,arcname='.')
# A running shell reads its source incrementally. Freeze it so concurrent
# source edits in the shared checkout cannot change the active launch.
harness_root=state/'harness';(harness_root/'scripts').mkdir(parents=True)
(harness_root/'kernel').symlink_to(args.kernel_dir.resolve(),target_is_directory=True)
runner=harness_root/'scripts/run-aarch64.sh'
runner.write_text((root/'scripts/run-aarch64.sh').read_text().replace('SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"','SCRIPT_DIR='+shlex.quote(str(root)),1));runner.chmod(0o755)
os.environ.update(VINIX_KERNEL_DIR=str(args.kernel_dir.resolve()),VINIX_ASAHI_STAGING=str(state/'native'),VINIX_INITRAMFS=str(archive),VINIX_QEMU_HOST_SOURCE='0',VINIX_QEMU_AUDIO='off')
status=runpy.run_path(str(root/'tests/agx-fake-g17/run_vm.py'))['run_vm'](harness_root,args.timeout)
metadata={'guest_exit_status':status,'original_implementation_lines':557,'retained_implementation_C_lines':0,'kernel_sha256':hashlib.sha256((args.kernel_dir/'bin/vinix').read_bytes()).hexdigest(),'native_binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'runtime_archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest()}
(state/'validation.json').write_text(json.dumps(metadata,indent=2)+'\n')
raise SystemExit(status)
