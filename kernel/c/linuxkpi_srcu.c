/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef VINIX_LINUXKPI
#include <linux/srcu.h>
#include <linux/percpu.h>
#include <linux/slab.h>
#include <linux/sched.h>
#include <linux/delay.h>
#include <linux/errno.h>

/* The public layouts and static initializers are the pinned Linux ones.
 * Native SRCU keeps the small-domain representation: counters on every CPU,
 * one callback FIFO in CPU 0's srcu_data, and the original embedded GP and
 * callback work items on one private boot-lifetime unbound workqueue.
 * There is no per-reader, per-callback or lazy-static allocation, and no
 * private thread whose stack would be retained for each domain.
 *
 * The combining-tree fields are unused. In that representation, CPU 0's
 * srcu_gp_seq_needed is the registered callback sequence and CPU 0's
 * srcu_gp_seq_needed_exp is the callback-ready sequence. The usage's
 * srcu_barrier_seq is the completed callback sequence. srcu_barrier_cpu_cnt
 * indicates the single barrier waiter serialized by srcu_barrier_mutex.
 * The domain gp_seq/needed fields retain Linux's two-bit GP encoding.
 */
static struct workqueue_struct *srcu_workqueue;
static void native_srcu_work(struct work_struct *work);
static void native_srcu_callbacks(struct work_struct *work);

static bool sequence_done(unsigned long observed, unsigned long target)
{
    /* Like Linux's ULONG_CMP_GE: outstanding operations must remain less
     * than half the sequence space. Counters may wrap without going stale. */
    return (long)(observed - target) >= 0;
}
static unsigned long sequence_snapshot(unsigned long sequence)
{
    return (sequence + 7UL) & ~3UL;
}
static void sequence_request(unsigned long *needed, unsigned long target)
{
    if (!sequence_done(*needed, target)) *needed = target;
}
static struct srcu_data *callback_data(struct srcu_struct *ssp)
{
    return per_cpu_ptr(ssp->sda, 0);
}
static void init_callback_list(struct rcu_segcblist *list)
{
    list->head = NULL;
    for (unsigned int segment = 0; segment < RCU_CBLIST_NSEGS; segment++) {
        list->tails[segment] = &list->head;
        list->gp_seq[segment] = 0;
        list->seglen[segment] = 0;
    }
    list->len = 0;
    list->flags = 0;
}
static void initialize_usage(struct srcu_struct *ssp, struct srcu_usage *sup,
                              struct srcu_data __percpu *data, bool is_static)
{
    /* Static read-side counters can already contain readers. Never clear
     * srcu_data wholesale, replace its allocation, or reset srcu_idx here. */
    sup->node = NULL;
    for (unsigned int level = 0; level < ARRAY_SIZE(sup->level); level++)
        sup->level[level] = NULL;
    sup->srcu_size_state = SRCU_SIZE_SMALL;
    mutex_init(&sup->srcu_cb_mutex);
    mutex_init(&sup->srcu_gp_mutex);
    mutex_init(&sup->srcu_barrier_mutex);
    init_completion(&sup->srcu_barrier_completion);
    atomic_set(&sup->srcu_barrier_cpu_cnt, 0);
    sup->srcu_gp_seq = 0;
    sup->srcu_gp_seq_needed_exp = 0;
    sup->srcu_barrier_seq = 0;
    sup->sda_is_static = is_static;
    sup->srcu_ssp = ssp;
    INIT_DELAYED_WORK(&sup->work, native_srcu_work);
    for (unsigned int cpu = 0; cpu < vinix_linuxkpi_percpu_count(); cpu++) {
        struct srcu_data *sdp = per_cpu_ptr(data, cpu);
        spin_lock_init(&sdp->lock);
        init_callback_list(&sdp->srcu_cblist);
        sdp->srcu_cblist_invoking = false;
        sdp->srcu_gp_seq_needed = 0;
        sdp->srcu_gp_seq_needed_exp = 0;
        INIT_WORK(&sdp->work, native_srcu_callbacks);
        sdp->mynode = NULL;
        sdp->grpmask = 0;
        sdp->cpu = cpu;
        sdp->ssp = ssp;
    }
    /* -1 is the actual upstream static initializer's lazy-init sentinel.
     * Publishing this last also makes the initialized updater visible. */
    __atomic_store_n(&sup->srcu_gp_seq_needed, 0UL, __ATOMIC_RELEASE);
}
static struct srcu_usage *initialized_usage(struct srcu_struct *ssp)
{
    struct srcu_usage *sup = __atomic_load_n(&ssp->srcu_sup, __ATOMIC_ACQUIRE);
    BUG_ON(!sup || !ssp->sda);
    if (__atomic_load_n(&sup->srcu_gp_seq_needed, __ATOMIC_ACQUIRE) != ~0UL)
        return sup;
    unsigned long flags;
    raw_spin_lock_irqsave(&sup->lock, flags);
    if (sup->srcu_gp_seq_needed == ~0UL)
        initialize_usage(ssp, sup, ssp->sda, true);
    raw_spin_unlock_irqrestore(&sup->lock, flags);
    return sup;
}

