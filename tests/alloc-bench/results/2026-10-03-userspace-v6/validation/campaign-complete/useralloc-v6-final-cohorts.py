#!/usr/bin/env python3
from pathlib import Path
import datetime,hashlib,importlib.util,json,subprocess,sys
root=Path(__file__).resolve().parent.parent
SPEC=importlib.util.spec_from_file_location('allocation_compare',root/'tests/alloc-bench/compare.py')
compare=importlib.util.module_from_spec(SPEC);sys.modules[SPEC.name]=compare;SPEC.loader.exec_module(compare)
inputs={
'build/useralloc-kernel-speed-v5/x86_64/vinix-x86_64':'16140916ef5abca52cc6f0a8e80bb6dedc24b5e5f05efd747f57182523098e74',
'third_party/useralloc-libc/build/useralloc/v6-source-freeze/build-support/musl/malloc-retain.patch':'ec459e48e5c3c9946c91e805428149802d0ab1835c64e5e023811ab54a48af1d',
'third_party/useralloc-speed-v5/kernel/katomic/katomic_amd64.v':'ec2d130780fe2fe72bdff53013594e2bc5dbe671c10ab260412f0de8c19d1bf4',
'third_party/useralloc-speed-v5/kernel/klock/klock_amd64.v':'3db4566c9a05ada0098109928957a56d8248f96a6da3ad95b555d8a35e89c4ee',
'third_party/useralloc-speed-v5/kernel/c/memory.c':'5082c545e7c16318cceeb51bf280c356c6b9713c0de8b336290be165f2a42eb5',
'third_party/useralloc-speed-v5/kernel/file/locks.v':'21937b5a7f0ee5d5bb233d855217d7c431b2793be40263b74f7073ead1327ac3',
'tests/alloc-bench/bench.c':'bd4a0d74f4f1e8d079d55877f8e90925e2622ce990120b54573a5dc94a9a54b9',
 'third_party/useralloc-libc/build/useralloc/optimized-v6-final/lib/ld-musl-x86_64.so.1':'ad78977e92f55d85ace71f1ca43bf650d216923ed3cf6650dd29f22c1d70af9d',
 'third_party/useralloc-libc/build/useralloc/optimized-v6-final/usr/lib/libc.a':'8d5c3deee3610c07c3f9bbfaee3b4fed244ef35051c3e2390e4452b13db34ace',
}
inputs.update({'third_party/useralloc-speed-v5/kernel/c/memory.c': '5082c545e7c16318cceeb51bf280c356c6b9713c0de8b336290be165f2a42eb5', 'third_party/useralloc-speed-v5/kernel/file/locks.v': '21937b5a7f0ee5d5bb233d855217d7c431b2793be40263b74f7073ead1327ac3', 'third_party/useralloc-speed-v5/kernel/file/timerfd.v': 'ba38d9a723efd67f9d221cb9c3e5961aeb2e8c1b7d603665aeb05abe44482c23', 'third_party/useralloc-speed-v5/kernel/katomic/katomic_amd64.v': 'ec2d130780fe2fe72bdff53013594e2bc5dbe671c10ab260412f0de8c19d1bf4', 'third_party/useralloc-speed-v5/kernel/klock/klock_amd64.v': '3db4566c9a05ada0098109928957a56d8248f96a6da3ad95b555d8a35e89c4ee', 'third_party/useralloc-speed-v5/kernel/memory/mmap/mmap.v': '95788b45183c6eac58f4fa5c01d5e5d3d5672e728d3051ce9d71d89107bf9980', 'third_party/useralloc-speed-v5/kernel/memory/mmap/mmap_amd64.v': '69e3648bb5419a1e0e9f06721080deabdb286abc7c0fdae1b6f5c6515bf85c58', 'third_party/useralloc-speed-v5/kernel/memory/mmap/mmap_arm64.v': 'ba522bfaff83fcf525ed52a34229c013af0ef1c7a27c099adc9089cd45714e4a', 'third_party/useralloc-speed-v5/kernel/memory/mmap/page_in.v': '1009d493f1998188f5a24c27e443e53f77506cd432e6241b0831bb785bc6ca8d', 'third_party/useralloc-speed-v5/kernel/memory/virtual_amd64.v': '718daf59003f9d992237fd41e26cea4de97600afaf874e24359118f6df70430a', 'third_party/useralloc-speed-v5/kernel/pipe/pipe.v': '2cb2d4e677ca89a16cb85cfbae4b637df9405d1409ab4b479fa24c987f2da411', 'third_party/useralloc-speed-v5/kernel/socket/socket.v': 'c82e100d74c07f3fbd2ddd55a9b8ea54d963ddb7ce4ca2ce7d27d0d66f5881f0', 'third_party/useralloc-speed-v5/kernel/socket/unix/unix.v': '24b8656b644f817bef99d21a19b6ac3b5b7fc424890eb4429f453a372ea4afb6', 'third_party/useralloc-speed-v5/kernel/time/sys/linux.v': '3cb9a6f155affa03a968604ef6de60aa263e38d30c67114d84a7607ce25967b2', 'third_party/useralloc-speed-v5/kernel/time/sys/syscalls.v': '847e11eef5747b1b63794e27a58321159c9ceead187895449ed710a561650f21', 'third_party/useralloc-speed-v5/kernel/time/time.v': '40767795f0d35378b010f9e74423d353f0b8194d130978a5e3bc0b961c20ffc3', 'third_party/useralloc-speed-v5/kernel/time/time_amd64.v': '58449cbb9eab4c201074f7563da7e2817fb5221a5beee61e57ba58f7512f5329', 'third_party/useralloc-speed-v5/kernel/time/time_arm64.v': '7cc360fd708b13fc67275455dc314d6d64db71769f2f094f5d92b14de0061be5', 'tests/alloc-bench/compare.py': 'e12ec5a8c90cab335c40e68257d596e0a2d0ba9f284b1e4bfe911fffa352dd06', 'build/useralloc-final-audit/compiler/v': '80c39942a71a8323754159b37624b69fe9469ca90892e97ea721fa4d5ac86bf0'})
inputs.update({'tests/alloc-bench/results/2026-10-03-userspace-v6/campaign-plan.json': 'df9db0e94ba5b9bce3ac71fbdfed469642b5b0a6492c764a44fd69df5e9ba012', 'tests/alloc-bench/run-vinix.py': '146a8318f8f2ad1daccf0409f96f88f492563a584fee896697ed2d58409ebb6c', 'build/useralloc-final-driver.py': '271a7215f36c5dfcacc133f0fae2e80f5a8bfd9d1445044f4105843eb53681e8', 'build/useralloc-macos-final-driver.py': 'd649c51d8f599d4d90c2852fc26892dcc5596d9d5f848f3199698ccd12ddfa48', 'build/useralloc-macos-runtime/measure.py': 'e321a5d856ff9f046b7ad287799c55199a64b04ea9309cbe0a4b8a33259effd1'})
readiness=json.loads((root/'build/useralloc-v6-final-readiness.json').read_text())
if readiness['status']!='PASS':raise SystemExit('Final gates are incomplete')
inputs.update({'tests/alloc-bench/results/2026-10-02/user-macos/config.json': '2207dc5b1c4d0782c94b813afd48b4a61a662147a1fc8c29f4a4ecaf8427ceb0', 'build/useralloc-macos-runtime/argv.json': '97b1c18ba48f89eb594fe1a7508e6f952824f934a616ec303596cd7e1cea3c60', 'build/alloc-bench-macos/alloc-bench-native': 'aed1e90c728e56b77cbff31c62277eb80762b9a0f54b02e815ce581913352b97', 'build/alloc-bench-macos/bench-native.s': 'ff4f96b50b88ea1482866c7fed1bbc0750d46e47c0f984466332615439136bdd'})
plan=json.loads((root/'tests/alloc-bench/results/2026-10-03-userspace-v6/campaign-plan.json').read_text())
def validate_declared(run, guest):
 if run.config.get('source_sha256')!=plan['source_sha256']:raise SystemExit('Benchmark source mismatch '+run.name)
 if run.config.get('compile_flags')!=list(compare.COMPILE_FLAGS):raise SystemExit('Compiler flags mismatch '+run.name)
 for key,value in plan['common_qemu'].items():
  if run.config.get(key)!=value:raise SystemExit('Declared QEMU mismatch '+run.name+' '+key)
 argv=run.config.get('argv',[])
 for option,key in [('-machine','machine'),('-accel','accelerator'),('-cpu','cpu'),('-smp','smp'),('-m','memory_mb')]:
  if argv.count(option)!=1 or argv[argv.index(option)+1]!=str(plan['common_qemu'][key]):raise SystemExit('Actual QEMU arguments mismatch '+run.name+' '+option)
 expected={'platform':'Vinix' if guest=='vinix' else 'Darwin','release':'0.1.0' if guest=='vinix' else '19.6.0','arch':'x86_64','compiler':'gcc','compiler_major':'14','compiler_minor':'2' if guest=='vinix' else '3','compiler_patch':'0','iterations':'200000','samples':'7'}
 for key,value in expected.items():
  if run.meta.get(key)!=value:raise SystemExit('Guest metadata mismatch '+run.name+' '+key)
 if guest=='vinix':
  for field,expected in [('kernel_sha256','16140916ef5abca52cc6f0a8e80bb6dedc24b5e5f05efd747f57182523098e74'),('libc_sha256','ad78977e92f55d85ace71f1ca43bf650d216923ed3cf6650dd29f22c1d70af9d'),('libc_a_sha256','8d5c3deee3610c07c3f9bbfaee3b4fed244ef35051c3e2390e4452b13db34ace')]:
   if run.config.get(field)!=expected:raise SystemExit('Executed Vinix artifact mismatch '+field)
 else:
  for field,expected in [('assembly_sha256','ff4f96b50b88ea1482866c7fed1bbc0750d46e47c0f984466332615439136bdd'),('binary_sha256','aed1e90c728e56b77cbff31c62277eb80762b9a0f54b02e815ce581913352b97')]:
   if run.config.get(field)!=expected:raise SystemExit('Executed Catalina artifact mismatch '+field)

