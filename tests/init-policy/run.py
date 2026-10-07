#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compare the freestanding V init policies against independent syscall traces."""
from pathlib import Path
import argparse
import os
import platform
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
def fixture(output,arch):
    run(['python3',ROOT/'build-support/compile-v-module.py',HERE/'hostfixture',output,
         '--arch',arch,'-d','nofloat'])
def validate(work,args):
    generated=work/'init.c'
    source=args.reference_fixture
    if source is None:
        source=work/'fixture.c'; fixture(source,args.arch)
    host_arch=(['-arch', 'arm64' if args.arch=='arm64' else 'x86_64']
               if platform.system()=='Darwin' else [])
    common=['clang']+host_arch+['-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-fno-builtin','-Wno-incompatible-pointer-types','-Wno-incompatible-library-redeclaration']
    fixture_obj=work/'fixture.o'
    strict=['clang']+host_arch+['-std=gnu11','-Wall','-Wextra','-Werror','-fno-builtin',
        '-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer']
    if args.reference_fixture is None:
        strict+=['-Wno-unused-function','-Wno-unused-parameter','-I'+str(HERE/'hostfixture')]
    run(strict+['-c',source,'-o',fixture_obj])
    for echo in (False,True):
        run(['python3',INIT/'compile-v.py','desktop',generated,'--host']+
            (['--busybox-echo-test'] if echo else []))
        defines=['-DVINIX_INIT_HOST_TEST']+(['-DVINIX_BUSYBOX_ECHO_TEST'] if echo else [])
        executable=work/('echo-test' if echo else 'test')
        run(common+defines+['-I'+str(INIT),generated,fixture_obj,'-o',executable])
        run([executable]+(['echo'] if echo else []))
        if args.reference_dir:
            originals=[]
            for kind,name in [('desktop','desktop-init.c'),('shell','init.c'),('full','full-init.c')]:
                out=work/('reference-'+kind+'.c'); reference(args.reference_dir/name,kind,out);originals.append(out)
            reference_exe=work/('reference-echo-test' if echo else 'reference-test')
            run(common+defines+originals+[fixture_obj,'-o',reference_exe])
            run([reference_exe]+(['echo'] if echo else []))
    for tool in ('shell','full','desktop'):
        source=work/(tool+'.c'); obj=work/(tool+'.o'); elf=work/tool
        abi=work/(tool+'-abi.o')
        run(['python3',INIT/'compile-v.py',tool,source])
        run(['clang','--target=aarch64-linux-none','-nostdlib','-ffreestanding','-O2','-fno-stack-protector','-fno-builtin','-ffunction-sections','-fdata-sections','-I'+str(INIT),'-c',source,'-o',obj])
        linker=os.environ.get('LD_AARCH64','/opt/homebrew/bin/ld.lld' if Path('/opt/homebrew/bin/ld.lld').exists() else 'ld.lld')
        run(['clang','--target=aarch64-linux-none','-c',INIT/'syscall_abi.S','-o',abi])
        run([linker,'-m','aarch64elf','--nostdlib','-static','--gc-sections','-o',elf,obj,abi])
        undefined=subprocess.check_output(['nm','-u',elf],text=True)
        assert not undefined.strip(),undefined
        text=source.read_text()
        assert not re.search(r'\b(?:memdup|new_array\w*|malloc|realloc|calloc)\s*\(',text)
        for record in ('initcore__SignalAction action =','initcore__Delay delay =','char buffer[256]'):
            assert record in text,record
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference-dir',type=Path,help='optional directory containing the original three C implementations')
    parser.add_argument('--reference-fixture',type=Path,help='untouched original C fixture for independent controls')
    parser.add_argument('--arch',choices=('arm64','amd64'),default='arm64' if platform.machine() in ('arm64','aarch64') else 'amd64')
    parser.add_argument('--work-dir',type=Path,help='retain generated sources and host executables in a fresh directory')
    args=parser.parse_args()
    if args.work_dir:
        args.work_dir.mkdir(parents=True,exist_ok=False); validate(args.work_dir,args)
    else:
        with tempfile.TemporaryDirectory(prefix='vinix-init-fixture-') as directory:
            validate(Path(directory),args)
    print('INIT POLICY HOST/ARM LINK TEST: PASS')
if __name__=='__main__': main()
