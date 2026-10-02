/* SPDX-License-Identifier: GPL-2.0-or-later */
.text
.global stack_syscall_on
.type stack_syscall_on, @function
stack_syscall_on:
#if defined(__aarch64__)
    mov x9, sp
    mov sp, x0
    mov x8, x1
    svc #0
    mov sp, x9
    ret
#elif defined(__x86_64__)
    mov %rsp, %r8
    mov %rdi, %rsp
    mov %rsi, %rax
    syscall
    mov %r8, %rsp
    ret
#endif
.size stack_syscall_on, .-stack_syscall_on
.section .note.GNU-stack,"",@progbits
