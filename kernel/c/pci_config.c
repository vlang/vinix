/* SPDX-License-Identifier: GPL-2.0-only */
/* Native PCI configuration validation and transaction serialization. This
 * operates on the platform transport and does not create Linux PCI devices. */
#include "pci_config.h"

static int valid_address(uint32_t bus, uint32_t slot, uint32_t function,
                         uint64_t offset, uint32_t width)
{
    return bus <= 255 && slot <= 31 && function <= 7 &&
           (width == 1 || width == 2 || width == 4) &&
           (offset & (width - 1)) == 0;
}

/* Called with the shared transport lock held. Subtract only after checking
 * width so even an invalid short platform window cannot wrap the bound. */
static int register_status(uint32_t bus, uint64_t offset, uint32_t width)
{
    uint32_t limit = vinix_pci_config_limit(bus);

    if (!limit) return VINIX_PCI_CONFIG_UNAVAILABLE;
    if (width > limit || offset > (uint64_t)(limit - width))
        return VINIX_PCI_CONFIG_BAD_REGISTER;
    return VINIX_PCI_CONFIG_OK;
}

static uint32_t width_mask(uint32_t width)
{
    if (width == 1) return UINT32_C(0xff);
    if (width == 2) return UINT32_C(0xffff);
    return UINT32_MAX;
}

int vinix_pci_config_read(uint32_t domain, uint32_t bus, uint32_t slot,
                          uint32_t function, uint64_t offset, uint32_t width,
                          uint32_t *value)
{
    int status;

    if (!value || !valid_address(bus, slot, function, offset, width))
        return VINIX_PCI_CONFIG_BAD_REGISTER;
    if (domain) return VINIX_PCI_CONFIG_UNAVAILABLE;

    vinix_pci_config_lock();
    status = register_status(bus, offset, width);
    if (status == VINIX_PCI_CONFIG_OK)
        *value = vinix_pci_config_read_raw(bus, slot, function,
                                          (uint32_t)offset, width) &
                 width_mask(width);
    vinix_pci_config_unlock();
    return status;
}

int vinix_pci_config_write(uint32_t domain, uint32_t bus, uint32_t slot,
                           uint32_t function, uint64_t offset, uint32_t width,
                           uint32_t value)
{
    int status;

    if (!valid_address(bus, slot, function, offset, width))
        return VINIX_PCI_CONFIG_BAD_REGISTER;
    if (domain) return VINIX_PCI_CONFIG_UNAVAILABLE;

    vinix_pci_config_lock();
    status = register_status(bus, offset, width);
    if (status == VINIX_PCI_CONFIG_OK)
        vinix_pci_config_write_raw(bus, slot, function, (uint32_t)offset,
                                   width, value & width_mask(width));
    vinix_pci_config_unlock();
    return status;
}

int vinix_pci_config_update_command(uint32_t domain, uint32_t bus,
                                    uint32_t slot, uint32_t function,
                                    uint16_t clear, uint16_t set)
{
    int status;

    if (!valid_address(bus, slot, function, 4, 2))
        return VINIX_PCI_CONFIG_BAD_REGISTER;
    if (domain) return VINIX_PCI_CONFIG_UNAVAILABLE;

    vinix_pci_config_lock();
    status = register_status(bus, 4, 2);
    if (status == VINIX_PCI_CONFIG_OK) {
        uint16_t old = (uint16_t)vinix_pci_config_read_raw(bus, slot,
                                                         function, 4, 2);
        uint16_t updated = (uint16_t)((old & (uint16_t)~clear) | set);

        if (updated != old)
            vinix_pci_config_write_raw(bus, slot, function, 4, 2, updated);
    }
    vinix_pci_config_unlock();
    return status;
}
