/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Declaration and ABI metadata only; all executable transport/checks are V. */
#ifndef VINIX_RWSEM_HOST_FIXTURE_H
#define VINIX_RWSEM_HOST_FIXTURE_H
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sched.h>
#include <stdint.h>
#include "linuxkpi_rwsem_v_contract.h"
typedef const char *rsh_const_charp;
#define rsh_load32(p) __atomic_load_n((p), __ATOMIC_ACQUIRE)
#define rsh_store32(p,v) __atomic_store_n((p),(v), __ATOMIC_RELEASE)
#define rsh_add32(p,v) __atomic_fetch_add((p),(v), __ATOMIC_ACQ_REL)
#define rsh_exchange32(p,v) __atomic_exchange_n((p),(v), __ATOMIC_ACQ_REL)
#define rsh_load64(p) __atomic_load_n((p), __ATOMIC_ACQUIRE)
#define rsh_store64(p,v) __atomic_store_n((p),(v), __ATOMIC_RELEASE)
#define rsh_line(v) ((v).str)
#define rsh_count(s) ((uint64_t)__atomic_load_n(&(s)->count.counter,__ATOMIC_ACQUIRE))
#define rsh_owner(s) ((uintptr_t)__atomic_load_n(&(s)->owner.counter,__ATOMIC_ACQUIRE))
#define rsh_lock(s) (&(s)->wait_lock)
#define rsh_list(s) (&(s)->wait_list)
#define rsh_set_count(s,v) __atomic_store_n(&(s)->count.counter,(long)(v),__ATOMIC_RELEASE)
#define rsh_set_owner(s,v) __atomic_store_n(&(s)->owner.counter,(long)(v),__ATOMIC_RELEASE)
static DECLARE_RWSEM(rsh_static_sem);
#define rsh_static_ptr() (&rsh_static_sem)
_Static_assert(__builtin_types_compatible_p(__typeof__(&__init_rwsem),void (*)(struct rw_semaphore *,const char *,struct lock_class_key *)),"original rwsem init prototype");
_Static_assert(__builtin_types_compatible_p(__typeof__(&down_read),void (*)(struct rw_semaphore *)) && __builtin_types_compatible_p(__typeof__(&down_write),void (*)(struct rw_semaphore *)),"original rwsem blocking prototypes");
_Static_assert(__builtin_types_compatible_p(__typeof__(&down_read_interruptible),int (*)(struct rw_semaphore *)) && __builtin_types_compatible_p(__typeof__(&down_read_killable),int (*)(struct rw_semaphore *)) && __builtin_types_compatible_p(__typeof__(&down_write_killable),int (*)(struct rw_semaphore *)),"original rwsem cancellation prototypes");
_Static_assert(__builtin_types_compatible_p(__typeof__(&down_read_trylock),int (*)(struct rw_semaphore *)) && __builtin_types_compatible_p(__typeof__(&down_write_trylock),int (*)(struct rw_semaphore *)),"original rwsem trylock prototypes");
_Static_assert(__builtin_types_compatible_p(__typeof__(&up_read),void (*)(struct rw_semaphore *)) && __builtin_types_compatible_p(__typeof__(&up_write),void (*)(struct rw_semaphore *)) && __builtin_types_compatible_p(__typeof__(&downgrade_write),void (*)(struct rw_semaphore *)),"original rwsem release prototypes");
#endif
