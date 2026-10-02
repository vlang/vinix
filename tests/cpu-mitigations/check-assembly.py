#!/usr/bin/env python3
"""Execute production x86 macros/thunks under Rosetta with privileged adapters."""
from pathlib import Path
import re
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[2]

C = r'''
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
struct policy { uint64_t kernel, user, flags, reserved; };
struct policy policies[2];
struct policy *vinix_x86_mitigation_policies = policies;
uint64_t host_cpu_number, host_spec_value, host_spec_writes, host_ibpb, host_clears;
uint64_t host_registers[15];
void host_enter(void), host_leave(void), host_switch(unsigned), host_rsb(void);
void host_probe(unsigned);
void host_resume_probe(uint64_t *, unsigned);
int main(void) {
    for (unsigned mask = 0; mask < 512; mask++) {
        for (unsigned cpu = 0; cpu < 2; cpu++) {
            policies[0] = (struct policy){0x1234567800000007, 0x1234567800000006, mask, 0};
            policies[1] = (struct policy){0x8765432100000007, 0x8765432100000006, mask, 0};
            struct policy original[2] = {policies[0],policies[1]};
            host_cpu_number = cpu;
            host_spec_value = host_spec_writes = host_ibpb = host_clears = 0;
            host_enter();
            assert(host_spec_writes == ((mask & 2) ? 1u : 0u));
            if (mask & 2) assert(host_spec_value == original[cpu].kernel);
            host_leave();
            assert(host_spec_writes == ((mask & 2) ? 2u : 0u));
            if (mask & 2) assert(host_spec_value == original[cpu].user);
            assert(host_ibpb == ((mask & 256) ? 1u : 0u));
            assert(host_clears == ((mask & 8) ? 1u : 0u));
            assert(policies[cpu].flags == (mask & ~256u));
            assert(policies[cpu ^ 1].flags == mask);
            host_leave();
            assert(host_ibpb == ((mask & 256) ? 1u : 0u));
            host_switch(cpu);
            assert(policies[cpu].flags == ((mask & ~256u) | ((mask & 1) ? 256 : 0)));
            host_leave();
            assert(host_ibpb == ((mask & 256) ? 1u : 0u) + ((mask & 1) ? 1u : 0u));
            assert(policies[cpu ^ 1].flags == mask);
        }
    }
    host_rsb();
    uint64_t storage[64] = {0}, *frame = storage + 32;
    for (unsigned user = 0; user < 2; user++) {
        for (unsigned i = 0; i < 32; i++) storage[i] = UINT64_C(0xfeedface12345678);
        for (unsigned i = 0; i < 23; i++) frame[i] = 0x12345678u+i;
        frame[19] = user ? 0x43 : 0x28; /* GPRState.CS. */
        frame[17] = 0xabcdef; /* An exception error is not a clear capability. */
        policies[1] = (struct policy){7,6,1|2|8,0};
        host_spec_writes = host_ibpb = host_clears = 0;
        host_resume_probe(frame,1);
        for (unsigned i = 0; i < 32; i++) assert(storage[i] == UINT64_C(0xfeedface12345678));
        for (unsigned i = 0; i < 15; i++) {
            const unsigned offsets[] = {2,3,4,5,6,7,8,9,10,11,12,13,14,15,16};
            assert(host_registers[i] == 0x12345678u+offsets[i]);
        }
        assert(frame[17] == (user ? 8u : 0u));
        assert(host_spec_writes == user && host_ibpb == user && host_clears == user);
        assert(policies[1].flags == (user ? (1|2|8) : (1|2|8|256)));
    }
    for (unsigned reg = 0; reg < 15; reg++) {
        host_probe(reg);
        for (unsigned i = 0; i < 15; i++) {
            /* The target register is the only modified GPR; the thunk must
             * preserve every other register, including syscall arguments. */
            if (i != reg) assert(host_registers[i] == 0x12345678u + i);
        }
    }
    puts("CPU MITIGATION ASSEMBLY PASS: 1024 per-CPU flag cases, pending barrier consumption, MSR halves, 15 thunks, RSB stack balance, actual scheduler epilogue and no writes below its saved frame");
}
'''

