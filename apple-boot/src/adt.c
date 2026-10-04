// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "adt.h"
#include "lib.h"

#define PROPERTY_HEADER_BYTES (ADT_NAME_BYTES + 4)

static uint32_t property_length(const struct adt *adt, size_t property)
{
    return load_le32(adt->base + property + ADT_NAME_BYTES) & ADT_LENGTH_MASK;
}

uint32_t adt_property_count(const struct adt *adt, size_t node)
{
    return load_le32(adt->base + node);
}

uint32_t adt_child_count(const struct adt *adt, size_t node)
{
    return load_le32(adt->base + node + 4);
}

size_t adt_first_property(size_t node)
{
    return node + 8;
}

size_t adt_next_property(const struct adt *adt, size_t property)
{
    return property + PROPERTY_HEADER_BYTES + align_up(property_length(adt, property), 4);
}

size_t adt_first_child(const struct adt *adt, size_t node)
{
    size_t offset = adt_first_property(node);
    uint32_t count = adt_property_count(adt, node);

    for (uint32_t index = 0; index < count; index++)
        offset = adt_next_property(adt, offset);
    return offset;
}

size_t adt_next_sibling(const struct adt *adt, size_t node)
{
    size_t offset = adt_first_child(adt, node);
    uint32_t count = adt_child_count(adt, node);

    for (uint32_t index = 0; index < count; index++)
        offset = adt_next_sibling(adt, offset);
    return offset;
}

/* Recursive structural check; returns the end offset of the node or 0. */
static size_t validate_node(const struct adt *adt, size_t node, unsigned depth)
{
    if (depth > ADT_MAX_DEPTH || node > adt->size || adt->size - node < 8)
        return 0;
    uint32_t properties = adt_property_count(adt, node);
    uint32_t children = adt_child_count(adt, node);
    if (properties > 0x10000 || children > 0x10000)
        return 0;
    size_t offset = adt_first_property(node);
    for (uint32_t index = 0; index < properties; index++) {
        if (adt->size - offset < PROPERTY_HEADER_BYTES)
            return 0;
        /* The name must be terminated inside its 32 bytes. */
        if (lib_strnlen((const char *)adt->base + offset, ADT_NAME_BYTES) == ADT_NAME_BYTES)
            return 0;
        uint64_t padded = align_up(property_length(adt, offset), 4);
        if (adt->size - offset - PROPERTY_HEADER_BYTES < padded)
            return 0;
        offset += PROPERTY_HEADER_BYTES + padded;
    }
    for (uint32_t index = 0; index < children; index++) {
        offset = validate_node(adt, offset, depth + 1);
        if (!offset)
            return 0;
    }
    return offset;
}

int adt_validate(const struct adt *adt)
{
    if (!adt->base || adt->size < 8)
        return -1;
    return validate_node(adt, 0, 0) == adt->size ? 0 : -1;
}

void adt_read_property(const struct adt *adt, size_t property, struct adt_property *out)
{
    out->name = (const char *)adt->base + property;
    out->name_length = lib_strnlen(out->name, ADT_NAME_BYTES);
    out->length = property_length(adt, property);
    out->value = adt->base + property + PROPERTY_HEADER_BYTES;
}

int adt_get(const struct adt *adt, size_t node, const char *name, struct adt_property *out)
{
    size_t name_length = strlen(name);
    size_t offset = adt_first_property(node);
    uint32_t count = adt_property_count(adt, node);

    for (uint32_t index = 0; index < count; index++) {
        struct adt_property property;
        adt_read_property(adt, offset, &property);
        if (property.name_length == name_length && !memcmp(property.name, name, name_length)) {
            *out = property;
            return 0;
        }
        offset = adt_next_property(adt, offset);
    }
    return -1;
}

int adt_get_u32(const struct adt *adt, size_t node, const char *name, uint32_t *value)
{
    struct adt_property property;

    if (adt_get(adt, node, name, &property) || property.length < 4)
        return -1;
    *value = load_le32(property.value);
    return 0;
}

int adt_get_u64(const struct adt *adt, size_t node, const char *name, uint64_t *value)
{
    struct adt_property property;

    if (adt_get(adt, node, name, &property))
        return -1;
    if (property.length >= 8)
        *value = load_le64(property.value);
    else if (property.length >= 4)
        *value = load_le32(property.value);
    else
        return -1;
    return 0;
}

const char *adt_node_name(const struct adt *adt, size_t node, size_t *length)
{
    struct adt_property property;

    if (adt_get(adt, node, "name", &property) || !property.length) {
        *length = 0;
        return "";
    }
    *length = lib_strnlen((const char *)property.value, property.length);
    return (const char *)property.value;
}

