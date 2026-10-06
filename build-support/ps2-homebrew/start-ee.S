/* SPDX-License-Identifier: MIT */
.set noreorder
.set noat
.text
.globl _start
_start:
    lui $sp, 0x01ff
    ori $sp, $sp, 0xff00
    jal game_main
    nop
1:  b 1b
    nop
