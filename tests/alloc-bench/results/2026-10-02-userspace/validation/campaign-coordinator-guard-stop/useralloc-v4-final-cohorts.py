#!/usr/bin/env python3
from pathlib import Path
import datetime,hashlib,importlib.util,json,subprocess,sys
root=Path(__file__).resolve().parent.parent
SPEC=importlib.util.spec_from_file_location('allocation_compare',root/'tests/alloc-bench/compare.py')
compare=importlib.util.module_from_spec(SPEC);sys.modules[SPEC.name]=compare;SPEC.loader.exec_module(compare)
inputs={
'build/useralloc-kernel-speed-v4/x86_64/vinix-x86_64':'f944412c7e30b2c3a25b2ef93938bdd21c311c6fa611ea08a76d45adfdd76733',
'build-support/musl/malloc-retain.patch':'ff14e55c5346e6add14c5bb085fcecb957c756b262231e21ee981a4b536d133e',
'kernel/katomic/katomic_amd64.v':'ec2d130780fe2fe72bdff53013594e2bc5dbe671c10ab260412f0de8c19d1bf4',
'kernel/klock/klock_amd64.v':'3db4566c9a05ada0098109928957a56d8248f96a6da3ad95b555d8a35e89c4ee',
'kernel/c/memory.c':'5082c545e7c16318cceeb51bf280c356c6b9713c0de8b336290be165f2a42eb5',
'kernel/file/locks.v':'21937b5a7f0ee5d5bb233d855217d7c431b2793be40263b74f7073ead1327ac3',
'tests/alloc-bench/bench.c':'bd4a0d74f4f1e8d079d55877f8e90925e2622ce990120b54573a5dc94a9a54b9',
 'third_party/useralloc-libc/build/useralloc/optimized-v4-final/lib/ld-musl-x86_64.so.1':'21258229461f6415812edc34ae2fb83525b9caeba863287a7bc37acac60baef4',
 'third_party/useralloc-libc/build/useralloc/optimized-v4-final/usr/lib/libc.a':'0f6227b80a608e4f487c554f1ed263f911223e0acf2e5be5ee1e67671fc5cd7c',
}
kernel=root/'build/useralloc-kernel-speed-v4/x86_64/vinix-x86_64'
steps=[('vinix-1','useralloc-vinix-v4-final-1','vinix'),('catalina-1','useralloc-macos-v4-final-1','catalina'),('catalina-2','useralloc-macos-v4-final-2','catalina'),('vinix-2','useralloc-vinix-v4-final-2','vinix')]
record_path=root/'build/useralloc-v4-final-cohorts.json'
records=[]
for report_name,state_name,guest in steps:
 for relative,expected in inputs.items():
  if hashlib.sha256((root/relative).read_bytes()).hexdigest()!=expected:
   raise SystemExit('Frozen input changed: '+relative)
 state=root/'build'/state_name
 if state.exists() or state.with_suffix('.exit.json').exists():raise SystemExit('Refusing existing capture '+str(state))
 command=([sys.executable,str(root/'build/useralloc-final-driver.py'),state_name,'optimized-v4-final',str(kernel)] if guest=='vinix' else [sys.executable,str(root/'build/useralloc-macos-final-driver.py'),state_name])
 started=datetime.datetime.now(datetime.timezone.utc).isoformat()
 print(started+' starting '+report_name,flush=True)
 host_before=subprocess.check_output(['ps','-axo','pid,ppid,pcpu,comm'],text=True)
 result=subprocess.run(command,cwd=root)
 item={'report_name':report_name,'state_dir':str(state),'argv':command,'started_utc':started,'finished_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'exit_code':result.returncode,'host_processes_before':host_before}
 records.append(item);record_path.write_text(json.dumps({'inputs':inputs,'captures':records},indent=2)+'\n')
 if result.returncode:raise SystemExit(result.returncode)
 driver=json.loads(state.with_suffix('.exit.json').read_text())
 if driver['exit_code']!=0:raise SystemExit('Actual driver failure '+report_name)
 run=compare.read_run(state/'serial.log',state/'config.json',report_name)
 if run.meta['iterations']!='200000' or run.meta['samples']!='7':raise SystemExit('Wrong final workload count '+report_name)
 item['validation']='Strict complete unchanged six workloads, all 42 samples, checksums and DONE verified.'
 item['source_sha256']=run.config['source_sha256']
 record_path.write_text(json.dumps({'inputs':inputs,'captures':records},indent=2)+'\n')
 print('Complete validated capture '+report_name,flush=True)
print('All four predeclared fresh captures completed and validated.',flush=True)
