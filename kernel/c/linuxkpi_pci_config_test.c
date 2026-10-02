/* SPDX-License-Identifier: GPL-2.0-only */
#if defined(VINIX_LINUXKPI) && !defined(VINIX_LINUXKPI_HOST_TEST)
#include "pci_config.h"
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <linux/sched.h>
#include <linux/sched/task.h>
#include <vinix/runtime.h>
#include <pthread.h>

int vinix_linuxkpi_pci_identity(u32 index, u32 *bdf, u32 *identity,
                               u32 *class_revision);
size_t vinix_linuxkpi_test_task_time_waiters(struct task_struct *task);
bool vinix_linuxkpi_test_thread_reap_ready(void *owner);
bool vinix_linuxkpi_test_reap_quiescent(void);
extern int kprintf(const char *, ...);

struct native_pci_identity {
    u32 bdf, identity, class_revision;
};

struct native_pci_worker {
    const struct native_pci_identity *devices;
    struct task_struct *task;
    pthread_t thread;
    struct completion entered, go, done;
    unsigned int cpu, reasons, reads, failed_width;
    u64 failed_offset;
    u32 failed_value, failed_expected;
    int failed_status;
    bool initialized, started, cancel;
};

static void native_pci_failed(struct native_pci_worker *worker,
                              unsigned int reason, u64 offset, unsigned int width,
                              int status, u32 value, u32 expected)
{
    if (!worker->reasons) {
        worker->failed_offset = offset;
        worker->failed_width = width;
        worker->failed_status = status;
        worker->failed_value = value;
        worker->failed_expected = expected;
    }
    worker->reasons |= reason;
}

static void native_pci_context(struct native_pci_worker *worker,
                               unsigned long flags, unsigned int depth)
{
    if (vinix_linuxkpi_irq_flags() != flags || vinix_linuxkpi_preempt_count() != depth)
        native_pci_failed(worker, 4, 0, 0, 0, 0, 0);
    if (vinix_linuxkpi_cpu_id() != worker->cpu)
        native_pci_failed(worker, 8, 0, 0, 0, vinix_linuxkpi_cpu_id(), worker->cpu);
}

static void native_pci_read(struct native_pci_worker *worker,
                            const struct native_pci_identity *device,
                            u64 offset, unsigned int width, u32 expected,
                            unsigned long flags, unsigned int depth)
{
    u32 value = 0x5aa55aa5;
    int status = vinix_pci_config_read(0, device->bdf >> 8,
            (device->bdf >> 3) & 31, device->bdf & 7, offset, width, &value);
    if (status != VINIX_PCI_CONFIG_OK || value != expected)
        native_pci_failed(worker, status ? 1 : 2, offset, width, status, value, expected);
    worker->reads++;
    native_pci_context(worker, flags, depth);
}

static void native_pci_read_identity(struct native_pci_worker *worker,
                                     const struct native_pci_identity *device,
                                     unsigned long flags, unsigned int depth)
{
    native_pci_read(worker, device, 0, 4, device->identity, flags, depth);
    native_pci_read(worker, device, 0, 2, device->identity & 0xffff, flags, depth);
    native_pci_read(worker, device, 2, 2, device->identity >> 16, flags, depth);
    for (unsigned int byte = 0; byte < 4; byte++)
        native_pci_read(worker, device, byte, 1,
                         (device->identity >> (byte * 8)) & 0xff, flags, depth);
    native_pci_read(worker, device, 8, 4, device->class_revision, flags, depth);
    native_pci_read(worker, device, 8, 2, device->class_revision & 0xffff, flags, depth);
    native_pci_read(worker, device, 10, 2, device->class_revision >> 16, flags, depth);
    for (unsigned int byte = 0; byte < 4; byte++)
        native_pci_read(worker, device, 8 + byte, 1,
                         (device->class_revision >> (byte * 8)) & 0xff, flags, depth);
}

