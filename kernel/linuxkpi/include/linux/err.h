/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_ERR_H
#define VINIX_LINUX_ERR_H
#include <linux/types.h>
#define MAX_ERRNO 4095
void *ERR_PTR(long);
long PTR_ERR(const void *);
bool IS_ERR(const void *);
bool IS_ERR_OR_NULL(const void *);
int PTR_ERR_OR_ZERO(const void *);
#endif
