from pathlib import Path
import json,subprocess,shutil,hashlib,os
root=Path('/Users/alex/code/vinix');state=root/'build/useralloc-arm-v5-final';old=root/'build/useralloc-arm-v4-final';libs=root/'third_party/useralloc-libc/build/useralloc'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
subprocess.run(['cp','-cR',str(old/'rootfs'),str(state/'rootfs')],check=True)
rootfs=state/'rootfs'
for f in ['verify.c','verify-all-classes.c','clock.c']:shutil.copyfile(root/'tests/user-alloc'/f,state/f)
shutil.copyfile(old/'launcher.c',state/'launcher.c')
for policy in ['optimized','disabled']:
 stage=libs/f'{policy}-arm126-v5-final';sysroot=state/f'sysroot-{policy}'
 subprocess.run(['cp','-cR',str(old/f'sysroot-{policy}'),str(sysroot)],check=True)
 shutil.copytree(stage/'usr/include',sysroot/'include',dirs_exist_ok=True)
 for f in ['libc.a','libc.so']:
  p=sysroot/'lib'/f;p.unlink(missing_ok=True);shutil.copyfile(stage/'usr/lib'/f,p)
 m=json.loads((stage/'usr/share/vinix/musl-build.json').read_text());(state/f'musl-{policy}.json').write_text(json.dumps(m,indent=2)+'\n')
 loader=rootfs/f'lib/ld-musl-aarch64-{policy}.so.1';shutil.copyfile(stage/'lib/ld-musl-aarch64.so.1',loader);loader.chmod(0o755)
 assert digest(loader)==m['libc_so_sha256'];assert digest(sysroot/'lib/libc.a')==m['libc_a_sha256']
commands=[[a.replace('useralloc-arm-v4-final','useralloc-arm-v5-final') for a in cmd] for cmd in json.loads((old/'build.json').read_text())['commands']]
for cmd in commands:subprocess.run(cmd,check=True)
(state/'kernel/bin').mkdir(parents=True);kernel=root/'build/useralloc-kernel-speed-v4/aarch64/vinix-aarch64';assert digest(kernel)=='c617cb9d695bccc3c7ada841fa60ac65fd45b942f45d3462b44c3f0378a995c9';shutil.copyfile(kernel,state/'kernel/bin/vinix')
subprocess.run(['tar','--format=ustar','-cf',str(state/'initramfs.tar'),'-C',str(rootfs),'.'],env=dict(os.environ,COPYFILE_DISABLE='1'),check=True)
build={'commands':commands,'compiler':subprocess.check_output([commands[0][0],'--version'],text=True).splitlines()[0],'source_sha256':{f:digest(state/f) for f in ['verify.c','verify-all-classes.c','clock.c','launcher.c']},'artifacts_sha256':{str(p.relative_to(rootfs)):digest(p) for p in rootfs.rglob('*') if p.is_file()},'kernel_sha256':digest(state/'kernel/bin/vinix'),'initramfs_sha256':digest(state/'initramfs.tar')}
(state/'build.json').write_text(json.dumps(build,indent=2)+'\n');print(json.dumps(build,indent=2))
