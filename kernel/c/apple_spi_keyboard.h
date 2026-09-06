/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_APPLE_SPI_KEYBOARD_H
#define VINIX_APPLE_SPI_KEYBOARD_H

#include <stddef.h>
#include <stdint.h>

/* Called only after the V platform layer has validated and mapped the DT
 * resources, enabled their power domains, and configured the SPI pinmux.
 * All addresses are mapped virtual addresses, not physical addresses.
 * ready_reg == 0 selects timer-only polling. A successful init does not
 * establish that a keyboard has actually returned a valid input report. */
int vinix_apple_spi_keyboard_init(uint64_t spi_base, uint64_t enable_reg,
    int enable_active_low, uint64_t ready_reg, int ready_active_low,
    uint32_t input_hz, uint32_t maximum_hz);

/* Non-reentrant: the V wrapper serializes calls. At most one bounded SPI
 * transaction per call. Returns bytes produced, -1 for a recoverable transfer
 * timeout/error, or -2 when repeated transfer errors disable the device. */
int vinix_apple_spi_keyboard_poll(uint8_t *out, size_t capacity,
    int application_cursor);
uint64_t vinix_apple_spi_keyboard_reports(void);

#endif
