// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Boot Vinix directly from iBoot on Apple silicon.
 *
 * iBoot starts this image as a custom kernel with the Apple DeviceTree and a
 * framebuffer already set up. The loader converts the tree to an FDT, loads
 * the kernel ELF appended to it, answers the kernel's Limine requests and
 * enters it exactly as Limine 12.8 would on the same CPU, so the kernel runs
 * unchanged. Stages, in the order their squares appear on screen:
 *
 *   0 boot arguments parsed       4 ADT converted to an FDT
 *   1 ADT validated               5 memory map built
 *   2 watchdog disarmed           6 page tables built
 *   3 kernel loaded               7 Limine requests answered, entering
 */
#include "fdt.h"
#include "lib.h"
#include "loader.h"

extern char loader_end[];

#define ALLOCATION_WINDOW_BYTES 0x10000000ull /* kernel, FDT and the late window */
#define LATE_ALLOCATION_BYTES 0x1000000ull /* page tables, responses, stack */
#define KERNEL_STACK_BYTES 0x40000ull
#define FDT_EXTRA_BYTES 0x100000ull
#define FDT_STRINGS_BYTES 0x100000ull
#define FDT_HASH_SLOTS 0x10000ull

#define MAIR_NORMAL 0xffull
#define MAIR_NORMAL_NONCACHEABLE 0x44ull
#define MAIR_DEVICE_NGNRE 0x04ull

#define SCTLR_KERNEL                                                                          \
    ((1ull << 29) | (1ull << 28) | (1ull << 23) | (1ull << 22) | (1ull << 20) |               \
     (1ull << 12) | (1ull << 11) | (1ull << 8) | (1ull << 7) | (1ull << 4) | (1ull << 3) |     \
     (1ull << 2) | (1ull << 0))

static uint64_t tcr_value(void)
{
    uint64_t pa_range = read_id_aa64mmfr0() & 0xf;

    if (pa_range > 5)
        pa_range = 5; /* 48 bits: the most a 4 KiB, four-level map expresses */
    return pa_range << 32 | 2ull << 30 | 3ull << 28 | 1ull << 26 | 1ull << 24 | 16ull << 16 |
           3ull << 12 | 1ull << 10 | 1ull << 8 | 16ull;
}

/* Map [0, 4 GiB) into the direct map around the RAM entries, as Limine does
 * below base revision 3. Only the QEMU harness asks for it; on Apple hardware
 * that window holds nothing the early kernel touches. */
static void map_low_4g(struct pagemap *map, const struct memmap *memmap)
{
    const struct memmap_entry *entries = memmap->entries;
    unsigned count = memmap->count;
    uint64_t cursor = 0, limit = 0x100000000ull;

    for (unsigned index = 0; index <= count && cursor < limit; index++) {
        uint64_t next = index < count ? entries[index].base : limit;
        if (next > limit)
            next = limit;
        if (next > cursor)
            map_range(map, HHDM_OFFSET + cursor, cursor, next - cursor, PTE_ATTR_DEVICE,
                      MAP_WRITE);
        if (index < count && entries[index].base + entries[index].length > cursor)
            cursor = entries[index].base + entries[index].length;
    }
}

