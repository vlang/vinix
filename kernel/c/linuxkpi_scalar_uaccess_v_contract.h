/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_SCALAR_UACCESS_V_CONTRACT_H
#define VINIX_LINUXKPI_SCALAR_UACCESS_V_CONTRACT_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

/* Borrowed synchronous ordinary scalar read. Both implementations are V. */
int vinix_linuxkpi_read_user_scalar(void *source, size_t size, uint64_t *result);

/* Existing native test observers; neither consumes the caller's thread pin. */
bool vinix_linuxkpi_test_thread_reap_ready(void *owner);
bool vinix_linuxkpi_test_reap_quiescent(void);

#endif