static void native_pci_errors(struct native_pci_worker *worker,
                              unsigned long flags, unsigned int depth)
{
    /* Native LinuxKPI is x86-only: this backend exposes conventional256-byte
     * CF8 registers. These are error-only writes, never valid device writes. */
    static const struct {
        u32 domain, bus, slot, function;
        u64 offset;
        u32 width;
        int status;
    } cases[] = {
        { 0, 0, 0, 0, 0, 0, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 0, 0, 0, 0, 0, 3, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 0, 0, 0, 0, 0, 8, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 0, 0, 0, 0, 1, 2, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 0, 0, 0, 0, 2, 4, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 0, 256, 0, 0, 0, 4, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 0, 0, 32, 0, 0, 4, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 0, 0, 0, 8, 0, 4, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 1, 0, 0, 0, 0, 4, VINIX_PCI_CONFIG_UNAVAILABLE },
        { 1, 0, 0, 0, 1, 2, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 0, 0, 0, 0, 256, 1, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 0, 0, 0, 0, 256, 4, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 0, 0, 0, 0, 0x100000000ULL, 4, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 0, 0, 0, 0, ~0ULL, 1, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 0, 0, 0, 0, ~0ULL - 3, 4, VINIX_PCI_CONFIG_BAD_REGISTER },
    };
    for (unsigned int i = 0; i < ARRAY_SIZE(cases); i++) {
        u32 value = 0x5aa55aa5;
        int status = vinix_pci_config_read(cases[i].domain, cases[i].bus,
                cases[i].slot, cases[i].function, cases[i].offset, cases[i].width, &value);
        if (status != cases[i].status || value != 0x5aa55aa5)
            native_pci_failed(worker, 32, cases[i].offset, cases[i].width,
                                status, value, 0x5aa55aa5);
        native_pci_context(worker, flags, depth);
        status = vinix_pci_config_write(cases[i].domain, cases[i].bus,
                cases[i].slot, cases[i].function, cases[i].offset, cases[i].width, 0xffffffff);
        if (status != cases[i].status)
            native_pci_failed(worker, 32, cases[i].offset, cases[i].width, status, 0, 0);
        native_pci_context(worker, flags, depth);
    }
    int status = vinix_pci_config_read(0, 0, 0, 0, 0, 4, NULL);
    if (status != VINIX_PCI_CONFIG_BAD_REGISTER)
        native_pci_failed(worker, 32, 0, 4, status, 0, 0);
    native_pci_context(worker, flags, depth);
    static const struct { u32 domain, bus, slot, function; int status; } updates[] = {
        { 0, 256, 0, 0, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 0, 0, 32, 0, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 0, 0, 0, 8, VINIX_PCI_CONFIG_BAD_REGISTER },
        { 1, 0, 0, 0, VINIX_PCI_CONFIG_UNAVAILABLE },
    };
    for (unsigned int i = 0; i < ARRAY_SIZE(updates); i++) {
        status = vinix_pci_config_update_command(updates[i].domain, updates[i].bus,
                updates[i].slot, updates[i].function, 0xffff, 0xffff);
        if (status != updates[i].status)
            native_pci_failed(worker, 32, 4, 2, status, 0, 0);
        native_pci_context(worker, flags, depth);
    }
}

static void *native_pci_worker(void *argument)
{
    struct native_pci_worker *worker = argument;
    __atomic_store_n(&worker->task, get_task_struct(current), __ATOMIC_RELEASE);
    if (vinix_linuxkpi_worker_bind(worker->cpu))
        native_pci_failed(worker, 16, 0, 0, 0, 0, 0);
    complete(&worker->entered);
    wait_for_completion(&worker->go);
    if (__atomic_load_n(&worker->cancel, __ATOMIC_ACQUIRE)) goto out;
    for (unsigned int round = 0; round < 32; round++) {
        if (__atomic_load_n(&worker->cancel, __ATOMIC_ACQUIRE)) goto out;
        unsigned long original_flags = vinix_linuxkpi_irq_flags();
        unsigned int original_depth = vinix_linuxkpi_preempt_count();
        unsigned long saved_flags = 0;
        if (round & 1) {
            saved_flags = vinix_linuxkpi_irq_save();
            vinix_linuxkpi_preempt_disable();
            vinix_linuxkpi_preempt_disable();
        }
        unsigned long flags = vinix_linuxkpi_irq_flags();
        unsigned int depth = vinix_linuxkpi_preempt_count();
        vinix_linuxkpi_test_alloc_oom(0);
        for (unsigned int i = 0; i < 2; i++)
            native_pci_read_identity(worker, &worker->devices[(i + round + worker->cpu) & 1],
                                     flags, depth);
        if (round < 2) native_pci_errors(worker, flags, depth);
        vinix_linuxkpi_test_alloc_oom(-1);
        if (round & 1) {
            vinix_linuxkpi_preempt_enable_no_resched();
            vinix_linuxkpi_preempt_enable_no_resched();
            vinix_linuxkpi_irq_restore(saved_flags);
        }
        native_pci_context(worker, original_flags, original_depth);
        if ((round & 7) == 7) {
            msleep(1);
            native_pci_context(worker, original_flags, original_depth);
        }
    }
    if (worker->reads != 32 * 2 * 14)
        native_pci_failed(worker, 128, 0, 0, 0, worker->reads, 32 * 2 * 14);
out:
    vinix_linuxkpi_test_alloc_oom(-1);
    if (!task_is_running(current) || !vinix_linuxkpi_may_sleep() || current->in_iowait)
        native_pci_failed(worker, 64, 0, 0, 0, 0, 0);
    /* Both the normal controller and common rollback cleanup observe done.
     * A completed-all gate lets each wait without consuming the publication. */
    complete_all(&worker->done);
    pthread_exit(NULL);
    return NULL;
}

