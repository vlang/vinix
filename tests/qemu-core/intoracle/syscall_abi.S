/* SPDX-License-Identifier: BSD-2-Clause */
/* Capture only the original syscall ABI arguments; all policies live in V. */
#if defined(__APPLE__) && defined(__aarch64__)
.text
.globl _vqt_host_syscall
.p2align 2
_vqt_host_syscall:
 ldr x1,[sp]
 ldr x2,[sp,#8]
 ldr w3,[sp,#16]
 ldr w4,[sp,#24]
 b _vqt_host_syscall_body
#elif defined(__aarch64__)
.text
.globl vqt_host_syscall
.type vqt_host_syscall,%function
.p2align 2
vqt_host_syscall:
 b vqt_host_syscall_body
.size vqt_host_syscall,.-vqt_host_syscall
.section .note.GNU-stack,"",%progbits
#else
.text
#if defined(__APPLE__)
.globl _vqt_host_syscall
_vqt_host_syscall:
 jmp _vqt_host_syscall_body
#else
.globl vqt_host_syscall
.type vqt_host_syscall,@function
vqt_host_syscall:
 jmp vqt_host_syscall_body
.size vqt_host_syscall,.-vqt_host_syscall
.section .note.GNU-stack,"",@progbits
#endif
#endif