PORTS = r'''
.global _host_wrmsr_adapter
_host_wrmsr_adapter:
    pushfq
    cmpl $0x48, %ecx
    jne 1f
    movl %eax, _host_spec_value(%rip)
    movl %edx, _host_spec_value+4(%rip)
    incq _host_spec_writes(%rip)
    jmp 2f
1:
    cmpl $0x49, %ecx
    jne 3f
    incq _host_ibpb(%rip)
2:
    popfq
    ret
3:
    ud2
.global _host_clear_adapter
_host_clear_adapter:
    pushfq
    incq _host_clears(%rip)
    popfq
    ret
.global _host_enter
_host_enter:
    VINIX_SPEC_ENTER
    ret
.global _host_leave
_host_leave:
    sub $128, %rsp
    VINIX_SPEC_RETURN gs0, 120
    add $120, %rsp
    VINIX_SPEC_CLEAR
    add $8, %rsp
    ret
.global _host_switch
_host_switch:
    mov %rdi, %rsi
    VINIX_SPEC_SWITCH rsi
    ret
.global _host_rsb
_host_rsb:
    mov %rsp, %r8
    mov $0x76543210, %r9
    push %r9
    VINIX_RSB_FILL
    pop %r10
    cmp %r9, %r10
    jne 1f
    cmp %r8, %rsp
    jne 1f
    ret
1:
    ud2
'''


