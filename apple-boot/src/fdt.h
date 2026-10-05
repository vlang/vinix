// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* A sequential flattened-device-tree writer, and the conversion of an Apple
 * DeviceTree into one.
 *
 * The conversion keeps every node and property under Apple's own names so the
 * kernel's native-ADT code (compatible "aic,3", "/arm-io/gfx-asc", ...) sees
 * the tree iBoot described. Property values stay little-endian, as that code
 * reads them with the devicetree module's le helpers, with one exception: the
 * cell-structured properties the generic FDT helpers parse -- #address-cells,
 * #size-cells, reg and ranges -- are re-encoded big-endian value by value, and
 * each AAPL,phandle gains a big-endian "phandle". */
#ifndef APPLE_BOOT_FDT_H
#define APPLE_BOOT_FDT_H

#include <stddef.h>
#include <stdint.h>

#include "adt.h"

#define FDT_MAGIC 0xd00dfeedu

struct fdt_builder {
    uint8_t *buffer; /* header, reservation map, then the structure block */
    size_t capacity;
    size_t length; /* end of the structure block written so far */
    char *strings;
    size_t strings_length;
    size_t strings_capacity;
    uint32_t *hash; /* offset + 1 into strings, 0 for empty */
    size_t hash_slots; /* power of two */
    int error;
};

/* Every buffer is provided by the caller; nothing is allocated. */
void fdt_begin(struct fdt_builder *builder, void *buffer, size_t capacity, char *strings,
               size_t strings_capacity, uint32_t *hash, size_t hash_slots);
void fdt_begin_node(struct fdt_builder *builder, const char *name, size_t name_length);
void fdt_property(struct fdt_builder *builder, const char *name, size_t name_length,
                  const void *value, size_t length);
void fdt_end_node(struct fdt_builder *builder);
/* Appends the strings block and fills in the header; returns the total size,
 * or 0 if anything overflowed. */
size_t fdt_finish(struct fdt_builder *builder);

/* Properties added to the converted root and /chosen. */
struct adt_fdt_extras {
    const char *bootargs; /* may be NULL */
    /* Out: reg/ranges properties kept verbatim because their length is not a
     * whole number of entries for the cell counts in force. */
    uint32_t malformed_cells;
};

/* Convert the whole ADT; returns 0 on success. */
int adt_to_fdt(const struct adt *adt, struct fdt_builder *builder,
               struct adt_fdt_extras *extras);

#endif
