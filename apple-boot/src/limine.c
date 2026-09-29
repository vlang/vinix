// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* The part of the Limine boot protocol the Vinix kernel uses, answered the
 * way Limine 12.8 answers it at base revision 2: every pointer in a response
 * is a higher-half direct-map address, responses live in bootloader-
 * reclaimable memory, and a request the loader cannot honour keeps a NULL
 * response (the kernel checks). Requests are found by scanning the loaded
 * image for the protocol's common identifier words, as Limine does. */
#include "lib.h"
#include "loader.h"

#define COMMON_0 0xc7b1dd30df4c8b88ull
#define COMMON_1 0x0a82e883a194f07bull
#define BASE_REVISION_0 0xf9562b2d5c95a6c8ull
#define BASE_REVISION_1 0x6a7b384944536bdcull
#define SUPPORTED_BASE_REVISION 2

#define REQUEST_BOOTLOADER_INFO 0xf55038d8e2a1202full
#define REQUEST_HHDM 0x48dcf1cb8ad2b852ull
#define REQUEST_FRAMEBUFFER 0x9d5827dcd881dd75ull
#define REQUEST_PAGING_MODE 0x95c1a0edab0944cbull
#define REQUEST_MEMMAP 0x67cf3d9d378a806full
#define REQUEST_KERNEL_FILE 0xad97e90e83f1ed67ull
#define REQUEST_MODULE 0x3e7e279702be32afull
#define REQUEST_BOOT_TIME 0x502746e184c088aaull
#define REQUEST_KERNEL_ADDRESS 0x71ba76863cc55f63ull
#define REQUEST_DTB 0xb40ddb48fb54bac7ull

#define RESPONSE_OFFSET 40 /* id[4], revision, then the response pointer */

struct limine_file {
    uint64_t revision;
    uint64_t address;
    uint64_t size;
    uint64_t path;
    uint64_t cmdline;
    uint32_t media_type;
    uint32_t unused;
    uint32_t tftp_ip;
    uint32_t tftp_port;
    uint32_t partition_index;
    uint32_t mbr_disk_id;
    uint8_t gpt_disk_uuid[16];
    uint8_t gpt_part_uuid[16];
    uint8_t part_uuid[16];
};

struct limine_framebuffer {
    uint64_t address;
    uint64_t width;
    uint64_t height;
    uint64_t pitch;
    uint16_t bpp;
    uint8_t memory_model;
    uint8_t red_mask_size;
    uint8_t red_mask_shift;
    uint8_t green_mask_size;
    uint8_t green_mask_shift;
    uint8_t blue_mask_size;
    uint8_t blue_mask_shift;
    uint8_t unused[7];
    uint64_t edid_size;
    uint64_t edid;
};

/* One reclaimable arena holds every response; carved sequentially. */
struct arena {
    uint64_t base;
    uint64_t used;
    uint64_t size;
};

static void *arena_take(struct arena *arena, uint64_t bytes)
{
    uint64_t start = align_up(arena->used, 16);
    if (start + bytes > arena->size)
        loader_fail(0x0c01, bytes);
    arena->used = start + bytes;
    return (void *)(uintptr_t)(arena->base + start);
}

static uint64_t hhdm(const void *physical)
{
    return (uint64_t)(uintptr_t)physical + HHDM_OFFSET;
}

static const char *copy_string(struct arena *arena, const char *text)
{
    size_t length = strlen(text);
    char *copy = arena_take(arena, length + 1);
    memcpy(copy, text, length + 1);
    return copy;
}

static void set_response(uint8_t *request, const void *response)
{
    uint64_t value = hhdm(response);
    memcpy(request + RESPONSE_OFFSET, &value, 8);
}

