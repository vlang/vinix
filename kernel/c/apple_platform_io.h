/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_APPLE_PLATFORM_IO_H
#define VINIX_APPLE_PLATFORM_IO_H
#include <stdint.h>
uint8_t vinix_mmio_read8(void *);
uint16_t vinix_mmio_read16(void *);
void vinix_mmio_write8(void *, uint8_t);
void vinix_mmio_write16(void *, uint16_t);
uint32_t vinix_mmio_read32(void *);
uint64_t vinix_mmio_read64(void *);
void vinix_mmio_write32(void *, uint32_t);
void vinix_mmio_write64(void *, uint64_t);
void vinix_account_disk_transfer(uint64_t, int);
#endif
