/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_UACCESS_H
#define VINIX_LINUX_UACCESS_H

#include <linux/types.h>

/* Ordinary, faulting process-context copies. The native pagemap backend
 * returns the uncopied byte count and does not retain either buffer. */
bool vinix_linuxkpi_access_ok(const void __user *address, unsigned long size);
bool vinix_linuxkpi_check_copy_size(size_t object_size, unsigned long size);

unsigned long __must_check raw_copy_from_user(void *to,
		const void __user *from, unsigned long size);
unsigned long __must_check raw_copy_to_user(void __user *to,
		const void *from, unsigned long size);
unsigned long __must_check __copy_from_user(void *to,
		const void __user *from, unsigned long size);
unsigned long __must_check __copy_to_user(void __user *to,
		const void *from, unsigned long size);
unsigned long __must_check _copy_from_user(void *to,
		const void __user *from, unsigned long size);
unsigned long __must_check _copy_to_user(void __user *to,
		const void *from, unsigned long size);

#define access_ok(address, size) \
	vinix_linuxkpi_access_ok((address), (size))

/* Object bounds belong to the call site: passing only an erased pointer to
 * the backend loses this compiler information. __builtin_object_size does
 * not evaluate its argument. Evaluate every ordinary argument once, and
 * preserve Linux's untouched destination on a copy-size rejection. Only
 * _copy_from_user zeroes the tail after an attempted or invalid user copy. */
#define copy_from_user(to, from, size) ({ \
	void *__vinix_uaccess_to = (to); \
	const void __user *__vinix_uaccess_from = (from); \
	unsigned long __vinix_uaccess_size = (size); \
	vinix_linuxkpi_check_copy_size(__builtin_object_size((to), 0), \
		__vinix_uaccess_size) \
		? _copy_from_user(__vinix_uaccess_to, __vinix_uaccess_from, \
			__vinix_uaccess_size) : __vinix_uaccess_size; \
})

#define copy_to_user(to, from, size) ({ \
	void __user *__vinix_uaccess_to = (to); \
	const void *__vinix_uaccess_from = (from); \
	unsigned long __vinix_uaccess_size = (size); \
	vinix_linuxkpi_check_copy_size(__builtin_object_size((from), 0), \
		__vinix_uaccess_size) \
		? _copy_to_user(__vinix_uaccess_to, __vinix_uaccess_from, \
			__vinix_uaccess_size) : __vinix_uaccess_size; \
})

/* Ordinary faulting scalar reads. The eight-byte output is a synchronous
 * kernel borrow; native page resolution emits a single width-specific load
 * when the scalar fits in one page. Failure returns -EFAULT and zero bits. */
int __must_check vinix_linuxkpi_get_user(const void __user *source,
		size_t size, void *bits);

#define get_user(x, ptr) ({ \
	__typeof__(ptr) __vinix_get_pointer = (ptr); \
	unsigned long long __vinix_get_bits = 0; \
	_Static_assert(sizeof(*__vinix_get_pointer) == 1 || \
		sizeof(*__vinix_get_pointer) == 2 || \
		sizeof(*__vinix_get_pointer) == 4 || \
		sizeof(*__vinix_get_pointer) == 8, "unsupported get_user scalar width"); \
	int __vinix_get_error = vinix_linuxkpi_get_user( \
		(const void __user *)__vinix_get_pointer, \
		sizeof(*__vinix_get_pointer), &__vinix_get_bits); \
	(x) = (__typeof__(*__vinix_get_pointer))__vinix_get_bits; \
	__vinix_get_error; \
})

/* The checked native backend is also safe for callers that already performed
 * access_ok. Both interfaces retain ordinary faulting task-context semantics. */
#define __get_user(x, ptr) get_user((x), (ptr))

/* Scalar stores, atomic/pagefault-disabled, unsafe-scope and noncached copies
 * still need their own native contracts and are not declared here. */
#endif
