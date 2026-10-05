/* SPDX-License-Identifier: GPL-2.0-only */
#ifdef VINIX_LINUXKPI
#include <pthread.h>
#ifdef VINIX_LINUXKPI_HOST_TEST
#undef CLOCKS_PER_SEC
#undef CLOCK_REALTIME
#undef CLOCK_MONOTONIC
#undef CLOCK_PROCESS_CPUTIME_ID
#undef CLOCK_THREAD_CPUTIME_ID
#undef CLOCK_MONOTONIC_RAW
#undef CLOCK_REALTIME_COARSE
#undef CLOCK_MONOTONIC_COARSE
#undef TIMER_ABSTIME
#endif
#include <linux/workqueue.h>
#include <linux/sched.h>
#include <linux/sched/task.h>
#include "linuxkpi_workqueue_v_primitives.h"
_Static_assert(WORK_STRUCT_FLAG_BITS == 8 && WORK_STRUCT_PENDING == 1 && WORK_STRUCT_INACTIVE == 2 && WORK_STRUCT_PWQ == 4, "V work data flags");
_Static_assert(WORK_STRUCT_NO_POOL == 0xfffffffe0UL && WORK_OFFQ_CANCELING == 16, "V off-queue work flags");
_Static_assert(WORK_CPU_UNBOUND == 256 && WQ_UNBOUND_MAX_ACTIVE == 512 && WQ_MAX_ACTIVE == 512 && WQ_DFL_ACTIVE == 256, "V pool limits");
_Static_assert(WQ_UNBOUND == 2 && WQ_HIGHPRI == 16 && __WQ_ORDERED == 131072 && __WQ_ORDERED_EXPLICIT == 524288, "V queue policies");
_Static_assert(sizeof(pthread_t) == sizeof(uint64_t), "V worker thread ABI");
struct vkw_list vkwq_running = { &vkwq_running, &vkwq_running };
struct vkw_list vkwq_canceling = { &vkwq_canceling, &vkwq_canceling };
struct vkw_list vkwq_all = { &vkwq_all, &vkwq_all };
struct workqueue_struct *system_wq, *system_highpri_wq, *system_unbound_wq;
void *vinix_linuxkpi_work_worker(void *);
void *vinix_linuxkpi_pool_manager(void *);
void vinix_linuxkpi_work_barrier(void *);
void *vkwq_worker_callback(void) { return vinix_linuxkpi_work_worker; }
void *vkwq_manager_callback(void) { return vinix_linuxkpi_pool_manager; }
void *vkwq_barrier_callback(void) { return vinix_linuxkpi_work_barrier; }
void *vkwq_delayed_callback(void) { return delayed_work_timer_fn; }
int vkwq_pthread_create(void *p, void *f, void *a) { return pthread_create(p, NULL, f, a); }
int vkwq_pthread_join(uint64_t id) { return pthread_join((pthread_t)(uintptr_t)id, NULL); }
void *vkwq_get_current(void) { return get_task_struct(current); }
void vkwq_put_task(void *p) { put_task_struct((struct task_struct *)p); }
unsigned int vkwq_task_state(void *p) { return __atomic_load_n(&((struct task_struct *)p)->__state, __ATOMIC_ACQUIRE); }
bool vkwq_current_running(void) { return task_is_running(current); }
#ifdef VINIX_LINUXKPI_HOST_TEST
void vinix_linuxkpi_host_worker_enter(void);
void vinix_linuxkpi_host_worker_leave(void);
void vinix_linuxkpi_host_delayed_timer_gate(struct timer_list *);
void vinix_linuxkpi_host_pool_publish_gate(struct workqueue_struct *, unsigned int);
void vkwq_worker_enter(void) { vinix_linuxkpi_host_worker_enter(); }
void vkwq_worker_leave(void) { vinix_linuxkpi_host_worker_leave(); }
void vkwq_delayed_gate(void *p) { vinix_linuxkpi_host_delayed_timer_gate(p); }
void vkwq_publish_gate(void *q, unsigned int cpu) { vinix_linuxkpi_host_pool_publish_gate(q, cpu); }
int vsnprintf(char *, size_t, const char *, va_list);
#else
void vkwq_worker_enter(void) {}
void vkwq_worker_leave(void) { pthread_exit(NULL); }
void vkwq_delayed_gate(void *p) { (void)p; }
void vkwq_publish_gate(void *q, unsigned int cpu) { (void)q; (void)cpu; }
int npf_vsnprintf(char *, size_t, const char *, va_list);
#endif
void vkwq_warn_queue_cpu(bool invalid) { WARN_ON_ONCE(invalid); }
void vkwq_warn_delayed_cpu(bool invalid) { WARN_ON_ONCE(invalid); }
void vkwq_warn_mod_cpu(bool invalid) { WARN_ON_ONCE(invalid); }
void vkwq_warn_limit(void) { WARN_ON_ONCE(true); }
void *vinix_linuxkpi_workqueue_allocate(unsigned int, int);
char *vinix_linuxkpi_workqueue_name(void *);
void *vinix_linuxkpi_workqueue_start(void *);
/* Native va_list access stays at this ABI entry point. Validation, allocation,
 * worker startup/rollback, ownership and queue policy are all V. */
struct workqueue_struct *alloc_workqueue(const char *fmt, unsigned int flags, int max_active, ...)
{
    void *queue = vinix_linuxkpi_workqueue_allocate(flags, max_active);
    if (!queue) return NULL;
    va_list arguments;
    va_start(arguments, max_active);
#ifdef VINIX_LINUXKPI_HOST_TEST
    vsnprintf(vinix_linuxkpi_workqueue_name(queue), 32, fmt, arguments);
#else
    npf_vsnprintf(vinix_linuxkpi_workqueue_name(queue), 32, fmt, arguments);
#endif
    va_end(arguments);
    return vinix_linuxkpi_workqueue_start(queue);
}
#endif
