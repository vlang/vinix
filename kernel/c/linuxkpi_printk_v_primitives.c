/* SPDX-License-Identifier: GPL-2.0-only */
#ifdef VINIX_LINUXKPI
#include <linux/printk.h>
#include <linux/sched/task.h>
#include <linux/mutex.h>
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/jiffies.h>
#include <vinix/format.h>
#include <vinix/printk.h>
#include <pthread.h>
#include "linuxkpi_runtime_v_primitives.h"
/* Native header initializers and thread handles, without queue policy. */
int console_printk[4] = { CONSOLE_LOGLEVEL_DEFAULT, MESSAGE_LOGLEVEL_DEFAULT,
    CONSOLE_LOGLEVEL_MIN, CONSOLE_LOGLEVEL_DEFAULT };
int suppress_printk;
int oops_in_progress;
static DEFINE_MUTEX(vkr_log_mutex);
static DECLARE_COMPLETION(vkr_log_completion);
static pthread_t vkr_log_thread;
_Static_assert(sizeof(raw_spinlock_t) == 4, "V logger raw-spin storage");
_Static_assert(sizeof(struct vinix_linuxkpi_printk_record) == 1048 &&
    offsetof(struct vinix_linuxkpi_printk_record, text) == 24,
    "V owned logger record ABI");
_Static_assert(sizeof(struct vinix_linuxkpi_printk_state) == 48, "V logger state ABI");
void *vkr_log_lifecycle(void) { return &vkr_log_mutex; }
void *vkr_log_ready(void) { return &vkr_log_completion; }
void vkr_log_reinit(void *p) { reinit_completion(p); }
void vkr_log_complete(void *p) { complete(p); }
void vkr_log_wait(void *p) { wait_for_completion(p); }
void *vkr_log_current_get(void) { return get_task_struct(current); }
void vkr_log_task_put(void *p) { put_task_struct(p); }
int vkr_log_create(void *(*worker)(void *), void *p) { return pthread_create(&vkr_log_thread, NULL, worker, p); }
int vkr_log_join(void) { return pthread_join(vkr_log_thread, NULL); }
void vkr_log_exit(void) { pthread_exit(NULL); }
void vkr_log_host_enter(void) {
#ifdef VINIX_LINUXKPI_HOST_TEST
    extern void vinix_linuxkpi_host_logger_enter(void);
    vinix_linuxkpi_host_logger_enter();
#endif
}
void vkr_log_host_leave(void) {
#ifdef VINIX_LINUXKPI_HOST_TEST
    extern void vinix_linuxkpi_host_logger_leave(void);
    vinix_linuxkpi_host_logger_leave();
#endif
}
int vkr_log_suppress(void) { return READ_ONCE(suppress_printk); }
int vkr_log_console(unsigned int index) { return READ_ONCE(console_printk[index]); }
void vkr_log_call_sink(void *sink, void *record, void *arg) { ((vinix_linuxkpi_printk_sink)sink)(record, arg); }
void vkr_log_write(void *text, size_t size) { vinix_linuxkpi_log_write(text, size); }
bool vkr_log_key(void *key) { return vinix_linuxkpi_log_key(key); }
extern int vkr_log_emit(int, int, void *, char *, void *);
int vprintk_emit(int facility, int level, const struct dev_printk_info *dev,
    const char *fmt, va_list args)
{
    return vkr_log_emit(facility, level, (void *)dev, (char *)fmt, VKR_VA_PARAMETER(args));
}
int vprintk(const char *fmt, va_list args) { return vprintk_emit(0, LOGLEVEL_DEFAULT, NULL, fmt, args); }
int _printk(const char *fmt, ...)
{
    va_list args; va_start(args, fmt);
    int count = vprintk(fmt, args);
    va_end(args); return count;
}
int _printk_deferred(const char *fmt, ...)
{
    va_list args; va_start(args, fmt);
    int count = vprintk_emit(0, LOGLEVEL_SCHED, NULL, fmt, args);
    va_end(args); return count;
}
void vinix_linuxkpi_warn_format(const char *file, int line, const char *fmt, ...)
{
    add_taint(TAINT_WARN, LOCKDEP_STILL_OK);
    if (!fmt) { _printk(KERN_WARNING "linuxkpi: warning at %s:%d\n", file, line); return; }
    va_list args; va_start(args, fmt);
    struct va_format nested = { .fmt = fmt, .va = &args };
    _printk(KERN_WARNING "linuxkpi: warning at %s:%d: %pV", file, line, &nested);
    va_end(args);
}
extern uint64_t vkr_log_snapshot(void);
extern void vkr_log_state(void *);
extern int vkr_log_flush(uint64_t, unsigned int);
extern int vkr_log_bootstrap(void);
extern int vkr_log_shutdown(void);
extern int vkr_log_pause(bool, unsigned int);
extern int vkr_log_sink(void *, void *);
extern void vkr_log_fail(bool);
u64 vinix_linuxkpi_printk_snapshot(void) { return vkr_log_snapshot(); }
void vinix_linuxkpi_printk_get_state(struct vinix_linuxkpi_printk_state *p) { vkr_log_state(p); }
int vinix_linuxkpi_printk_flush(u64 seq, unsigned int timeout) { return vkr_log_flush(seq, timeout); }
int vinix_linuxkpi_printk_bootstrap(void) { return vkr_log_bootstrap(); }
int vinix_linuxkpi_printk_shutdown(void) { return vkr_log_shutdown(); }
int vinix_linuxkpi_printk_test_pause(bool pause, unsigned int timeout) { return vkr_log_pause(pause, timeout); }
int vinix_linuxkpi_printk_test_sink(vinix_linuxkpi_printk_sink sink, void *p) { return vkr_log_sink((void *)sink, p); }
void vinix_linuxkpi_printk_test_fail_create(bool fail) { vkr_log_fail(fail); }
#endif
