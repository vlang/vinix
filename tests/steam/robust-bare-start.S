// SPDX-License-Identifier: GPL-2.0-or-later
.text
.global _start
_start:
#if defined(__i386__)
	xor %ebp, %ebp
	and $-16, %esp
	call main
	push %eax
	call robust_bare_exit
#else
	xor %ebp, %ebp
	and $-16, %rsp
	call main
	mov %eax, %edi
	call robust_bare_exit
#endif

.global robust_bare_write
robust_bare_write:
#if defined(__i386__)
	push %ebx
	mov 8(%esp), %ebx
	mov 12(%esp), %ecx
	mov 16(%esp), %edx
	mov $4, %eax
	int $0x80
	pop %ebx
#else
	mov $1, %eax
	syscall
#endif
	ret

.global robust_bare_open
robust_bare_open:
#if defined(__i386__)
	push %ebx
	mov 8(%esp), %ebx
	mov 12(%esp), %ecx
	xor %edx, %edx
	mov $5, %eax
	int $0x80
	pop %ebx
#else
	xor %edx, %edx
	mov $2, %eax
	syscall
#endif
	ret

.global robust_bare_exit
robust_bare_exit:
#if defined(__i386__)
	mov 4(%esp), %ebx
	mov $1, %eax
	int $0x80
#else
	mov $60, %eax
	syscall
#endif
	ud2
.section .note.GNU-stack,"",@progbits
