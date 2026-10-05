/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_GFP_H
#define VINIX_LINUXKPI_GFP_H
#include <linux/types.h>
#include <linux/gfp_types.h>

/* Keep kmalloc and cache allocation on the same checked native GFP policy.
 * The page helper returns uninitialized backing pages; object allocators
 * apply __GFP_ZERO after their own metadata/constructor initialization. */
bool vinix_linuxkpi_gfp_supported(gfp_t flags);
void *vinix_linuxkpi_alloc_gfp_pages(size_t pages, gfp_t flags);
#endif
