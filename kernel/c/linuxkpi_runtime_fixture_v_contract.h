/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_RUNTIME_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_RUNTIME_FIXTURE_V_CONTRACT_H
#include "linuxkpi_common_v_contract.h"
#include <linux/slab.h>
#include <linux/errno.h>
#include <linux/list_sort.h>
#include <linux/rbtree.h>
#include <linux/sort.h>
#include <linux/preempt.h>
#include <linux/kstrtox.h>
#include <linux/kref.h>
#include <linux/bitmap.h>
#include <asm/unaligned.h>
#include <linux/percpu.h>
#include <vinix/runtime.h>
#include <vinix/gfp.h>
#include <drm/i915_pciids.h>
typedef const void *vkf_constvoidp;
typedef const struct list_head *vkf_constlistp;
typedef unsigned long long vkf_ull;
typedef long long vkf_ll;
_Static_assert(sizeof(vkf_ull)==sizeof(uint64_t) && sizeof(vkf_ll)==sizeof(int64_t), "parser native scalar storage");
DECLARE_PER_CPU_ALIGNED(unsigned long, vinix_linuxkpi_fixture_percpu_probe);
int vinix_linuxkpi_fixture_compare_int(const void *, const void *);
int vinix_linuxkpi_fixture_compare_node(void *, const struct list_head *, const struct list_head *);
#ifndef VINIX_LINUXKPI_HOST_TEST
#include <asm/fpu/api.h>
#include "i915_memcpy.h"
void vinix_linuxkpi_fixture_xmm_save(void *, unsigned int *);
void vinix_linuxkpi_fixture_xmm_set(const void *, const unsigned int *);
void vinix_linuxkpi_fixture_xmm_clear(void);
#endif
int kprintf(const char *, ...);
#endif
