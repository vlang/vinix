/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <assert.h>
#include <stdint.h>
/* The media fixture injects its own hardware callbacks. Architectural MMIO
 * must never execute in the host test process. */
uint32_t vinix_mmio_read32(void *p) { (void)p; assert(!"unexpected MMIO"); return 0; }
uint64_t vinix_mmio_read64(void *p) { (void)p; assert(!"unexpected MMIO"); return 0; }
void vinix_mmio_write32(void *p, uint32_t v) { (void)p; (void)v; assert(!"unexpected MMIO"); }
void vinix_mmio_write64(void *p, uint64_t v) { (void)p; (void)v; assert(!"unexpected MMIO"); }
void vinix_account_disk_transfer(uint64_t n, int write) { (void)n; (void)write; }
