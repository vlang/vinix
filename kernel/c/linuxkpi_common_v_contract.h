/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_COMMON_V_CONTRACT_H
#define VINIX_LINUXKPI_COMMON_V_CONTRACT_H
#include "linuxkpi_srcu_v_contract.h"
#include <linux/refcount.h>
#include <linux/spinlock.h>
#include <linux/mutex.h>
#include <linux/sched/signal.h>
#include <linux/wait_bit.h>
#include <linux/jiffies.h>
#include <linux/printk.h>
#include <vinix/printk.h>
#include "linuxkpi_v_primitives.h"
typedef const char *vkh_const_char_p;
_Static_assert(sizeof(spinlock_t) == 4, "V spinlock storage must match Linux");
_Static_assert(sizeof(refcount_t) == 4, "V refcount storage must match Linux");
_Static_assert(CONFIG_NR_CPUS == 256, "V per-CPU ABI storage must match Linux");
#ifndef VINIX_LINUXKPI_HOST_TEST
extern const unsigned char __vinix_percpu_start[], __vinix_percpu_end[];
#endif
void vinix_linuxkpi_test_warn_note(const char *, int);
void vinix_linuxkpi_test_refcount_note(int);
#endif
