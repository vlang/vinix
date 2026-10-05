// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "fdt.h"
#include "lib.h"

#define FDT_BEGIN_NODE 1
#define FDT_END_NODE 2
#define FDT_PROP 3
#define FDT_END 9
#define FDT_HEADER_BYTES 40
#define FDT_RESERVE_MAP_BYTES 16 /* one terminating entry */
#define FDT_VERSION 17
#define FDT_LAST_COMPATIBLE_VERSION 16

static void put32(struct fdt_builder *builder, uint32_t value)
{
    if (builder->error || builder->capacity - builder->length < 4) {
        builder->error = 1;
        return;
    }
    store_be32(builder->buffer + builder->length, value);
    builder->length += 4;
}

static void put_bytes(struct fdt_builder *builder, const void *bytes, size_t length)
{
    size_t padded = align_up(length, 4);

    if (builder->error || builder->capacity - builder->length < padded) {
        builder->error = 1;
        return;
    }
    memcpy(builder->buffer + builder->length, bytes, length);
    memset(builder->buffer + builder->length + length, 0, padded - length);
    builder->length += padded;
}

void fdt_begin(struct fdt_builder *builder, void *buffer, size_t capacity, char *strings,
               size_t strings_capacity, uint32_t *hash, size_t hash_slots)
{
    builder->buffer = buffer;
    builder->capacity = capacity;
    builder->strings = strings;
    builder->strings_length = 0;
    builder->strings_capacity = strings_capacity;
    builder->hash = hash;
    builder->hash_slots = hash_slots;
    builder->error = (hash_slots & (hash_slots - 1)) != 0 ||
                     capacity < FDT_HEADER_BYTES + FDT_RESERVE_MAP_BYTES;
    if (builder->error)
        return;
    memset(hash, 0, hash_slots * sizeof(*hash));
    memset(buffer, 0, FDT_HEADER_BYTES + FDT_RESERVE_MAP_BYTES);
    builder->length = FDT_HEADER_BYTES + FDT_RESERVE_MAP_BYTES;
}

void fdt_begin_node(struct fdt_builder *builder, const char *name, size_t name_length)
{
    size_t padded = align_up(name_length + 1, 4);

    put32(builder, FDT_BEGIN_NODE);
    if (builder->error || builder->capacity - builder->length < padded) {
        builder->error = 1;
        return;
    }
    memcpy(builder->buffer + builder->length, name, name_length);
    memset(builder->buffer + builder->length + name_length, 0, padded - name_length);
    builder->length += padded;
}

static uint32_t string_offset(struct fdt_builder *builder, const char *name, size_t length)
{
    uint32_t hash = 2166136261u;

    for (size_t index = 0; index < length; index++) {
        hash ^= (uint8_t)name[index];
        hash *= 16777619u;
    }
    size_t mask = builder->hash_slots - 1;
    for (size_t probe = 0; probe < builder->hash_slots; probe++) {
        size_t slot = (hash + probe) & mask;
        uint32_t entry = builder->hash[slot];
        if (!entry) {
            if (builder->strings_capacity - builder->strings_length < length + 1) {
                builder->error = 1;
                return 0;
            }
            uint32_t offset = (uint32_t)builder->strings_length;
            memcpy(builder->strings + offset, name, length);
            builder->strings[offset + length] = 0;
            builder->strings_length += length + 1;
            builder->hash[slot] = offset + 1;
            return offset;
        }
        const char *existing = builder->strings + entry - 1;
        if (lib_strnlen(existing, length + 1) == length && !memcmp(existing, name, length))
            return entry - 1;
    }
    builder->error = 1;
    return 0;
}

void fdt_property(struct fdt_builder *builder, const char *name, size_t name_length,
                  const void *value, size_t length)
{
    uint32_t offset = string_offset(builder, name, name_length);

    put32(builder, FDT_PROP);
    put32(builder, (uint32_t)length);
    put32(builder, offset);
    put_bytes(builder, value, length);
}

void fdt_end_node(struct fdt_builder *builder)
{
    put32(builder, FDT_END_NODE);
}

size_t fdt_finish(struct fdt_builder *builder)
{
    put32(builder, FDT_END);
    if (builder->error)
        return 0;
    size_t structure_offset = FDT_HEADER_BYTES + FDT_RESERVE_MAP_BYTES;
    size_t structure_length = builder->length - structure_offset;
    size_t strings_offset = builder->length;
    if (builder->capacity - builder->length < builder->strings_length) {
        builder->error = 1;
        return 0;
    }
    memcpy(builder->buffer + strings_offset, builder->strings, builder->strings_length);
    size_t total = align_up(strings_offset + builder->strings_length, 8);
    if (total > builder->capacity) {
        builder->error = 1;
        return 0;
    }
    memset(builder->buffer + strings_offset + builder->strings_length, 0,
           total - strings_offset - builder->strings_length);

    uint8_t *header = builder->buffer;
    store_be32(header + 0, FDT_MAGIC);
    store_be32(header + 4, (uint32_t)total);
    store_be32(header + 8, (uint32_t)structure_offset);
    store_be32(header + 12, (uint32_t)strings_offset);
    store_be32(header + 16, FDT_HEADER_BYTES);
    store_be32(header + 20, FDT_VERSION);
    store_be32(header + 24, FDT_LAST_COMPATIBLE_VERSION);
    store_be32(header + 28, 0);
    store_be32(header + 32, (uint32_t)builder->strings_length);
    store_be32(header + 36, (uint32_t)structure_length);
    return total;
}

/* --- ADT conversion ---------------------------------------------------- */

#define CONVERT_SCRATCH_BYTES 0x10000

static int name_is(const struct adt_property *property, const char *name)
{
    size_t length = strlen(name);
    return property->name_length == length && !memcmp(property->name, name, length);
}

