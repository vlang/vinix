/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_I915_POLICY_V_CONTRACT_H
#define VINIX_LINUXKPI_I915_POLICY_V_CONTRACT_H
#include "linuxkpi_common_v_contract.h"
#include <i915_config.h>
#include <display/intel_qp_tables.h>
#include <drm/display/drm_dsc.h>
#include <linux/array_size.h>
#include <linux/errno.h>
#include <linux/jiffies.h>
#include <linux/kdev_t.h>
#include <linux/sprintf.h>
#include <linux/string.h>
#include <vinix/runtime.h>
_Static_assert(HZ == 1000 && CONFIG_DRM_I915_FENCE_TIMEOUT == 10000,
    "Use the pinned i915 fence timeout policy at native HZ");
_Static_assert(sizeof(dev_t) == 4 && (dev_t)-1 > 0 && MINORBITS == 20,
    "Linux internal dev_t is unsigned 12:20, not Vinix Stat.dev");
_Static_assert(DSC_NUM_BUF_RANGES == 15, "Pinned DSC tables contain 15 ranges");
#endif
