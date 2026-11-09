OUTPUT_FORMAT(elf32-powerpc)
OUTPUT_ARCH(powerpc)
ENTRY(vinix_of_entry)
SECTIONS
{
    . = 0x01000000;
    .text : { KEEP(*(.text.vinix_of_entry)) *(.text .text.*) }
    .rodata : { *(.rodata .rodata.*) }
    .data : { *(.data .data.*) *(.sdata .sdata.*) }
    .bss : { *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON) }
    . = ALIGN(4096);
    vinix_image_end = .;
    /DISCARD/ : { *(.eh_frame*) *(.comment) *(.note*) *(.init_array*) *(.fini_array*) }
}
