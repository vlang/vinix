#!/usr/bin/env python3
"""Reject raw indirect calls/jumps in the final x86 production executable."""
from pathlib import Path
import argparse
import re
import subprocess
parser = argparse.ArgumentParser()
parser.add_argument('kernel',type=Path)
parser.add_argument('--objdump',default='/opt/homebrew/opt/llvm/bin/llvm-objdump')
args = parser.parse_args()
listing = subprocess.check_output([args.objdump,'-d','--no-show-raw-insn',str(args.kernel)],text=True)
if 'file format elf64-x86-64' not in listing:
    raise SystemExit('FAIL: expected an x86-64 production ELF')
raw = re.findall(r'(?m)^.*\b(?:callq?|jmpq?)\s+\*.*$',listing)
if raw:
    raise SystemExit('FAIL: raw indirect branches:\n' + '\n'.join(raw[:20]))
for register in ['rax','rbx','rcx','rdx','rsi','rdi','rbp','r8','r9','r10','r11','r12','r13','r14','r15']:
    if f'<__x86_indirect_thunk_{register}>:' not in listing:
        # Section collection can discard compiler-unused register thunks.
        if re.search(r'<__x86_indirect_thunk_'+register+r'(?:[+>])',listing):
            raise SystemExit(f'FAIL: unresolved thunk {register}')
if '<vinix_x86_resume_context>:' not in listing:
    raise SystemExit('FAIL: missing final scheduler mitigation stub')
calls = len(re.findall(r'\b(?:callq?|jmpq?)\s+[^\n]*<__x86_indirect_thunk_',listing))
if calls < 100:
    raise SystemExit('FAIL: compiler mitigation appears absent')
print(f'CPU MITIGATION LINKED PASS: {calls} thunk branches, no raw indirect CALL/JMP')
