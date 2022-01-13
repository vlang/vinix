// int_thunks_asm.S: Thunks used for IRQ bodies.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

.section .data

.globl interrupt_thunk_begin
.globl interrupt_thunk_number
.globl interrupt_thunk_offset
.globl interrupt_thunk_size
.globl interrupt_thunk_storage

interrupt_thunk_begin:
    push $0

    cmpq $0x43, 16(%rsp) // if user
    jne 1f
    swapgs

1:
    push %r15
    push %r14
    push %r13
    push %r12
    push %r11
    push %r10
    push %r9
    push %r8
    push %rbp
    push %rdi
    push %rsi
    push %rdx
    push %rcx
    push %rbx
    push %rax
    mov %es, %eax
    push %rax
    mov %ds, %eax
    push %rax

    cld

    mov $0x30, %eax
    mov %eax, %ds
    mov %eax, %es
    mov %eax, %ss

    mov %rsp, %rsi

    // those get filled in for each copy of the thunk template in prepare_interrupt_thunks()
    // mov {interrupt_thunk_number}, %edi
    .byte 0xbf
interrupt_thunk_number: .long 0
    // movabs {interrupt_thunk_offset}, %rbx
    .byte 0x48
    .byte 0xbb
interrupt_thunk_offset: .quad 0

    xor %rbp, %rbp
    call *(%rbx)

    pop %rax
    mov %eax, %ds
    pop %rax
    mov %eax, %es
    pop %rax
    pop %rbx
    pop %rcx
    pop %rdx
    pop %rsi
    pop %rdi
    pop %rbp
    pop %r8
    pop %r9
    pop %r10
    pop %r11
    pop %r12
    pop %r13
    pop %r14
    pop %r15
    add $8, %rsp

    cmpq $0x43, 8(%rsp) // if user
    jne 1f
    swapgs

1:
    iretq

interrupt_thunk_end:
.equ interrupt_thunk_size, interrupt_thunk_end - interrupt_thunk_begin
interrupt_thunk_storage: .space (interrupt_thunk_end - interrupt_thunk_begin) * 256
