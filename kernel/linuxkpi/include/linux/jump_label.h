/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_JUMP_LABEL_H
#define VINIX_LINUX_JUMP_LABEL_H
#include <linux/atomic.h>
/* Equivalent branch semantics without Linux's text-patching optimization.
 * Only the boolean static-branch API is currently supported. */
struct static_key { atomic_t enabled; };
struct static_key_false { struct static_key key; };
struct static_key_true { struct static_key key; };
#define STATIC_KEY_FALSE_INIT { .key = { .enabled = ATOMIC_INIT(0) } }
#define STATIC_KEY_TRUE_INIT { .key = { .enabled = ATOMIC_INIT(1) } }
#define DEFINE_STATIC_KEY_FALSE(name) struct static_key_false name = STATIC_KEY_FALSE_INIT
#define DEFINE_STATIC_KEY_TRUE(name) struct static_key_true name = STATIC_KEY_TRUE_INIT
#define DECLARE_STATIC_KEY_FALSE(name) extern struct static_key_false name
#define DECLARE_STATIC_KEY_TRUE(name) extern struct static_key_true name
#define static_branch_likely(p) likely(atomic_read_acquire(&(p)->key.enabled) > 0)
#define static_branch_unlikely(p) unlikely(atomic_read_acquire(&(p)->key.enabled) > 0)
#define static_branch_enable(p) atomic_set_release(&(p)->key.enabled, 1)
#define static_branch_disable(p) atomic_set_release(&(p)->key.enabled, 0)
#endif
