/* SPDX-License-Identifier: GPL-2.0-or-later
 *
 * C11 atomics for the aarch64 cross build, in terms of clang's own builtins.
 *
 * The desktop is compiled by clang against a GCC/musl sysroot. -nostdinc drops
 * clang's own headers, so <stdatomic.h> would come from GCC 11, whose
 * atomic_load_explicit expands to __atomic_load. Clang implements that builtin
 * too, but refuses an _Atomic-qualified pointer for it -- and an _Atomic cast
 * is exactly what V's generated code passes. Clang's own header maps the same
 * call to __c11_atomic_load, which takes that pointer.
 *
 * Putting clang's header back on the path does not help: it forwards to the
 * system one with #include_next whenever __STDC_HOSTED__ is set. So this
 * shadows the header instead, and is what clang's own would have expanded to.
 * It only has to cover what V's sync.stdatomic emits.
 */
#ifndef VINIX_AARCH64_STDATOMIC_H
#define VINIX_AARCH64_STDATOMIC_H

#include <stddef.h>
#include <stdint.h>

typedef enum memory_order {
	memory_order_relaxed = __ATOMIC_RELAXED,
	memory_order_consume = __ATOMIC_CONSUME,
	memory_order_acquire = __ATOMIC_ACQUIRE,
	memory_order_release = __ATOMIC_RELEASE,
	memory_order_acq_rel = __ATOMIC_ACQ_REL,
	memory_order_seq_cst = __ATOMIC_SEQ_CST
} memory_order;

#define ATOMIC_VAR_INIT(value) (value)
#define atomic_init __c11_atomic_init
#define kill_dependency(y) (y)

#define atomic_thread_fence(order) __c11_atomic_thread_fence(order)
#define atomic_signal_fence(order) __c11_atomic_signal_fence(order)

#define atomic_load_explicit __c11_atomic_load
#define atomic_load(object) __c11_atomic_load(object, __ATOMIC_SEQ_CST)
#define atomic_store_explicit __c11_atomic_store
#define atomic_store(object, desired) __c11_atomic_store(object, desired, __ATOMIC_SEQ_CST)
#define atomic_exchange_explicit __c11_atomic_exchange
#define atomic_exchange(object, desired) __c11_atomic_exchange(object, desired, __ATOMIC_SEQ_CST)

#define atomic_compare_exchange_strong_explicit __c11_atomic_compare_exchange_strong
#define atomic_compare_exchange_strong(object, expected, desired) \
	__c11_atomic_compare_exchange_strong(object, expected, desired, __ATOMIC_SEQ_CST, \
		__ATOMIC_SEQ_CST)
#define atomic_compare_exchange_weak_explicit __c11_atomic_compare_exchange_weak
#define atomic_compare_exchange_weak(object, expected, desired) \
	__c11_atomic_compare_exchange_weak(object, expected, desired, __ATOMIC_SEQ_CST, \
		__ATOMIC_SEQ_CST)

#define atomic_fetch_add_explicit __c11_atomic_fetch_add
#define atomic_fetch_add(object, operand) __c11_atomic_fetch_add(object, operand, __ATOMIC_SEQ_CST)
#define atomic_fetch_sub_explicit __c11_atomic_fetch_sub
#define atomic_fetch_sub(object, operand) __c11_atomic_fetch_sub(object, operand, __ATOMIC_SEQ_CST)
#define atomic_fetch_and_explicit __c11_atomic_fetch_and
#define atomic_fetch_and(object, operand) __c11_atomic_fetch_and(object, operand, __ATOMIC_SEQ_CST)
#define atomic_fetch_or_explicit __c11_atomic_fetch_or
#define atomic_fetch_or(object, operand) __c11_atomic_fetch_or(object, operand, __ATOMIC_SEQ_CST)
#define atomic_fetch_xor_explicit __c11_atomic_fetch_xor
#define atomic_fetch_xor(object, operand) __c11_atomic_fetch_xor(object, operand, __ATOMIC_SEQ_CST)

typedef _Atomic(_Bool) atomic_bool;
typedef _Atomic(char) atomic_char;
typedef _Atomic(signed char) atomic_schar;
typedef _Atomic(unsigned char) atomic_uchar;
typedef _Atomic(short) atomic_short;
typedef _Atomic(unsigned short) atomic_ushort;
typedef _Atomic(int) atomic_int;
typedef _Atomic(unsigned int) atomic_uint;
typedef _Atomic(long) atomic_long;
typedef _Atomic(unsigned long) atomic_ulong;
typedef _Atomic(long long) atomic_llong;
typedef _Atomic(unsigned long long) atomic_ullong;
typedef _Atomic(intptr_t) atomic_intptr_t;
typedef _Atomic(uintptr_t) atomic_uintptr_t;
typedef _Atomic(size_t) atomic_size_t;
typedef _Atomic(ptrdiff_t) atomic_ptrdiff_t;

typedef struct atomic_flag {
	atomic_bool _Value;
} atomic_flag;

#define ATOMIC_FLAG_INIT { 0 }

#define atomic_flag_test_and_set_explicit(object, order) \
	__c11_atomic_exchange(&(object)->_Value, 1, order)
#define atomic_flag_test_and_set(object) \
	atomic_flag_test_and_set_explicit(object, __ATOMIC_SEQ_CST)
#define atomic_flag_clear_explicit(object, order) __c11_atomic_store(&(object)->_Value, 0, order)
#define atomic_flag_clear(object) atomic_flag_clear_explicit(object, __ATOMIC_SEQ_CST)

#endif /* VINIX_AARCH64_STDATOMIC_H */
