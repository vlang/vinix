// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Apple DeviceTree (ADT), the recursive little-endian tree iBoot hands over.
 * A node is {u32 property count, u32 child count}, its properties, then its
 * children. A property is a 32-byte NUL-padded name, a u32 whose low 24 bits
 * are the length (iBoot keeps flags in the top byte), and the value padded to
 * four bytes. Nodes are addressed by their byte offset in the blob. */
#ifndef APPLE_BOOT_ADT_H
#define APPLE_BOOT_ADT_H

#include <stddef.h>
#include <stdint.h>

#define ADT_NAME_BYTES 32
#define ADT_LENGTH_MASK 0x00ffffffu
#define ADT_MAX_DEPTH 64

struct adt {
    const uint8_t *base;
    size_t size;
};

struct adt_property {
    const char *name; /* not NUL-terminated past ADT_NAME_BYTES */
    size_t name_length;
    const uint8_t *value;
    uint32_t length;
};

/* Check that the whole blob is exactly one well-formed tree. */
int adt_validate(const struct adt *adt);

uint32_t adt_property_count(const struct adt *adt, size_t node);
uint32_t adt_child_count(const struct adt *adt, size_t node);

/* Offsets of a node's first property, next property, first child and next
 * sibling. Callers iterate with the counts above; every offset was checked by
 * adt_validate. */
size_t adt_first_property(size_t node);
size_t adt_next_property(const struct adt *adt, size_t property);
size_t adt_first_child(const struct adt *adt, size_t node);
size_t adt_next_sibling(const struct adt *adt, size_t node);

void adt_read_property(const struct adt *adt, size_t property, struct adt_property *out);
int adt_get(const struct adt *adt, size_t node, const char *name, struct adt_property *out);
int adt_get_u32(const struct adt *adt, size_t node, const char *name, uint32_t *value);
int adt_get_u64(const struct adt *adt, size_t node, const char *name, uint64_t *value);

/* The node's "name" property, or "" when it has none. */
const char *adt_node_name(const struct adt *adt, size_t node, size_t *length);
int adt_is_compatible(const struct adt *adt, size_t node, const char *compatible);

/* Resolve "/arm-io/wdt" style paths below the root. On success the chain of
 * node offsets from the root is written to path (terminated by SIZE_MAX), so
 * reg translation can walk back up through each bus. */
int adt_find_path(const struct adt *adt, const char *path, size_t *node,
                  size_t *chain, size_t chain_capacity);

/* Translate reg[index] of the last node in chain to a CPU physical address
 * through every ancestor's ranges, as XNU's IODTResolveAddressCell does. */
int adt_get_reg(const struct adt *adt, const size_t *chain, size_t index,
                uint64_t *address, uint64_t *size);

/* Default cell counts when a bus omits them. */
#define ADT_DEFAULT_ADDRESS_CELLS 2
#define ADT_DEFAULT_SIZE_CELLS 2

void adt_cell_counts(const struct adt *adt, size_t node, uint32_t *address_cells,
                     uint32_t *size_cells);

#endif
