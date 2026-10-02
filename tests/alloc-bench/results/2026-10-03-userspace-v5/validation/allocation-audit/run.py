from pathlib import Path
import subprocess,os,json,hashlib,re,collections,datetime
r=Path('/Users/alex/code/vinix');w=r/'third_party/useralloc-speed-v5';s=Path(__file__).resolve().parent;v=r/'build/useralloc-final-audit/compiler/v'
cmd=[str(w/'tests/kernel-allocs/run.sh')]
with (s/'candidate.log').open('wb') as out:run=subprocess.run(cmd,env=dict(os.environ,V=str(v)),stdout=out,stderr=subprocess.STDOUT,cwd=w)
def counts(text):
 c=collections.Counter()
 for line in text.splitlines():
  m=re.match(r'^([^: ]+\.v):[0-9]+:[0-9]+ (.+)$',line)
  if m:c[m[1]+' '+m[2]]+=1
 return c
raw=(s/'candidate.log').read_text(errors='replace');prior=(r/'build/useralloc-kernel-speed-v4/allocation-audit/candidate.log').read_text(errors='replace');base=counts(prior);new=counts(raw);deltas={k:new[k]-base[k] for k in sorted(set(base)|set(new)) if base[k]!=new[k]}
m={'command':cmd,'environment':{'V':str(v)},'candidate_exit_code':run.returncode,'baseline_source':'build/useralloc-kernel-speed-v4/allocation-audit/candidate.log','baseline_sites':sum(base.values()),'candidate_sites':sum(new.values()),'path_kind_deltas':deltas,'allocation_site_regression':any(n>0 for n in deltas.values()),'reported_architectures':re.findall(r'^(aarch64|x86_64): (.+)$',raw,re.M),'compiler_sha256':hashlib.sha256(v.read_bytes()).hexdigest(),'notes':'Literal unchanged allowlist result retained; compare exact frozen-V e29 baseline without line-number noise. No allowlist edits.'};(s/'comparison.json').write_text(json.dumps(m,indent=2)+'\n');print(json.dumps(m,indent=2),flush=True)
