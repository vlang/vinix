// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Host driver for the loader's ADT code: converts an Apple DeviceTree blob to
 * an FDT file with exactly the code the loader runs, and prints reg
 * translations for selected paths. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../src/adt.h"
#include "../src/fdt.h"

static void *read_file(const char *path, size_t *size)
{
    FILE *file = fopen(path, "rb");
    if (!file)
        return NULL;
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    fseek(file, 0, SEEK_SET);
    void *data = malloc((size_t)length);
    if (!data || fread(data, 1, (size_t)length, file) != (size_t)length) {
        fclose(file);
        free(data);
        return NULL;
    }
    fclose(file);
    *size = (size_t)length;
    return data;
}

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "usage: %s ADT FDT [bootargs] [--reg PATH]...\n", argv[0]);
        return 2;
    }
    size_t size;
    void *blob = read_file(argv[1], &size);
    if (!blob) {
        fprintf(stderr, "cannot read %s\n", argv[1]);
        return 1;
    }
    struct adt adt = {blob, size};
    size_t capacity = size + (1u << 20);
    void *buffer = malloc(capacity);
    char *strings = malloc(1u << 20);
    uint32_t *hash = malloc(sizeof(uint32_t) << 16);
    struct fdt_builder builder;
    fdt_begin(&builder, buffer, capacity, strings, 1u << 20, hash, 1u << 16);
    struct adt_fdt_extras extras = {0};
    int argument = 3;
    if (argc > 3 && strcmp(argv[3], "--reg")) {
        extras.bootargs = argv[3];
        argument = 4;
    }
    if (adt_to_fdt(&adt, &builder, &extras)) {
        fprintf(stderr, "conversion failed\n");
        return 1;
    }
    size_t total = fdt_finish(&builder);
    if (!total) {
        fprintf(stderr, "FDT overflowed\n");
        return 1;
    }
    FILE *out = fopen(argv[2], "wb");
    if (!out || fwrite(buffer, 1, total, out) != total) {
        fprintf(stderr, "cannot write %s\n", argv[2]);
        return 1;
    }
    fclose(out);
    printf("adt %zu bytes -> fdt %zu bytes, malformed-cells %u\n", size, total,
           extras.malformed_cells);

    for (; argument + 1 < argc; argument += 2) {
        if (strcmp(argv[argument], "--reg"))
            break;
        size_t node, chain[ADT_MAX_DEPTH + 2];
        if (adt_find_path(&adt, argv[argument + 1], &node, chain, ADT_MAX_DEPTH + 2)) {
            printf("reg %s: not found\n", argv[argument + 1]);
            continue;
        }
        for (size_t index = 0;; index++) {
            uint64_t address, length;
            if (adt_get_reg(&adt, chain, index, &address, &length))
                break;
            printf("reg %s[%zu] 0x%llx 0x%llx\n", argv[argument + 1], index,
                   (unsigned long long)address, (unsigned long long)length);
        }
    }
    return 0;
}
