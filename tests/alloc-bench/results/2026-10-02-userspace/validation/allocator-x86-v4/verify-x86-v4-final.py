#!/usr/bin/env python3
"""Private native-GCC four-mode allocation verification; no timed workload."""
from pathlib import Path
import hashlib,json,os,shlex,shutil,subprocess,sys,tarfile,time
ROOT=Path('/Users/alex/code/vinix')
WORK=ROOT/'third_party/useralloc-libc'
BASE=WORK/'build/useralloc'
STATE=BASE/'verify-x86-v4-final'
FLAGS=['-std=c11','-O2','-Wall','-Wextra','-Werror','-fno-builtin','-pthread']
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def prepare():
 STATE.mkdir(exist_ok=False)
 rootfs=STATE/'rootfs'
 subprocess.run(['cp','-cR',str(BASE/'optimized-v4-final'),str(rootfs)],check=True)
 for d in ['dev','proc','sys','tmp','root','sbin']:(rootfs/d).mkdir(exist_ok=True)
 (rootfs/'tmp').chmod(0o1777)
 source=ROOT/'tests/user-alloc/verify.c'
 shutil.copyfile(source,rootfs/'root/verify.c')
 supplementary=ROOT/'tests/user-alloc/verify-all-classes.c'
 shutil.copyfile(supplementary,rootfs/'root/verify-all-classes.c')
 clock_source=ROOT/'tests/user-alloc/clock.c'
 shutil.copyfile(clock_source,rootfs/'root/clock.c')
 manifests={}
 for policy,stage in [('optimized','optimized-v4-final'),('disabled','disabled-v4-final')]:
  stage=BASE/stage
  target=rootfs/f'root/libcs/{policy}';target.mkdir(parents=True)
  m=json.loads((stage/'usr/share/vinix/musl-build.json').read_text())
  for origin,dest,field in [('lib/ld-musl-x86_64.so.1','libc.so','libc_so_sha256'),('usr/lib/libc.a','libc.a','libc_a_sha256')]:
   assert digest(stage/origin)==m[field]
   shutil.copyfile(stage/origin,target/dest)
  shutil.copyfile(stage/'usr/share/vinix/musl-build.json',target/'build.json')
  manifests[policy]=m
 init=rootfs/'sbin/init';init.unlink(missing_ok=True)
 init.write_text('''#!/bin/sh
exec >/dev/com1 2>&1
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
mount -t proc proc /proc
echo UALLOC-VERIFY-BEGIN
gcc --version | head -n1
gcc -dM -E - </dev/null | grep __clang__ && exit 1
sha256sum /root/verify.c
sha256sum /root/clock.c
gcc -std=c11 -O2 -Wall -Wextra -Werror -fno-builtin /root/clock.c -o /root/clock || {
    echo CLOCK-FAIL stage=compile
    while :; do sleep 60; done
}
/root/clock || {
    echo CLOCK-FAIL stage=run
    while :; do sleep 60; done
}
for policy in optimized disabled; do
    cp /root/libcs/$policy/libc.so /lib/.vinix-libc.new || exit 1
    chmod 755 /lib/.vinix-libc.new
    mv -f /lib/.vinix-libc.new /lib/ld-musl-x86_64.so.1 || exit 1
    cp /root/libcs/$policy/libc.a /usr/lib/.vinix-libc.a.new || exit 1
    chmod 644 /usr/lib/.vinix-libc.a.new
    mv -f /usr/lib/.vinix-libc.a.new /usr/lib/libc.a || exit 1
    echo UALLOC-POLICY policy=$policy
    sha256sum /lib/ld-musl-x86_64.so.1 /usr/lib/libc.a /root/libcs/$policy/build.json
    for linkage in dynamic static; do
        extra=
        [ "$linkage" = static ] && extra=-static
        echo UALLOC-LINKAGE policy=$policy mode=$linkage
        gcc '''+shlex.join(FLAGS)+''' $extra /root/verify.c -o /root/verify || {
            echo UALLOC-FAIL stage=compile policy=$policy mode=$linkage
            while :; do sleep 60; done
        }
        /root/verify || {
            echo UALLOC-FAIL stage=run policy=$policy mode=$linkage
            while :; do sleep 60; done
        }
        echo UALLOC-ORIGINAL-COMPLETE policy=$policy mode=$linkage
        gcc -std=c11 -O2 -Wall -Wextra -Werror -fno-builtin -pthread $extra /root/verify-all-classes.c -o /root/verify-all-classes || {
            echo UALLOC-FAIL stage=supplemental-compile policy=$policy mode=$linkage
            while :; do sleep 60; done
        }
        /root/verify-all-classes || {
            echo UALLOC-FAIL stage=supplemental-run policy=$policy mode=$linkage
            while :; do sleep 60; done
        }
        echo UALLOC-MODE-COMPLETE policy=$policy mode=$linkage
    done
done
echo UALLOC-VERIFY-COMPLETE
while :; do sleep 60; done
''')
 init.chmod(0o755)
 with tarfile.open(STATE/'initramfs.tar','w',format=tarfile.USTAR_FORMAT) as t:t.add(rootfs,arcname='.')
 config={'source_sha256':digest(source),'supplemental_source_sha256':digest(supplementary),'clock_source_sha256':digest(clock_source),'compile_flags':FLAGS,'libc_builds':manifests}
 (STATE/'config.json').write_text(json.dumps(config,indent=2)+'\n')
 print('Prepared',STATE,flush=True)
