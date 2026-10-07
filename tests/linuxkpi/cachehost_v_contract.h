/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_CACHE_HOST_V_CONTRACT_H
#define VINIX_CACHE_HOST_V_CONTRACT_H
#include "host_model_v_contract.h"
#include <vinix/gfp.h>
void vmc_cache_ctor(void *);
void vmc_cache_gated_ctor(void *);
void *vmc_cache_refill_thread(void *);
void *vmc_cache_stress_thread(void *);
#endif
