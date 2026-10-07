/* SPDX-License-Identifier: MIT */
/* Native variadic register capture only; policy and formatting entry are V. */
#ifdef __APPLE__
#define N64_SYMBOL_INNER(name) _##name
#define N64_SYMBOL(name) N64_SYMBOL_INNER(name)
#else
#define N64_SYMBOL(name) name
#endif
.text
.global N64_SYMBOL(vinix_n64_log_message)
#if defined(__aarch64__)
.balign 4
#ifndef __APPLE__
.type vinix_n64_log_message, %function
#endif
N64_SYMBOL(vinix_n64_log_message):
#ifdef __APPLE__
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    add x9, sp, #32
    str x9, [sp, #16]
    add x2, sp, #16
    bl N64_SYMBOL(vinix_n64_log_entry)
    ldp x29, x30, [sp], #32
#else
    stp x29, x30, [sp, #-240]!
    mov x29, sp
    stp x0, x1, [sp, #16]
    stp x2, x3, [sp, #32]
    stp x4, x5, [sp, #48]
    stp x6, x7, [sp, #64]
    stp q0, q1, [sp, #80]
    stp q2, q3, [sp, #112]
    stp q4, q5, [sp, #144]
    stp q6, q7, [sp, #176]
    add x9, sp, #240
    str x9, [sp, #208]
    add x9, sp, #80
    str x9, [sp, #216]
    add x9, sp, #208
    str x9, [sp, #224]
    mov w9, #-48
    str w9, [sp, #232]
    mov w9, #-128
    str w9, [sp, #236]
    add x2, sp, #208
    bl vinix_n64_log_entry
    ldp x29, x30, [sp], #240
#endif
    ret
#ifndef __APPLE__
.size vinix_n64_log_message, .-vinix_n64_log_message
.section .note.GNU-stack,"",%progbits
#endif
#elif defined(__x86_64__)
#ifndef __APPLE__
.type vinix_n64_log_message, @function
#endif
N64_SYMBOL(vinix_n64_log_message):
    pushq %rbp
    movq %rsp, %rbp
    subq $208, %rsp
    movq %rdi, 0(%rsp)
    movq %rsi, 8(%rsp)
    movq %rdx, 16(%rsp)
    movq %rcx, 24(%rsp)
    movq %r8, 32(%rsp)
    movq %r9, 40(%rsp)
    movdqu %xmm0, 48(%rsp)
    movdqu %xmm1, 64(%rsp)
    movdqu %xmm2, 80(%rsp)
    movdqu %xmm3, 96(%rsp)
    movdqu %xmm4, 112(%rsp)
    movdqu %xmm5, 128(%rsp)
    movdqu %xmm6, 144(%rsp)
    movdqu %xmm7, 160(%rsp)
    movl $16, 176(%rsp)
    movl $48, 180(%rsp)
    leaq 16(%rbp), %r10
    movq %r10, 184(%rsp)
    movq %rsp, 192(%rsp)
    leaq 176(%rsp), %rdx
    call N64_SYMBOL(vinix_n64_log_entry)
    leave
    ret
#ifndef __APPLE__
.size vinix_n64_log_message, .-vinix_n64_log_message
.section .note.GNU-stack,"",@progbits
#endif
#else
#error Unsupported N64 bridge native ABI
#endif