static int bootstrap_srcu(unsigned int active_limit)
{
    might_sleep();
    /* Bootstrap/shutdown are serialized by the boot owner. Static readers
     * do not depend on this queue. Two active slots let a GP advance while
     * its separate callback dispatcher is still executing a callback. */
    BUG_ON(!system_unbound_wq || !vinix_linuxkpi_percpu_count());
    if (__atomic_load_n(&srcu_workqueue, __ATOMIC_ACQUIRE)) return 0;
    struct workqueue_struct *queue = alloc_workqueue("linuxkpi-srcu", WQ_UNBOUND, active_limit);
    if (!queue) return -ENOMEM;
    __atomic_store_n(&srcu_workqueue, queue, __ATOMIC_RELEASE);
    return 0;
}
int vinix_linuxkpi_srcu_bootstrap(void)
{
    return bootstrap_srcu(0);
}
void srcu_init(void)
{
    BUG_ON(vinix_linuxkpi_srcu_bootstrap());
}
int init_srcu_struct(struct srcu_struct *ssp)
{
    might_sleep();
    BUG_ON(!ssp);
    /* Initialization requires an unpublished, quiescent object, as in Linux.
     * Keep failure results empty and retryable instead of dangling pointers. */
    ssp->srcu_idx = 0;
    ssp->sda = NULL;
    ssp->srcu_sup = NULL;
    struct srcu_usage *sup = kzalloc(sizeof(*sup), GFP_KERNEL);
    if (!sup) return -ENOMEM;
    struct srcu_data __percpu *data = alloc_percpu(struct srcu_data);
    if (!data) { kfree(sup); return -ENOMEM; }
    spin_lock_init(&sup->lock);
    initialize_usage(ssp, sup, data, false);
    __atomic_store_n(&ssp->sda, data, __ATOMIC_RELEASE);
    __atomic_store_n(&ssp->srcu_sup, sup, __ATOMIC_RELEASE);
    return 0;
}

