// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* iBoot's boot arguments, as xnu's pexpert/arm64/boot.h and m1n1's
 * xnuboot.h describe them. Revisions 1-3 differ only in the length of the
 * command line, which moves the two trailing fields; like m1n1, a later
 * revision is read as revision 3.
 *
 *   0x00 u16 revision, u16 version       0x28 video {base, display, stride,
 *   0x08 virt_base                                     width, height, depth}
 *   0x10 phys_base                       0x58 u32 machine_type
 *   0x18 mem_size                        0x60 device tree (iBoot virtual)
 *   0x20 top_of_kernel_data              0x68 u32 device tree size
 *                                        0x6c command line, then
 *                                             boot_flags, mem_size_actual
 */
#include "lib.h"
#include "loader.h"

static const uint32_t cmdline_bytes[] = {0, 256, 608, 1024};

int parse_boot_args(uint64_t address, struct boot_info *out)
{
    const uint8_t *args = (const uint8_t *)(uintptr_t)address;

    out->revision = (uint16_t)(args[0] | args[1] << 8);
    out->version = (uint16_t)(args[2] | args[3] << 8);
    if (out->revision < 1)
        return -1;
    out->virt_base = load_le64(args + 0x08);
    out->phys_base = load_le64(args + 0x10);
    out->mem_size = load_le64(args + 0x18);
    out->top_of_kernel_data = load_le64(args + 0x20);
    out->video.base = load_le64(args + 0x28);
    out->video.display = load_le64(args + 0x30);
    out->video.stride = load_le64(args + 0x38);
    out->video.width = load_le64(args + 0x40);
    out->video.height = load_le64(args + 0x48);
    out->video.depth = load_le64(args + 0x50);
    out->machine_type = load_le32(args + 0x58);
    uint64_t devtree_virtual = load_le64(args + 0x60);
    out->devtree_size = load_le32(args + 0x68);
    out->cmdline = (const char *)args + 0x6c;

    uint64_t tail = align_up(0x6c + cmdline_bytes[out->revision < 3 ? out->revision : 3], 8);
    out->boot_flags = load_le64(args + tail);
    out->mem_size_actual = load_le64(args + tail + 8);

    /* iBoot passes the tree at its virtual address for the kernel it thinks
     * it is starting; the phys/virt pair converts it. */
    if (devtree_virtual < out->virt_base)
        return -1;
    out->devtree = devtree_virtual - out->virt_base + out->phys_base;
    if (!out->mem_size || !out->devtree_size || out->top_of_kernel_data <= out->phys_base ||
        out->top_of_kernel_data >= out->phys_base + out->mem_size)
        return -1;
    return 0;
}
