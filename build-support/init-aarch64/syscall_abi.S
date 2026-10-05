// SPDX-License-Identifier: GPL-2.0-only
// Raw ARM64 register entry and the kernel's signal-return trampoline.
.text
.balign 4
.global vinit_syscall
.type vinit_syscall, %function
vinit_syscall:
	mov x8, x0
	mov x0, x1
	mov x1, x2
	mov x2, x3
	mov x3, x4
	mov x4, x5
	svc #0
	ret
.size vinit_syscall, .-vinit_syscall

.balign 4
.global vinit_signal_restorer
.type vinit_signal_restorer, %function
vinit_signal_restorer:
	mov x8, #139
	svc #0
	brk #0
.size vinit_signal_restorer, .-vinit_signal_restorer
.section .note.GNU-stack,"",%progbits
