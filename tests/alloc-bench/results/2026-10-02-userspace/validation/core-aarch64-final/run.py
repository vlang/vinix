from pathlib import Path
import os,subprocess,json,hashlib,datetime
root=Path('/Users/alex/code/vinix');core=root/'build/useralloc-arm-core-final-v5';tree=root/'third_party/useralloc-vm-next';manifest=json.loads((core/'run.json').read_text());assert os.access(core/'init',os.X_OK)
env=dict(os.environ,**manifest['run_environment']);cmd=manifest['run_command'];manifest.update(started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat());manifest.pop('exit_code',None);manifest.pop('finished_utc',None);(core/'run.json').write_text(json.dumps(manifest,indent=2)+'\n')
with (core/'serial.log').open('wb') as out:r=subprocess.run(cmd,env=env,stdout=out,stderr=subprocess.STDOUT)
manifest.update(exit_code=r.returncode,finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),serial_sha256=hashlib.sha256((core/'serial.log').read_bytes()).hexdigest());(core/'run.json').write_text(json.dumps(manifest,indent=2)+'\n');print('core',r.returncode,flush=True);raise SystemExit(r.returncode)
