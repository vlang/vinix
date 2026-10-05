/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_PCI_CONFIG_H
#define VINIX_PCI_CONFIG_H

#include <stdint.h>

enum {
    VINIX_PCI_CONFIG_OK = 0,
    VINIX_PCI_CONFIG_BAD_REGISTER = 1,
    VINIX_PCI_CONFIG_UNAVAILABLE = 2,
};

/* These synchronous native operations support domain zero. Width is a byte
 * count (1, 2 or 4); offsets must be aligned and within the boot-mapped window.
 * A read borrows writable result storage for the call and leaves it untouched
 * on error. Missing PCI functions are successful all-ones hardware reads. */
int vinix_pci_config_read(uint32_t domain, uint32_t bus, uint32_t slot,
                          uint32_t function, uint64_t offset, uint32_t width,
                          uint32_t *value);
int vinix_pci_config_write(uint32_t domain, uint32_t bus, uint32_t slot,
                           uint32_t function, uint64_t offset, uint32_t width,
                           uint32_t value);

/* Clear then set COMMAND bits using one locked 16-bit transaction. STATUS
 * shares the adjacent dword and must never be written by this operation. */
int vinix_pci_config_update_command(uint32_t domain, uint32_t bus,
                                    uint32_t slot, uint32_t function,
                                    uint16_t clear, uint16_t set);

/* Platform contract: every native config user shares this IRQ-safe lock.
 * limit is queried under the lock and returns 0 for an unavailable bus, 256
 * for legacy CF8 access or 4096 for a verified ECAM window. Raw operations
 * are called under the lock after validation; transport and mapping cannot
 * fail or change during the operation. They must not allocate, sleep, log,
 * acquire a mapping lock or recurse through the public operations. */
void vinix_pci_config_lock(void);
void vinix_pci_config_unlock(void);
uint32_t vinix_pci_config_limit(uint32_t bus);
uint32_t vinix_pci_config_read_raw(uint32_t bus, uint32_t slot,
                                   uint32_t function, uint32_t offset,
                                   uint32_t width);
void vinix_pci_config_write_raw(uint32_t bus, uint32_t slot, uint32_t function,
                                uint32_t offset, uint32_t width,
                                uint32_t value);

#endif
