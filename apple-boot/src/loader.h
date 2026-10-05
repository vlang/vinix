// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef APPLE_BOOT_LOADER_H
#define APPLE_BOOT_LOADER_H

#include <stddef.h>
#include <stdint.h>

#include "adt.h"

#define PAGE_SIZE 0x4000ull /* Apple's native page; also a multiple of 4 KiB */
#define HHDM_OFFSET 0xffff000000000000ull

/* --- iBoot boot arguments (xnu pexpert/arm64/boot.h) -------------------- */

struct boot_video {
    uint64_t base;
    uint64_t display;
    uint64_t stride;
    uint64_t width;
    uint64_t height;
    uint64_t depth;
};

struct boot_info {
    uint16_t revision;
    uint16_t version;
    uint64_t virt_base;
    uint64_t phys_base;
    uint64_t mem_size;
    uint64_t top_of_kernel_data;
    struct boot_video video;
    uint32_t machine_type;
    uint64_t devtree; /* physical */
    uint32_t devtree_size;
    const char *cmdline; /* NUL-terminated inside boot_args */
    uint64_t boot_flags;
    uint64_t mem_size_actual;
};

int parse_boot_args(uint64_t address, struct boot_info *out);

/* --- Payload appended to the loader image --------------------------------- */

#define PAYLOAD_MAGIC "VNXAPPL1"
#define PAYLOAD_FLAG_MAP_LOW_4G 1u /* QEMU harness: HHDM-map 0-4 GiB like Limine rev 2 */

struct payload_header {
    char magic[8];
    uint32_t header_bytes;
    uint32_t flags;
    uint64_t kernel_offset;
    uint64_t kernel_bytes;
    uint64_t initramfs_offset;
    uint64_t initramfs_bytes;
    uint64_t cmdline_offset;
    uint64_t cmdline_bytes;
    uint64_t build_time; /* seconds since the epoch; Limine boot time */
    uint64_t total_bytes;
};

/* --- On-screen diagnostics -------------------------------------------------- */

void console_init(const struct boot_video *video);
/* A coloured square per stage along the top of the screen. */
void console_stage(unsigned stage);
/* Stops with a red band carrying the failing stage, a code and a value. */
__attribute__((noreturn)) void loader_fail(unsigned code, uint64_t value);
/* Draws a labelled hex value on the diagnostic rows below the stage squares. */
void console_hex(unsigned row, unsigned label, uint64_t value);

/* --- Physical memory ------------------------------------------------------ */

struct allocator {
    uint64_t start;
    uint64_t next;
    uint64_t end;
};

uint64_t alloc_pages(struct allocator *allocator, uint64_t bytes, uint64_t alignment);
uint64_t alloc_zeroed(struct allocator *allocator, uint64_t bytes, uint64_t alignment);

/* --- Page tables (4 KiB granule, 48-bit VA, as Limine hands over) ---------- */

#define PTE_ATTR_NORMAL 0u
#define PTE_ATTR_FRAMEBUFFER 1u
#define PTE_ATTR_DEVICE 2u

#define MAP_WRITE 1u
#define MAP_EXEC 2u

struct pagemap {
    uint64_t root;
    struct allocator *allocator;
};

void pagemap_init(struct pagemap *map, struct allocator *allocator);
void map_range(struct pagemap *map, uint64_t virt, uint64_t phys, uint64_t bytes,
               unsigned attribute, unsigned flags);

/* --- Kernel image ----------------------------------------------------------- */

struct loaded_kernel {
    uint64_t entry;
    uint64_t phys_base;
    uint64_t virt_base;
    uint64_t bytes; /* span from virt_base, page-rounded */
    struct {
        uint64_t virt, bytes;
        unsigned flags;
    } segments[16];
    unsigned segment_count;
};

int load_elf(const uint8_t *image, uint64_t size, struct allocator *allocator,
             struct loaded_kernel *out);

/* --- Limine protocol -------------------------------------------------------- */

#define MEMMAP_USABLE 0
#define MEMMAP_RESERVED 1
#define MEMMAP_BOOTLOADER_RECLAIMABLE 5
#define MEMMAP_KERNEL_AND_MODULES 6
#define MEMMAP_FRAMEBUFFER 7
#define MEMMAP_MAX_ENTRIES 64
#define RESERVED_MAX_RANGES 48

struct memmap_entry {
    uint64_t base;
    uint64_t length;
    uint64_t type;
};

struct memmap {
    struct memmap_entry entries[MEMMAP_MAX_ENTRIES];
    unsigned count;
};

/* Firmware-owned spans inside RAM, page-aligned, sorted and merged. */
struct reserved_range {
    uint64_t base, end;
};

struct reserved_set {
    struct reserved_range ranges[RESERVED_MAX_RANGES];
    unsigned count;
};

void reserved_collect(const struct adt *adt, uint64_t ram_base, uint64_t ram_end,
                      struct reserved_set *set);
/* The first aligned address at or above from where bytes fit clear of every
 * reserved range. */
uint64_t reserved_window(const struct reserved_set *set, uint64_t from, uint64_t end,
                         uint64_t bytes, uint64_t alignment);
/* Add [base, end) as type, minus the reserved ranges. */
void memmap_add(struct memmap *map, uint64_t base, uint64_t end, uint64_t type,
                const struct reserved_set *reserved);
void memmap_add_reserved(struct memmap *map, const struct reserved_set *reserved);

struct limine_inputs {
    const struct loaded_kernel *kernel;
    uint64_t kernel_file_phys, kernel_file_bytes;
    uint64_t initramfs_phys, initramfs_bytes;
    const char *cmdline;
    uint64_t dtb_phys;
    const struct boot_video *video;
    const struct memmap_entry *memmap;
    unsigned memmap_count;
    uint64_t boot_time;
};

/* Fills every request the loaded kernel carries; returns how many. */
unsigned limine_answer(const struct limine_inputs *inputs, struct allocator *allocator);

/* --- Assembly --------------------------------------------------------------- */

__attribute__((noreturn)) void enter_kernel(uint64_t entry, uint64_t stack, uint64_t sctlr,
                                            uint64_t mair, uint64_t tcr, uint64_t ttbr0,
                                            uint64_t ttbr1);
void cache_invalidate_range(uint64_t start, uint64_t end);
void quiesce_fiq_sources(void);
uint64_t read_id_aa64mmfr0(void);
uint64_t read_current_el(void);
uint64_t read_midr(void);
__attribute__((noreturn)) void halt_forever(void);

void disable_watchdog(const struct adt *adt);

#endif
