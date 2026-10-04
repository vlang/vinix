from pathlib import Path
import subprocess,sys
state=Path('/Users/alex/code/vinix/build/useralloc-arm-v6-final');base=Path('/Users/alex/code/vinix/third_party/useralloc-libc/build/useralloc')
subprocess.run([sys.executable,str(state/'prepare.py')],check=True)
subprocess.run([sys.executable,str(state/'run.py')],check=True)
subprocess.run([sys.executable,str(base/'collect-v6-verification.py'),'aarch64'],check=True)
