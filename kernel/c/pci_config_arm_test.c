/* SPDX-License-Identifier: GPL-2.0-only */
#if defined(__aarch64__) && defined(VINIX_PCI_CONFIG_TEST)
#include "pci_config.h"
#include "pci_config_arm_test.h"

int vinix_pci_config_arm_context_selftest(void)
{
    uint32_t slots[2], identities[2];
    unsigned int found = 0;
    for (uint32_t slot = 0; slot < 32 && found < 2; slot++) {
        uint32_t identity;
        if (vinix_pci_config_read(0, 0, slot, 0, 0, 4, &identity)) return 1;
        if ((identity & 0xffff) != 0xffff) {
            slots[found] = slot;
            identities[found++] = identity;
        }
    }
    if (found != 2) return 2;

    uint64_t original;
    __asm__ volatile("mrs %0, daif" : "=r"(original) :: "memory");
    int result = 0;
    /* Keep IRQs masked throughout the controlled vectors. Independently vary
     * debug, SError and FIQ masks; a bool-I lock would lose these on release. */
    for (unsigned int mask = 0; mask < 8; mask++) {
        uint64_t state = UINT64_C(0x80) | ((uint64_t)(mask & 1) << 6) |
                         ((uint64_t)(mask & 2) << 7) | ((uint64_t)(mask & 4) << 7);
        __asm__ volatile("msr daif, %0" :: "r"(state) : "memory");
        for (unsigned int device = 0; device < 2; device++) {
            for (uint32_t width = 1; width <= 4; width *= 2) {
                for (uint32_t offset = 0; offset < 4; offset += width) {
                    uint32_t value = 0x5aa55aa5;
                    uint32_t expected = identities[device] >> (offset * 8);
                    if (width < 4) expected &= (UINT32_C(1) << (width * 8)) - 1;
                    if (vinix_pci_config_read(0, 0, slots[device], 0, offset, width, &value) ||
                        value != expected) result = 3;
                    uint64_t observed;
                    __asm__ volatile("mrs %0, daif" : "=r"(observed) :: "memory");
                    if (observed != state) result = 4;
                }
            }
        }
        uint32_t value = 0x5aa55aa5;
        if (vinix_pci_config_read(0, 0, slots[0], 0, 1, 2, &value) !=
                VINIX_PCI_CONFIG_BAD_REGISTER || value != 0x5aa55aa5 ||
            vinix_pci_config_read(0, 0, slots[0], 0, UINT64_C(0x100000000), 4, &value) !=
                VINIX_PCI_CONFIG_BAD_REGISTER || value != 0x5aa55aa5 ||
            vinix_pci_config_write(0, 0, slots[0], 0, 4096, 4, 0xffffffff) !=
                VINIX_PCI_CONFIG_BAD_REGISTER) result = 5;
        uint64_t observed;
        __asm__ volatile("mrs %0, daif" : "=r"(observed) :: "memory");
        if (observed != state) result = 4;
    }
    __asm__ volatile("msr daif, %0" :: "r"(original) : "memory");
    return result;
}
#endif
