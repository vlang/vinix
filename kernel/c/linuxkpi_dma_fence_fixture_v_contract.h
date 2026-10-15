/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_DMA_FENCE_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_DMA_FENCE_FIXTURE_V_CONTRACT_H
#include "linuxkpi_dma_fence_v_contract.h"
#include "linuxkpi_dma_fence_fixture_v_primitives.h"
_Static_assert(sizeof(struct dma_fence) == 64 && sizeof(struct dma_fence) == sizeof(struct vinix_dmafence_fixture) &&
    _Alignof(struct dma_fence) == _Alignof(struct vinix_dmafence_fixture) &&
    offsetof(struct dma_fence, lock) == offsetof(struct vinix_dmafence_fixture, lock) &&
    offsetof(struct dma_fence, ops) == offsetof(struct vinix_dmafence_fixture, ops) &&
    offsetof(struct dma_fence, cb_list) == offsetof(struct vinix_dmafence_fixture, shared) &&
    offsetof(struct dma_fence, context) == offsetof(struct vinix_dmafence_fixture, context) &&
    offsetof(struct dma_fence, seqno) == offsetof(struct vinix_dmafence_fixture, seqno) &&
    offsetof(struct dma_fence, flags) == offsetof(struct vinix_dmafence_fixture, flags) &&
    offsetof(struct dma_fence, refcount) == offsetof(struct vinix_dmafence_fixture, refcount) &&
    offsetof(struct dma_fence, error) == offsetof(struct vinix_dmafence_fixture, error), "original complete fence fixture layout");
_Static_assert(sizeof(struct dma_fence_cb) == 24 && sizeof(struct dma_fence_cb) == sizeof(struct vinix_dmafence_cb) &&
    offsetof(struct dma_fence_cb, node) == offsetof(struct vinix_dmafence_cb, next) &&
    offsetof(struct dma_fence_cb, func) == offsetof(struct vinix_dmafence_cb, func), "original fence callback layout");
_Static_assert(sizeof(struct dma_fence_ops) == 80 && sizeof(struct dma_fence_ops) == sizeof(struct vinix_dmafence_ops) &&
    offsetof(struct dma_fence_ops, get_driver_name) == offsetof(struct vinix_dmafence_ops, get_driver_name) &&
    offsetof(struct dma_fence_ops, set_deadline) == offsetof(struct vinix_dmafence_ops, set_deadline), "original fence operations layout");
#endif
