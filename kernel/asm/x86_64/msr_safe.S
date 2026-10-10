// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Model-specific registers that may not be there; see x86/msr/safe.v.
//
// RDMSR and WRMSR of a register the CPU does not have raise #GP, and whether
// it has one is often known only by trying: the thermal and energy registers
// are named by CPUID bits that a hypervisor passes through without the
// registers behind them. Each instruction that may fault has a label of its
// own, and the #GP handler sends a fault at exactly that address on to the
// `_fault` label after it, which returns false. Plain assembly, so that the
// compiler has no say in where the instruction is or what follows it.

.section .text

// bool x86_rdmsr_safe(u32 index, u64 *value)
.global x86_rdmsr_safe
x86_rdmsr_safe:
    mov %edi, %ecx
.global x86_rdmsr_safe_insn
x86_rdmsr_safe_insn:
    rdmsr
    shl $32, %rdx
    mov %eax, %eax
    or %rdx, %rax
    mov %rax, (%rsi)
    mov $1, %eax
    ret
.global x86_rdmsr_safe_fault
x86_rdmsr_safe_fault:
    xor %eax, %eax
    ret

// bool x86_wrmsr_safe(u32 index, u64 value)
.global x86_wrmsr_safe
x86_wrmsr_safe:
    mov %edi, %ecx
    mov %esi, %eax
    mov %rsi, %rdx
    shr $32, %rdx
.global x86_wrmsr_safe_insn
x86_wrmsr_safe_insn:
    wrmsr
    mov $1, %eax
    ret
.global x86_wrmsr_safe_fault
x86_wrmsr_safe_fault:
    xor %eax, %eax
    ret

.section .note.GNU-stack,"",%progbits
