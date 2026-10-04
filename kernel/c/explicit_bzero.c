/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <stddef.h>

/*
 * OpenBSD's explicit_bzero(3): clear memory that held a secret. A plain
 * memset() of a buffer about to go out of scope is a dead store the compiler
 * may drop; these volatile stores are not. It clears the bytes named, not
 * any copies the compiler made in registers or elsewhere.
 */
void vinix_explicit_bzero(void *buf, size_t len)
{
	volatile unsigned char *p = buf;

	while (len != 0) {
		*p++ = 0;
		--len;
	}
}
