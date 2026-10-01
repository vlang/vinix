/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_ASM_DELAY_H
#define VINIX_ASM_DELAY_H
void udelay(unsigned long microseconds);
void ndelay(unsigned long nanoseconds);
#define ndelay ndelay
#endif
