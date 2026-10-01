/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_ATOMIC_H
#define VINIX_LINUX_ATOMIC_H
#include <linux/types.h>
#define ATOMIC_INIT(v) { (v) }
#define ATOMIC64_INIT(v) { (v) }
#define VINIX_ATOMIC_OPS(type, prefix, value_type) \
static inline value_type prefix##_read(const type *p) { return __atomic_load_n(&p->counter, __ATOMIC_RELAXED); } \
static inline void prefix##_set(type *p, value_type v) { __atomic_store_n(&p->counter, v, __ATOMIC_RELAXED); } \
static inline value_type prefix##_add_return(value_type v, type *p) { return __atomic_add_fetch(&p->counter, v, __ATOMIC_SEQ_CST); } \
static inline value_type prefix##_sub_return(value_type v, type *p) { return __atomic_sub_fetch(&p->counter, v, __ATOMIC_SEQ_CST); } \
static inline void prefix##_inc(type *p) { (void)__atomic_fetch_add(&p->counter, 1, __ATOMIC_RELAXED); } \
static inline void prefix##_dec(type *p) { (void)__atomic_fetch_sub(&p->counter, 1, __ATOMIC_RELAXED); } \
static inline value_type prefix##_inc_return(type *p) { return prefix##_add_return(1, p); } \
static inline value_type prefix##_dec_return(type *p) { return prefix##_sub_return(1, p); } \
static inline bool prefix##_dec_and_test(type *p) { return prefix##_dec_return(p) == 0; } \
static inline value_type prefix##_xchg(type *p, value_type v) { return __atomic_exchange_n(&p->counter, v, __ATOMIC_SEQ_CST); } \
static inline value_type prefix##_cmpxchg(type *p, value_type old, value_type v) { \
    __atomic_compare_exchange_n(&p->counter, &old, v, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); return old; \
}
VINIX_ATOMIC_OPS(atomic_t, atomic, int)
VINIX_ATOMIC_OPS(atomic64_t, atomic64, long long)
#undef VINIX_ATOMIC_OPS
#endif
