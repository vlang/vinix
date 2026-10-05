// SPDX-License-Identifier: GPL-2.0-or-later
// All seven integer arguments already occupy their native syscall() ABI slots.
#if defined(__APPLE__)
#define SYMBOL(name) _##name
#else
#define SYMBOL(name) name
#endif
.text
#ifndef __APPLE__
.global syscall
.hidden vinix_steam_syscall
.type syscall, @function
syscall:
	jmp vinix_steam_syscall
.size syscall, .-syscall
#endif

.global SYMBOL(vinix_steam_forward_syscall)
#ifndef __APPLE__
.hidden vinix_steam_forward_syscall
#endif
SYMBOL(vinix_steam_forward_syscall):
#if defined(__aarch64__) && defined(__APPLE__)
	mov x9, x0
	mov x0, x1
	sub sp, sp, #80
	stp x29, x30, [sp, #64]
	stp x2, x3, [sp]
	stp x4, x5, [sp, #16]
	stp x6, x7, [sp, #32]
	blr x9
	ldp x29, x30, [sp, #64]
	add sp, sp, #80
	ret
#elif defined(__i386__)
	mov 4(%esp), %edx
	mov 8(%esp), %eax
	mov %eax, 4(%esp)
	mov 12(%esp), %eax
	mov %eax, 8(%esp)
	mov 16(%esp), %eax
	mov %eax, 12(%esp)
	mov 20(%esp), %eax
	mov %eax, 16(%esp)
	mov 24(%esp), %eax
	mov %eax, 20(%esp)
	mov 28(%esp), %eax
	mov %eax, 24(%esp)
	mov 32(%esp), %eax
	mov %eax, 28(%esp)
	jmp *%edx
#else
	mov %rdi, %r11
	mov %rsi, %rdi
	mov %rdx, %rsi
	mov %rcx, %rdx
	mov %r8, %rcx
	mov %r9, %r8
	mov 8(%rsp), %r9
	mov 16(%rsp), %rax
	mov %rax, 8(%rsp)
	xor %eax, %eax
	jmp *%r11
#endif

#ifndef __APPLE__
.section .note.GNU-stack,"",@progbits
#endif