/* Re-encode a sequence of little-endian values of the given cell widths as
 * big-endian FDT cells. A multi-cell value is one little-endian integer (low
 * word first), so reversing all of its bytes gives the FDT order. */
static int encode_cells(const struct adt_property *property, const uint32_t *widths,
                        size_t width_count, uint8_t *out, size_t out_capacity)
{
    size_t stride = 0;

    for (size_t index = 0; index < width_count; index++)
        stride += 4 * widths[index];
    if (!stride || property->length % stride || property->length > out_capacity)
        return -1;
    for (size_t offset = 0; offset < property->length; offset += stride) {
        size_t field = offset;
        for (size_t index = 0; index < width_count; index++) {
            size_t bytes = 4 * widths[index];
            for (size_t byte = 0; byte < bytes; byte++)
                out[field + byte] = property->value[field + bytes - 1 - byte];
            field += bytes;
        }
    }
    return 0;
}

struct convert_state {
    const struct adt *adt;
    struct fdt_builder *builder;
    const struct adt_fdt_extras *extras;
    uint32_t malformed;
    uint8_t scratch[CONVERT_SCRATCH_BYTES];
};

static void emit_u32(struct fdt_builder *builder, const char *name, uint32_t value)
{
    uint8_t encoded[4];
    store_be32(encoded, value);
    fdt_property(builder, name, strlen(name), encoded, 4);
}

/* Converts the node at offset; returns the offset just past it, or 0. */
static size_t convert_node(struct convert_state *state, size_t node, uint32_t parent_address,
                           uint32_t parent_size, unsigned depth)
{
    const struct adt *adt = state->adt;
    struct fdt_builder *builder = state->builder;
    uint32_t address_cells, size_cells;
    int has_address_cells, has_size_cells;

    if (depth > ADT_MAX_DEPTH)
        return 0;
    has_address_cells = !adt_get_u32(adt, node, "#address-cells", &address_cells);
    has_size_cells = !adt_get_u32(adt, node, "#size-cells", &size_cells);
    if (!has_address_cells)
        address_cells = ADT_DEFAULT_ADDRESS_CELLS;
    if (!has_size_cells)
        size_cells = ADT_DEFAULT_SIZE_CELLS;

    if (depth == 0) {
        fdt_begin_node(builder, "", 0);
    } else {
        size_t name_length;
        const char *name = adt_node_name(adt, node, &name_length);
        fdt_begin_node(builder, name, name_length);
    }

    uint32_t property_count = adt_property_count(adt, node);
    size_t offset = adt_first_property(node);
    for (uint32_t index = 0; index < property_count; index++) {
        struct adt_property property;
        adt_read_property(adt, offset, &property);
        offset = adt_next_property(adt, offset);

        if (name_is(&property, "#address-cells") || name_is(&property, "#size-cells")) {
            if (property.length != 4)
                return 0;
            emit_u32(builder, property.name, load_le32(property.value));
            continue;
        }
        if (name_is(&property, "reg") && depth > 0) {
            uint32_t widths[2] = {parent_address, parent_size};
            if (property.length &&
                !encode_cells(&property, widths, 2, state->scratch, sizeof(state->scratch))) {
                fdt_property(builder, "reg", 3, state->scratch, property.length);
                continue;
            }
            /* Not a whole number of entries: keep the bytes, and let a reader
             * that trusts the cell counts reject it rather than misparse it. */
            state->malformed++;
        }
        if (name_is(&property, "ranges")) {
            uint32_t widths[3] = {address_cells, parent_address, size_cells};
            if (property.length &&
                !encode_cells(&property, widths, 3, state->scratch, sizeof(state->scratch))) {
                fdt_property(builder, "ranges", 6, state->scratch, property.length);
                continue;
            }
            state->malformed++;
        }
        if (name_is(&property, "AAPL,phandle") && property.length == 4)
            emit_u32(builder, "phandle", load_le32(property.value));
        fdt_property(builder, property.name, property.name_length, property.value,
                     property.length);
    }

    uint32_t child_count = adt_child_count(adt, node);
    /* The kernel's defaults for missing cell counts are not Apple's, so make
     * them explicit wherever a child's reg or this node's ranges need them. */
    if (child_count) {
        if (!has_address_cells)
            emit_u32(builder, "#address-cells", address_cells);
        if (!has_size_cells)
            emit_u32(builder, "#size-cells", size_cells);
    }
    if (depth == 0)
        fdt_property(builder, "vinix,apple-adt", 15, "", 0);
    if (depth == 1 && state->extras && state->extras->bootargs) {
        size_t name_length;
        const char *name = adt_node_name(adt, node, &name_length);
        if (name_length == 6 && !memcmp(name, "chosen", 6)) {
            const char *bootargs = state->extras->bootargs;
            fdt_property(builder, "bootargs", 8, bootargs, strlen(bootargs) + 1);
        }
    }

    for (uint32_t index = 0; index < child_count; index++) {
        offset = convert_node(state, offset, address_cells, size_cells, depth + 1);
        if (!offset)
            return 0;
    }
    fdt_end_node(builder);
    return offset;
}

int adt_to_fdt(const struct adt *adt, struct fdt_builder *builder,
               struct adt_fdt_extras *extras)
{
    static struct convert_state state;

    if (adt_validate(adt))
        return -1;
    state.adt = adt;
    state.builder = builder;
    state.extras = extras;
    state.malformed = 0;
    size_t end = convert_node(&state, 0, ADT_DEFAULT_ADDRESS_CELLS, ADT_DEFAULT_SIZE_CELLS, 0);
    if (extras)
        extras->malformed_cells = state.malformed;
    if (end != adt->size || builder->error)
        return -1;
    return 0;
}
