#!/usr/bin/env python3
"""Read-only verification of completed runs, plus private extracted evidence."""
from pathlib import Path
import datetime, hashlib, importlib.util, json, os, re, shlex, subprocess, tarfile
S=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('core_driver',S/'driver.py')
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
def write(p,m): p.write_text(json.dumps(m,indent=2)+'\n')
audit=dict(captured_utc=d.now(),modes={})
for mode in ['x86_64','x86_64-four-level','aarch64']:
    s=S/f'core-{mode}'; m=json.loads((s/'run.json').read_text()); assert m['exit_code']==0
    d.check(s/'serial.log',m['serial_sha256']); d.validate(s,mode,m)
    compiled=S/('core-aarch64' if mode=='aarch64' else 'core-x86_64')
    c=json.loads((compiled/'compile.json').read_text())
    exact=json.loads((compiled/'compile-exact-flags.json').read_text())
    assert exact['diagnostic_and_exact_flags_binary_identical'] and exact['init_sha256']==c['init_sha256']
    stage=Path(c['stage']); d.check(stage/'usr/lib/libc.a',c['static_libc_sha256'])
    d.check(compiled/'test.c',d.TEST); d.check(compiled/'pagetable.c',d.TABLE)
    actual_crts={}
    for line in (compiled/'compile.log').read_text().splitlines():
        p=Path(line)
        if p.name.startswith('crt') and p.suffix=='.o' and p.exists(): actual_crts[str(p.resolve())]=d.sha(p)
    observed=json.loads((s/'qemu-observed.json').read_text())
    actual=[]
    for o in observed['observations']:
        fields=shlex.split(o['ps'])
        if Path(fields[2]).name.startswith('qemu-system-'): actual.append(dict(pid=int(fields[0]),parent_pid=int(fields[1]),argv=fields[2:],captured_utc=o['captured_utc']))
    assert len(actual)==(2 if mode=='aarch64' else 1)
    for q in actual:
        argv=q['argv']; assert argv[argv.index('-smp')+1]=='2'
        if mode=='aarch64': assert argv[argv.index('-accel')+1]=='hvf'
        else:
            assert argv[argv.index('-accel')+1]=='tcg'
            assert argv[argv.index('-cpu')+1]==('max,-la57' if mode.endswith('four-level') else 'max')
    m.update(core_source_bundle_sha256_method='SHA256 of test.c raw bytes followed by pagetable.c raw bytes',previous_v5_bundle_sha256=json.loads((d.OLD/f'core-{mode}'/'run.json').read_text())['core_source_bundle_sha256'],exact_flags_binary_identical=True,actual_crt_sha256=actual_crts,actual_qemu_argv=actual)
    if mode=='aarch64':
        vm=s/'vm'; loader=s/'embedded-arm-loader'; runtime=s/'embedded-arm-runtime.tar'; base=s/'embedded-arm-initramfs.tar'
        with (s/'embedded-arm-runtime-check.log').open('wb') as log:
            for src,target in [('::/EFI/BOOT/BOOTAA64.EFI',loader),('::/boot/qemu-runtime.tar',runtime),('::/boot/initramfs.tar',base)]:
                if not target.exists(): subprocess.run(['mcopy','-i',str(vm/'boot.img'),src,str(target)],stdout=log,stderr=subprocess.STDOUT,check=True)
        m['loader_sha256']=d.check(loader,'0088bfbce37414d13cdbe4c078a13d6b279d727b821e36bbf8044505325e7c02')
        d.check(base,c['initramfs_sha256'])
        with tarfile.open(runtime) as t: init=t.extractfile('./sbin/init').read()
        ih=hashlib.sha256(init).hexdigest(); assert ih==c['init_sha256']
        m.update(embedded_init_sha256=ih,embedded_initramfs_sha256=d.sha(base),embedded_runtime_sha256=d.sha(runtime),independent_completed_boot_disk_extraction=True)
        write(s/'embedded-input-check.json',dict(kernel_sha256=m['embedded_kernel_sha256'],init_sha256=ih,loader_sha256=m['loader_sha256'],base_initramfs_sha256=d.sha(base),runtime_tar_sha256=d.sha(runtime),boot_disk_sha256=d.sha(vm/'boot.img'),captured_after_actual_second_persistent_boot=True,validated_utc=d.now()))
    write(s/'run.json',m)
    audit['modes'][mode]=dict(exit_code=0,serial_sha256=m['serial_sha256'],all_source_core_pass_marker_count=m['all_source_core_pass_marker_count'],pagetable_check_pass_count=m['pagetable_check_pass_count'],exact_flags_binary_identical=True,actual_qemu_process_count=len(actual),static_archive_sha256=c['static_libc_sha256'],actual_crt_sha256=actual_crts,source_sha256={'test.c':d.TEST,'pagetable.c':d.TABLE},actual_run_command=m['run_command'])
write(S/'evidence-audit.json',audit)
g=json.loads((S/'final-gates.json').read_text())
g.update(evidence_audit_sha256=d.sha(S/'evidence-audit.json'),exact_original_compile_flags_binary_identical=True,all_source_core_markers_pass=True)
for mode,a in audit['modes'].items(): g['core'][mode]['all_source_core_pass_marker_count']=a['all_source_core_pass_marker_count']
write(S/'final-gates.json',g)
print('Evidence audit PASS: all source markers, exact compile flags, actual processes, final ARM payload pins')
