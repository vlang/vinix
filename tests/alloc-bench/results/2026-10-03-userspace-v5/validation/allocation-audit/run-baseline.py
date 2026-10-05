from pathlib import Path
import subprocess,os,json,datetime,hashlib
root=Path('/Users/alex/code/vinix');w=root/'third_party/useralloc-speed-v5-audit-base';s=root/'build/useralloc-kernel-speed-v5/allocation-audit';v=root/'build/useralloc-final-audit/compiler/v'
cmd=[str(w/'tests/kernel-allocs/run.sh')]
with (s/'baseline.log').open('wb') as out:r=subprocess.run(cmd,cwd=w,env=dict(os.environ,V=str(v)),stdout=out,stderr=subprocess.STDOUT)
(s/'baseline-run.json').write_text(json.dumps({'command':cmd,'environment':{'V':str(v)},'exit_code':r.returncode,'compiler_sha256':hashlib.sha256(v.read_bytes()).hexdigest(),'allowed_sha256':hashlib.sha256((w/'tests/kernel-allocs/allowed.txt').read_bytes()).hexdigest(),'finished_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'notes':'Exact frozen v4 kernel sources with same fixed checker/full literal allowlist as v5. No allowlist edits.'},indent=2)+'\n')
print(r.returncode,flush=True)
