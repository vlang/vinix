/*
 * linker.ld: Linker script of the kernel.
 * Code is governed by the GPL-2.0 license.
 * Copyright (C) 2021-2022 The Vinix authors.
 */

OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)

/* Tell the linker that we want the symbol main__kmain to be our entry point */
ENTRY(main__kmain)

/* Define the program headers we want so the bootloader gives us the right */
/* MMU permissions */
PHDRS
{
    null    PT_NULL    FLAGS(0) ;
    text    PT_LOAD    FLAGS((1 << 0) | (1 << 2)) ;
    rodata  PT_LOAD    FLAGS(1 << 2) ;
    data    PT_LOAD    FLAGS((1 << 1) | (1 << 2)) ;
}

SECTIONS
{
    /* We wanna be placed in the higher half, 2MiB above 0 in physical memory. */
    . = 0xffffffff80000000;

    .text : {
        *(.text .text.*)
    } : text

    . += CONSTANT(MAXPAGESIZE);

    /* We place the .stivalehdr section containing the header in its own section, */
    /* and we use the KEEP directive on it to make sure it doesn't get discarded. */
    .stivale2hdr : {
        KEEP(*(.stivale2hdr))
    } : rodata

    /* Then let's place all the other traditional executable sections afterwards. */
    .rodata : {
        *(.rodata .rodata.*)
    } : rodata

    .symbol_table : {
        *(.symbol_table)
    } : rodata

    . += CONSTANT(MAXPAGESIZE);

    .data : {
        *(.data .data.*)
    } : data

    .bss : {
        *(COMMON)
        *(.bss .bss.*)
    } : data
}
