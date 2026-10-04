from pathlib import Path
import json,time,subprocess
root=Path('/Users/alex/code/vinix');base=root/'build/useralloc-socket-operations-v3';core=root/'build/useralloc-arm-core-final-v5'
while True:
 m=json.loads((core/'run.json').read_text())
 if 'finished_utc' in m:
  if m['exit_code']:raise SystemExit('core failed; no supplementary ARM guest launched')
  break
 time.sleep(.25)
results=[]
for name,kernel in [('settlement-candidate',root/'third_party/useralloc-vm-next/kernel'),('settlement-baseline',root/'third_party/useralloc-audit-baseline-v3/kernel')]:
 state=base/name;cmd=['python3',str(root/'build/useralloc-final-kernel-aarch64/run-probe.py'),str(state),'settlement',str(kernel)]
 with (state/'output.log').open('wb') as out:r=subprocess.run(cmd,stdout=out,stderr=subprocess.STDOUT)
 results.append({'name':name,'exit_code':r.returncode});(base/'settlement-exit.json').write_text(json.dumps(results,indent=2)+'\n');print(name,r.returncode,flush=True)
raise SystemExit(0 if all(v['exit_code']==0 for v in results) else 1)
