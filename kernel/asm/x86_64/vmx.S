/* SPDX-License-Identifier: GPL-2.0-only
 * Copyright (c) 2026 Alexander Medvednikov */
/* Preserve the VMCS host stack and all guest GPRs across VM entry/exit. */
.text
.global vinix_vmx_enter
.type vinix_vmx_enter, @function
vinix_vmx_enter:
pushq %rbp
pushq %rbx
pushq %r12
pushq %r13
pushq %r14
pushq %r15
pushq %rdi
movq $0x6c14, %rax
vmwrite %rsp, %rax
jna .Lvinix_vmx_failure
leaq .Lvinix_vmx_exit(%rip), %r10
movq $0x6c16, %rax
vmwrite %r10, %rax
jna .Lvinix_vmx_failure
movq (%rsp), %rax
movq 8(%rax), %rbx
movq 16(%rax), %rcx
movq 24(%rax), %rdx
movq 32(%rax), %rsi
movq 48(%rax), %rbp
movq 56(%rax), %r8
movq 64(%rax), %r9
movq 72(%rax), %r10
movq 80(%rax), %r11
movq 88(%rax), %r12
movq 96(%rax), %r13
movq 104(%rax), %r14
movq 112(%rax), %r15
movq 40(%rax), %rdi
movq (%rax), %rax
vmlaunch
.Lvinix_vmx_failure:
movl $-1, %eax
jmp .Lvinix_vmx_return
.Lvinix_vmx_exit:
cld
pushq %rax
pushq %r10
movq 16(%rsp), %rax
movq %rbx, 8(%rax)
movq %rcx, 16(%rax)
movq %rdx, 24(%rax)
movq %rsi, 32(%rax)
movq %rdi, 40(%rax)
movq %rbp, 48(%rax)
movq %r8, 56(%rax)
movq %r9, 64(%rax)
movq (%rsp), %r10
movq %r10, 72(%rax)
movq %r11, 80(%rax)
movq %r12, 88(%rax)
movq %r13, 96(%rax)
movq %r14, 104(%rax)
movq %r15, 112(%rax)
movq 8(%rsp), %r10
movq %r10, (%rax)
addq $16, %rsp
xorl %eax, %eax
.Lvinix_vmx_return:
addq $8, %rsp
popq %r15
popq %r14
popq %r13
popq %r12
popq %rbx
popq %rbp
ret
.size vinix_vmx_enter, .-vinix_vmx_enter
