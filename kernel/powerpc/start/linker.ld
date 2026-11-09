OUTPUT_FORMAT(elf32-powerpc)
OUTPUT_ARCH(powerpc)
ENTRY(vinix_ppc_entry)
SECTIONS {
    . = 0x02000000;
    .text : { KEEP(*(.text.vinix_ppc_entry)) *(.text .text.*) }
    .rodata : { *(.rodata .rodata.*) }
    .data : { *(.data .data.*) *(.sdata .sdata.*) }
    .bss : { *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON) }
    /DISCARD/ : { *(.eh_frame*) *(.comment) *(.note*) *(.init_array*) *(.fini_array*) }
}
