/* Tell the linker that we want the symbol _start to be our entry point */
ENTRY(main__kmain)

SECTIONS
{
    /* We wanna be placed in the higher half, 2MiB above 0 in physical memory. */
    . = 0xffffffff80200000;

    /* We place the .stivalehdr section containing the header in its own section, */
    /* and we use the KEEP directive on it to make sure it doesn't get discarded. */
    .stivale2hdr : {
        KEEP(*(.stivale2hdr))
    }

    /* Then let's place all the other traditional executable sections afterwards. */
    .text : {
        *(.text*)
    }

    .rodata : {
        *(.rodata*)
    }

    .data : {
        *(.data*)
        *(.symbol_map*)
    }

    .bss : {
        *(COMMON)
        *(.bss*)
    }
}
