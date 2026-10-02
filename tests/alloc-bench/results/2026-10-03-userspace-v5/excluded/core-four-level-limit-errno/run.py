from pathlib import Path
import subprocess,json,hashlib,datetime,os
s=Path(__file__).resolve().parent;m=json.loads((s/'run.json').read_text())
with (s/'serial.log').open('wb') as out:r=subprocess.run(m['run_command'],env=dict(os.environ,**m['run_environment']),stdout=out,stderr=subprocess.STDOUT)
supplement_ok=(s/'serial.log').read_bytes().count(b'PAGETABLE CHECK: PASS')==1
if r.returncode==0 and not supplement_ok:r.returncode=1
m.update(boundary_supplement_pass=supplement_ok,exit_code=r.returncode,finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),serial_sha256=hashlib.sha256((s/'serial.log').read_bytes()).hexdigest());(s/'run.json').write_text(json.dumps(m,indent=2)+'\n');print('full core',r.returncode,flush=True);raise SystemExit(r.returncode)
