/* SPDX-License-Identifier: MIT */
ENTRY(_start)
PHDRS { text PT_LOAD FLAGS(5); }
SECTIONS {
    . = 0xa4000040;
    .text : { *(.text) *(.text.*) } :text
    /DISCARD/ : { *(.MIPS.abiflags) *(.reginfo) *(.pdr) *(.mdebug*) *(.comment) }
}
