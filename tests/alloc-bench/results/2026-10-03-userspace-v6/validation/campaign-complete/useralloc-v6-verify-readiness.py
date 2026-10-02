from pathlib import Path
import datetime,hashlib,json
root=Path('/Users/alex/code/vinix')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
gates={
'build/useralloc-kernel-speed-v5/x86_64/build.json':('build_exit_code',0),
'build/useralloc-kernel-speed-v5/aarch64/build.json':('build_exit_code',0),
'build/useralloc-core-v6/core-x86_64/run.json':('exit_code',0),
'build/useralloc-core-v6/core-x86_64-four-level/run.json':('exit_code',0),
'build/useralloc-core-v6/core-aarch64/run.json':('exit_code',0),
'build/useralloc-core-v6/exit.json':('exit_code',0),
'third_party/useralloc-libc/build/useralloc/v6-verification-summary.json':('all_passed',True),
'third_party/useralloc-libc/build/useralloc-production-v6/amd64/results.json':('status','PASS'),
'third_party/useralloc-libc/build/useralloc-production-v6/aarch64/results.json':('status','PASS'),
'third_party/useralloc-libc/build/useralloc-production-v6/amd64/root-review.json':('status','PASS'),
'third_party/useralloc-libc/build/useralloc-production-v6/aarch64/root-review.json':('status','PASS'),
'build/useralloc-pipe/static-desktop-v6/build.json':('build_exit_code',0),
'build/useralloc-pipe/static-desktop-v6/driver.exit.json':('exit_code',0),
'build/useralloc-review-v6/review.json':('status','PASS'),
'build/useralloc-desktop-perf-v6/validation.json':('status','PASS'),
'build/useralloc-hot-v5-diagnostic/driver.exit.json':('exit_code',0),
}
records={}
for name,(field,expected) in gates.items():
 p=root/name;d=json.loads(p.read_text());assert d[field]==expected,(name,field,d[field]);records[name]={'sha256':sha(p),'checked_field':field,'value':d[field]}
patch=root/'third_party/useralloc-libc/build/useralloc/v6-source-freeze/build-support/musl/malloc-retain.patch'
assert sha(patch)=='ec459e48e5c3c9946c91e805428149802d0ab1835c64e5e023811ab54a48af1d'
for name,expected in [('build/useralloc-kernel-speed-v5/x86_64/vinix-x86_64','16140916ef5abca52cc6f0a8e80bb6dedc24b5e5f05efd747f57182523098e74'),('build/useralloc-kernel-speed-v5/aarch64/vinix-aarch64','3d721f3168a990373cb2549bd26322329923014ee4613cda2ae3d4f6884bf8f7'),('third_party/useralloc-libc/build/useralloc/optimized-v6-final/lib/ld-musl-x86_64.so.1','ad78977e92f55d85ace71f1ca43bf650d216923ed3cf6650dd29f22c1d70af9d'),('third_party/useralloc-libc/build/useralloc/optimized-v6-final/usr/lib/libc.a','8d5c3deee3610c07c3f9bbfaee3b4fed244ef35051c3e2390e4452b13db34ace')]:assert sha(root/name)==expected,name
result={'status':'PASS','checked_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'gates':records,'notes':'Same immutable validated v5 kernels; final v6 libc correctness, production packaging/static desktop, full3core modes and43rowfunctionaldesktop plan complete. Full allocation checker historical literalallowlist failure remains unchanged with same kernel source.'}
(root/'build/useralloc-v6-final-readiness.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
