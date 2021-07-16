/* Tell the linker that we want the symbol _start to be our entry point */
ENTRY(main__kmain)

SECTIONS
{
    /* We wanna be placed in the higher half, 2MiB above 0 in physical memory. */
    . = 0xffffffff80200000;

    /* We place the .stivalehdr section containing the header in its own section, */
    /* and we use the KEEP directive on it to make sure it doesn't get discarded. */
    .stivale2hdr ALIGN(4K) : {
        KEEP(*(.stivale2hdr))
    }

    /* Then let's place all the other traditional executable sections afterwards. */
    .text ALIGN(4K) : {
        *(.text*)
    }

    .rodata ALIGN(4K) : {
        *(.rodata*)
    }

    .data ALIGN(4K) : {
        *(.data*)
    }

    .bss ALIGN(4K) : {
        *(COMMON)
        *(.bss*)
    }
}
