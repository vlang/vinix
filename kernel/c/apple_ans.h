/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_APPLE_ANS_H
#define VINIX_APPLE_ANS_H
#include <stddef.h>
#include <stdint.h>

/* No format, discard or admin-passthrough API. Writes require a boot-selected
 * Linux-data GPT partition; whole namespaces remain read-only. V owns discovery, lifetime and serialization. DMA memory stays pinned
 * until reboot, including on failed initialization or a command timeout. */
#define VINIX_ANS_DMA_BYTES 0x460000u
#define VINIX_ANS_MAX_NS 8u
#define VINIX_ANS_MAX_PARTS 128u
#define VINIX_ANS_ENABLE 1u
#define VINIX_ANS_WRITE 2u
#define VINIX_ANS_ROOT 4u
#define VINIX_ANS_FALLBACK 8u

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
int vinix_ans_boot_flags(const char *, size_t);
int vinix_ans_apply_policy(const char *, size_t);
int vinix_ans_partition_writable(unsigned, unsigned);
int vinix_ans_partition_uuid(unsigned, unsigned, char *, size_t);
int vinix_ans_write(unsigned ns, unsigned partition, const void *, uint64_t, size_t);
int vinix_ans_flush(void);
int vinix_ans_shutdown(void);
int vinix_ans_root_ns(void);
int vinix_ans_root_part(void);
int vinix_ans_root_open(void);
int vinix_ans_root_stat(uint32_t inode, uint64_t fields[10]);
int64_t vinix_ans_root_read(uint32_t inode, void *, uint64_t offset, size_t count);
int vinix_ans_root_next(uint32_t directory, uint64_t *offset, uint32_t *inode,
    char *name, size_t capacity);
int vinix_ans_error(void);
unsigned vinix_ans_stage(void);
uint16_t vinix_ans_completion_status(void);
/* Length-bounded, whitespace-tokenized boot opt-in (not a substring match). */
int vinix_ans_requested(const char *cmdline, size_t length);
#endif
