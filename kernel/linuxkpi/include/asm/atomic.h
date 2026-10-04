/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_ASM_ATOMIC_H
#define VINIX_ASM_ATOMIC_H
#include <linux/types.h>
#define ATOMIC_INIT(v) { (v) }
#define ATOMIC64_INIT(v) { (v) }

/* Supply the architecture primitives, retaining Linux's unmodified generated
 * ordering, conditional-update, atomic_long and instrumentation wrappers. */
#define VINIX_ARCH_ATOMICS(type, prefix, value_type) \
static inline value_type prefix##_read(const type *p) { return __atomic_load_n(&p->counter, __ATOMIC_RELAXED); } \
static inline void prefix##_set(type *p, value_type v) { __atomic_store_n(&p->counter, v, __ATOMIC_RELAXED); } \
static inline void prefix##_add(value_type v, type *p) { (void)__atomic_fetch_add(&p->counter, v, __ATOMIC_RELAXED); } \
static inline void prefix##_sub(value_type v, type *p) { (void)__atomic_fetch_sub(&p->counter, v, __ATOMIC_RELAXED); } \
static inline void prefix##_and(value_type v, type *p) { (void)__atomic_fetch_and(&p->counter, v, __ATOMIC_RELAXED); } \
static inline void prefix##_or(value_type v, type *p) { (void)__atomic_fetch_or(&p->counter, v, __ATOMIC_RELAXED); } \
static inline void prefix##_xor(value_type v, type *p) { (void)__atomic_fetch_xor(&p->counter, v, __ATOMIC_RELAXED); } \
static inline value_type prefix##_add_return_relaxed(value_type v, type *p) { return __atomic_add_fetch(&p->counter, v, __ATOMIC_RELAXED); } \
static inline value_type prefix##_sub_return_relaxed(value_type v, type *p) { return __atomic_sub_fetch(&p->counter, v, __ATOMIC_RELAXED); } \
static inline value_type prefix##_fetch_add_relaxed(value_type v, type *p) { return __atomic_fetch_add(&p->counter, v, __ATOMIC_RELAXED); } \
static inline value_type prefix##_fetch_sub_relaxed(value_type v, type *p) { return __atomic_fetch_sub(&p->counter, v, __ATOMIC_RELAXED); } \
static inline value_type prefix##_fetch_and_relaxed(value_type v, type *p) { return __atomic_fetch_and(&p->counter, v, __ATOMIC_RELAXED); } \
static inline value_type prefix##_fetch_or_relaxed(value_type v, type *p) { return __atomic_fetch_or(&p->counter, v, __ATOMIC_RELAXED); } \
static inline value_type prefix##_fetch_xor_relaxed(value_type v, type *p) { return __atomic_fetch_xor(&p->counter, v, __ATOMIC_RELAXED); } \
static inline value_type prefix##_xchg_relaxed(type *p, value_type v) { return __atomic_exchange_n(&p->counter, v, __ATOMIC_RELAXED); } \
static inline value_type prefix##_cmpxchg_relaxed(type *p, value_type old, value_type v) { \
    __atomic_compare_exchange_n(&p->counter, &old, v, false, __ATOMIC_RELAXED, __ATOMIC_RELAXED); return old; \
}
VINIX_ARCH_ATOMICS(atomic_t, arch_atomic, int)
VINIX_ARCH_ATOMICS(atomic64_t, arch_atomic64, s64)
#undef VINIX_ARCH_ATOMICS

/* The generated Linux fallback tests these names with defined(). */
#define arch_atomic_add_return_relaxed arch_atomic_add_return_relaxed
#define arch_atomic_sub_return_relaxed arch_atomic_sub_return_relaxed
#define arch_atomic_fetch_add_relaxed arch_atomic_fetch_add_relaxed
#define arch_atomic_fetch_sub_relaxed arch_atomic_fetch_sub_relaxed
#define arch_atomic_fetch_and_relaxed arch_atomic_fetch_and_relaxed
#define arch_atomic_fetch_or_relaxed arch_atomic_fetch_or_relaxed
#define arch_atomic_fetch_xor_relaxed arch_atomic_fetch_xor_relaxed
#define arch_atomic_xchg_relaxed arch_atomic_xchg_relaxed
#define arch_atomic_cmpxchg_relaxed arch_atomic_cmpxchg_relaxed
#define arch_atomic64_add_return_relaxed arch_atomic64_add_return_relaxed
#define arch_atomic64_sub_return_relaxed arch_atomic64_sub_return_relaxed
#define arch_atomic64_fetch_add_relaxed arch_atomic64_fetch_add_relaxed
#define arch_atomic64_fetch_sub_relaxed arch_atomic64_fetch_sub_relaxed
#define arch_atomic64_fetch_and_relaxed arch_atomic64_fetch_and_relaxed
#define arch_atomic64_fetch_or_relaxed arch_atomic64_fetch_or_relaxed
#define arch_atomic64_fetch_xor_relaxed arch_atomic64_fetch_xor_relaxed
#define arch_atomic64_xchg_relaxed arch_atomic64_xchg_relaxed
#define arch_atomic64_cmpxchg_relaxed arch_atomic64_cmpxchg_relaxed

#define arch_xchg_relaxed(ptr, value) __atomic_exchange_n((ptr), (value), __ATOMIC_RELAXED)
#define arch_cmpxchg_relaxed(ptr, old, value) ({ \
    __auto_type __p = (ptr); __typeof__(*__p) __old = (old); \
    __atomic_compare_exchange_n(__p, &__old, (value), false, __ATOMIC_RELAXED, __ATOMIC_RELAXED); __old; \
})
#define arch_cmpxchg64_relaxed arch_cmpxchg_relaxed
/* UP-local operations may provide stronger SMP atomicity. */
#define arch_cmpxchg_local arch_cmpxchg_relaxed
#define arch_cmpxchg64_local arch_cmpxchg_relaxed
#endif
