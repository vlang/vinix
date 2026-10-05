from pathlib import Path
import datetime,json,subprocess,sys
root=Path('/Users/alex/code/vinix')
started=datetime.datetime.now(datetime.timezone.utc).isoformat()
command=[sys.executable,str(root/'build/useralloc-v6-final-cohorts.py')]
with (root/'build/useralloc-v6-final-cohorts.driver.log').open('wb') as log:
 result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,cwd=root)
(root/'build/useralloc-v6-final-cohorts.exit.json').write_text(json.dumps({'argv':command,'started_utc':started,'finished_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'exit_code':result.returncode},indent=2)+'\n')
raise SystemExit(result.returncode)
