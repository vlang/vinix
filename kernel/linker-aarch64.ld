/* Emit a little-endian AArch64 ELF64 image for the Limine boot protocol. */
OUTPUT_FORMAT(elf64-littleaarch64)
OUTPUT_ARCH(aarch64)

ENTRY(main__kmain)

PHDRS
{
    text    PT_LOAD FLAGS(5); /* read + execute */
    rodata  PT_LOAD FLAGS(4); /* read */
    data    PT_LOAD FLAGS(6); /* read + write */
}

SECTIONS
{
    /* Limine maps executable segments at or above this higher-half address. */
    . = 0xffffffff80000000;

    text_start = .;
    .text : {
        *(.text .text.*)
    } :text

    . = ALIGN(CONSTANT(MAXPAGESIZE));
    text_end = .;
    rodata_start = .;
    .rodata : {
        *(.rodata .rodata.*)
    } :rodata

    . = ALIGN(CONSTANT(MAXPAGESIZE));
    rodata_end = .;
    data_start = .;
    .data : {
        *(.data .data.*)
        . = ALIGN(8);
        KEEP(*(.requests_start_marker))
        KEEP(*(.requests))
        KEEP(*(.requests_end_marker))
    } :data

    .bss : {
        *(.bss .bss.*)
        *(COMMON)
    } :data

    data_end = .;

    /DISCARD/ : {
        *(.eh_frame*)
        *(.note .note.*)
    }
}
