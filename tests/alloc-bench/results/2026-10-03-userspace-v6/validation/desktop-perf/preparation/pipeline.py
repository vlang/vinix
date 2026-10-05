from pathlib import Path
import datetime,hashlib,importlib.util,json,subprocess,sys,time
root=Path('/Users/alex/code/vinix');setup=Path(__file__).resolve().parent
state=root/'build/useralloc-desktop-perf-v6'
start=datetime.datetime.now(datetime.timezone.utc).isoformat()
checkpoint=setup/'pipeline-checkpoint.json'
def save(phase,**kw):checkpoint.write_text(json.dumps(dict(phase=phase,started_utc=start,updated_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),**kw),indent=2)+'\n')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
save('waiting-static-desktop')
desktopstate=root/'build/useralloc-pipe/static-desktop-v6'
for _ in range(600):
    if (desktopstate/'driver.exit.json').exists():break
    time.sleep(2)
else:raise RuntimeError('Static desktop wait exceeded20minutes')
assert json.loads((desktopstate/'driver.exit.json').read_text())['exit_code']==0
assert json.loads((desktopstate/'build.json').read_text())['build_exit_code']==0
save('perf-running')
command=[sys.executable,str(setup/'run-driver.py'),str(state),'ops,churn,cache,idle,apps,drag',str(root/'build/useralloc-kernel-speed-v5/aarch64/vinix-aarch64')]
result=subprocess.run(command)
(setup/'driver.exit.json').write_text(json.dumps({'exit_code':result.returncode,'started_utc':start,'finished_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'argv':command},indent=2)+'\n')
assert result.returncode==0
save('independent-validation')
spec=importlib.util.spec_from_file_location('useralloc_perf_v6',setup/'run.py');module=importlib.util.module_from_spec(spec);sys.modules[spec.name]=module;spec.loader.exec_module(module)
scenarios=['ops','churn','cache','idle','apps','drag']
rows,reports,errors=module.inspect_run((state/'serial.log').read_bytes(),['final'],scenarios,1,False,0)
assert not errors,errors
assert len(rows)==43,len(rows)
actual=json.loads((state/'results.json').read_text())
assert actual==rows,(type(actual),len(actual))
run=json.loads((state/'run.json').read_text());assert run['runner_exit_code']==0
for field,path in [('kernel_sha256',root/'build/useralloc-kernel-speed-v5/aarch64/vinix-aarch64'),('desktop_sha256',desktopstate/'vinix-desktop'),('serial_sha256',state/'serial.log'),('harness_sha256',setup/'run.py')]:assert run[field]==sha(path)
validation={'status':'PASS','checked_rows':len(rows),'scenarios':scenarios,'runner_exit_code':0,**{k:run[k] for k in ('kernel_sha256','desktop_sha256','serial_sha256','harness_sha256')},'notes':'Complete functional/memory scenarios with unchanged workloads. Existing ops/churn growth remains visible; this does not claim flat kernel memory.'}
(state/'validation.json').write_text(json.dumps(validation,indent=2)+'\n')
save('complete',validation=validation)
