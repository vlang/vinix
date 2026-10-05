#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compare the freestanding V init policies against independent syscall traces."""
from pathlib import Path
import argparse
import os
import re
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
INIT=ROOT/'build-support/init-aarch64'
def run(command): subprocess.run([str(item) for item in command],check=True)
def reference(source,kind,output):
    text=source.read_text()
    wrappers=[]
    for match in re.finditer(r'static inline i64 syscall([1-5])\([^\n]+\) \{.*?\n\}',text,re.S):
        count=int(match[1])
        args=['u64 nr']+['u64 a'+str(i) for i in range(count)]
        values=['nr']+['a'+str(i) if i<count else '0' for i in range(5)]
        wrappers.append('static inline i64 syscall'+str(count)+'('+','.join(args)+') { return vinit_syscall('+','.join(values)+'); }\n')
    text=re.sub(r'static inline i64 syscall[1-5]\([^\n]+\) \{.*?\n\}', '', text,flags=re.S)
    text=re.sub(r'__attribute__\(\(naked\)\) static void signal_restorer\(void\) \{.*?\n\}', 'static void signal_restorer(void) {}',text,flags=re.S)
    text=text.replace('void _start(void)', 'void vinix_init_'+kind+'(void)')
    if kind=='desktop':
        text=text.replace('static volatile int requested_power_signal','volatile int vinit_power').replace('static volatile int requested_desktop_reload','volatile int vinit_reload')
        text=re.sub(r'\brequested_power_signal\b','vinit_power',text)
        text=re.sub(r'\brequested_desktop_reload\b','vinit_reload',text)
        text=text.replace('static void power_signal_handler','void vinix_init_power_signal').replace('static void child_signal_handler','void vinix_init_child_signal')
        text=text.replace('power_signal_handler','vinix_init_power_signal').replace('child_signal_handler','vinix_init_child_signal')
    # Keep the algorithm source intact; replace only native register boundaries.
    typedef_end=text.index('typedef long i64;')+len('typedef long i64;')
    text=text[:typedef_end]+'\nextern i64 vinit_syscall(u64,u64,u64,u64,u64,u64);\n'+''.join(wrappers)+text[typedef_end:]
    if kind=='desktop':
        text+='''
#include <stdbool.h>
void initcore__prepare_desktop_boot(void) { prepare_desktop_boot(); }
void initcore__prepare_hosted_x11_storage(void) { prepare_hosted_x11_storage(); }
void initcore__install_power_signals(void) { install_power_signals(); install_child_signal(); }
void initcore__apply_power_request(void) { apply_power_request(); }
void initcore__pause_for(struct kernel_timespec delay) { pause_for(delay); }
void initcore__wait_for_child(i64 child,int *status) { wait_for_child(child,status); }
void initcore__stop_desktop_group(i64 child) { stop_desktop_group(child); }
i64 initcore__spawn_program(char **args,char **fallback,bool group,int *status,char **env,bool trace) { return spawn_program(args,fallback,group,status,env,trace); }
'''
    output.write_text(text)
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference-dir',type=Path,help='optional directory containing the original three C implementations')
    args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='vinix-init-fixture-') as directory:
        work=Path(directory)
        generated=work/'init.c'
        run(['python3',INIT/'compile-v.py','desktop',generated,'--host'])
        common=['clang','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-fno-builtin','-Wno-incompatible-pointer-types','-Wno-incompatible-library-redeclaration']
        for echo in (False,True):
            defines=['-DVINIX_INIT_HOST_TEST']+(['-DVINIX_BUSYBOX_ECHO_TEST'] if echo else [])
            executable=work/('echo-test' if echo else 'test')
            run(common+defines+['-I'+str(INIT),generated,HERE/'test.c','-o',executable])
            run([executable]+(['echo'] if echo else []))
            if args.reference_dir:
                originals=[]
                for kind,name in [('desktop','desktop-init.c'),('shell','init.c'),('full','full-init.c')]:
                    out=work/('reference-'+kind+'.c'); reference(args.reference_dir/name,kind,out);originals.append(out)
                reference_exe=work/('reference-echo-test' if echo else 'reference-test')
                run(common+defines+originals+[HERE/'test.c','-o',reference_exe])
                run([reference_exe]+(['echo'] if echo else []))
        for tool in ('shell','full','desktop'):
            source=work/(tool+'.c'); obj=work/(tool+'.o'); elf=work/tool
            run(['python3',INIT/'compile-v.py',tool,source])
            run(['clang','--target=aarch64-linux-none','-nostdlib','-ffreestanding','-O2','-fno-stack-protector','-fno-builtin','-ffunction-sections','-fdata-sections','-I'+str(INIT),'-c',source,'-o',obj])
            linker=os.environ.get('LD_AARCH64','/opt/homebrew/bin/ld.lld' if Path('/opt/homebrew/bin/ld.lld').exists() else 'ld.lld')
            run([linker,'-m','aarch64elf','--nostdlib','-static','--gc-sections','-o',elf,obj])
            undefined=subprocess.check_output(['nm','-u',obj],text=True)
            assert not undefined.strip(),undefined
            text=source.read_text()
            assert not re.search(r'\b(?:memdup|new_array\w*|malloc|realloc|calloc)\s*\(',text)
            for record in ('initcore__SignalAction action =','initcore__Delay delay =','char buffer[256]'):
                assert record in text,record
    print('INIT POLICY HOST/ARM LINK TEST: PASS')
if __name__=='__main__': main()