static int native_pci_retire(struct native_pci_worker *workers, unsigned int count)
{
    int result = 0;
    for (unsigned int i = 0; i < count; i++) {
        if (!workers[i].initialized) continue;
        __atomic_store_n(&workers[i].cancel, true, __ATOMIC_RELEASE);
        complete_all(&workers[i].go);
    }
    for (unsigned int i = 0; i < count; i++) {
        if (!workers[i].started) continue;
        if (!wait_for_completion_timeout(&workers[i].done, 500)) {
            kprintf("linuxkpi: PCI worker=%u did not finish before cleanup watchdog\n", i);
            BUG();
        }
        BUG_ON(pthread_join(workers[i].thread, NULL));
    }
    u64 retirement_started = vinix_linuxkpi_clock_ns();
    for (unsigned int i = 0; i < count; i++) {
        if (!workers[i].started) continue;
        struct task_struct *task = __atomic_load_n(&workers[i].task, __ATOMIC_ACQUIRE);
        BUG_ON(!task);
        if (workers[i].reasons) {
            kprintf("linuxkpi: PCI worker=%u reasons=0x%x offset=%llu width=%u status=%d value=%08x expected=%08x\n",
                    i, workers[i].reasons, (unsigned long long)workers[i].failed_offset,
                    workers[i].failed_width, workers[i].failed_status,
                    workers[i].failed_value, workers[i].failed_expected);
            result = -EIO;
        }
        while (__atomic_load_n(&task->__state, __ATOMIC_ACQUIRE) != TASK_DEAD) {
            if (vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000ULL) BUG();
            cond_resched();
        }
        BUG_ON(vinix_linuxkpi_test_task_time_waiters(task));
    }
    for (unsigned int i = 0; i < count; i++) {
        if (!workers[i].started) continue;
        while (!vinix_linuxkpi_test_thread_reap_ready(workers[i].task->vinix_thread)) {
            if (vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000ULL) BUG();
            cond_resched();
        }
    }
    for (unsigned int i = 0; i < count; i++) {
        if (!workers[i].started) continue;
        put_task_struct(workers[i].task); /* No reads after the final release. */
        workers[i].started = false;
    }
    while (!vinix_linuxkpi_test_reap_quiescent()) {
        if (vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000ULL) BUG();
        cond_resched();
    }
    return result;
}

static int native_pci_group(const struct native_pci_identity *devices,
                             unsigned int fail_after, unsigned int oom_stage)
{
    struct native_pci_worker workers[4] = {{0}};
    int result = 0;
    BUG_ON(oom_stage && (oom_stage > 4 || fail_after >= ARRAY_SIZE(workers)));
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) {
        struct native_pci_worker *worker = &workers[i];
        worker->devices = devices;
        worker->cpu = i;
        init_completion(&worker->entered);
        init_completion(&worker->go);
        init_completion(&worker->done);
        worker->initialized = true;
        if (oom_stage && i == fail_after) vinix_linuxkpi_test_worker_oom(oom_stage);
        int error = pthread_create(&worker->thread, NULL, native_pci_worker, worker);
        vinix_linuxkpi_test_worker_oom(0);
        if (!error) worker->started = true;
        if (oom_stage && i == fail_after) {
            if (error != EAGAIN || worker->started) result = -EIO;
            goto out;
        }
        if (error) { result = -ENOMEM; goto out; }
        if (!wait_for_completion_timeout(&worker->entered, 500)) { result = -EIO; goto out; }
    }
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++) complete(&workers[i].go);
    for (unsigned int i = 0; i < ARRAY_SIZE(workers); i++)
        if (!wait_for_completion_timeout(&workers[i].done, 500)) { result = -EIO; goto out; }
out:
    if (native_pci_retire(workers, ARRAY_SIZE(workers))) result = -EIO;
    return result;
}

int vinix_linuxkpi_pci_config_native_selftest(void)
{
    if (vinix_linuxkpi_percpu_count() < 4) return -EIO;
    struct native_pci_identity devices[2];
    for (unsigned int i = 0; i < ARRAY_SIZE(devices); i++) {
        if (vinix_linuxkpi_pci_identity(i, &devices[i].bdf, &devices[i].identity,
                                       &devices[i].class_revision) ||
            devices[i].bdf > 0xffff || (devices[i].identity & 0xffff) == 0xffff)
            return -EIO;
    }
    if (devices[0].bdf == devices[1].bdf) return -EIO;
    int result = 0;
    for (unsigned int stage = 1; stage <= 4; stage++)
        for (unsigned int before = 0; before < 4; before++)
            if (native_pci_group(devices, before, stage)) {
                kprintf("linuxkpi: PCI constructor rollback stage=%u after=%u failed\n", stage, before);
                result = -EIO;
            }
    if (native_pci_group(devices, 0, 0)) result = -EIO;
    return result;
}
#endif
