#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,os,subprocess,sys,shutil,re,time
root=Path('/Users/alex/code/vinix')
setup=root/'build/useralloc-pipe/perf-v6-preparation'
state=Path(sys.argv[1]).resolve();state.mkdir(parents=True,exist_ok=True)
scenarios=sys.argv[2]
kernel=Path(sys.argv[3]).resolve();desktop=root/'build/useralloc-pipe/static-desktop-v6/vinix-desktop'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
kdir=state/'kernel/bin';kdir.mkdir(parents=True,exist_ok=True);shutil.copy2(kernel,kdir/'vinix')
env=os.environ.copy();env.update(VINIX_KERNEL_DIR=str(kdir.parent),VINIX_AARCH64_SYSROOT=str(root/'build/useralloc-pipe/static-desktop-v6/sysroot'),VINIX_QEMU_SMP='2',USE_TCG='0')
command=['python3',str(setup/'run.py'),'final='+str(desktop),'--scenarios='+scenarios,'--rounds','1','--initramfs',str(setup/'initramfs-desktop-frozen.tar'),'--settle','5','--seconds','20','--timeout','1800','--json',str(state/'results.json'),'--shots',str(state/'shots')]
manifest={'kernel_sha256':sha(kernel),'desktop_sha256':sha(desktop),'loader_sha256':sha(root/'third_party/useralloc-libc/build/useralloc/optimized-arm126-v6-final/lib/ld-musl-aarch64.so.1'),'static_libc_sha256':sha(root/'third_party/useralloc-libc/build/useralloc/optimized-arm126-v6-final/usr/lib/libc.a'),'initramfs_sha256':sha(setup/'initramfs-desktop-frozen.tar'),'harness_sha256':sha(setup/'run.py'),'measure_source_sha256':sha(setup/'measure.c'),'guest_init_sha256':sha(setup/'perf-init.sh'),'command':command,'environment':{k:env[k] for k in ('VINIX_KERNEL_DIR','VINIX_AARCH64_SYSROOT','VINIX_QEMU_SMP','USE_TCG')},'start_time_utc':time.strftime('%Y-%m-%d %H:%M:%S UTC',time.gmtime()),'timeout_seconds':1800,'notes':'Unmodified workload sources; private harness overlays final production loader/manifest. Existing full desktop image, frozen final isolated kernel and new static desktop with verified final libc.a.'}
(state/'run.json').write_text(json.dumps(manifest,indent=2)+'\n')
with (state/'driver.log').open('wb') as log:
    p=subprocess.Popen(command,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    (state/'runner.pid').write_text(str(p.pid)+'\n');result=p.wait()
manifest.update(runner_exit_code=result,end_time_utc=time.strftime('%Y-%m-%d %H:%M:%S UTC',time.gmtime()))
log=(state/'driver.log').read_bytes()
match=re.search(rb'==> Serial log: (.+)',log)
if match:
    path=Path(match.group(1).decode().strip());shutil.copy2(path,state/'serial.log');manifest['serial_sha256']=sha(state/'serial.log');manifest['guest_temp_state']=str(path.parent)
else:manifest['serial_capture_error']='Guest transcript path was not reported; inspect driver.log.'
(state/'run.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2),flush=True)
raise SystemExit(result)
