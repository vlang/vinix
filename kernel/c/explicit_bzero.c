/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "explicit_bzero.h"

/*
 * OpenBSD explicit_bzero(3) semantics, implemented with volatile stores rather
 * than its weak-hook mechanism. These stores must survive dead-store removal,
 * including when the caller's buffer is otherwise dead and under LTO.
 * This does not promise to erase registers or additional compiler-made copies.
 */
void
vinix_explicit_bzero(void *buf, size_t len)
{
	volatile unsigned char *p = buf;

	while (len != 0) {
		*p++ = 0;
		--len;
	}
}
