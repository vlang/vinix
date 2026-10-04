from pathlib import Path
import subprocess,json,hashlib,shutil,os
root=Path('/Users/alex/code/vinix');state=root/'build/useralloc-allocation-audit-final';work=root/'third_party/useralloc-pipe';v=root/'build/useralloc-final-audit/compiler/v';src=state/'x86-diagnostic-source';src.mkdir(exist_ok=True)
make=subprocess.run(['make','-Bn','obj/blob.c.o','ARCH=x86_64','V='+str(v),'PROD=false'],cwd=work/'kernel',text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True);(state/'x86-diagnostic.make').write_text(make.stdout)
line=next(line for line in make.stdout.splitlines() if line.startswith('for f in '));paths=line[len('for f in '):].split(';',1)[0].split()
for name in paths:
 target=src/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(work/'kernel'/name,target)
shutil.copy2(work/'kernel/v.mod',src/'v.mod')
command=[str(v),'-os','vinix','-enable-globals','-nofloat','-manualfree','-message-limit','100000','-gc','none','-target-libc-headers','-no-closures','-d','no_backtrace','-arch','amd64','-warn-about-allocs','-o',str(state/'x86-diagnostic.c'),str(src)]
with (state/'x86-diagnostic.log').open('wb') as log: result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
(state/'x86-diagnostic.json').write_text(json.dumps({'command':command,'exit_code':result.returncode,'compiler_sha256':hashlib.sha256(v.read_bytes()).hexdigest(),'source_count':len(paths),'log_sha256':hashlib.sha256((state/'x86-diagnostic.log').read_bytes()).hexdigest(),'note':'Exact required audit V command and final source; complete diagnostics retained because normal script filters and removes these.'},indent=2)+'\n');print('exit',result.returncode,flush=True)
