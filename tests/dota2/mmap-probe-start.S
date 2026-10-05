// SPDX-License-Identifier: GPL-2.0-or-later
// Exact original Linux x86-64 __libc_start_main startup ABI.
.text
.global _start
.type _start, @function
_start:
	xor %ebp, %ebp
	mov %rdx, %r9
	pop %rsi
	mov %rsp, %rdx
	and $-16, %rsp
	push %rax
	push %rsp
	xor %r8d, %r8d
	xor %ecx, %ecx
	lea main(%rip), %rdi
	call *__libc_start_main@GOTPCREL(%rip)
	hlt
.size _start, .-_start
.section .note.GNU-stack,"",@progbits