int __srcu_read_lock(struct srcu_struct *ssp)
{
    BUG_ON(!ssp || !ssp->sda);
    preempt_disable();
    int index = __atomic_load_n(&ssp->srcu_idx, __ATOMIC_RELAXED) & 1;
    struct srcu_data *sdp = per_cpu_ptr(ssp->sda, vinix_linuxkpi_cpu_id());
    atomic_long_inc(&sdp->srcu_lock_count[index]);
    smp_mb(); /* Count registration precedes every protected access. */
    preempt_enable();
    return index;
}
void __srcu_read_unlock(struct srcu_struct *ssp, int index)
{
    BUG_ON(!ssp || !ssp->sda || (index & ~1));
    smp_mb(); /* Every protected access precedes reader completion. */
    preempt_disable();
    struct srcu_data *sdp = per_cpu_ptr(ssp->sda, vinix_linuxkpi_cpu_id());
    /* A sleeping reader may have migrated. Count this CPU's unlock; only
     * the domain-wide sums, not a per-CPU subtraction, determine quiescence. */
    atomic_long_inc(&sdp->srcu_unlock_count[index]);
    preempt_enable();
}
static bool readers_done(struct srcu_struct *ssp, unsigned int index)
{
    unsigned long unlocks = 0, locks = 0;
    for (unsigned int cpu = 0; cpu < vinix_linuxkpi_percpu_count(); cpu++)
        unlocks += (unsigned long)atomic_long_read(
            &per_cpu_ptr(ssp->sda, cpu)->srcu_unlock_count[index]);
    smp_mb(); /* Linux's unlock-first scan cannot count an uncounted lock. */
    for (unsigned int cpu = 0; cpu < vinix_linuxkpi_percpu_count(); cpu++)
        locks += (unsigned long)atomic_long_read(
            &per_cpu_ptr(ssp->sda, cpu)->srcu_lock_count[index]);
    return locks == unlocks;
}
static struct workqueue_struct *updater_queue(void)
{
    struct workqueue_struct *queue = __atomic_load_n(&srcu_workqueue, __ATOMIC_ACQUIRE);
    BUG_ON(!queue);
    return queue;
}
static void kick_updater(struct srcu_usage *sup)
{
    /* Coalesce an already queued or timer-reserved scan. A new request need
     * not cancel its pending one-tick retry; neither path allocates. */
    queue_delayed_work(updater_queue(), &sup->work, 0);
}
void call_srcu(struct srcu_struct *ssp, struct rcu_head *head, rcu_callback_t function)
{
    BUG_ON(!head || !function);
    struct srcu_usage *sup = initialized_usage(ssp);
    unsigned long flags;
    smp_mb();
    raw_spin_lock_irqsave(&sup->lock, flags);
    struct srcu_data *sdp = callback_data(ssp);
    struct rcu_segcblist *list = &sdp->srcu_cblist;
    BUG_ON(list->len == LONG_MAX);
    head->next = NULL;
    head->func = function;
    *list->tails[RCU_NEXT_TAIL] = head;
    list->tails[RCU_NEXT_TAIL] = &head->next;
    list->len++;
    sdp->srcu_gp_seq_needed++;
    sequence_request(&sup->srcu_gp_seq_needed, sequence_snapshot(sup->srcu_gp_seq));
    kick_updater(sup);
    raw_spin_unlock_irqrestore(&sup->lock, flags);
}
static void native_srcu_work(struct work_struct *work)
{
    struct srcu_usage *sup = container_of(to_delayed_work(work), struct srcu_usage, work);
    struct srcu_struct *ssp = sup->srcu_ssp;
    struct srcu_data *sdp = callback_data(ssp);
    unsigned long flags;
    raw_spin_lock_irqsave(&sup->lock, flags);
    unsigned long sequence = sup->srcu_gp_seq;
    if (!(sequence & 3UL)) {
        if (sequence_done(sequence, sup->srcu_gp_seq_needed)) {
            raw_spin_unlock_irqrestore(&sup->lock, flags);
            return;
        }
        /* The callback FIFO stays linked. Its registration-count boundary
         * survives deferred scans; later arrivals await another full GP. */
        sdp->srcu_cblist.gp_seq[RCU_WAIT_TAIL] = sdp->srcu_gp_seq_needed;
        sequence++;
        __atomic_store_n(&sup->srcu_gp_seq, sequence, __ATOMIC_RELEASE);
    }
    raw_spin_unlock_irqrestore(&sup->lock, flags);

    /* Never occupy an active worker slot waiting for a reader. The phase is
     * persistent in gp_seq and each unsuccessful scan reserves a timer, then
     * returns. Embedded work never overlaps itself, including immediate kicks
     * racing a deferred retry, so its flip is performed exactly once. */
    unsigned int index = __atomic_load_n(&ssp->srcu_idx, __ATOMIC_RELAXED) & 1;
    if ((sequence & 3UL) == SRCU_STATE_SCAN1) {
        if (!readers_done(ssp, index ^ 1)) goto retry;
        smp_mb();
        __atomic_add_fetch(&ssp->srcu_idx, 1U, __ATOMIC_RELAXED);
        smp_mb();
        raw_spin_lock_irqsave(&sup->lock, flags);
        sequence++;
        __atomic_store_n(&sup->srcu_gp_seq, sequence, __ATOMIC_RELEASE);
        raw_spin_unlock_irqrestore(&sup->lock, flags);
        index ^= 1;
    }
    BUG_ON((sequence & 3UL) != SRCU_STATE_SCAN2);
    if (!readers_done(ssp, index ^ 1)) goto retry;
    smp_mb();
    raw_spin_lock_irqsave(&sup->lock, flags);
    unsigned long completed = (sequence & ~3UL) + 4UL;
    __atomic_store_n(&sup->srcu_gp_seq, completed, __ATOMIC_RELEASE);
    sequence_request(&sdp->srcu_gp_seq_needed_exp,
                     sdp->srcu_cblist.gp_seq[RCU_WAIT_TAIL]);
    if (!sequence_done(sup->srcu_barrier_seq, sdp->srcu_gp_seq_needed_exp))
        queue_work(updater_queue(), &sdp->work);
    if (!sequence_done(completed, sup->srcu_gp_seq_needed)) kick_updater(sup);
    raw_spin_unlock_irqrestore(&sup->lock, flags);
    return;
retry:
    /* A producer may already have queued an immediate next run. A false
     * return means that pending run will advance this same persistent phase. */
    queue_delayed_work(updater_queue(), &sup->work, 1);
}
static void native_srcu_callbacks(struct work_struct *work)
{
    struct srcu_data *sdp = container_of(work, struct srcu_data, work);
    struct srcu_usage *sup = sdp->ssp->srcu_sup;
    unsigned long flags;
    raw_spin_lock_irqsave(&sup->lock, flags);
    unsigned long target = sdp->srcu_gp_seq_needed_exp;
    sdp->srcu_cblist_invoking = true;
    while (!sequence_done(sup->srcu_barrier_seq, target)) {
        struct rcu_segcblist *list = &sdp->srcu_cblist;
        struct rcu_head *head = list->head;
        BUG_ON(!head || !list->len);
        list->head = head->next;
        if (!list->head) list->tails[RCU_NEXT_TAIL] = &list->head;
        rcu_callback_t function = head->func;
        head->next = NULL;
        raw_spin_unlock_irqrestore(&sup->lock, flags);
        BUG_ON(!vinix_linuxkpi_may_sleep());
        preempt_disable();
        function(head); /* May free/requeue head; never access it again. */
        BUG_ON(preempt_count() != 1 || irqs_disabled());
        preempt_enable();
        raw_spin_lock_irqsave(&sup->lock, flags);
        BUG_ON(!list->len);
        list->len--;
        sup->srcu_barrier_seq++;
        if (atomic_read(&sup->srcu_barrier_cpu_cnt))
            complete(&sup->srcu_barrier_completion);
    }
    sdp->srcu_cblist_invoking = false;
    if (!sequence_done(sup->srcu_barrier_seq, sdp->srcu_gp_seq_needed_exp))
        queue_work(updater_queue(), &sdp->work);
    raw_spin_unlock_irqrestore(&sup->lock, flags);
}

