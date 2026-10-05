// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* iBoot leaves the SoC watchdog armed for the OS it started; nothing in Vinix
 * services it, so disarm it before the kernel runs, as m1n1's wdt_disable
 * does: clear the control register at reg[0] + 0x1c, and on watchdog
 * versions 2 and 3 also the secondary control word at reg[2]. */
#include "lib.h"
#include "loader.h"

#define WDT_CONTROL 0x1c

static void write32(uint64_t address, uint32_t value)
{
    *(volatile uint32_t *)(uintptr_t)address = value;
}

void disable_watchdog(const struct adt *adt)
{
    size_t node, chain[8];
    uint64_t base, size, version;

    if (adt_find_path(adt, "/arm-io/wdt", &node, chain, 8) ||
        adt_get_reg(adt, chain, 0, &base, &size)) {
        console_hex(1, 0xd1, 0);
        return;
    }
    write32(base + WDT_CONTROL, 0);
    if (adt_get_u64(adt, node, "wdt-version", &version))
        version = 0;
    if ((uint32_t)version == 2 || (uint32_t)version == 3) {
        uint64_t secondary;
        if (!adt_get_reg(adt, chain, 2, &secondary, &size))
            write32(secondary, 0);
    }
    console_hex(1, 0xd1, base);
}
