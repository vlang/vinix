/* Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
 * Use of this source code is governed by a GPL v2 license
 * that can be found in the LICENSE file.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Position-independent raw image. iBoot loads the file anywhere and jumps to
 * +0x800. The payload (kernel, initramfs, command line) is appended to the
 * file at loader_end, so every byte the loader uses -- its stack and .bss
 * included -- must be inside the file: an uninitialised tail would overlap
 * the payload. */
ENTRY(_start)

SECTIONS
{
    . = 0;
    loader_base = .;

    .init : { KEEP(*(.init)) }
    .text : ALIGN(16) { *(.text .text.*) }
    .rodata : ALIGN(16) { *(.rodata .rodata.*) *(.srodata .srodata.*) }
    .data.rel.ro : ALIGN(16) { *(.data.rel.ro .data.rel.ro.*) }
    .got : ALIGN(8) { *(.got .got.plt) }
    /* Zero-initialised data goes in with .data, which lld writes out as
     * zeros: a NOBITS tail would lie under the payload. */
    .data : ALIGN(16) { *(.data .data.*) *(.bss .bss.*) *(COMMON) }
    .dynamic : ALIGN(8) { *(.dynamic) }
    .rela.dyn : ALIGN(8) {
        loader_rela_start = .;
        *(.rela.dyn .rela.*)
        loader_rela_end = .;
    }
    /* The stack is a PROGBITS section in start.S for the same reason. */
    .stack : ALIGN(16) { KEEP(*(.stack)) }
    . = ALIGN(0x4000);
    loader_end = .;

    /DISCARD/ : { *(.comment) *(.note .note.*) *(.eh_frame .eh_frame_hdr) }
}
