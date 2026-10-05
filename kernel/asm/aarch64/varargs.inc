// Capture the platform va_list and append its address to the named arguments.
#ifdef __APPLE__
#define ABI_JOIN(name) _##name
#define ABI_SYMBOL(name) ABI_JOIN(name)
#else
#define ABI_SYMBOL(name) name
#endif
.macro VINIX_VARIADIC name, target, named
    .balign 4
    .global \name
#ifndef __APPLE__
    .type \name, %function
#endif
\name:
#ifdef __APPLE__
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    add x9, sp, #32
    str x9, [sp, #16]
    add x\named, sp, #16
#else
    stp x29, x30, [sp, #-112]!
    mov x29, sp
    stp x0, x1, [sp, #16]
    stp x2, x3, [sp, #32]
    stp x4, x5, [sp, #48]
    stp x6, x7, [sp, #64]
    add x9, sp, #112
    str x9, [sp, #80]
    add x9, sp, #80
    str x9, [sp, #88]
    str xzr, [sp, #96]
    mov w9, #(-(8 - \named) * 8)
    str w9, [sp, #104]
    str wzr, [sp, #108]
    add x\named, sp, #80
#endif
    bl \target
#ifdef __APPLE__
    ldp x29, x30, [sp], #32
#else
    ldp x29, x30, [sp], #112
#endif
    ret
#ifndef __APPLE__
    .size \name, .-\name
#endif
.endm