void loader_main(uint64_t boot_args, uint64_t image_base)
{
    struct boot_info info;
    int arguments_valid = parse_boot_args(boot_args, &info);

    console_init(&info.video);
    console_stage(0);
    console_hex(0, 0xb0, (uint64_t)info.revision | (uint64_t)read_current_el() << 32);
    if (arguments_valid)
        loader_fail(0x0001, boot_args);

    struct adt adt = {(const uint8_t *)(uintptr_t)info.devtree, info.devtree_size};
    if (adt_validate(&adt))
        loader_fail(0x0101, info.devtree);
    console_stage(1);

    disable_watchdog(&adt);
    console_stage(2);

    const struct payload_header *payload = (const struct payload_header *)loader_end;
    uint64_t payload_base = (uint64_t)(uintptr_t)payload;
    if (memcmp(payload->magic, PAYLOAD_MAGIC, 8) || payload->header_bytes < sizeof(*payload) ||
        payload->kernel_offset + payload->kernel_bytes > payload->total_bytes ||
        payload->initramfs_offset + payload->initramfs_bytes > payload->total_bytes ||
        payload->cmdline_offset + payload->cmdline_bytes > payload->total_bytes ||
        image_base < info.phys_base || payload_base < image_base ||
        payload_base + payload->total_bytes > info.top_of_kernel_data)
        loader_fail(0x0301, payload_base);
    const char *cmdline = payload->cmdline_bytes
                              ? (const char *)payload + payload->cmdline_offset
                              : "";

    /* The loader's own allocations start above iBoot's data, in the first
     * window no coprocessor firmware lies in. */
    uint64_t ram_end = info.phys_base + info.mem_size;
    static struct reserved_set reserved;
    reserved_collect(&adt, info.phys_base, ram_end, &reserved);
    uint64_t window = reserved_window(&reserved, info.top_of_kernel_data, ram_end,
                                      ALLOCATION_WINDOW_BYTES, 0x200000);
    struct allocator allocator = {
        .start = window,
        .next = window,
        .end = window + ALLOCATION_WINDOW_BYTES,
    };
    struct loaded_kernel kernel;
    const uint8_t *kernel_file = (const uint8_t *)payload + payload->kernel_offset;
    if (load_elf(kernel_file, payload->kernel_bytes, &allocator, &kernel))
        loader_fail(0x0302, payload->kernel_bytes);
    console_hex(2, 0xe0, kernel.entry);
    console_stage(3);

    uint64_t fdt_capacity = info.devtree_size + FDT_EXTRA_BYTES;
    uint64_t fdt = alloc_pages(&allocator, fdt_capacity, PAGE_SIZE);
    char *strings = (char *)(uintptr_t)alloc_pages(&allocator, FDT_STRINGS_BYTES, PAGE_SIZE);
    uint32_t *hash = (uint32_t *)(uintptr_t)alloc_pages(&allocator, 4 * FDT_HASH_SLOTS, PAGE_SIZE);
    struct fdt_builder builder;
    fdt_begin(&builder, (void *)(uintptr_t)fdt, fdt_capacity, strings, FDT_STRINGS_BYTES, hash,
              FDT_HASH_SLOTS);
    struct adt_fdt_extras extras = {.bootargs = cmdline};
    if (adt_to_fdt(&adt, &builder, &extras) || !fdt_finish(&builder))
        loader_fail(0x0401, builder.length);
    console_stage(4);

    /* Everything the kernel still reads after hand-off -- tables, responses,
     * its stack -- comes from one window fixed now, so the memory map it is
     * described by can be final before any of it is built. */
    uint64_t late_start = align_up(allocator.next, 0x200000);
    uint64_t late_end = late_start + LATE_ALLOCATION_BYTES;
    if (late_end > allocator.end)
        loader_fail(0x0502, late_end);
    static struct memmap memmap;
    uint64_t kernel_end = kernel.phys_base + kernel.bytes;
    uint64_t payload_start = payload_base & ~0xfffull;
    uint64_t payload_end = align_up(payload_base + payload->total_bytes, 0x1000);
    /* Below the kernel: iBoot's data, the loader and the ADT, which the
     * kernel may reclaim, and the payload, which it keeps: the initramfs
     * module and its own file live there. */
    memmap_add(&memmap, info.phys_base, payload_start, MEMMAP_BOOTLOADER_RECLAIMABLE, &reserved);
    memmap_add(&memmap, payload_start, payload_end, MEMMAP_KERNEL_AND_MODULES, &reserved);
    memmap_add(&memmap, payload_end, kernel.phys_base, MEMMAP_BOOTLOADER_RECLAIMABLE, &reserved);
    memmap_add(&memmap, kernel.phys_base, kernel_end, MEMMAP_KERNEL_AND_MODULES, &reserved);
    memmap_add(&memmap, kernel_end, late_end, MEMMAP_BOOTLOADER_RECLAIMABLE, &reserved);
    memmap_add(&memmap, late_end, ram_end, MEMMAP_USABLE, &reserved);
    memmap_add_reserved(&memmap, &reserved);
    uint64_t fb_base = info.video.base & ~(PAGE_SIZE - 1);
    uint64_t fb_end = align_up(info.video.base + info.video.stride * info.video.height, PAGE_SIZE);
    if (info.video.base)
        memmap_add(&memmap, fb_base, fb_end, MEMMAP_FRAMEBUFFER, &reserved);
    allocator.next = late_start;
    allocator.end = late_end;
    console_hex(3, 0xa0, info.phys_base);
    console_hex(4, 0xa1, info.mem_size | (uint64_t)reserved.count << 56);
    console_stage(5);

    struct pagemap kernel_map, identity_map;
    pagemap_init(&kernel_map, &allocator);
    pagemap_init(&identity_map, &allocator);
    for (unsigned index = 0; index < memmap.count; index++) {
        const struct memmap_entry *entry = &memmap.entries[index];
        if (entry->type == MEMMAP_RESERVED)
            continue;
        unsigned attribute =
            entry->type == MEMMAP_FRAMEBUFFER ? PTE_ATTR_FRAMEBUFFER : PTE_ATTR_NORMAL;
        map_range(&kernel_map, HHDM_OFFSET + entry->base, entry->base, entry->length, attribute,
                  MAP_WRITE);
    }
    if (payload->flags & PAYLOAD_FLAG_MAP_LOW_4G)
        map_low_4g(&kernel_map, &memmap);
    for (unsigned index = 0; index < kernel.segment_count; index++) {
        uint64_t virt = kernel.segments[index].virt & ~0xfffull;
        uint64_t end = align_up(kernel.segments[index].virt + kernel.segments[index].bytes, 0x1000);
        map_range(&kernel_map, virt, kernel.phys_base + (virt - kernel.virt_base), end - virt,
                  PTE_ATTR_NORMAL, kernel.segments[index].flags);
    }
    /* The loader keeps running from physical addresses as the MMU comes on;
     * only its own image needs to be reachable there. */
    uint64_t image_start = image_base & ~0xfffull;
    map_range(&identity_map, image_start, image_start, payload_base - image_start,
              PTE_ATTR_NORMAL, MAP_WRITE | MAP_EXEC);
    console_stage(6);

    uint64_t stack = alloc_zeroed(&allocator, KERNEL_STACK_BYTES, PAGE_SIZE);
    struct limine_inputs inputs = {
        .kernel = &kernel,
        .kernel_file_phys = (uint64_t)(uintptr_t)kernel_file,
        .kernel_file_bytes = payload->kernel_bytes,
        .initramfs_phys = (uint64_t)(uintptr_t)payload + payload->initramfs_offset,
        .initramfs_bytes = payload->initramfs_bytes,
        .cmdline = cmdline,
        .dtb_phys = fdt,
        .video = &info.video,
        .memmap = memmap.entries,
        .memmap_count = memmap.count,
        .boot_time = payload->build_time,
    };
    unsigned answered = limine_answer(&inputs, &allocator);
    console_hex(5, 0xc0, answered);
    console_stage(7);

    quiesce_fiq_sources();

    /* Written with the caches off: drop whatever the firmware still holds
     * for these lines before the kernel reads them cacheably. */
    cache_invalidate_range(kernel.phys_base, kernel_end);
    cache_invalidate_range(allocator.start, late_end);

    enter_kernel(kernel.entry, stack + KERNEL_STACK_BYTES + HHDM_OFFSET, SCTLR_KERNEL,
                 MAIR_NORMAL | MAIR_NORMAL_NONCACHEABLE << 8 | MAIR_DEVICE_NGNRE << 16,
                 tcr_value(), identity_map.root, kernel_map.root);
}
