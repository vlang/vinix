// SPDX-License-Identifier: GPL-2.0-or-later
// Complete native va_list, including floating-point register arguments.
#ifdef __APPLE__
.global _kprintf
.balign 4
_kprintf:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    add x9, sp, #32
    str x9, [sp, #16]
    add x1, sp, #16
    bl _vinix_krandom_host_vprintf
    ldp x29, x30, [sp], #32
    ret
#else
.global kprintf
.type kprintf, %function
.balign 4
kprintf:
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
    mov w9, #-56
    str w9, [sp, #232]
    mov w9, #-128
    str w9, [sp, #236]
    add x1, sp, #208
    bl vinix_krandom_host_vprintf
    ldp x29, x30, [sp], #240
    ret
.size kprintf, .-kprintf
.section .note.GNU-stack,"",%progbits
#endif
