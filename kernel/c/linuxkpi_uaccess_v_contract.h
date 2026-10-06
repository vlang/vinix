/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_UACCESS_V_CONTRACT_H
#define VINIX_LINUXKPI_UACCESS_V_CONTRACT_H
#include <stdbool.h>
#include <stddef.h>

/* Borrowed synchronous native pagemap calls. Their implementations are V. */
unsigned long vinix_linuxkpi_raw_copy_from_user(void *to,
		void *from, unsigned long size);
unsigned long vinix_linuxkpi_raw_copy_to_user(void *to,
		void *from, unsigned long size);
unsigned long vinix_linuxkpi_user_address_limit(void);
#endif
