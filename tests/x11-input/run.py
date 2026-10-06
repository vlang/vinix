#!/usr/bin/env python3
"""Verify production V XTEST event traces against frozen original C traces."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline',type=Path,help='original C source, for migration comparison only')
args=parser.parse_args()
include=Path(os.environ.get('VINIX_X11_INCLUDE',str(ROOT/'build-aarch64-x11/sysroot/usr/include')))
if not (include/'X11/Xlib.h').exists(): include=ROOT/'build-aarch64-x11/staging/usr/include'
flags=['clang','-std=gnu11','-O2','-g','-Wall','-Wextra','-Werror','-Wno-unused-function','-Wno-unused-parameter','-ffreestanding','-fno-builtin','-fsanitize=address,undefined','-fno-omit-frame-pointer','-idirafter',str(include),'-I'+str(ROOT/'build-support/xorg-server')]
mocks=['sigaction','open','close','read','tcgetattr','tcsetattr','nanosleep']
flags += ['-D'+name+'=vxi_test_'+name for name in mocks]
with tempfile.TemporaryDirectory(prefix='vinix-xinput-test-') as directory:
    work=Path(directory)
    generated=work/'core.c'; obj=work/'core.o'
    subprocess.run(['python3',str(ROOT/'build-support/xorg-server/compile-v-host.py'),'xinputcore',str(generated)],check=True)
    subprocess.run([*flags,'-Dmain=xinput_bridge_main','-c',str(generated),'-o',str(obj)],check=True)
    symbols=subprocess.check_output(['nm','-u',str(obj)],text=True)
    assert not re.search(r'\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b',symbols),symbols
    program=work/'test'
    subprocess.run([*flags,str(obj),str(ROOT/'tests/x11-input/fixture.c'),'-o',str(program)],check=True)
    expected=json.loads((ROOT/'tests/x11-input/traces.json').read_text()) if not args.baseline else {}
    if args.baseline:
        old=work/'original.o'; baseline=work/'baseline'
        subprocess.run([*flags,'-Dmain=xinput_bridge_main','-c',str(args.baseline),'-o',str(old)],check=True)
        subprocess.run([*flags,str(old),str(ROOT/'tests/x11-input/fixture.c'),'-o',str(baseline)],check=True)
    for scenario in range(6):
        result=subprocess.run([str(program),str(scenario)],check=True,capture_output=True)
        trace=result.stdout+result.stderr
        digest=hashlib.sha256(trace).hexdigest()
        if args.baseline:
            before=subprocess.run([str(baseline),str(scenario)],check=True,capture_output=True)
            assert before.stdout==result.stdout and before.stderr==result.stderr,(scenario, "original C and V traces differ")
            expected[str(scenario)]=digest
            fnv=14695981039346656037
            for byte in before.stdout: fnv=((fnv ^ byte)*1099511628211)&((1<<64)-1)
            expected['stdout_fnv_'+str(scenario)]=fnv
        assert expected[str(scenario)]==digest,(scenario,expected[str(scenario)],digest)
    if args.baseline:
        (ROOT/'tests/x11-input/traces.json').write_text(json.dumps(expected,indent=2)+'\n')
        values=', '.join(str(expected['stdout_fnv_'+str(i)])+'ull' for i in range(6))
        (ROOT/'tests/x11-input/expected.h').write_text('/* Original C fixture stdout traces, FNV-1a; see run.py --baseline. */\nstatic const uint64_t expected_traces[6] = {'+values+'};\n')
print('X11 input: six original C event traces passed under ASan/UBSan; no V allocator imports')
