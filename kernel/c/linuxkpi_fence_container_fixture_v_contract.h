/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_FENCE_CONTAINER_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_FENCE_CONTAINER_FIXTURE_V_CONTRACT_H
#include "linuxkpi_dma_fence_array_v_contract.h"
#include "linuxkpi_dma_fence_chain_v_contract.h"
#include "linuxkpi_fence_container_fixture_v_primitives.h"
/* Metadata access only; all fixture control flow is V. */
#define fct_refcount(p) kref_read(&((struct dma_fence *)(p))->refcount)
#define fct_pending(p) atomic_read(&((struct dma_fence_array *)(p))->num_pending)
#endif
