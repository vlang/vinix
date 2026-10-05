#include "varargs.inc"
.text
VINIX_VARIADIC ABI_SYMBOL(printf), ABI_SYMBOL(vinix_printf_entry), 1
VINIX_VARIADIC ABI_SYMBOL(printf_panic), ABI_SYMBOL(vinix_panic_entry), 1
VINIX_VARIADIC ABI_SYMBOL(kprintf), ABI_SYMBOL(vinix_kprintf_entry), 1
VINIX_VARIADIC ABI_SYMBOL(printf_benchmark), ABI_SYMBOL(vinix_benchmark_entry), 1
VINIX_VARIADIC ABI_SYMBOL(fprintf), ABI_SYMBOL(vinix_fprintf_entry), 2

// AAPCS64 passes va_list by value through an indirect copy. Darwin passes
// its stack cursor by value. Keep those consumption rules at the ABI edge.
.macro NPF_CALL name, target
    .balign 4
    .global \name
#ifndef __APPLE__
    .type \name, %function
#endif
\name:
#ifdef __APPLE__
    ldr x3, [x3]
    b \target
#else
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    ldp x9, x10, [x3]
    stp x9, x10, [sp, #16]
    ldp x9, x10, [x3, #16]
    stp x9, x10, [sp, #32]
    add x3, sp, #16
    bl \target
    ldp x29, x30, [sp], #48
    ret
#endif
#ifndef __APPLE__
    .size \name, .-\name
#endif
.endm
NPF_CALL ABI_SYMBOL(vp_format), ABI_SYMBOL(npf_vpprintf)
NPF_CALL ABI_SYMBOL(vp_snprintf), ABI_SYMBOL(npf_vsnprintf)

#ifdef __APPLE__
.section __DATA,__data
#else
.data
#endif
.balign 8
.global ABI_SYMBOL(stderr)
ABI_SYMBOL(stderr):
    .quad .Lstderr_file
.Lstderr_file:
    .quad 0
#ifndef __APPLE__
.section .note.GNU-stack,"",%progbits
#endif
