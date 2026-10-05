/* SPDX-License-Identifier: GPL-2.0-or-later */
.text
.global syscall_at
.type syscall_at, @function
syscall_at:
#if defined(__aarch64__)
    mov x9, x30
    mov x8, x1
    blr x0
    mov x30, x9
    ret
#elif defined(__x86_64__)
    mov %rsi, %rax
    call *%rdi
    ret
#endif
.size syscall_at, .-syscall_at
.section .note.GNU-stack,"",@progbits
