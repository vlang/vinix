/* SPDX-License-Identifier: MIT */
ENTRY(_start)
PHDRS { text PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); }
SECTIONS {
    . = 0x80000400;
    .text : { *(.text) *(.text.*) } :text
    .rodata : { *(.rodata) *(.rodata.*) } :text
    .data : { *(.data) *(.data.*) } :data
    . = ALIGN(4);
    __bss_start = .;
    .bss : { *(.bss) *(.bss.*) *(COMMON) } :data
    . = ALIGN(4);
    __bss_end = .;
    /DISCARD/ : { *(.MIPS.abiflags) *(.reginfo) *(.pdr) *(.mdebug*) *(.comment) }
}
