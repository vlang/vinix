#include "speculation.h"
.section .text

/* External compiler thunks also serve the handwritten dispatch sites.
 * No target instruction executes architecturally until RET consumes the
 * overwritten slot; speculation follows the CALL prediction into the trap. */
.macro RETPOLINE reg
.global __x86_indirect_thunk_\reg
.type __x86_indirect_thunk_\reg,@function
__x86_indirect_thunk_\reg:
    call 1f
2:
    pause
    lfence
    jmp 2b
1:
    mov %\reg, (%rsp)
    ret
.size __x86_indirect_thunk_\reg, .-__x86_indirect_thunk_\reg
.endm
RETPOLINE rax
RETPOLINE rbx
RETPOLINE rcx
RETPOLINE rdx
RETPOLINE rsi
RETPOLINE rdi
RETPOLINE rbp
RETPOLINE r8
RETPOLINE r9
RETPOLINE r10
RETPOLINE r11
RETPOLINE r12
RETPOLINE r13
RETPOLINE r14
RETPOLINE r15

/* Noreturn replacement of the scheduler's inline IRETQ sequence.
 * RDI is the complete GPR frame; RSI is a trusted logical CPU number. GS
 * may already be the user's base when resuming a kernel frame, so use RSI. */
.global vinix_x86_resume_context
.type vinix_x86_resume_context,@function
vinix_x86_resume_context:
    VINIX_RSB_FILL
    mov %rdi, %rsp
    VINIX_SPEC_SWITCH rsi
    pop %rax
    mov %eax, %ds
    pop %rax
    mov %eax, %es
    movq $0, 120(%rsp)
    testb $3, 136(%rsp)
    jz 3f
    VINIX_SPEC_RETURN rsi, 120
3:
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
    VINIX_SPEC_CLEAR
    add $8, %rsp
    swapgs
    lfence
    iretq
.size vinix_x86_resume_context, .-vinix_x86_resume_context

.section .rodata
.align 2
.global vinix_x86_verw_selector
vinix_x86_verw_selector:
    .word 0x30
.section .note.GNU-stack,"",%progbits