static void answer(const struct limine_inputs *inputs, struct arena *arena, uint8_t *request,
                   uint64_t id)
{
    switch (id) {
    case REQUEST_BOOTLOADER_INFO: {
        uint64_t *response = arena_take(arena, 24);
        response[0] = 0;
        response[1] = hhdm(copy_string(arena, "Vinix Apple loader"));
        response[2] = hhdm(copy_string(arena, "1"));
        set_response(request, response);
        break;
    }
    case REQUEST_HHDM: {
        uint64_t *response = arena_take(arena, 16);
        response[0] = 0;
        response[1] = HHDM_OFFSET;
        set_response(request, response);
        break;
    }
    case REQUEST_PAGING_MODE: {
        uint64_t *response = arena_take(arena, 16);
        response[0] = 0;
        response[1] = 0; /* four levels, 48-bit */
        set_response(request, response);
        break;
    }
    case REQUEST_KERNEL_ADDRESS: {
        uint64_t *response = arena_take(arena, 24);
        response[0] = 0;
        response[1] = inputs->kernel->phys_base;
        response[2] = inputs->kernel->virt_base;
        set_response(request, response);
        break;
    }
    case REQUEST_DTB: {
        uint64_t *response = arena_take(arena, 16);
        response[0] = 0;
        response[1] = inputs->dtb_phys + HHDM_OFFSET;
        set_response(request, response);
        break;
    }
    case REQUEST_BOOT_TIME: {
        uint64_t *response = arena_take(arena, 16);
        response[0] = 0;
        response[1] = inputs->boot_time;
        set_response(request, response);
        break;
    }
    case REQUEST_MEMMAP: {
        uint64_t *response = arena_take(arena, 24);
        struct memmap_entry *entries =
            arena_take(arena, sizeof(struct memmap_entry) * inputs->memmap_count);
        uint64_t *pointers = arena_take(arena, 8ull * inputs->memmap_count);
        for (unsigned index = 0; index < inputs->memmap_count; index++) {
            entries[index] = inputs->memmap[index];
            pointers[index] = hhdm(&entries[index]);
        }
        response[0] = 0;
        response[1] = inputs->memmap_count;
        response[2] = hhdm(pointers);
        set_response(request, response);
        break;
    }
    case REQUEST_FRAMEBUFFER: {
        const struct boot_video *video = inputs->video;
        unsigned depth = (unsigned)(video->depth & 0xff);
        if (!video->base || (depth != 30 && depth != 32))
            break;
        struct limine_framebuffer *framebuffer = arena_take(arena, sizeof(*framebuffer));
        memset(framebuffer, 0, sizeof(*framebuffer));
        framebuffer->address = video->base + HHDM_OFFSET;
        framebuffer->width = video->width;
        framebuffer->height = video->height;
        framebuffer->pitch = video->stride;
        framebuffer->bpp = 32;
        framebuffer->memory_model = 1; /* RGB */
        unsigned channel = depth == 30 ? 10 : 8;
        framebuffer->red_mask_size = (uint8_t)channel;
        framebuffer->red_mask_shift = (uint8_t)(2 * channel);
        framebuffer->green_mask_size = (uint8_t)channel;
        framebuffer->green_mask_shift = (uint8_t)channel;
        framebuffer->blue_mask_size = (uint8_t)channel;
        framebuffer->blue_mask_shift = 0;
        uint64_t *pointers = arena_take(arena, 8);
        pointers[0] = hhdm(framebuffer);
        uint64_t *response = arena_take(arena, 24);
        response[0] = 0;
        response[1] = 1;
        response[2] = hhdm(pointers);
        set_response(request, response);
        break;
    }
    case REQUEST_KERNEL_FILE: {
        struct limine_file *file = arena_take(arena, sizeof(*file));
        memset(file, 0, sizeof(*file));
        file->address = inputs->kernel_file_phys + HHDM_OFFSET;
        file->size = inputs->kernel_file_bytes;
        file->path = hhdm(copy_string(arena, "/boot/vinix"));
        file->cmdline = hhdm(copy_string(arena, inputs->cmdline));
        uint64_t *response = arena_take(arena, 16);
        response[0] = 0;
        response[1] = hhdm(file);
        set_response(request, response);
        break;
    }
    case REQUEST_MODULE: {
        if (!inputs->initramfs_bytes)
            break;
        struct limine_file *file = arena_take(arena, sizeof(*file));
        memset(file, 0, sizeof(*file));
        file->address = inputs->initramfs_phys + HHDM_OFFSET;
        file->size = inputs->initramfs_bytes;
        file->path = hhdm(copy_string(arena, "/boot/initramfs.tar"));
        file->cmdline = hhdm(copy_string(arena, "initramfs"));
        uint64_t *pointers = arena_take(arena, 8);
        pointers[0] = hhdm(file);
        uint64_t *response = arena_take(arena, 24);
        response[0] = 0;
        response[1] = 1;
        response[2] = hhdm(pointers);
        set_response(request, response);
        break;
    }
    default:
        /* MP, RSDP, SMBIOS, EFI, stack size, ...: not offered on Apple
         * hardware; the kernel falls back when the response is NULL. */
        break;
    }
}

unsigned limine_answer(const struct limine_inputs *inputs, struct allocator *allocator)
{
    const struct loaded_kernel *kernel = inputs->kernel;
    uint8_t *image = (uint8_t *)(uintptr_t)kernel->phys_base;
    struct arena arena = {alloc_zeroed(allocator, 0x10000, PAGE_SIZE), 0, 0x10000};
    unsigned answered = 0;

    for (uint64_t offset = 0; offset + 32 <= kernel->bytes; offset += 8) {
        uint64_t first = *(const uint64_t *)(const void *)(image + offset);
        if (first == BASE_REVISION_0) {
            if (*(const uint64_t *)(const void *)(image + offset + 8) == BASE_REVISION_1) {
                uint64_t *revision = (uint64_t *)(void *)(image + offset + 16);
                /* Zero acknowledges a revision this loader implements. */
                if (*revision <= SUPPORTED_BASE_REVISION)
                    *revision = 0;
            }
            continue;
        }
        if (first != COMMON_0 || *(const uint64_t *)(const void *)(image + offset + 8) != COMMON_1)
            continue;
        uint64_t id = *(const uint64_t *)(const void *)(image + offset + 16);
        answer(inputs, &arena, image + offset, id);
        answered++;
        offset += 40;
    }
    return answered;
}
