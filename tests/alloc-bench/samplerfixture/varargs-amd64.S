// SPDX-License-Identifier: GPL-2.0-or-later
// Complete SysV register save area, not the integer-only kernel cursor.
#ifdef __APPLE__
#define SAMPLER_SYMBOL(name) _##name
#else
#define SAMPLER_SYMBOL(name) name
#endif
.global SAMPLER_SYMBOL(vkb_test_log)
#ifndef __APPLE__
.type vkb_test_log, @function
#endif
SAMPLER_SYMBOL(vkb_test_log):
    pushq %rbp
    movq %rsp, %rbp
    subq $208, %rsp
    movq %rdi, 0(%rsp)
    movq %rsi, 8(%rsp)
    movq %rdx, 16(%rsp)
    movq %rcx, 24(%rsp)
    movq %r8, 32(%rsp)
    movq %r9, 40(%rsp)
    movaps %xmm0, 48(%rsp)
    movaps %xmm1, 64(%rsp)
    movaps %xmm2, 80(%rsp)
    movaps %xmm3, 96(%rsp)
    movaps %xmm4, 112(%rsp)
    movaps %xmm5, 128(%rsp)
    movaps %xmm6, 144(%rsp)
    movaps %xmm7, 160(%rsp)
    movl $8, 176(%rsp)
    movl $48, 180(%rsp)
    leaq 16(%rbp), %r10
    movq %r10, 184(%rsp)
    movq %rsp, 192(%rsp)
    leaq 176(%rsp), %rsi
    call SAMPLER_SYMBOL(vsampler_capture_log)
    leave
    ret
#ifndef __APPLE__
.size vkb_test_log, .-vkb_test_log
.section .note.GNU-stack,"",@progbits
#endif
