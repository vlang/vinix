/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_OVERFLOW_H
#define VINIX_LINUX_OVERFLOW_H
#include <linux/types.h>
#include <linux/compiler.h>
#include <linux/const.h>
#define check_add_overflow(a, b, d) __builtin_add_overflow((a), (b), (d))
#define check_sub_overflow(a, b, d) __builtin_sub_overflow((a), (b), (d))
#define check_mul_overflow(a, b, d) __builtin_mul_overflow((a), (b), (d))
#define __type_half_max(type) ((type)1 << (8*sizeof(type) - 1 - is_signed_type(type)))
#define __type_max(T) ((T)((__type_half_max(T) - 1) + __type_half_max(T)))
#define type_max(t)	__type_max(typeof(t))
#define __type_min(T) ((T)((T)-type_max(T)-(T)1))
#define type_min(t)	__type_min(typeof(t))

#define __overflows_type_constexpr(x, T) (			\
	is_unsigned_type(typeof(x)) ?				\
		(x) > type_max(T) :				\
	is_unsigned_type(typeof(T)) ?				\
		(x) < 0 || (x) > type_max(T) :			\
	(x) < type_min(T) || (x) > type_max(T))

#define __overflows_type(x, T)		({	\
	typeof(T) v = 0;			\
	check_add_overflow((x), v, &v);		\
})

#define overflows_type(n, T)					\
	__builtin_choose_expr(__is_constexpr(n),		\
			      __overflows_type_constexpr(n, T),	\
			      __overflows_type(n, T))

#define castable_to_type(n, T)						\
	__builtin_choose_expr(__is_constexpr(n),			\
			      !__overflows_type_constexpr(n, T),	\
			      __same_type(n, T))

size_t array_size(size_t, size_t);
size_t size_add(size_t, size_t);
size_t size_mul(size_t, size_t);
#endif
