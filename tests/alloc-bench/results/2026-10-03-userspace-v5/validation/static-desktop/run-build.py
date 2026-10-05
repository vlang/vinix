#!/usr/bin/env python3
import hashlib,json,os,subprocess,shutil
from pathlib import Path
root=Path('/Users/alex/code/vinix')
state=root/'build/useralloc-pipe/static-desktop-v5'
private=root/'third_party/useralloc-pipe'
env=os.environ.copy()
env.update(V=str(root/'build/useralloc-final-audit/compiler/v'),VINIX_AARCH64_SYSROOT=str(state/'sysroot'),VINIX_AARCH64_APP_CACHE=str(state/'app-cache'),VINIX_MUSL_BUILD_DIR=str(state/'musl-cache'),VINIX_MUSL_CC_AARCH64='/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/aarch64-linux-musl-gcc',VINIX_UI2_SOURCE=str(state/'ui2'),LLVM_BIN=str(state/'llvm-bin'))
command=['/bin/bash','-x',str(private/'scripts/build-desktop-aarch64.sh'),'--no-initramfs']
with (state/'build.log').open('wb') as log:
    process=subprocess.Popen(command,cwd=private,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    (state/'build.pid').write_text(str(process.pid)+'\n')
    result=process.wait()
manifest=json.loads((state/'preparation.json').read_text())
manifest.update(command=command,environment={k:v for k,v in env.items() if k in ('V','VINIX_AARCH64_SYSROOT','VINIX_AARCH64_APP_CACHE','VINIX_MUSL_BUILD_DIR','VINIX_MUSL_CC_AARCH64','VINIX_UI2_SOURCE','LLVM_BIN')},build_exit_code=result)
output=private/'build/vinix-desktop'
if result==0:
    archive=state/'sysroot/usr/lib/libc.a'
    assert hashlib.sha256(archive.read_bytes()).hexdigest()==manifest['static_libc_sha256']
    assert (state/'linked-libc.sha256').read_text().strip()==manifest['static_libc_sha256']
    assert 'malloc_trim' in (state/'linked-symbols.txt').read_text()
    shutil.copy2(output,state/'vinix-desktop')
    manifest['desktop_sha256']=hashlib.sha256(output.read_bytes()).hexdigest()
    manifest['link_map_sha256']=hashlib.sha256((state/'link.map').read_bytes()).hexdigest()
    manifest['linked_symbol_checks']=['malloc_trim exists in final linked binary; final libc.a hash matched before and after production hook']
(state/'build.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2),flush=True)
raise SystemExit(result)
