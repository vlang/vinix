#!/usr/bin/env python3
"""Resumable final-v6 static-libc core integration; owns this directory only."""
from pathlib import Path
import datetime, hashlib, importlib.util, json, os, re, shlex, shutil, subprocess, sys, tarfile, time, traceback

ROOT = Path('/Users/alex/code/vinix')
OUT = Path(__file__).resolve().parent
OLD = ROOT / 'build/useralloc-kernel-speed-v5'
PRIVATE = ROOT / 'third_party/useralloc-speed-v5'
PATCH = 'ec459e48e5c3c9946c91e805428149802d0ab1835c64e5e023811ab54a48af1d'
TEST = '705b57f7ff40b934d438ff62187ca7bc9983839af8ee3ff0039ed59bcbd77abe'
TABLE = 'f71d45c78c2db0e1c198d2aa3443513a5fd2f51975a8209a8fdbf374dc7abf5d'
KHASH = {'x86_64':'16140916ef5abca52cc6f0a8e80bb6dedc24b5e5f05efd747f57182523098e74','aarch64':'3d721f3168a990373cb2549bd26322329923014ee4613cda2ae3d4f6884bf8f7'}
HARNESS = PRIVATE / 'tests/qemu-core/run_vm.py'
HSH = '3f3d4852c58548bc7ade08a1c8f4850c259f592f3816f71d78fda8c45d38eb8c'
FOUR = OLD / 'core-x86_64-four-level/run_vm.py'
FOURSH = '5f3c543bffefc67219a30d5837042ef6a2a34f9850c0588132878d205792a797'
ACTIVE = None

