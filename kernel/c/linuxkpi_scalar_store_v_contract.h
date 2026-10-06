/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_SCALAR_STORE_V_CONTRACT_H
#define VINIX_LINUXKPI_SCALAR_STORE_V_CONTRACT_H

#include <stddef.h>
#include <stdint.h>

/* Ordinary faulting scalar writes. Both implementations are V. Values are
 * passed by value; split-page failure may leave a committed prefix. */
int vinix_linuxkpi_write_user_scalar(void *destination, size_t size,
		uint64_t value);

#endif
