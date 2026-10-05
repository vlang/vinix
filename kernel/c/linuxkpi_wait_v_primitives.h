/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_WAIT_V_PRIMITIVES_H
#define VINIX_LINUXKPI_WAIT_V_PRIMITIVES_H
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

/* Narrow ABI views, checked against the unchanged Linux layouts in the
 * binding translation unit. The generated V blob need not import Linux. */
struct vkw_list { struct vkw_list *next, *prev; };
struct vkw_wait_key { void *flags; int bit_nr; unsigned long timeout; };
struct vkw_wait_entry {
    unsigned int flags;
    void *private;
    int (*func)(void *, unsigned int, int, void *);
    struct vkw_list entry;
};
struct vkw_wait_queue { unsigned int lock; struct vkw_list head; };
struct vkw_wait_bit { struct vkw_wait_key key; struct vkw_wait_entry wq_entry; };
struct vkw_mutex { long owner; unsigned int wait_lock; struct vkw_list wait_list; };
struct vkw_ww_mutex { struct vkw_mutex base; void *ctx; };
struct vkw_ww_ctx {
    void *task;
    unsigned long stamp;
    unsigned int acquired;
    unsigned short wounded, is_wait_die;
};
struct vkw_swait_head { unsigned int lock; struct vkw_list task_list; };
struct vkw_swait { void *task; struct vkw_list task_list; };
struct vkw_completion { unsigned int done; struct vkw_swait_head wait; };

void *vkw_wait_table(void);
void vkw_wait_init(void *);
void vkw_wait_prepare(void *, void *, unsigned int);
void vkw_wait_prepare_exclusive(void *, void *, unsigned int);
void vkw_wait_finish(void *, void *);
bool vkw_wait_active(void *);
void vkw_wait_wake(void *, unsigned int, int, void *);
int vkw_wait_autoremove(void *, unsigned int, int, void *);
bool vkw_test_bit(int, void *);
bool vkw_test_bit_acquire(int, void *);
bool vkw_test_and_set_bit(int, void *);
void *vkw_bit_wake_callback(void);
void *vkw_var_wake_callback(void);
bool vkw_signal_state(unsigned int, void *);
void vkw_current_state(unsigned int);
int vkw_wake_task(void *);
int vkw_wake_state(void *, unsigned int);
bool vkw_irqs_disabled(void);
void vkw_spin_lock_irq(void *);
void vkw_spin_unlock_irq(void *);
bool vkw_atomic_add_unless(void *, int, int);
bool vkw_atomic_dec_and_test(void *);
void *vkw_autoremove_callback(void);

#ifdef VINIX_V_RUNTIME
void wait_bit_init(void);
void *bit_waitqueue(void *, int);
void *__var_waitqueue(void *);
int wake_bit_function(void *, unsigned int, int, void *);
int vinix_linuxkpi_var_wake_function(void *, unsigned int, int, void *);
void init_wait_var_entry(void *, void *, int);
int __wait_on_bit(void *, void *, int (*)(void *, int), unsigned int);
int __wait_on_bit_lock(void *, void *, int (*)(void *, int), unsigned int);
int out_of_line_wait_on_bit(void *, int, int (*)(void *, int), unsigned int);
int out_of_line_wait_on_bit_timeout(void *, int, int (*)(void *, int), unsigned int, uint64_t);
int out_of_line_wait_on_bit_lock(void *, int, int (*)(void *, int), unsigned int);
void __wake_up_bit(void *, void *, int);
void wake_up_bit(void *, int);
void wake_up_var(void *);
int bit_wait(void *, int);
int bit_wait_timeout(void *, int);
int ww_mutex_lock(void *, void *);
int ww_mutex_lock_interruptible(void *, void *);
int ww_mutex_trylock(void *, void *);
void ww_mutex_unlock(void *);
void __mutex_init(void *, char *, void *);
bool mutex_is_locked(void *);
void mutex_destroy(void *);
void mutex_lock(void *);
void mutex_lock_io(void *);
int mutex_lock_interruptible(void *);
int mutex_lock_killable(void *);
int mutex_trylock(void *);
void mutex_unlock(void *);
int atomic_dec_and_mutex_lock(void *, void *);
void __init_waitqueue_head(void *, char *, void *);
void add_wait_queue(void *, void *);
void add_wait_queue_exclusive(void *, void *);
void add_wait_queue_priority(void *, void *);
void remove_wait_queue(void *, void *);
int __wake_up(void *, unsigned int, int, void *);
void __wake_up_locked(void *, unsigned int, int);
void __wake_up_locked_key(void *, unsigned int, void *);
int default_wake_function(void *, unsigned int, int, void *);
int autoremove_wake_function(void *, unsigned int, int, void *);
void init_wait_entry(void *, int);
void prepare_to_wait(void *, void *, int);
bool prepare_to_wait_exclusive(void *, void *, int);
int64_t prepare_to_wait_event(void *, void *, int);
void finish_wait(void *, void *);
void __init_swait_queue_head(void *, char *, void *);
void swake_up_locked(void *, int);
void swake_up_all_locked(void *);
void swake_up_one(void *);
void swake_up_all(void *);
void __prepare_to_swait(void *, void *);
void prepare_to_swait_exclusive(void *, void *, int);
int64_t prepare_to_swait_event(void *, void *, int);
void __finish_swait(void *, void *);
void finish_swait(void *, void *);
void complete(void *);
void complete_all(void *);
int wait_for_completion_state(void *, unsigned int);
void wait_for_completion(void *);
int wait_for_completion_interruptible(void *);
int wait_for_completion_killable(void *);
uint64_t wait_for_completion_timeout(void *, uint64_t);
int64_t wait_for_completion_interruptible_timeout(void *, uint64_t);
int64_t wait_for_completion_killable_timeout(void *, uint64_t);
bool try_wait_for_completion(void *);
bool completion_done(void *);
#endif
#endif
