/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_SRCU_V_PRIMITIVES_H
#define VINIX_LINUXKPI_SRCU_V_PRIMITIVES_H
#include "linuxkpi_wait_v_primitives.h"
/* Exact pinned ABI views. The binding checks every accessed field and type
 * alignment, while the main generated V blob avoids broad Linux headers. */
struct vks_rcu_head { struct vks_rcu_head *next; void (*func)(struct callback_head *); };
struct vks_cblist {
    struct vks_rcu_head *head, **tails[4];
    unsigned long gp_seq[4];
    long len, seglen[4];
    unsigned char flags;
};
struct vks_work { long data; struct vkw_list entry; void (*func)(struct work_struct *); };
struct vks_timer {
    void *next, *pprev;
    unsigned long expires;
    void (*function)(struct timer_list *);
    unsigned int flags;
};
struct vks_delayed_work {
    struct vks_work work;
    struct vks_timer timer;
    void *wq;
    int cpu;
};
struct vks_srcu_data {
    long srcu_lock_count[2], srcu_unlock_count[2];
    int srcu_nmi_safety;
    unsigned int lock __attribute__((aligned(64)));
    struct vks_cblist srcu_cblist;
    unsigned long srcu_gp_seq_needed, srcu_gp_seq_needed_exp;
    bool srcu_cblist_invoking;
    struct vks_timer delay_work;
    struct vks_work work;
    struct vks_rcu_head srcu_barrier_head;
    void *mynode;
    unsigned long grpmask;
    int cpu;
    void *ssp;
};
struct vks_srcu_usage {
    void *node, *level[3];
    int srcu_size_state;
    struct vkw_mutex srcu_cb_mutex;
    unsigned int lock;
    struct vkw_mutex srcu_gp_mutex;
    unsigned long srcu_gp_seq, srcu_gp_seq_needed, srcu_gp_seq_needed_exp;
    unsigned long srcu_gp_start, srcu_last_gp_end, srcu_size_jiffies;
    unsigned long srcu_n_lock_retries, srcu_n_exp_nodelay;
    bool sda_is_static;
    unsigned long srcu_barrier_seq;
    struct vkw_mutex srcu_barrier_mutex;
    struct vkw_completion srcu_barrier_completion;
    int srcu_barrier_cpu_cnt;
    unsigned long reschedule_jiffies, reschedule_count;
    struct vks_delayed_work work;
    void *srcu_ssp;
};
struct vks_srcu { unsigned int srcu_idx; void *sda, *srcu_sup; };

void vks_init_work(void *, void *);
void vks_init_delayed_work(void *, void *);
void *vks_gp_callback(void);
void *vks_cblist_callback(void);
bool vks_unbound_ready(void);
void vks_preempt_disable(void);
void vks_preempt_enable(void);
unsigned int vks_preempt_count(void);
unsigned int vks_cpu_id(void);
size_t vks_data_alignment(void);
bool vks_queue_work(void *, void *);
bool vks_queue_delayed_work(void *, void *, unsigned long);
#ifdef VINIX_V_RUNTIME
void *alloc_workqueue(char *, unsigned int, int, ...);
bool cancel_delayed_work_sync(void *);
bool flush_work(void *);
bool cancel_work_sync(void *);
void destroy_workqueue(void *);
void msleep(unsigned int);
int vinix_linuxkpi_srcu_bootstrap(void);
void srcu_init(void);
int init_srcu_struct(void *);
int __srcu_read_lock(void *);
void __srcu_read_unlock(void *, int);
void call_srcu(void *, void *, void (*)(struct callback_head *));
void vinix_linuxkpi_srcu_gp_work(struct work_struct *);
void vinix_linuxkpi_srcu_callback_work(struct work_struct *);
uint64_t get_state_synchronize_srcu(void *);
uint64_t start_poll_synchronize_srcu(void *);
bool poll_state_synchronize_srcu(void *, uint64_t);
void synchronize_srcu(void *);
void synchronize_srcu_expedited(void *);
void srcu_barrier(void *);
void cleanup_srcu_struct(void *);
int vinix_linuxkpi_srcu_bootstrap_limit_for_test(unsigned int);
void *vinix_linuxkpi_srcu_queue_for_test(void);
void vinix_linuxkpi_srcu_shutdown_for_test(void);
void vinix_linuxkpi_srcu_static_quiesce_for_test(void *);
#endif
#endif
