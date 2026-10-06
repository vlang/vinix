/* SPDX-License-Identifier: MIT */
.set noreorder
.set noat
.text
.globl _start
_start:
    lui $sp, 0x001f
    ori $sp, $sp, 0xff00
    jal iop_main
    nop
1:  b 1b
    nop
