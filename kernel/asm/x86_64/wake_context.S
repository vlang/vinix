// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What a processor is, kept across a suspend to RAM.
//
// x86_wake_save() writes down everything the processor holds that a C
// function does not expect to lose across a call and that is not somewhere in
// memory already: the callee-saved registers and the stack pointer, the
// control registers, where the descriptor tables are and which entries of
// them are loaded. It returns 0. The kernel then asks firmware to sleep, and
// when the machine comes back the trampoline (wake_trampoline.S) ends in
// x86_wake_resume() with the same record, which puts it all back and returns
// from x86_wake_save() a second time, with 1: the sleep appears to its caller
// as one call that returned twice, as setjmp() does.
//
// The record is x86.wake's Context (x86/wake/context.v), and the offsets here
// are that structure's.

#define CTX_RBX     0
#define CTX_RBP     8
#define CTX_R12     16
#define CTX_R13     24
#define CTX_R14     32
#define CTX_R15     40
#define CTX_RSP     48
#define CTX_RFLAGS  56
#define CTX_CR0     64
#define CTX_CR2     72
#define CTX_CR3     80
#define CTX_CR4     88
#define CTX_GDT     96
#define CTX_IDT     112
#define CTX_TR      128
#define CTX_LDT     130
#define CTX_DS      132
#define CTX_ES      134
#define CTX_FS      136
#define CTX_GS      138
#define CTX_SS      140
#define CTX_CS      142
#define CTX_RIP     144
#define CTX_MSRS    152
#define CTX_MSR     160

.section .text

// u64 x86_wake_save(Context *context)
.global x86_wake_save
.type x86_wake_save, @function
x86_wake_save:
    movq %rbx, CTX_RBX(%rdi)
    movq %rbp, CTX_RBP(%rdi)
    movq %r12, CTX_R12(%rdi)
    movq %r13, CTX_R13(%rdi)
    movq %r14, CTX_R14(%rdi)
    movq %r15, CTX_R15(%rdi)
    // Where this call returns to and the stack as it will be once it has:
    // the return address itself is not left on the stack to be found again,
    // as the next call the caller makes puts its own in the same place.
    movq (%rsp), %rax
    movq %rax, CTX_RIP(%rdi)
    leaq 8(%rsp), %rax
    movq %rax, CTX_RSP(%rdi)
    pushfq
    popq CTX_RFLAGS(%rdi)
    movq %cr0, %rax
    movq %rax, CTX_CR0(%rdi)
    movq %cr2, %rax
    movq %rax, CTX_CR2(%rdi)
    movq %cr3, %rax
    movq %rax, CTX_CR3(%rdi)
    movq %cr4, %rax
    movq %rax, CTX_CR4(%rdi)
    sgdt CTX_GDT(%rdi)
    sidt CTX_IDT(%rdi)
    str CTX_TR(%rdi)
    sldt CTX_LDT(%rdi)
    movw %ds, CTX_DS(%rdi)
    movw %es, CTX_ES(%rdi)
    movw %fs, CTX_FS(%rdi)
    movw %gs, CTX_GS(%rdi)
    movw %ss, CTX_SS(%rdi)
    movw %cs, CTX_CS(%rdi)
    xorl %eax, %eax
    ret
.size x86_wake_save, .-x86_wake_save

// void x86_wake_resume(Context *context)
//
// Entered from the trampoline: long mode, the trampoline's page table and
// GDT, no interrupt table, no stack, interrupts off.
.global x86_wake_resume
.type x86_wake_resume, @function
x86_wake_resume:
    // The rest of CR4 before CR3: a CR3 that names a process context needs
    // CR4.PCIDE, which may only be set while CR3 names none -- as the
    // trampoline's does not.
    movq CTX_CR4(%rdi), %rax
    movq %rax, %cr4
    movq CTX_CR3(%rdi), %rax
    movq %rax, %cr3
    movq CTX_CR0(%rdi), %rax
    movq %rax, %cr0
    movq CTX_CR2(%rdi), %rax
    movq %rax, %cr2

    lgdt CTX_GDT(%rdi)
    lidt CTX_IDT(%rdi)
    movq CTX_RSP(%rdi), %rsp

    // The code segment is loaded by a far return. What is pushed here and
    // further down lands below the saved stack pointer, in frames that ended
    // when the machine went to sleep.
    movzwl CTX_CS(%rdi), %eax
    pushq %rax
    leaq 1f(%rip), %rax
    pushq %rax
    lretq
1:
    movw CTX_SS(%rdi), %ax
    movw %ax, %ss
    movw CTX_DS(%rdi), %ax
    movw %ax, %ds
    movw CTX_ES(%rdi), %ax
    movw %ax, %es

    // The task register cannot be loaded with a descriptor that says the
    // task is busy, which is what loading it the first time made it say.
    movq CTX_GDT + 2(%rdi), %rax
    movzwl CTX_TR(%rdi), %ecx
    andb $0xfd, 5(%rax, %rcx)
    ltr CTX_TR(%rdi)
    // The LDT before FS and GS, which may select from it.
    lldt CTX_LDT(%rdi)
    movw CTX_FS(%rdi), %ax
    movw %ax, %fs
    movw CTX_GS(%rdi), %ax
    movw %ax, %gs

    // The model-specific registers, the FS and GS bases among them: loading
    // the selectors above overwrote those.
    movq CTX_MSRS(%rdi), %r8
    leaq CTX_MSR(%rdi), %r9
2:
    testq %r8, %r8
    jz 3f
    movl (%r9), %ecx
    movl 8(%r9), %eax
    movl 12(%r9), %edx
    wrmsr
    addq $16, %r9
    decq %r8
    jmp 2b
3:
    movq CTX_RBX(%rdi), %rbx
    movq CTX_RBP(%rdi), %rbp
    movq CTX_R12(%rdi), %r12
    movq CTX_R13(%rdi), %r13
    movq CTX_R14(%rdi), %r14
    movq CTX_R15(%rdi), %r15
    pushq CTX_RFLAGS(%rdi)
    popfq
    movq CTX_RIP(%rdi), %rdx
    movl $1, %eax
    jmpq *%rdx
.size x86_wake_resume, .-x86_wake_resume

// void x86_wake_secondary(cpulocal.Local *cpu)
//
// Where the trampoline sends a processor that is being started again, on the
// top of its own idle stack. A function is entered as if by CALL.
.global x86_wake_secondary
.type x86_wake_secondary, @function
x86_wake_secondary:
    andq $-16, %rsp
    xorl %ebp, %ebp
    pushq $0
    jmp x86_wake_secondary_entry
.size x86_wake_secondary, .-x86_wake_secondary

.section .note.GNU-stack,"",%progbits
