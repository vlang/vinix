/*
 * linker.ld: Linker script of the kernel.
 * Code is governed by the GPL-2.0 license.
 * Copyright (C) 2021-2022 The Vinix authors.
 */

/* Tell the linker that we want an x86_64 ELF64 output file */
OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)

/* We want the symbol main__kmain to be our entry point */
ENTRY(main__kmain)

SECTIONS
{
    /* We want to be placed in the topmost 2GiB of the address space, for optimisations */
    /* and because that is what the Limine spec mandates. */
    /* Any address in this region will do, but often 0xffffffff80000000 is chosen as */
    /* that is the beginning of the region. */
    /* Additionally, given there may need to be some space allocated before .text for */
    /* additonal ELF cruft, have .text start at 0xffffffff80000000 + its own alignment */
    /* instead of just 0xffffffff80000000. */
    . = 0xffffffff80000000 + CONSTANT(MAXPAGESIZE);

    text_start = .;

    .text ALIGN(CONSTANT(MAXPAGESIZE)) : {
        *(.text .text.*)
    }

    text_end = .;

    rodata_start = .;

    .rodata ALIGN(CONSTANT(MAXPAGESIZE)) : {
        *(.rodata .rodata.*)
    }

    rodata_end = .;

    data_start = .;

    .data ALIGN(CONSTANT(MAXPAGESIZE)) : {
        *(.data .data.*)

        /* Place the sections that contain the Limine requests as part of the .data */
        /* output section. */
        KEEP(*(.requests_start_marker))
        KEEP(*(.requests))
        KEEP(*(.requests_end_marker))
    }

    /* Dynamic section for relocations and other PIE information. */
    .dynamic : {
        *(.dynamic)
    }

    /* NOTE: .bss needs to be the last thing mapped to the data PHDR, otherwise lots of */
    /* unnecessary zeros will be written to the binary. */
    /* If you need, for example, .init_array and .fini_array, those should be placed */
    /* above this. */
    .bss : {
        *(.bss .bss.*)
        *(COMMON)
    }

    data_end = .;

    /* Discard the program interpreter section since we do not need one. This is */
    /* more or less equivalent to the --no-dynamic-linker linker flag, except that it */
    /* works with ld.gold. */
    /DISCARD/ : {
        *(.interp)
    }
}
