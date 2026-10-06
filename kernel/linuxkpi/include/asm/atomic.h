/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_ASM_ATOMIC_H
#define VINIX_ASM_ATOMIC_H
#include <linux/types.h>
#define ATOMIC_INIT(v) { (v) }
#define ATOMIC64_INIT(v) { (v) }

/* Supply the architecture primitives, retaining Linux's unmodified generated
 * ordering, conditional-update, atomic_long and instrumentation wrappers. */
int arch_atomic_read(const atomic_t *);
void arch_atomic_set(atomic_t *, int);
void arch_atomic_add(int, atomic_t *);
void arch_atomic_sub(int, atomic_t *);
void arch_atomic_and(int, atomic_t *);
void arch_atomic_or(int, atomic_t *);
void arch_atomic_xor(int, atomic_t *);
int arch_atomic_add_return_relaxed(int, atomic_t *);
int arch_atomic_sub_return_relaxed(int, atomic_t *);
int arch_atomic_fetch_add_relaxed(int, atomic_t *);
int arch_atomic_fetch_sub_relaxed(int, atomic_t *);
int arch_atomic_fetch_and_relaxed(int, atomic_t *);
int arch_atomic_fetch_or_relaxed(int, atomic_t *);
int arch_atomic_fetch_xor_relaxed(int, atomic_t *);
int arch_atomic_xchg_relaxed(atomic_t *, int);
int arch_atomic_cmpxchg_relaxed(atomic_t *, int, int);
s64 arch_atomic64_read(const atomic64_t *);
void arch_atomic64_set(atomic64_t *, s64);
void arch_atomic64_add(s64, atomic64_t *);
void arch_atomic64_sub(s64, atomic64_t *);
void arch_atomic64_and(s64, atomic64_t *);
void arch_atomic64_or(s64, atomic64_t *);
void arch_atomic64_xor(s64, atomic64_t *);
s64 arch_atomic64_add_return_relaxed(s64, atomic64_t *);
s64 arch_atomic64_sub_return_relaxed(s64, atomic64_t *);
s64 arch_atomic64_fetch_add_relaxed(s64, atomic64_t *);
s64 arch_atomic64_fetch_sub_relaxed(s64, atomic64_t *);
s64 arch_atomic64_fetch_and_relaxed(s64, atomic64_t *);
s64 arch_atomic64_fetch_or_relaxed(s64, atomic64_t *);
s64 arch_atomic64_fetch_xor_relaxed(s64, atomic64_t *);
s64 arch_atomic64_xchg_relaxed(atomic64_t *, s64);
s64 arch_atomic64_cmpxchg_relaxed(atomic64_t *, s64, s64);

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

#include <vinix/atomic_exchange.h>
#endif
