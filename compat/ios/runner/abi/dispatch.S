/* SPDX-License-Identifier: GPL-2.0-or-later
 * Preserve every argument, including FP/HFA and indirect-result registers.
 * All runtime policy and framework methods live in V. */
#ifdef __APPLE__
#define SYM_(x) _##x
#define SYM(x) SYM_(x)
#else
#define SYM(x) x
#endif
.text
.p2align 2
.global SYM(ios_objc_msgsend)
SYM(ios_objc_msgsend):
    mov x16, #0
    b 1f
.global SYM(ios_objc_super)
SYM(ios_objc_super):
    mov x16, #1
1:
    sub sp, sp, #224
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]
    stp x8, x30, [sp, #64]
    stp q0, q1, [sp, #80]
    stp q2, q3, [sp, #112]
    stp q4, q5, [sp, #144]
    stp q6, q7, [sp, #176]
    mov x0, sp
    mov x1, x16
    bl SYM(ios_dispatch)
    mov x16, x0
    ldp x0, x1, [sp, #0]
    ldp x2, x3, [sp, #16]
    ldp x4, x5, [sp, #32]
    ldp x6, x7, [sp, #48]
    ldp x8, x30, [sp, #64]
    ldp q0, q1, [sp, #80]
    ldp q2, q3, [sp, #112]
    ldp q4, q5, [sp, #144]
    ldp q6, q7, [sp, #176]
    add sp, sp, #224
    cbz x16, 2f
    br x16
2:
    ret
/* Darwin ARM64 variadic doubles arrive in stack slots; the V adapter has a
 * fixed signature, so the host compiler supplies its own libc varargs ABI. */
.global SYM(ios_snprintf)
SYM(ios_snprintf):
    ldr d0, [sp]
    b SYM(ios_format_double)
#ifndef __APPLE__
.section .note.GNU-stack,"",%progbits
#endif
