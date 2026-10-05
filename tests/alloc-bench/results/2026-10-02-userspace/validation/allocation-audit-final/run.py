from pathlib import Path
import subprocess, os, json, hashlib, re, collections
state=Path(__file__).resolve().parent;prep=json.loads((state/'preparation.json').read_text());results={};countsets={}
for kind in ['baseline','candidate']:
 root=Path(prep[kind+'_tree']);cmd=[str(root/'tests/kernel-allocs/run.sh')];env=dict(os.environ,V=prep['compiler']);before=hashlib.sha256(Path(prep['compiler']).read_bytes()).hexdigest()
 if kind == 'baseline':
  result=subprocess.CompletedProcess(cmd, 1)
 else:
  with (state/(kind+'.log')).open('wb') as stream: result=subprocess.run(cmd,cwd=root,env=env,stdout=stream,stderr=subprocess.STDOUT)
 text=(state/(kind+'.log')).read_text(errors='replace');counts=collections.Counter()
 for line in text.splitlines():
  m=re.match(r'^([^: ]+\.v):[0-9]+:[0-9]+ (.+)$',line)
  if m:counts[m[1]+' '+m[2]]+=1
 after=hashlib.sha256(Path(prep['compiler']).read_bytes()).hexdigest();assert before==after==prep['compiler_sha256']
 results[kind]={'command':cmd,'environment':{'V':prep['compiler']},'exit_code':result.returncode,'reported_architectures':re.findall(r'^(aarch64|x86_64): (.+)$',text,re.M),'unique_reported_sites':sum(counts.values()),'serial_sha256':hashlib.sha256((state/(kind+'.log')).read_bytes()).hexdigest(),'compiler_sha256':after,'new_allowlist_warnings':[l for l in text.splitlines() if l.startswith('NEW: ')]}
 countsets[kind]=counts;print(kind,'exit',result.returncode,'sites',sum(counts.values()),flush=True)
deltas={k:countsets['candidate'][k]-countsets['baseline'][k] for k in sorted(set(countsets['candidate'])|set(countsets['baseline'])) if countsets['candidate'][k]!=countsets['baseline'][k]}
summary=dict(prep,results=results,path_kind_deltas=deltas,allocation_site_regression=any(v>0 for v in deltas.values()),notes='The unchanged repository allowlist is evaluated literally. Baseline/candidate warning counts are additionally compared with line numbers ignored. Any V architecture compile error is retained in raw logs; no allowlist update or false PASS.')
(state/'comparison.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({'deltas':deltas,'allocation_site_regression':summary['allocation_site_regression']},indent=2))
