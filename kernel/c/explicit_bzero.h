/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_EXPLICIT_BZERO_H
#define VINIX_EXPLICIT_BZERO_H

#include <stddef.h>

/* Erase exactly len bytes; a zero length does not access buf. */
void vinix_explicit_bzero(void *buf, size_t len);

#endif