def main():
    header = (ROOT / 'kernel/asm/x86_64/speculation.h').read_text()
    if header.count('mov %gs:0, %rax') != 1 or header.count('wrmsr') != 3 or header.count('verw ') != 1:
        raise RuntimeError('hardware adapters require reinspection')
    header = header.replace('mov %gs:0, %rax', 'mov _host_cpu_number(%rip), %rax')
    header = header.replace('    wrmsr', '    call _host_wrmsr_adapter')
    header = header.replace('    verw vinix_x86_verw_selector(%rip)', '    call _host_clear_adapter')
    source = (ROOT / 'kernel/asm/x86_64/speculation.S').read_text()
    start = source.index('.macro RETPOLINE')
    end = source.index('/* Noreturn')
    thunks = source[start:end]
    thunks = re.sub(r'(?m)^\.type .*\n|^\.size .*\n', '', thunks)
    thunks = thunks.replace('__x86_indirect_thunk_', '___x86_indirect_thunk_')
    header = header.replace('vinix_x86_mitigation_policies', '_vinix_x86_mitigation_policies')
    regs = ['rax','rbx','rcx','rdx','rsi','rdi','rbp','r8','r9','r10','r11','r12','r13','r14','r15']
    probes = ['.global _host_probe', '_host_probe:', 'push %rbx', 'push %rbp',
              'push %r12', 'push %r13', 'push %r14', 'push %r15', 'push %rdi']
    for index in range(len(regs)):
        probes += [f'cmp ${index}, %rdi', f'je Lcase{index}']
    probes += ['ud2']
    for index, target in enumerate(regs):
        probes += [f'Lcase{index}:']
        probes += [f'mov ${0x12345678+i}, %{reg}' for i, reg in enumerate(regs)]
        probes += [f'lea Ltarget(%rip), %{target}', f'call ___x86_indirect_thunk_{target}', 'jmp Ldone']
    probes += ['Ltarget:']
    probes += [f'mov %{reg}, _host_registers+{i*8}(%rip)' for i, reg in enumerate(regs)]
    probes += ['ret', 'Ldone:', 'pop %rdi', 'pop %r15', 'pop %r14', 'pop %r13',
               'pop %r12', 'pop %rbp', 'pop %rbx', 'ret']
    resume = source[source.index('.global vinix_x86_resume_context'):source.index('.size vinix_x86_resume_context')]
    if resume.count('    mov %eax, %ds') != 1 or resume.count('    mov %eax, %es') != 1 or resume.count('    swapgs') != 1 or resume.count('    iretq') != 1:
        raise RuntimeError('scheduler port adapters require reinspection')
    resume = resume.replace('vinix_x86_resume_context','_vinix_x86_resume_context')
    resume = re.sub(r'(?m)^\.type .*\n','',resume)
    resume = resume.replace('    mov %eax, %ds','    nop').replace('    mov %eax, %es','    nop')
    resume = resume.replace('    swapgs','    nop').replace('    iretq','    jmp _host_resume_finish')
    finish = ['.global _host_resume_probe','_host_resume_probe:', 'push %rbx','push %rbp',
              'push %r12','push %r13','push %r14','push %r15',
              'mov %rsp, _host_resume_sp(%rip)','jmp _vinix_x86_resume_context',
              '_host_resume_finish:']
    finish += [f'mov %{reg}, _host_registers+{i*8}(%rip)' for i,reg in enumerate(regs)]
    finish += ['mov _host_resume_sp(%rip), %rsp','pop %r15','pop %r14','pop %r13','pop %r12','pop %rbp','pop %rbx','ret']
    with tempfile.TemporaryDirectory(prefix='vinix-cpu-assembly-') as directory:
        work = Path(directory)
        globals_ = ['vinix_x86_mitigation_policies','host_cpu_number','host_spec_value',
                    'host_spec_writes','host_ibpb','host_clears','host_registers','host_resume_sp']
        data = '\n.align 8\n' + ''.join(f'.global _{name}\n_{name}:\n.zero {120 if name == "host_registers" else 8}\n' for name in globals_)
        (work / 'test.S').write_text('.text\n' + header + thunks + PORTS + '\n'.join(probes) + '\n' + resume + '\n'.join(finish) + data)
        subprocess.run(['clang','--target=x86_64-unknown-none','-c',str(work / 'test.S'),'-o',str(work / 'test.o')], check=True)
        subprocess.run(['ld.lld','-m','elf_x86_64','-Ttext=0','--image-base=0','--entry=_host_enter',str(work / 'test.o'),'-o',str(work / 'test.elf')], check=True)
        llvm = Path('/opt/homebrew/opt/llvm/bin')
        subprocess.run([str(llvm / 'llvm-objcopy'),'-O','binary','--only-section=.text',str(work / 'test.elf'),str(work / 'test.bin')], check=True)
        symbols = {}
        listing = subprocess.check_output([str(llvm / 'llvm-nm'),str(work / 'test.elf')],text=True)
        for line in listing.splitlines():
            fields = line.split()
            if len(fields) == 3: symbols[fields[2]] = int(fields[0],16)
        data_ = (work / 'test.bin').read_bytes()
        prefix = '#include <sys/mman.h>\n#include <string.h>\nstatic unsigned char *blob;\n'
        prefix += 'static const unsigned char code[]={' + ','.join(map(str,data_)) + '};\n'
        for name in globals_:
            type_ = 'struct policy *' if name == 'vinix_x86_mitigation_policies' else 'uint64_t'
            if name == 'host_registers':
                prefix += f'#define {name} ((uint64_t *)(blob+{symbols["_"+name]}))\n'
            else:
                prefix += f'#define {name} (*({type_} *)(blob+{symbols["_"+name]}))\n'
        for name in ['host_enter','host_leave','host_switch','host_rsb','host_probe','host_resume_probe']:
            arg = 'uint64_t *, unsigned' if name == 'host_resume_probe' else ('unsigned' if name in ['host_switch','host_probe'] else 'void')
            prefix += f'#define {name} ((void (*)({arg}))(blob+{symbols["_"+name]}))\n'
        code = C.replace('struct policy *vinix_x86_mitigation_policies = policies;','')
        code = re.sub(r'(?m)^uint64_t host_.*;\n|^void host_.*;\n','',code)
        code = code.replace('int main(void) {',prefix + 'int main(void) {\n'
            'blob=mmap(NULL,sizeof(code),PROT_READ|PROT_WRITE|PROT_EXEC,MAP_PRIVATE|MAP_ANON,-1,0);\n'
            'assert(blob!=MAP_FAILED); memcpy(blob,code,sizeof(code));\n'
            'vinix_x86_mitigation_policies=policies;\n')
        (work / 'test.c').write_text(code)
        subprocess.run(['clang','-target','x86_64-apple-darwin','-O1','-g','-Wall','-Wextra','-Werror',
                        '-fsanitize=address,undefined',str(work / 'test.c'),'-o',str(work / 'test')],check=True)
        subprocess.run(['arch','-x86_64',str(work / 'test')],check=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