int adt_is_compatible(const struct adt *adt, size_t node, const char *compatible)
{
    struct adt_property property;
    size_t wanted = strlen(compatible);

    if (adt_get(adt, node, "compatible", &property))
        return 0;
    for (size_t offset = 0; offset < property.length;) {
        const char *entry = (const char *)property.value + offset;
        size_t length = lib_strnlen(entry, property.length - offset);
        if (length == wanted && !memcmp(entry, compatible, wanted))
            return 1;
        offset += length + 1;
    }
    return 0;
}

static int find_child(const struct adt *adt, size_t node, const char *name, size_t length,
                      size_t *child)
{
    size_t offset = adt_first_child(adt, node);
    uint32_t count = adt_child_count(adt, node);

    for (uint32_t index = 0; index < count; index++) {
        size_t child_length;
        const char *child_name = adt_node_name(adt, offset, &child_length);
        if (child_length == length && !memcmp(child_name, name, length)) {
            *child = offset;
            return 0;
        }
        offset = adt_next_sibling(adt, offset);
    }
    return -1;
}

int adt_find_path(const struct adt *adt, const char *path, size_t *node, size_t *chain,
                  size_t chain_capacity)
{
    size_t current = 0;
    size_t depth = 0;

    if (chain_capacity < 2)
        return -1;
    chain[depth++] = current;
    while (*path) {
        while (*path == '/')
            path++;
        if (!*path)
            break;
        size_t length = 0;
        while (path[length] && path[length] != '/')
            length++;
        if (find_child(adt, current, path, length, &current))
            return -1;
        if (depth + 1 >= chain_capacity)
            return -1;
        chain[depth++] = current;
        path += length;
    }
    chain[depth] = SIZE_MAX;
    *node = current;
    return 0;
}

void adt_cell_counts(const struct adt *adt, size_t node, uint32_t *address_cells,
                     uint32_t *size_cells)
{
    if (adt_get_u32(adt, node, "#address-cells", address_cells))
        *address_cells = ADT_DEFAULT_ADDRESS_CELLS;
    if (adt_get_u32(adt, node, "#size-cells", size_cells))
        *size_cells = ADT_DEFAULT_SIZE_CELLS;
}

static uint64_t read_cells(const uint8_t *value, uint32_t cells)
{
    if (cells == 0)
        return 0;
    if (cells == 1)
        return load_le32(value);
    return load_le64(value);
}

int adt_get_reg(const struct adt *adt, const size_t *chain, size_t index, uint64_t *address,
                uint64_t *size)
{
    size_t depth = 0;

    while (chain[depth] != SIZE_MAX)
        depth++;
    if (depth < 2)
        return -1;
    size_t node = chain[depth - 1];
    uint32_t address_cells, size_cells;
    adt_cell_counts(adt, chain[depth - 2], &address_cells, &size_cells);
    if (address_cells > 2 || size_cells > 2)
        return -1;

    struct adt_property reg;
    if (adt_get(adt, node, "reg", &reg))
        return -1;
    size_t stride = 4 * (address_cells + size_cells);
    if (!stride || (index + 1) * stride > reg.length)
        return -1;
    const uint8_t *entry = reg.value + index * stride;
    uint64_t result = read_cells(entry, address_cells);
    if (size)
        *size = read_cells(entry + 4 * address_cells, size_cells);

    /* Walk each bus from the node's parent up to (not including) the root.
     * Like XNU's IODTResolveAddressCell, a bus without ranges ends the walk:
     * the address is already a CPU physical address there. */
    for (size_t bus_index = depth - 2; bus_index > 0; bus_index--) {
        size_t bus = chain[bus_index];
        size_t parent = chain[bus_index - 1];
        struct adt_property ranges;
        if (adt_get(adt, bus, "ranges", &ranges) || !ranges.length)
            break;
        uint32_t child_cells, bus_size_cells, parent_cells, parent_size_cells;
        adt_cell_counts(adt, bus, &child_cells, &bus_size_cells);
        adt_cell_counts(adt, parent, &parent_cells, &parent_size_cells);
        size_t range_stride = 4 * (child_cells + parent_cells + bus_size_cells);
        if (!range_stride || ranges.length % range_stride)
            return -1;
        int translated = 0;
        for (size_t offset = 0; offset < ranges.length; offset += range_stride) {
            const uint8_t *range = ranges.value + offset;
            uint64_t child = read_cells(range, child_cells);
            uint64_t parent_address = read_cells(range + 4 * child_cells, parent_cells);
            uint64_t length = read_cells(range + 4 * (child_cells + parent_cells), bus_size_cells);
            if (result >= child && result - child < length) {
                result = parent_address + (result - child);
                translated = 1;
                break;
            }
        }
        if (!translated)
            return -1;
    }
    *address = result;
    return 0;
}
