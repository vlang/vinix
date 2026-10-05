/* SPDX-License-Identifier: GPL-2.0-only */
#ifdef VINIX_LINUXKPI
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/bitops.h>
#include <linux/wait_bit.h>
#include <linux/cache.h>
#include <linux/ww_mutex.h>
#include <linux/completion.h>
#include "linuxkpi_wait_v_primitives.h"

#define VKW_MATCH_SIZE(view, native) _Static_assert(sizeof(struct view) == sizeof(struct native), #view " size")
#define VKW_MATCH_FIELD(view, native, field) _Static_assert(offsetof(struct view, field) == offsetof(struct native, field), #view "." #field " offset")
VKW_MATCH_SIZE(vkw_list, list_head);
VKW_MATCH_SIZE(vkw_wait_key, wait_bit_key);
VKW_MATCH_FIELD(vkw_wait_key, wait_bit_key, flags);
VKW_MATCH_FIELD(vkw_wait_key, wait_bit_key, bit_nr);
VKW_MATCH_FIELD(vkw_wait_key, wait_bit_key, timeout);
VKW_MATCH_SIZE(vkw_wait_entry, wait_queue_entry);
VKW_MATCH_FIELD(vkw_wait_entry, wait_queue_entry, flags);
VKW_MATCH_FIELD(vkw_wait_entry, wait_queue_entry, private);
VKW_MATCH_FIELD(vkw_wait_entry, wait_queue_entry, func);
VKW_MATCH_FIELD(vkw_wait_entry, wait_queue_entry, entry);
VKW_MATCH_SIZE(vkw_wait_queue, wait_queue_head);
VKW_MATCH_FIELD(vkw_wait_queue, wait_queue_head, lock);
VKW_MATCH_FIELD(vkw_wait_queue, wait_queue_head, head);
VKW_MATCH_SIZE(vkw_wait_bit, wait_bit_queue_entry);
VKW_MATCH_FIELD(vkw_wait_bit, wait_bit_queue_entry, key);
VKW_MATCH_FIELD(vkw_wait_bit, wait_bit_queue_entry, wq_entry);
VKW_MATCH_SIZE(vkw_mutex, mutex);
VKW_MATCH_FIELD(vkw_mutex, mutex, owner);
VKW_MATCH_FIELD(vkw_mutex, mutex, wait_lock);
VKW_MATCH_FIELD(vkw_mutex, mutex, wait_list);
VKW_MATCH_SIZE(vkw_ww_mutex, ww_mutex);
VKW_MATCH_FIELD(vkw_ww_mutex, ww_mutex, base);
VKW_MATCH_FIELD(vkw_ww_mutex, ww_mutex, ctx);
VKW_MATCH_SIZE(vkw_ww_ctx, ww_acquire_ctx);
VKW_MATCH_FIELD(vkw_ww_ctx, ww_acquire_ctx, task);
VKW_MATCH_FIELD(vkw_ww_ctx, ww_acquire_ctx, stamp);
VKW_MATCH_FIELD(vkw_ww_ctx, ww_acquire_ctx, acquired);
VKW_MATCH_FIELD(vkw_ww_ctx, ww_acquire_ctx, wounded);
VKW_MATCH_FIELD(vkw_ww_ctx, ww_acquire_ctx, is_wait_die);
VKW_MATCH_SIZE(vkw_swait_head, swait_queue_head);
VKW_MATCH_FIELD(vkw_swait_head, swait_queue_head, lock);
VKW_MATCH_FIELD(vkw_swait_head, swait_queue_head, task_list);
VKW_MATCH_SIZE(vkw_swait, swait_queue);
VKW_MATCH_FIELD(vkw_swait, swait_queue, task);
VKW_MATCH_FIELD(vkw_swait, swait_queue, task_list);
VKW_MATCH_SIZE(vkw_completion, completion);
VKW_MATCH_FIELD(vkw_completion, completion, done);
VKW_MATCH_FIELD(vkw_completion, completion, wait);
_Static_assert(BITS_PER_LONG == 64, "V wait hash uses the native 64-bit word");

/* Keep Linux's exact table alignment/section. Initialization and publication
 * are owned by V; this permanent storage never allocates per waiter. */
static wait_queue_head_t vkw_bit_wait_table[256] __cacheline_aligned;
void *vkw_wait_table(void) { return vkw_bit_wait_table; }
void vkw_wait_init(void *p) { init_waitqueue_head((wait_queue_head_t *)p); }
void vkw_wait_prepare(void *q, void *e, unsigned int s) { prepare_to_wait(q, e, s); }
void vkw_wait_prepare_exclusive(void *q, void *e, unsigned int s) { prepare_to_wait_exclusive(q, e, s); }
void vkw_wait_finish(void *q, void *e) { finish_wait(q, e); }
bool vkw_wait_active(void *q) { return waitqueue_active(q); }
void vkw_wait_wake(void *q, unsigned int m, int n, void *k) { __wake_up(q, m, n, k); }
int vkw_wait_autoremove(void *e, unsigned int m, int s, void *k) { return autoremove_wake_function(e, m, s, k); }
bool vkw_test_bit(int b, void *p) { return test_bit(b, p); }
bool vkw_test_bit_acquire(int b, void *p) { return test_bit_acquire(b, p); }
bool vkw_test_and_set_bit(int b, void *p) { return test_and_set_bit(b, p); }
int vinix_linuxkpi_var_wake_function(struct wait_queue_entry *, unsigned int, int, void *);
void *vkw_bit_wake_callback(void) { return wake_bit_function; }
void *vkw_var_wake_callback(void) { return vinix_linuxkpi_var_wake_function; }
bool vkw_signal_state(unsigned int state, void *task) { return signal_pending_state(state, task); }
void vkw_current_state(unsigned int state) { set_current_state(state); }
int vkw_wake_task(void *task) { return wake_up_process(task); }
int vkw_wake_state(void *task, unsigned int state) { return wake_up_state(task, state); }
bool vkw_irqs_disabled(void) { return irqs_disabled(); }
void vkw_spin_lock_irq(void *p) { raw_spin_lock_irq((raw_spinlock_t *)p); }
void vkw_spin_unlock_irq(void *p) { raw_spin_unlock_irq((raw_spinlock_t *)p); }
bool vkw_atomic_add_unless(void *p, int add, int unless) { return atomic_add_unless((atomic_t *)p, add, unless); }
bool vkw_atomic_dec_and_test(void *p) { return atomic_dec_and_test((atomic_t *)p); }
void *vkw_autoremove_callback(void) { return autoremove_wake_function; }
#endif
