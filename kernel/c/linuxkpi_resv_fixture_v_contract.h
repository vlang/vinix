/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_RESV_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_RESV_FIXTURE_V_CONTRACT_H
#include "linuxkpi_dma_resv_v_contract.h"
#include "linuxkpi_resv_fixture_v_primitives.h"
typedef enum dma_resv_usage vrf_usage;
/* Data access only. Every fixture algorithm and branch remains V. */
#define vrf_list_entry(p, i) READ_ONCE((p)->table[i])
#define vrf_list_load(p) READ_ONCE((p)->fences)
#define vrf_cursor_index(p) ((p)->index)
_Static_assert(sizeof(struct dma_resv) == sizeof(struct vinix_resv_fixture) &&
    _Alignof(struct dma_resv) == _Alignof(struct vinix_resv_fixture) &&
    offsetof(struct dma_resv, lock) == offsetof(struct vinix_resv_fixture, lock) &&
    offsetof(struct dma_resv, fences) == offsetof(struct vinix_resv_fixture, fences),
    "original reservation fixture storage");
_Static_assert(sizeof(struct dma_resv_iter) == sizeof(struct vinix_resv_iter_fixture) &&
    _Alignof(struct dma_resv_iter) == _Alignof(struct vinix_resv_iter_fixture) &&
    offsetof(struct dma_resv_iter, obj) == offsetof(struct vinix_resv_iter_fixture, obj) &&
    offsetof(struct dma_resv_iter, usage) == offsetof(struct vinix_resv_iter_fixture, usage) &&
    offsetof(struct dma_resv_iter, fence) == offsetof(struct vinix_resv_iter_fixture, fence) &&
    offsetof(struct dma_resv_iter, fence_usage) == offsetof(struct vinix_resv_iter_fixture, fence_usage) &&
    offsetof(struct dma_resv_iter, index) == offsetof(struct vinix_resv_iter_fixture, index) &&
    offsetof(struct dma_resv_iter, fences) == offsetof(struct vinix_resv_iter_fixture, fences) &&
    offsetof(struct dma_resv_iter, num_fences) == offsetof(struct vinix_resv_iter_fixture, num_fences) &&
    offsetof(struct dma_resv_iter, is_restarted) == offsetof(struct vinix_resv_iter_fixture, is_restarted),
    "original reservation iterator fixture storage");
_Static_assert(sizeof(vrf_usage) == 4 && DMA_RESV_USAGE_KERNEL == 0 &&
    DMA_RESV_USAGE_WRITE == 1 && DMA_RESV_USAGE_READ == 2 &&
    DMA_RESV_USAGE_BOOKKEEP == 3, "original usage enum ABI");
#endif
