/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_KSTRTOX_HOST_V_CONTRACT_H
#define VINIX_KSTRTOX_HOST_V_CONTRACT_H
#include "host_model_v_contract.h"
#include <linux/kstrtox.h>
typedef long long vmk_s64;
_Static_assert(sizeof(unsigned long)==8 && sizeof(long)==8, "original parser native word widths");
_Static_assert(sizeof(vmh_u64)==8 && sizeof(vmk_s64)==8, "original parser long long widths");
#endif
