#!/usr/bin/env python3
from pathlib import Path
import datetime,hashlib,importlib.util,json,subprocess,sys
root=Path(__file__).resolve().parent.parent
SPEC=importlib.util.spec_from_file_location('allocation_compare',root/'tests/alloc-bench/compare.py')
compare=importlib.util.module_from_spec(SPEC);sys.modules[SPEC.name]=compare;SPEC.loader.exec_module(compare)
inputs={
'build/useralloc-kernel-speed-v5/x86_64/vinix-x86_64':'16140916ef5abca52cc6f0a8e80bb6dedc24b5e5f05efd747f57182523098e74',
'build/useralloc-review-v5/sources/build-support/musl/malloc-retain.patch':'5ff7f0e2fdc9525d83b43fa98fdc27e34d5ef2e6d7f7b74e29c57113a34eca86',
'third_party/useralloc-speed-v5/kernel/katomic/katomic_amd64.v':'ec2d130780fe2fe72bdff53013594e2bc5dbe671c10ab260412f0de8c19d1bf4',
'third_party/useralloc-speed-v5/kernel/klock/klock_amd64.v':'3db4566c9a05ada0098109928957a56d8248f96a6da3ad95b555d8a35e89c4ee',
'third_party/useralloc-speed-v5/kernel/c/memory.c':'5082c545e7c16318cceeb51bf280c356c6b9713c0de8b336290be165f2a42eb5',
'third_party/useralloc-speed-v5/kernel/file/locks.v':'21937b5a7f0ee5d5bb233d855217d7c431b2793be40263b74f7073ead1327ac3',
'tests/alloc-bench/bench.c':'bd4a0d74f4f1e8d079d55877f8e90925e2622ce990120b54573a5dc94a9a54b9',
 'third_party/useralloc-libc/build/useralloc/optimized-v5-final/lib/ld-musl-x86_64.so.1':'6cf9e5ead03671c57dc0661e0fc02a675a34a5cf57826a09452001ded8932b03',
 'third_party/useralloc-libc/build/useralloc/optimized-v5-final/usr/lib/libc.a':'eb50810aa7d3583f6469e23fce4c2f464a86197cfb2a0cdf5293b75baaedd90c',
}
inputs.update({'third_party/useralloc-speed-v5/kernel/c/memory.c': '5082c545e7c16318cceeb51bf280c356c6b9713c0de8b336290be165f2a42eb5', 'third_party/useralloc-speed-v5/kernel/file/locks.v': '21937b5a7f0ee5d5bb233d855217d7c431b2793be40263b74f7073ead1327ac3', 'third_party/useralloc-speed-v5/kernel/file/timerfd.v': 'ba38d9a723efd67f9d221cb9c3e5961aeb2e8c1b7d603665aeb05abe44482c23', 'third_party/useralloc-speed-v5/kernel/katomic/katomic_amd64.v': 'ec2d130780fe2fe72bdff53013594e2bc5dbe671c10ab260412f0de8c19d1bf4', 'third_party/useralloc-speed-v5/kernel/klock/klock_amd64.v': '3db4566c9a05ada0098109928957a56d8248f96a6da3ad95b555d8a35e89c4ee', 'third_party/useralloc-speed-v5/kernel/memory/mmap/mmap.v': '95788b45183c6eac58f4fa5c01d5e5d3d5672e728d3051ce9d71d89107bf9980', 'third_party/useralloc-speed-v5/kernel/memory/mmap/mmap_amd64.v': '69e3648bb5419a1e0e9f06721080deabdb286abc7c0fdae1b6f5c6515bf85c58', 'third_party/useralloc-speed-v5/kernel/memory/mmap/mmap_arm64.v': 'ba522bfaff83fcf525ed52a34229c013af0ef1c7a27c099adc9089cd45714e4a', 'third_party/useralloc-speed-v5/kernel/memory/mmap/page_in.v': '1009d493f1998188f5a24c27e443e53f77506cd432e6241b0831bb785bc6ca8d', 'third_party/useralloc-speed-v5/kernel/memory/virtual_amd64.v': '718daf59003f9d992237fd41e26cea4de97600afaf874e24359118f6df70430a', 'third_party/useralloc-speed-v5/kernel/pipe/pipe.v': '2cb2d4e677ca89a16cb85cfbae4b637df9405d1409ab4b479fa24c987f2da411', 'third_party/useralloc-speed-v5/kernel/socket/socket.v': 'c82e100d74c07f3fbd2ddd55a9b8ea54d963ddb7ce4ca2ce7d27d0d66f5881f0', 'third_party/useralloc-speed-v5/kernel/socket/unix/unix.v': '24b8656b644f817bef99d21a19b6ac3b5b7fc424890eb4429f453a372ea4afb6', 'third_party/useralloc-speed-v5/kernel/time/sys/linux.v': '3cb9a6f155affa03a968604ef6de60aa263e38d30c67114d84a7607ce25967b2', 'third_party/useralloc-speed-v5/kernel/time/sys/syscalls.v': '847e11eef5747b1b63794e27a58321159c9ceead187895449ed710a561650f21', 'third_party/useralloc-speed-v5/kernel/time/time.v': '40767795f0d35378b010f9e74423d353f0b8194d130978a5e3bc0b961c20ffc3', 'third_party/useralloc-speed-v5/kernel/time/time_amd64.v': '58449cbb9eab4c201074f7563da7e2817fb5221a5beee61e57ba58f7512f5329', 'third_party/useralloc-speed-v5/kernel/time/time_arm64.v': '7cc360fd708b13fc67275455dc314d6d64db71769f2f094f5d92b14de0061be5', 'tests/alloc-bench/compare.py': 'e12ec5a8c90cab335c40e68257d596e0a2d0ba9f284b1e4bfe911fffa352dd06', 'build/useralloc-final-audit/compiler/v': '80c39942a71a8323754159b37624b69fe9469ca90892e97ea721fa4d5ac86bf0'})
kernel=root/'build/useralloc-kernel-speed-v5/x86_64/vinix-x86_64'
steps=[('vinix-1','useralloc-vinix-v5-final-1','vinix'),('catalina-1','useralloc-macos-v5-final-1','catalina'),('catalina-2','useralloc-macos-v5-final-2','catalina'),('vinix-2','useralloc-vinix-v5-final-2','vinix')]
record_path=root/'build/useralloc-v5-final-cohorts.json'
records=json.loads(record_path.read_text())['captures'] if record_path.exists() else []
for ordinal,item in enumerate(records):
 if item['report_name']!=steps[ordinal][0] or item['exit_code']!=0:raise SystemExit('Invalid completed-prefix record')
 prior_state=Path(item['state_dir'])
 if json.loads(prior_state.with_suffix('.exit.json').read_text())['exit_code']!=0:raise SystemExit('Prior actual driver failure')
 prior_run=compare.read_run(prior_state/'serial.log',prior_state/'config.json',item['report_name'])
 if prior_run.meta['iterations']!='200000' or prior_run.meta['samples']!='7':raise SystemExit('Prior workload mismatch')
for ordinal,(report_name,state_name,guest) in enumerate(steps):
 for relative,expected in inputs.items():
  if hashlib.sha256((root/relative).read_bytes()).hexdigest()!=expected:
   raise SystemExit('Frozen input changed: '+relative)
 if ordinal<len(records):continue
 state=root/'build'/state_name
 if state.exists() or state.with_suffix('.exit.json').exists():raise SystemExit('Refusing existing capture '+str(state))
 command=([sys.executable,str(root/'build/useralloc-final-driver.py'),state_name,'optimized-v5-final',str(kernel)] if guest=='vinix' else [sys.executable,str(root/'build/useralloc-macos-final-driver.py'),state_name])
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