def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def sha(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()
def write(p,d):
    p=Path(p); t=p.with_name(p.name+'.tmp'); t.write_text(json.dumps(d,indent=2)+'\n'); t.replace(p)
def check(p,s):
    v=sha(p)
    if v!=s: raise RuntimeError(f'Hash mismatch {p}: {v} != {s}')
    return v
def checkpoint(status,**extra):
    write(OUT/'checkpoint.json',dict(status=status,updated_utc=now(),driver_pid=os.getpid(),active_mode=ACTIVE,**extra))
def logged(cmd,log,env=None):
    with Path(log).open('wb') as f:
        p=subprocess.run(cmd,cwd=ROOT,env=dict(os.environ,**(env or {})),stdout=f,stderr=subprocess.STDOUT)
    if p.returncode: raise RuntimeError(f'Command exit {p.returncode}: {cmd}; see {log}')

def compile_arch(arch):
    s=OUT/f'core-{arch}'; s.mkdir(exist_ok=True)
    if (s/'compile.json').exists():
        m=json.loads((s/'compile.json').read_text())
        for k,f in [('init_sha256','init'),('initramfs_sha256','initramfs.tar'),('test_source_sha256','test.c'),('boundary_supplement_sha256','pagetable.c')]: check(s/f,m[k])
        check(Path(m['stage'])/'usr/lib/libc.a',m['static_libc_sha256'])
        return m
    stage=ROOT/'third_party/useralloc-libc/build/useralloc'/('optimized-v6-final' if arch=='x86_64' else 'optimized-arm126-v6-final')
    provenance=json.loads((stage/'usr/share/vinix/musl-build.json').read_text())
    assert next(p['sha256'] for p in provenance['patches'] if p['name']=='malloc-retain.patch')==PATCH
    lib=stage/'usr/lib/libc.a'; check(lib,provenance['libc_a_sha256'])
    for f,h in [('test.c',TEST),('pagetable.c',TABLE)]:
        src=OLD/f'core-{arch}'/f; check(src,h); shutil.copyfile(src,s/f); check(s/f,h)
    shutil.copyfile(stage/'usr/share/vinix/musl-build.json',s/'musl-build.json')
    prior=json.loads((OLD/f'core-{arch}'/'compile.json').read_text())
    cmd=[str(v).replace(str(OLD/f'core-{arch}'),str(s)).replace('optimized-v5-final','optimized-v6-final').replace('optimized-arm126-v5-final','optimized-arm126-v6-final') for v in prior['compile_command']]
    # Linker diagnostics affect no executable code; the production compile flags are unchanged.
    diagnostic_cmd=cmd[:-4]+[f'-Wl,-Map,{s}/link.map','-Wl,-t']+cmd[-4:]
    compiler=subprocess.check_output([cmd[0],'--version'],text=True).splitlines()[0]
    assert compiler==provenance['compiler_version'] and '14.2.0' in compiler
    logged(diagnostic_cmd,s/'compile.log')
    trace=(s/'compile.log').read_text()
    linkmap=(s/'link.map').read_text()
    assert str(lib) in trace and str(lib) in linkmap
    readelf='/opt/homebrew/opt/musl-cross/bin/'+arch+'-linux-musl-readelf'
    logged([readelf,'-h','-l','-d',str(s/'init')],s/'elf.log')
    elf=(s/'elf.log').read_text(); assert 'INTERP' not in elf and 'There is no dynamic section' in elf
    rootfs=s/'rootfs'; rootfs.mkdir(exist_ok=True)
    for d in ['sbin','root','dev','tmp']: (rootfs/d).mkdir(exist_ok=True)
    if arch=='x86_64': shutil.copyfile(s/'init',rootfs/'sbin/init'); (rootfs/'sbin/init').chmod(0o755)
    with tarfile.open(s/'initramfs.tar','w',format=tarfile.USTAR_FORMAT) as t:
        def filt(i): i.uid=i.gid=0; i.uname=i.gname='root'; i.mtime=0; return i
        t.add(rootfs,arcname='.',filter=filt)
    shutil.copyfile(OUT/'run.py',s/'run.py')
    m=dict(compile_command=cmd,diagnostic_compile_command=diagnostic_cmd,diagnostics_note='Only -Wl,-Map and -Wl,-t added for actual archive linkage proof; identical prior core code generation flags.',stage=str(stage),test_source_sha256=TEST,original_core_source_sha256=prior['original_core_source_sha256'],boundary_supplement_sha256=TABLE,core_source_bundle_sha256=hashlib.sha256((s/'test.c').read_bytes()+(s/'pagetable.c').read_bytes()).hexdigest(),init_sha256=sha(s/'init'),static_libc_sha256=sha(lib),crt_sha256={p.name:sha(p) for p in (stage/'usr/lib').glob('crt*.o')},allocator_patch_sha256=PATCH,compiler=compiler,initramfs_sha256=sha(s/'initramfs.tar'),kernel_sha256=KHASH[arch],harness_sha256=HSH,archive_linkage_verified=True,static_elf_verified=True,link_map_sha256=sha(s/'link.map'),compile_log_sha256=sha(s/'compile.log'),musl_build_sha256=sha(s/'musl-build.json'),built_utc=now())
    write(s/'compile.json',m)
    return m

def image(m):
    s=OUT/'core-x86_64'
    if (s/'embedded-input-check.json').exists():
        x=json.loads((s/'embedded-input-check.json').read_text())
        check(s/'test.iso',x['iso_sha256']); check(s/'embedded-kernel',KHASH['x86_64']); check(s/'embedded-initramfs.tar',x['embedded_initramfs_sha256'])
        return x
    iso_build=s/'iso-build'; (iso_build/'limine').mkdir(parents=True,exist_ok=True)
    for p in (OLD/'core-x86_64/iso-build/limine').iterdir(): shutil.copy2(p,iso_build/'limine'/p.name)
    env={'VINIX_AMD64_ISO_BUILD_DIR':str(iso_build),'VINIX_AMD64_KERNEL':str(OLD/'x86_64/vinix-x86_64'),'VINIX_AMD64_INITRAMFS':str(s/'initramfs.tar'),'VINIX_AMD64_ISO':str(s/'test.iso')}
    script=PRIVATE/'build-support/build-amd64-iso.sh'
    write(s/'image-build.json',dict(command=[str(script)],environment=env,script_sha256=sha(script)))
    logged([str(script)],s/'image-build.log',env)
    # Extract completed ISO bytes independently of assembly directories.
    logged(['xorriso','-osirrox','on','-indev',str(s/'test.iso'),'-extract','/boot/vinix',str(s/'embedded-kernel'),'-extract','/boot/initramfs.tar',str(s/'embedded-initramfs.tar')],s/'embedded-input-check.log')
    check(s/'embedded-kernel',KHASH['x86_64'])
    with tarfile.open(s/'embedded-initramfs.tar') as t:
        embedded_init=t.extractfile('./sbin/init').read()
        image_id=t.extractfile('./.vinix-image-id').read().decode().strip()
    assert hashlib.sha256(embedded_init).hexdigest()==m['init_sha256']
    assert image_id==m['initramfs_sha256'][:16]
    x=dict(iso_sha256=sha(s/'test.iso'),embedded_kernel_sha256=sha(s/'embedded-kernel'),embedded_initramfs_sha256=sha(s/'embedded-initramfs.tar'),embedded_init_sha256=hashlib.sha256(embedded_init).hexdigest(),pre_image_id_initramfs_sha256=m['initramfs_sha256'],image_id=image_id,verified_utc=now(),independent_completed_iso_extraction=True)
    write(s/'embedded-input-check.json',x)
    return x

def capture_qemu(s,mode):
    r=subprocess.run(['ps','-axo','pid=,ppid=,command='],stdout=subprocess.PIPE,text=True)
    lines=[v.strip() for v in r.stdout.splitlines() if 'qemu-system-' in v and str(s if mode=='aarch64' else OUT/'core-x86_64') in v and Path(shlex.split(v)[2]).name.startswith('qemu-system-')]
    if lines:
        file=s/'qemu-observed.json'
        v=json.loads(file.read_text()) if file.exists() else dict(provenance='Live ps capture during the actual frozen harness execution',observations=[])
        for line in lines:
            if not any(o['ps']==line for o in v['observations']): v['observations'].append(dict(captured_utc=now(),ps=line))
        write(file,v)

def run_mode(mode,base,im):
    global ACTIVE
    ACTIVE=mode; s=OUT/f'core-{mode}'; s.mkdir(exist_ok=True)
    if (s/'run.json').exists():
        prior=json.loads((s/'run.json').read_text())
        if prior.get('exit_code')==0:
            check(s/'serial.log',prior['serial_sha256']); validate(s,mode,prior)
            checkpoint('mode_already_passed'); return prior
        if 'exit_code' in prior: raise RuntimeError(f'Prior invalid completed run retained at {s}; choose a new attempt directory explicitly, never overwrite')
        if (s/'serial.log').exists(): raise RuntimeError(f'Incomplete run retained at {s}; choose a new attempt directory explicitly, never overwrite')
    check(HARNESS,HSH); check(FOUR,FOURSH)
    m=dict(base)
    m.update(mode=mode,notes='Final v6 static musl allocator with the unchanged v5 kernel and immutable full core/pagetable source; SMP2.',started_utc=now())
    if mode!='aarch64':
        if mode=='x86_64-four-level':
            shutil.copyfile(FOUR,s/'run_vm.py'); check(s/'run_vm.py',FOURSH); shutil.copyfile(OUT/'run.py',s/'run.py')
        harness=s/'run_vm.py' if mode.endswith('four-level') else HARNESS
        m.update(harness_sha256=FOURSH if mode.endswith('four-level') else HSH,run_command=[sys.executable,str(harness),'--arch','amd64','--iso',str(OUT/'core-x86_64/test.iso'),'--qemu','/opt/homebrew/Cellar/qemu/11.1.1/bin/qemu-system-x86_64','--firmware','/opt/homebrew/Cellar/qemu/11.1.1/share/qemu/edk2-x86_64-code.fd','--timeout','900','--cpus','2'],run_environment={},iso_sha256=im['iso_sha256'],embedded_initramfs_sha256=im['embedded_initramfs_sha256'],qemu_cpu='max,-la57' if mode.endswith('four-level') else 'max',qemu_accelerator='tcg')
    else:
        check(PRIVATE/'kernel/bin/vinix',KHASH['aarch64'])
        m.update(run_command=[sys.executable,str(HARNESS),'--init',str(s/'init'),'--initramfs',str(s/'initramfs.tar'),'--state-dir',str(s/'vm'),'--timeout','900'],run_environment={'VINIX_KERNEL_DIR':str(PRIVATE/'kernel'),'VINIX_QEMU_CORE_NO_BUILD':'1','VINIX_QEMU_HOST_SOURCE':'0','VINIX_QEMU_AUDIO':'off','VINIX_QEMU_SMP':'2','VINIX_BOOT_DISK_SIZE_MB':'128','USE_TCG':'0'},loader_sha256=check(PRIVATE/'boot-image/limine-bin/BOOTAA64.EFI','0088bfbce37414d13cdbe4c078a13d6b279d727b821e36bbf8044505325e7c02'))
    write(s/'run.json',m); checkpoint('running_mode',run_path=str(s/'run.json'))
    with (s/'serial.log').open('xb') as log:
        p=subprocess.Popen(m['run_command'],cwd=ROOT,env=dict(os.environ,**m['run_environment']),stdout=log,stderr=subprocess.STDOUT)
        write(s/'harness-process.json',dict(pid=p.pid,parent_pid=os.getpid(),started_utc=now(),command=m['run_command']))
        while p.poll() is None:
            capture_qemu(s,mode)
            time.sleep(.5)
    m.update(harness_exit_code=p.returncode,finished_utc=now(),serial_sha256=sha(s/'serial.log'))
    try: validate(s,mode,m); m['exit_code']=p.returncode
    except Exception as e: m.update(exit_code=p.returncode or 1,validation_error=str(e))
    write(s/'run.json',m); write(s/'exit.json',dict(exit_code=m['exit_code'],finished_utc=m['finished_utc']))
    if m['exit_code']: raise RuntimeError(f'{mode} failed: {m.get("validation_error",p.returncode)}')
    checkpoint('mode_passed',run_path=str(s/'run.json'))
    return m

def validate(s,mode,m):
    spec=importlib.util.spec_from_file_location('frozen_core_harness',HARNESS); h=importlib.util.module_from_spec(spec); spec.loader.exec_module(h)
    b=(s/'serial.log').read_bytes()
    expected=[*h.FEATURE_MARKERS,h.PASS_MARKER,b'PAGETABLE CHECK: PASS']
    if mode!='aarch64': expected.extend(h.AMD64_FEATURE_MARKERS)
    else: expected.extend([h.PERSIST_MARKER,b'AArch64 QEMU core regression passed across reboot'])
    missing=[v.decode() for v in expected if b.count(v)!=1]
    failed=[v.decode() for v in (*h.FAIL_MARKERS,b'PAGETABLE FAIL',b'ERROR:') if v in b]
    source=(OUT/'core-x86_64/test.c').read_text()
    source_markers=re.findall(r'puts\("(QEMU CORE PASS:[^"\n]+)"\)',source)
    if mode=='aarch64': source_markers=[v for v in source_markers if 'QEMU CORE PASS: x86-64 ' not in v]
    missing.extend(v for v in source_markers if b.count(v.encode())!=1)
    m['all_source_core_pass_marker_count']=len(source_markers)
    if mode=='x86_64':
        high=b'PAGETABLE PASS: boundary=0x1000000000000 page=4096'; assert b.count(high)==1
        assert b'PAGETABLE SKIP: boundary=0x1000000000000' not in b
        m['la57_256tib_boundary_pass']=True
    elif mode=='x86_64-four-level':
        skip=b'PAGETABLE SKIP: boundary=0x1000000000000 CPU has four-level paging'; assert b.count(skip)==1
        assert b'PAGETABLE PASS: boundary=0x1000000000000' not in b
        m['cpuid_la57_disabled_explicit_skip']=True
    if missing or failed: raise RuntimeError(f'missing={missing}; failed={failed}')
    assert m.get('harness_exit_code',m.get('exit_code'))==0
    m.update(boundary_supplement_pass=True,all_core_markers_pass=True,pagetable_check_pass_count=b.count(b'PAGETABLE CHECK: PASS'),persistent_second_boot_pass=mode=='aarch64',required_marker_count=len(expected))
    if mode=='aarch64':
        vm=s/'vm'; extracted=s/'embedded-arm-kernel'
        if not extracted.exists(): logged(['mcopy','-i',str(vm/'boot.img'),'::/boot/vinix',str(extracted)],s/'embedded-arm-check.log')
        check(extracted,KHASH['aarch64']); check(PRIVATE/'kernel/bin/vinix',KHASH['aarch64'])
        m['embedded_kernel_sha256']=sha(extracted)
        for image in ['root.ext2','boot.img']: m[image.replace('.','_')+'_sha256']=sha(vm/image)

def main():
    global ACTIVE
    (OUT/'driver.pid').write_text(str(os.getpid())+'\n')
    checkpoint('checking_pins')
    check(ROOT/'build-support/musl/malloc-retain.patch',PATCH)
    for arch in KHASH: check(OLD/arch/f'vinix-{arch}',KHASH[arch])
    check(HARNESS,HSH); check(FOUR,FOURSH)
    checkpoint('compiling_static_v6')
    x=compile_arch('x86_64'); a=compile_arch('aarch64')
    checkpoint('building_frozen_x86_iso'); im=image(x)
    results={}
    for mode,base in [('x86_64',x),('x86_64-four-level',x),('aarch64',a)]: results[mode]=run_mode(mode,base,im)
    ACTIVE=None
    write(OUT/'final-gates.json',dict(captured_utc=now(),allocator_patch_sha256=PATCH,kernels=KHASH,test_source_sha256=TEST,boundary_supplement_sha256=TABLE,core={k:{j:v[j] for j in ['exit_code','serial_sha256','started_utc','finished_utc','boundary_supplement_pass','all_core_markers_pass','pagetable_check_pass_count','static_libc_sha256','init_sha256','kernel_sha256','archive_linkage_verified','static_elf_verified']} for k,v in results.items()},owned_jobs_running=[],all_three_modes_pass=True,owned_directory=str(OUT),notes='No kernel rebuilds, tracked changes or benchmarks. Final v6 static archives linked and executed on identical frozen v5 kernels. Completed x86 ISO independently extracted; ARM disk kernel independently extracted.'))
    checkpoint('complete',final_gates=str(OUT/'final-gates.json'),owned_jobs_running=[])
    write(OUT/'exit.json',dict(exit_code=0,finished_utc=now(),owned_jobs_running=[]))
    print('Final v6 core all three modes PASS',flush=True)

if __name__=='__main__':
    try: main()
    except BaseException as e:
        traceback.print_exc(); checkpoint('failed',error=str(e)); write(OUT/'exit.json',dict(exit_code=1,finished_utc=now(),error=str(e))); sys.exit(1)
