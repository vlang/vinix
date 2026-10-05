// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Loads the kernel ELF physically contiguous with one uniform virtual offset,
 * which is what the Limine protocol promises. */
#include "lib.h"
#include "loader.h"

#define PT_LOAD 1
#define PF_X 1
#define PF_W 2
#define EM_AARCH64 183

static uint16_t le16(const uint8_t *bytes)
{
    return (uint16_t)(bytes[0] | bytes[1] << 8);
}

int load_elf(const uint8_t *image, uint64_t size, struct allocator *allocator,
             struct loaded_kernel *out)
{
    if (size < 64 || memcmp(image, "\177ELF", 4) || image[4] != 2 || image[5] != 1 ||
        le16(image + 18) != EM_AARCH64)
        return -1;
    uint64_t entry = load_le64(image + 24);
    uint64_t phoff = load_le64(image + 32);
    uint16_t phentsize = le16(image + 54);
    uint16_t phnum = le16(image + 56);
    if (phentsize < 56 || phoff > size || (uint64_t)phnum * phentsize > size - phoff)
        return -1;

    uint64_t low = UINT64_MAX, high = 0;
    for (uint16_t index = 0; index < phnum; index++) {
        const uint8_t *header = image + phoff + (uint64_t)index * phentsize;
        if (load_le32(header) != PT_LOAD)
            continue;
        uint64_t vaddr = load_le64(header + 16);
        uint64_t memsz = load_le64(header + 40);
        if (vaddr < low)
            low = vaddr;
        if (vaddr + memsz > high)
            high = vaddr + memsz;
    }
    if (low == UINT64_MAX || low < 0xffffffff80000000ull)
        return -1;
    low &= ~0xfffull;
    high = align_up(high, PAGE_SIZE);

    uint64_t phys = alloc_zeroed(allocator, high - low, 0x200000);
    out->entry = entry;
    out->phys_base = phys;
    out->virt_base = low;
    out->bytes = high - low;
    out->segment_count = 0;

    for (uint16_t index = 0; index < phnum; index++) {
        const uint8_t *header = image + phoff + (uint64_t)index * phentsize;
        if (load_le32(header) != PT_LOAD)
            continue;
        uint32_t flags = load_le32(header + 4);
        uint64_t offset = load_le64(header + 8);
        uint64_t vaddr = load_le64(header + 16);
        uint64_t filesz = load_le64(header + 32);
        uint64_t memsz = load_le64(header + 40);
        if (filesz > memsz || offset > size || filesz > size - offset)
            return -1;
        memcpy((void *)(uintptr_t)(phys + vaddr - low), image + offset, filesz);
        if (out->segment_count == 16)
            return -1;
        out->segments[out->segment_count].virt = vaddr;
        out->segments[out->segment_count].bytes = memsz;
        out->segments[out->segment_count].flags =
            (flags & PF_W ? MAP_WRITE : 0) | (flags & PF_X ? MAP_EXEC : 0);
        out->segment_count++;
    }
    if (entry < low || entry >= high)
        return -1;
    return 0;
}
