from pathlib import Path
import subprocess,sys
base=Path('/Users/alex/code/vinix/third_party/useralloc-libc/build/useralloc')
subprocess.run([sys.executable,str(base/'verify-x86-v6-final.py'),'prepare'],check=True)
subprocess.run([sys.executable,str(base/'verify-x86-v6-final.py'),'run','/Users/alex/code/vinix/build/useralloc-kernel-speed-v5/x86_64/vinix-x86_64'],check=True)
subprocess.run([sys.executable,str(base/'collect-v6-verification.py'),'x86_64'],check=True)
