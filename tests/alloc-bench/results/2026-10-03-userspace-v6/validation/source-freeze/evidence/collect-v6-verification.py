from pathlib import Path
import hashlib,json,re,sys,tarfile,subprocess
ROOT=Path('/Users/alex/code/vinix');BASE=ROOT/'third_party/useralloc-libc/build/useralloc'
PATCH='ec459e48e5c3c9946c91e805428149802d0ab1835c64e5e023811ab54a48af1d'
EXPECTED_KERNEL={'x86_64':'16140916ef5abca52cc6f0a8e80bb6dedc24b5e5f05efd747f57182523098e74','aarch64':'3d721f3168a990373cb2549bd26322329923014ee4613cda2ae3d4f6884bf8f7'}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
arch=sys.argv[1]
state=BASE/'verify-x86-v6-final' if arch=='x86_64' else ROOT/'build/useralloc-arm-v6-final'
serial=state/'serial.log';output=serial.read_text(errors='replace');lines=output.splitlines()
assert not any(x in output for x in ['UALLOC-FAIL','UALLOC-ARM-FAIL','CLOCK-FAIL','KERNEL PANIC','FATAL EXCEPTION'])
assert output.count('UALLOC-VERIFY-COMPLETE' if arch=='x86_64' else 'UALLOC-ARM-DONE')==1
assert output.count('CLOCK-DONE ')==1
for marker in ['UALLOC-ALL-CLASSES classes=48 burst=72 rounds=3','UALLOC-THREAD-TRANSITIONS cycles=24','UALLOC-GROUP-REFILLS requests=18 rounds=129','UALLOC-ATFORK-ALLOCATIONS phases=2 forks=8']:
 assert lines.count(marker)==4,marker
cases=[];footprints=[];corruption=[];policy=mode=None
for line in lines:
 if arch=='x86_64':
  m=re.fullmatch(r'UALLOC-POLICY policy=(optimized|disabled)',line)
  if m:policy=m[1]
  m=re.fullmatch(r'UALLOC-LINKAGE policy=(optimized|disabled) mode=(dynamic|static)',line)
  if m:policy,mode=m.groups()
 else:
  m=re.fullmatch(r'UALLOC-ARM-BEGIN program=/tests/(verify(?:-all-classes)?)-(optimized|disabled)-(dynamic|static)',line)
  if m:policy,mode=m[2],m[3]
 m=re.fullmatch(r'UALLOC-(SUPPLEMENT-)?DONE checks=(\d+)',line)
 if m:
  suite='supplemental' if m[1] else 'original';n=int(m[2]);assert n==({'original':1910,'supplemental':30942}[suite])
  cases.append({'policy':policy,'mode':mode,'suite':suite,'checks':n})
 m=re.fullmatch(r'UALLOC-FOOTPRINT before=(\d+) retained=(\d+) trimmed=(\d+)',line)
 if m:
  before,retained,trimmed=map(int,m.groups());assert trimmed==before
  assert retained-before<=12*1024*1024
  footprints.append({'policy':policy,'mode':mode,'before':before,'retained':retained,'trimmed':trimmed,'retained_delta':retained-before,'trimmed_delta':trimmed-before})
 m=re.fullmatch(r'UALLOC-CORRUPTION test=([0-3]) status=(\d+) signal=(\d+) exit=(-?\d+)',line)
 if m:
  test,status,signal,exitcode=map(int,m.groups());assert signal in ([4,6,11] if arch=='x86_64' else [4,5,6,11]) and exitcode==-1
  assert status&0x7f==signal and signal not in (0,0x7f)
  corruption.append({'policy':policy,'mode':mode,'test':test,'status':status,'signal':signal,'exit':exitcode,'line':line})
expected={(p,m,s) for p in ['optimized','disabled'] for m in ['dynamic','static'] for s in ['original','supplemental']}
assert {(x['policy'],x['mode'],x['suite']) for x in cases}==expected and len(cases)==8
assert len(footprints)==4 and len(corruption)==16
assert {(x['policy'],x['mode'],x['test']) for x in corruption}=={(p,m,t) for p in ['optimized','disabled'] for m in ['dynamic','static'] for t in range(4)}
if arch=='x86_64':
 config=json.loads((state/'config.json').read_text());proof=json.loads((state/'embedded-input-check.json').read_text())
 assert config['source_sha256']==sha(ROOT/'tests/user-alloc/verify.c')
 assert config['supplemental_source_sha256']==sha(ROOT/'tests/user-alloc/verify-all-classes.c')
 assert config['clock_source_sha256']==sha(ROOT/'tests/user-alloc/clock.c')
else:
 config=json.loads((state/'build.json').read_text())
 assert all(config['source_sha256'][f]==sha(ROOT/'tests/user-alloc'/f) for f in ['verify.c','verify-all-classes.c','clock.c'])
 for name,remote in [('embedded-kernel','::/boot/vinix'),('embedded-initramfs.tar','::/boot/initramfs.tar')]:
  subprocess.run(['mcopy','-o','-i',str(state/'boot.img'),remote,str(state/name)],check=True)
 assert sha(state/'embedded-kernel')==config['kernel_sha256']
 files={}
 with tarfile.open(state/'embedded-initramfs.tar') as archive:
  for path,expected_sha in config['artifacts_sha256'].items():
   embedded=archive.extractfile('./'+path).read();assert hashlib.sha256(embedded).hexdigest()==expected_sha,path
   files[path]=expected_sha
 proof={'match':True,'kernel_sha256':sha(state/'embedded-kernel'),'boot_disk_sha256':sha(state/'boot.img'),'files_sha256':files}
 (state/'embedded-input-check.json').write_text(json.dumps(proof,indent=2)+'\n')
assert config['kernel_sha256']==EXPECTED_KERNEL[arch]==proof['kernel_sha256'] and proof['match']
for policy in ['optimized','disabled']:
 stage=BASE/(policy+'-v6-final' if arch=='x86_64' else policy+'-arm126-v6-final')
 manifest=json.loads((stage/'usr/share/vinix/musl-build.json').read_text())
 assert manifest['patches'][-1]['sha256']==PATCH
 assert sha(stage/f'lib/ld-musl-{arch}.so.1')==manifest['libc_so_sha256']
 assert sha(stage/'usr/lib/libc.a')==manifest['libc_a_sha256']
 actual=config['libc_builds'][policy] if arch=='x86_64' else json.loads((state/f'musl-{policy}.json').read_text())
 assert actual==manifest
result={'passed':True,'cases':cases,'total_checks':sum(x['checks'] for x in cases),'footprints':footprints,'corruption':corruption,'clock_lines':[x for x in lines if x.startswith('CLOCK-')],'serial_sha256':sha(serial),'config':config,'embedded_input_check':proof,'patch_sha256':PATCH,'kernel_sha256':EXPECTED_KERNEL[arch]}
(state/'results.json').write_text(json.dumps(result,indent=2)+'\n')
print(arch,'PASS',result['total_checks'],'checks',len(corruption),'rejected corruption children',flush=True)