kernel=root/'build/useralloc-kernel-speed-v5/x86_64/vinix-x86_64'
steps=[('vinix-1','useralloc-vinix-v6-final-1','vinix'),('catalina-1','useralloc-macos-v6-final-1','catalina'),('catalina-2','useralloc-macos-v6-final-2','catalina'),('vinix-2','useralloc-vinix-v6-final-2','vinix')]
record_path=root/'build/useralloc-v6-final-cohorts.json'
records=json.loads(record_path.read_text())['captures'] if record_path.exists() else []
for ordinal,item in enumerate(records):
 if item['report_name']!=steps[ordinal][0] or item['exit_code']!=0:raise SystemExit('Invalid completed-prefix record')
 prior_state=Path(item['state_dir'])
 if json.loads(prior_state.with_suffix('.exit.json').read_text())['exit_code']!=0:raise SystemExit('Prior actual driver failure')
 prior_run=compare.read_run(prior_state/'serial.log',prior_state/'config.json',item['report_name'])
 validate_declared(prior_run,steps[ordinal][2])
 if prior_run.meta['iterations']!='200000' or prior_run.meta['samples']!='7':raise SystemExit('Prior workload mismatch')
for ordinal,(report_name,state_name,guest) in enumerate(steps):
 for relative,expected in inputs.items():
  if hashlib.sha256((root/relative).read_bytes()).hexdigest()!=expected:
   raise SystemExit('Frozen input changed: '+relative)
 if ordinal<len(records):continue
 state=root/'build'/state_name
 if state.exists() or state.with_suffix('.exit.json').exists():raise SystemExit('Refusing existing capture '+str(state))
 command=([sys.executable,str(root/'build/useralloc-final-driver.py'),state_name,'optimized-v6-final',str(kernel)] if guest=='vinix' else [sys.executable,str(root/'build/useralloc-macos-final-driver.py'),state_name])
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
 validate_declared(run,guest)
 if run.meta['iterations']!='200000' or run.meta['samples']!='7':raise SystemExit('Wrong final workload count '+report_name)
 item['validation']='Strict complete unchanged six workloads, all 42 samples, checksums and DONE verified.'
 item['source_sha256']=run.config['source_sha256']
 record_path.write_text(json.dumps({'inputs':inputs,'captures':records},indent=2)+'\n')
 print('Complete validated capture '+report_name,flush=True)
runs={item['report_name']:compare.read_run(Path(item['state_dir'])/'serial.log',Path(item['state_dir'])/'config.json',item['report_name']) for item in records}
for number in (1,2):
 mismatches,notes=compare.comparability(runs['vinix-'+str(number)],runs['catalina-'+str(number)])
 if mismatches:raise SystemExit('Matched cohort config mismatch: '+repr(mismatches))
print('All four predeclared fresh captures completed and validated.',flush=True)
