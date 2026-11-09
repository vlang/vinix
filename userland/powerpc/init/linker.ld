OUTPUT_FORMAT(elf32-powerpc)
OUTPUT_ARCH(powerpc)
ENTRY(vinix_user_init)
PHDRS { text PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); }
SECTIONS {
    . = 0x40000000;
    .text : { KEEP(*(.text.vinix_user_init)) *(.text .text.*) } :text
    .rodata : { *(.rodata .rodata.*) } :text
    . = 0x50000000;
    .data : { *(.data .data.*) *(.sdata .sdata.*) } :data
    .bss : { *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON) } :data
    /DISCARD/ : { *(.eh_frame*) *(.comment) *(.note*) *(.init_array*) *(.fini_array*) }
}
