/* This fixture has no TLS variables. Do not emit an empty, unmapped PT_TLS
 * header: some lld versions retain it and the kernel correctly rejects it. */
OUTPUT_FORMAT(elf32-powerpc)
OUTPUT_ARCH(powerpc)
ENTRY(_start)
PHDRS {
    headers PT_PHDR PHDRS;
    text PT_LOAD FILEHDR PHDRS FLAGS(5);
    data PT_LOAD FLAGS(6);
}
SECTIONS {
    . = 0x40000000 + SIZEOF_HEADERS;
    .text : { *(.text .text.*) *(.init) *(.fini) } :text
    .rodata : { *(.rodata .rodata.*) *(.eh_frame*) } :text
    . = 0x50000000;
    .data : { *(.data .data.*) *(.sdata .sdata.*) *(.got .got.*) } :data
    .init_array : {
        __init_array_start = .;
        KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*))) KEEP(*(.init_array))
        __init_array_end = .;
    } :data
    .fini_array : {
        __fini_array_start = .;
        KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*))) KEEP(*(.fini_array))
        __fini_array_end = .;
    } :data
    .bss : { *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON) } :data
    /DISCARD/ : { *(.comment) *(.note*) }
}
