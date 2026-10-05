/* SPDX-License-Identifier: GPL-2.0-only */
/* Native sticky taint bits. Panic policy, crash reporting and lockdep are
 * separate services; this build has no lockdep implementation enabled. */
#ifdef VINIX_LINUXKPI
#include <linux/bug.h>
#include <linux/panic.h>
#include <linux/printk.h>
#include <vinix/printk.h>

static unsigned long native_tainted_mask;

void add_taint(unsigned int flag, enum lockdep_ok lockdep_ok)
{
    BUG_ON(flag >= TAINT_FLAGS_COUNT);
    /* CONFIG_LOCKDEP is disabled. Recording a taint neither invents a lock
     * validator nor claims that its state has been repaired. */
    (void)lockdep_ok;
    __atomic_fetch_or(&native_tainted_mask, 1UL << flag, __ATOMIC_RELAXED);
}

int test_taint(unsigned int flag)
{
    BUG_ON(flag >= TAINT_FLAGS_COUNT);
    return !!(__atomic_load_n(&native_tainted_mask, __ATOMIC_RELAXED) & (1UL << flag));
}

unsigned long get_taint(void)
{
    return __atomic_load_n(&native_tainted_mask, __ATOMIC_RELAXED);
}

#ifdef VINIX_LINUXKPI_HOST_TEST
void vinix_linuxkpi_test_warn_note(const char *, int);
void vinix_linuxkpi_test_refcount_note(int);
#endif

void vinix_linuxkpi_warn(const char *file, int line)
{
#ifdef VINIX_LINUXKPI_HOST_TEST
    vinix_linuxkpi_test_warn_note(file, line);
#endif
    vinix_linuxkpi_warn_format(file, line, NULL);
}

void vinix_linuxkpi_refcount_warning(int kind)
{
#ifdef VINIX_LINUXKPI_HOST_TEST
    vinix_linuxkpi_test_refcount_note(kind);
#endif
    add_taint(TAINT_WARN, LOCKDEP_STILL_OK);
    _printk(KERN_WARNING "linuxkpi: refcount saturated after invalid operation %d; retaining object\n", kind);
}
#endif
