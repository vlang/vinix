/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_PRINTK_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_PRINTK_FIXTURE_V_CONTRACT_H
#include "linuxkpi_task_v_contract.h"
#include <linux/printk.h>
#include <linux/panic.h>
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <linux/err.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <vinix/runtime.h>
#include <vinix/format.h>
#include <vinix/printk.h>
typedef const struct vinix_linuxkpi_printk_record *vkfp_const_record_p;
struct vkfp_va_descriptor_layout { const char *fmt; void *va; };
_Static_assert(sizeof(struct vkfp_va_descriptor_layout) == sizeof(struct va_format), "fixture nested format size");
_Static_assert(_Alignof(struct vkfp_va_descriptor_layout) == _Alignof(struct va_format), "fixture nested format alignment");
_Static_assert(offsetof(struct vkfp_va_descriptor_layout, va) == offsetof(struct va_format, va), "fixture nested cursor field");
int vinix_linuxkpi_fixture_nested_format(const char *, ...);
int vinix_linuxkpi_fixture_nested_emit(const char *, ...);
int vinix_linuxkpi_fixture_nested_format_entry(char *, void *);
int vinix_linuxkpi_fixture_nested_emit_entry(char *, void *);
int vkr_format_entry(char *, size_t, const char *, void *, unsigned int *);
void vinix_linuxkpi_fixture_printk_sink(vkfp_const_record_p, void *);
void *vinix_linuxkpi_fixture_printk_produce(void *);
void *vinix_linuxkpi_fixture_printk_flusher(void *);
int vinix_linuxkpi_test_printk_locks(void);
int kprintf(const char *, ...);
#endif
