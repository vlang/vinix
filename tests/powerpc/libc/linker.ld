OUTPUT_FORMAT(elf32-powerpc)
OUTPUT_ARCH(powerpc)
ENTRY(_start)
PHDRS {
    headers PT_PHDR PHDRS;
    text PT_LOAD FILEHDR PHDRS FLAGS(5);
    data PT_LOAD FLAGS(6);
    tls PT_TLS FLAGS(4);
}
SECTIONS {
    . = 0x40000000 + SIZEOF_HEADERS;
    .text : { *(.text .text.*) *(.init) *(.fini) } :text
    .rodata : { *(.rodata .rodata.*) *(.eh_frame*) } :text
    . = 0x50000000;
    .data : { *(.data .data.*) *(.sdata .sdata.*) *(.got .got.*) } :data
    .tdata : { *(.tdata .tdata.*) } :data :tls
    .tbss : { *(.tbss .tbss.*) } :data :tls
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
