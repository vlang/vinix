#!/usr/bin/env python3
"""Run unchanged original-C XTEST event traces through native V guest callers."""
from pathlib import Path
import argparse
import os
import subprocess
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--arch',choices=('aarch64','x86_64'),required=True)
p.add_argument('--kernel-dir',type=Path,required=True)
p.add_argument('--state-dir',type=Path,required=True)
p.add_argument('--timeout',type=int,default=3600)
a=p.parse_args();a.state_dir.mkdir(parents=True,exist_ok=False)
core=a.state_dir/'core.c'
subprocess.run(['python3',str(ROOT/'build-support/xorg-server/compile-v-host.py'),'xinputcore',str(core),'--arch','arm64' if a.arch=='aarch64' else 'amd64'],check=True)
# Include only portable X11 declarations; native POSIX headers come from the
# selected musl toolchain. The production ABI shim and independent Cfixture
# share the syscall mock names, while guest process control uses real syscalls.
(a.state_dir/'X11').symlink_to(ROOT/'build-aarch64-x11/sysroot/usr/include/X11',target_is_directory=True)
source=a.state_dir/'guest.c'
macros=('sigaction','open','close','read','tcgetattr','tcsetattr','nanosleep')
text=''.join('#define '+name+' vxi_test_'+name+'\n' for name in macros)
text += '#define main xinput_bridge_main\n#include "'+str(core.resolve())+'"\n#undef main\n#define main xinput_fixture_main\n#include "'+str(ROOT/'tests/x11-input/fixture.c')+'"\n#undef main\n'
text += ''.join('#undef '+name+'\n' for name in macros)
text += '#include "'+str(ROOT/'tests/x11-input/guest.c')+'"\n'
source.write_text(text)
# The harness compiles one independent caller as PID1 and redirects its serial
# verdicts. Its selected include path also supplies the narrow generated ABI.
env={**os.environ}
compiler='CC' if a.arch=='aarch64' else 'CC_AMD64'
original=env.get(compiler,'clang' if a.arch=='aarch64' else 'x86_64-linux-musl-gcc')
wrapper=a.state_dir/'cc.py'
wrapper.write_text('#!/usr/bin/env python3\nimport os,sys\nos.execv('+repr(str(Path(__import__('shutil').which(original) or original).resolve()))+',['+repr(original)+',"-std=gnu11","-Wno-unused-function","-Wno-unused-label","-I'+str(ROOT/'build-support/xorg-server')+'","-I'+str(a.state_dir)+'",*sys.argv[1:],"-Wno-unused-parameter"])\n')
wrapper.chmod(0o755);env[compiler]=str(wrapper.resolve())
subprocess.run(['python3',str(ROOT/'tests/kernel-gaps/run.py'),'--source',str(source),'--arch',a.arch,'--kernel-dir',str(a.kernel_dir),'--state-dir',str(a.state_dir/'guest'),'--expect','X11 INPUT GUEST PASS','--timeout',str(a.timeout)],check=True,env=env)
