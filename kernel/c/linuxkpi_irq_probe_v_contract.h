/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_IRQ_PROBE_V_CONTRACT_H
#define VINIX_LINUXKPI_IRQ_PROBE_V_CONTRACT_H
#include <stdint.h>
/* Fixture only: execute a real IDT software interrupt on a private vector.
 * Invalid vectors fail before lookup; success returns only after IRET. */
int32_t vinix_linuxkpi_irq_probe(uint32_t vector);
#endif