unsigned long get_state_synchronize_srcu(struct srcu_struct *ssp)
{
    struct srcu_usage *sup = initialized_usage(ssp);
    smp_mb();
    unsigned long sequence = __atomic_load_n(&sup->srcu_gp_seq, __ATOMIC_ACQUIRE);
    unsigned long cookie = sequence_snapshot(sequence);
    smp_mb();
    return cookie;
}
unsigned long start_poll_synchronize_srcu(struct srcu_struct *ssp)
{
    struct srcu_usage *sup = initialized_usage(ssp);
    unsigned long flags;
    smp_mb();
    raw_spin_lock_irqsave(&sup->lock, flags);
    unsigned long cookie = sequence_snapshot(sup->srcu_gp_seq);
    sequence_request(&sup->srcu_gp_seq_needed, cookie);
    kick_updater(sup);
    raw_spin_unlock_irqrestore(&sup->lock, flags);
    return cookie;
}
bool poll_state_synchronize_srcu(struct srcu_struct *ssp, unsigned long cookie)
{
    struct srcu_usage *sup = initialized_usage(ssp);
    if (!sequence_done(__atomic_load_n(&sup->srcu_gp_seq, __ATOMIC_ACQUIRE), cookie))
        return false;
    smp_mb();
    return true;
}
static void synchronize_domain(struct srcu_struct *ssp, bool expedited)
{
    might_sleep();
    struct srcu_usage *sup = initialized_usage(ssp);
    unsigned long flags;
    smp_mb();
    raw_spin_lock_irqsave(&sup->lock, flags);
    unsigned long cookie = sequence_snapshot(sup->srcu_gp_seq);
    sequence_request(&sup->srcu_gp_seq_needed, cookie);
    if (expedited) sequence_request(&sup->srcu_gp_seq_needed_exp, cookie);
    kick_updater(sup);
    raw_spin_unlock_irqrestore(&sup->lock, flags);
    while (!poll_state_synchronize_srcu(ssp, cookie)) msleep(1);
    smp_mb();
}
void synchronize_srcu(struct srcu_struct *ssp)
{
    synchronize_domain(ssp, false);
}
void synchronize_srcu_expedited(struct srcu_struct *ssp)
{
    /* The native backend supplies the same correct full grace period. It has
     * no separate expedited retry interval or scheduling latency guarantee. */
    synchronize_domain(ssp, true);
}
void srcu_barrier(struct srcu_struct *ssp)
{
    might_sleep();
    struct srcu_usage *sup = initialized_usage(ssp);
    unsigned long flags;
    smp_mb();
    raw_spin_lock_irqsave(&sup->lock, flags);
    /* Snapshot before serializing waiters. This includes detached/executing
     * callbacks and excludes submissions after this caller's boundary. */
    unsigned long target = callback_data(ssp)->srcu_gp_seq_needed;
    raw_spin_unlock_irqrestore(&sup->lock, flags);
    mutex_lock(&sup->srcu_barrier_mutex);
    raw_spin_lock_irqsave(&sup->lock, flags);
    while (!sequence_done(sup->srcu_barrier_seq, target)) {
        reinit_completion(&sup->srcu_barrier_completion);
        atomic_set(&sup->srcu_barrier_cpu_cnt, 1);
        raw_spin_unlock_irqrestore(&sup->lock, flags);
        wait_for_completion(&sup->srcu_barrier_completion);
        raw_spin_lock_irqsave(&sup->lock, flags);
        atomic_set(&sup->srcu_barrier_cpu_cnt, 0);
    }
    raw_spin_unlock_irqrestore(&sup->lock, flags);
    mutex_unlock(&sup->srcu_barrier_mutex);
    smp_mb();
}
static void quiesce_domain(struct srcu_struct *ssp, struct srcu_usage *sup)
{
    /* The owner has already stopped readers, producers and other API users.
     * A requested full GP finishes any earlier deferred scan. GP completion
     * and barrier completion can both precede their work callbacks' return. */
    BUG_ON(!readers_done(ssp, 0) || !readers_done(ssp, 1));
    synchronize_srcu(ssp);
    srcu_barrier(ssp);
    cancel_delayed_work_sync(&sup->work);
    struct srcu_data *sdp = callback_data(ssp);
    flush_work(&sdp->work);
    cancel_work_sync(&sdp->work);
    BUG_ON(!readers_done(ssp, 0) || !readers_done(ssp, 1));
    BUG_ON(sdp->srcu_cblist.len || sdp->srcu_cblist.head || sdp->srcu_cblist_invoking ||
           (sup->srcu_gp_seq & 3UL) ||
           !sequence_done(sup->srcu_gp_seq, sup->srcu_gp_seq_needed));
}
void cleanup_srcu_struct(struct srcu_struct *ssp)
{
    might_sleep();
    BUG_ON(!ssp);
    if (!ssp->srcu_sup) { BUG_ON(ssp->sda); return; }
    struct srcu_usage *sup = initialized_usage(ssp);
    BUG_ON(sup->sda_is_static); /* Upstream explicitly forbids static cleanup. */
    quiesce_domain(ssp, sup);
    struct srcu_data __percpu *data = ssp->sda;
    ssp->sda = NULL;
    ssp->srcu_sup = NULL;
    free_percpu(data);
    kfree(sup);
}
#ifdef VINIX_LINUXKPI_HOST_TEST
int vinix_linuxkpi_srcu_bootstrap_limit_for_test(unsigned int active_limit)
{
    BUG_ON(active_limit < 2 || active_limit > WQ_UNBOUND_MAX_ACTIVE);
    return bootstrap_srcu(active_limit);
}
struct workqueue_struct *vinix_linuxkpi_srcu_queue_for_test(void)
{
    return updater_queue();
}
void vinix_linuxkpi_srcu_shutdown_for_test(void)
{
    /* Every domain and its users must already be quiescent. The private
     * queue has boot lifetime in the native kernel and is reclaimed only by
     * the isolated host fixture after all domains finish. */
    struct workqueue_struct *queue = __atomic_load_n(&srcu_workqueue, __ATOMIC_ACQUIRE);
    if (!queue) return;
    destroy_workqueue(queue);
    __atomic_store_n(&srcu_workqueue, NULL, __ATOMIC_RELEASE);
}
void vinix_linuxkpi_srcu_static_quiesce_for_test(struct srcu_struct *ssp)
{
    struct srcu_usage *sup = initialized_usage(ssp);
    BUG_ON(!sup->sda_is_static);
    quiesce_domain(ssp, sup);
}
#endif
#endif
