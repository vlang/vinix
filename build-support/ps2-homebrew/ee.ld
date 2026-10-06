/* SPDX-License-Identifier: MIT */
ENTRY(_start)
PHDRS { text PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); }
SECTIONS {
    . = 0x00100000;
    .text : { *(.text) *(.text.*) } :text
    .rodata : { *(.rodata) *(.rodata.*) } :text
    .data : { *(.data) *(.data.*) } :data
    .bss : { *(.bss) *(.bss.*) *(COMMON) } :data
    /DISCARD/ : { *(.MIPS.abiflags) *(.reginfo) *(.pdr) *(.mdebug*) *(.comment) }
}
