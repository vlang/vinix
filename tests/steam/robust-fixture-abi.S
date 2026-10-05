// SPDX-License-Identifier: GPL-2.0-or-later
// Only the native integer variadic convention differs on Darwin ARM64.
#if defined(__APPLE__)
#define SYMBOL(name) _##name
#else
#define SYMBOL(name) name
#endif
.text
.global SYMBOL(fixture_call_syscall)
SYMBOL(fixture_call_syscall):
#if defined(__aarch64__) && defined(__APPLE__) && defined(STEAM_ROBUST_ORIGINAL)
	sub sp, sp, #80
	stp x29, x30, [sp, #64]
	stp x1, x2, [sp]
	stp x3, x4, [sp, #16]
	stp x5, x6, [sp, #32]
	bl SYMBOL(robust_subject_syscall)
	ldp x29, x30, [sp, #64]
	add sp, sp, #80
	ret
#elif defined(__aarch64__)
#ifdef STEAM_ROBUST_ORIGINAL
	b SYMBOL(robust_subject_syscall)
#else
	b SYMBOL(vinix_steam_syscall)
#endif
#else
#ifdef STEAM_ROBUST_ORIGINAL
	xor %eax, %eax
	jmp SYMBOL(robust_subject_syscall)
#else
	jmp SYMBOL(vinix_steam_syscall)
#endif
#endif

.global SYMBOL(robust_mock_syscall)
SYMBOL(robust_mock_syscall):
#if defined(__aarch64__) && defined(__APPLE__)
	ldp x1, x2, [sp]
	ldp x3, x4, [sp, #16]
	ldp x5, x6, [sp, #32]
	b SYMBOL(robust_mock_dispatch)
#elif defined(__aarch64__)
	b SYMBOL(robust_mock_dispatch)
#else
	jmp SYMBOL(robust_mock_dispatch)
#endif

#ifndef __APPLE__
.section .note.GNU-stack,"",@progbits
#endif
