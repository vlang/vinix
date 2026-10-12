/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_RCUPDATE_H
#define VINIX_LINUX_RCUPDATE_H
/* Retain the pinned original readers and pointer publication primitives.
 * The native nonpreemptible backend implements the ordinary callback/cookie
 * subset; declarations for other RCU services stay unresolved until supplied. */
#include_next <linux/rcupdate.h>
#endif
