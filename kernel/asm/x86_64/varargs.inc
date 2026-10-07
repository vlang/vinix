// Preserve the six integer registers and SysV overflow stack cursor.
#ifdef __APPLE__
#define ABI_SYMBOL_INNER(name) _##name
#define ABI_SYMBOL(name) ABI_SYMBOL_INNER(name)
#else
#define ABI_SYMBOL(name) name
#endif
.macro VINIX_VARIADIC name, target, named
    .global \name
#ifndef __APPLE__
    .type \name, @function
#endif
\name:
    pushq %rbp
    movq %rsp, %rbp
    subq $80, %rsp
    movq %rdi, 0(%rsp)
    movq %rsi, 8(%rsp)
    movq %rdx, 16(%rsp)
    movq %rcx, 24(%rsp)
    movq %r8, 32(%rsp)
    movq %r9, 40(%rsp)
    movl $(\named * 8), 48(%rsp)
    movl $48, 52(%rsp)
    leaq 16(%rbp), %r10
    movq %r10, 56(%rsp)
    movq %rsp, 64(%rsp)
    .if \named == 1
        leaq 48(%rsp), %rsi
    .elseif \named == 2
        leaq 48(%rsp), %rdx
    .elseif \named == 3
        leaq 48(%rsp), %rcx
    .elseif \named == 4
        leaq 48(%rsp), %r8
    .else
        .error "Unsupported variadic named-argument count"
    .endif
    call \target
    leave
    ret
#ifndef __APPLE__
    .size \name, .-\name
#endif
.endm