def run(kernel):
 config=json.loads((STATE/'config.json').read_text())
 kernel=Path(kernel).resolve();iso=STATE/'vinix.iso'
 env=dict(os.environ,VINIX_AMD64_ISO_BUILD_DIR=str(STATE/'iso-build'),VINIX_AMD64_KERNEL=str(kernel),VINIX_AMD64_INITRAMFS=str(STATE/'initramfs.tar'),VINIX_AMD64_ISO=str(iso))
 assert json.loads((STATE/'embedded-input-check.json').read_text())['match']
 assert digest(iso)==json.loads((STATE/'embedded-input-check.json').read_text())['iso_sha256']
 # Existing completed ISO was verified against every relevant embedded input.
 assert digest(STATE/'boot-kernel')==digest(kernel)
 qemu=Path(shutil.which('qemu-system-x86_64')).resolve();fw=qemu.parent.parent/'share/qemu/edk2-x86_64-code.fd';serial=STATE/'serial.log'
 command=[str(qemu),'-machine','q35,vmport=off','-accel','tcg,thread=single,tb-size=1024','-cpu','Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt','-smp','2,sockets=1,cores=2,threads=1','-m','4096','-display','none','-monitor','none','-drive',f'if=pflash,format=raw,readonly=on,file={fw}','-cdrom',str(iso),'-serial',f'file:{serial}','-no-reboot']
 config.update({'kernel_sha256':digest(STATE/'boot-kernel'),'qemu_version':subprocess.check_output([str(qemu),'--version'],text=True).splitlines()[0],'argv':command})
 (STATE/'config.json').write_text(json.dumps(config,indent=2)+'\n')
 with (STATE/'qemu.log').open('wb') as out:
  proc=subprocess.Popen(command,stdout=out,stderr=out)
  try:
   deadline=time.monotonic()+3600;printed=0
   while time.monotonic()<deadline:
    output=serial.read_text(errors='replace') if serial.exists() else ''
    lines=[line for line in output.splitlines() if line.startswith(('UALLOC-','CLOCK-'))]
    for line in lines[printed:]:print(line,flush=True)
    printed=len(lines)
    if any(x in output for x in ['KERNEL PANIC','FATAL EXCEPTION','UALLOC-FAIL','CLOCK-FAIL']):raise RuntimeError('Guest failed: '+str(serial))
    if 'UALLOC-VERIFY-COMPLETE' in output:
     assert 'CLOCK-DONE ' in output
     assert sum(x.startswith('UALLOC-DONE ') for x in lines)==4
     assert sum(x.startswith('UALLOC-SUPPLEMENT-DONE ') for x in lines)==4
     assert sum(x.startswith('UALLOC-MODE-COMPLETE ') for x in lines)==4
     assert sum(x.startswith('UALLOC-ALL-CLASSES ') for x in lines)==4
     assert sum(x.startswith('UALLOC-THREAD-TRANSITIONS ') for x in lines)==4
     assert sum(x.startswith('UALLOC-ORIGINAL-COMPLETE ') for x in lines)==4
     print('All four allocator modes and supplemental suites verified',flush=True);return
    if proc.poll() is not None:raise RuntimeError('QEMU exited')
    time.sleep(.25)
   raise TimeoutError('Guest verification timeout')
  finally:
   if proc.poll() is None:
    proc.terminate()
    try:proc.wait(timeout=5)
    except subprocess.TimeoutExpired:proc.kill();proc.wait()
if sys.argv[1]=='prepare':prepare()
elif sys.argv[1]=='run':run(sys.argv[2])
else:raise SystemExit('prepare | run KERNEL')
