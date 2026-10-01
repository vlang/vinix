/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_POISON_H
#define VINIX_LINUX_POISON_H
#define LIST_POISON1 ((void *)0x100UL)
#define LIST_POISON2 ((void *)0x122UL)
#define TIMER_ENTRY_STATIC ((void *)0x300UL)
#endif
