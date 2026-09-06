/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_APPLE_ANS_H
#define VINIX_APPLE_ANS_H
#include <stddef.h>
#include <stdint.h>

/* This driver intentionally has NO write, format, discard or admin-passthrough
 * API. V owns discovery, lifetime and serialization. DMA memory stays pinned
 * until reboot, including on failed initialization or a command timeout. */
#define VINIX_ANS_DMA_BYTES 0x460000u
#define VINIX_ANS_MAX_NS 8u
#define VINIX_ANS_MAX_PARTS 128u

int vinix_ans_init(uint64_t nvme, uint64_t asc, uint64_t mailbox,
    uint64_t sart, uint64_t reset, void *dma, uint64_t dma_phys, size_t dma_size);
int vinix_ans_namespace_count(void);
uint32_t vinix_ans_namespace_id(unsigned index);
uint32_t vinix_ans_sector_size(unsigned index);
uint64_t vinix_ans_sector_count(unsigned index);
int vinix_ans_partition_count(unsigned index);
unsigned vinix_ans_partition_number(unsigned index, unsigned partition);
uint64_t vinix_ans_partition_start(unsigned index, unsigned partition);
uint64_t vinix_ans_partition_blocks(unsigned index, unsigned partition);
/* Exact byte read; supports unaligned/partial-sector reads using a private
 * DMA bounce buffer. The caller validates/clamps EOF before invoking this. */
int vinix_ans_read(unsigned index, void *buffer, uint64_t offset, size_t count);
int vinix_ans_error(void);
unsigned vinix_ans_stage(void);
uint16_t vinix_ans_completion_status(void);
/* Length-bounded, whitespace-tokenized boot opt-in (not a substring match). */
int vinix_ans_requested(const char *cmdline, size_t length);
#endif
