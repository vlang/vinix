/* SPDX-License-Identifier: MIT */
.set noreorder
.set noat
.text
.globl _start
_start:
    mtc0 $zero, $12
    lui $sp, 0x807f
    ori $sp, $sp, 0xff00
    lui $t0, %hi(__bss_start)
    addiu $t0, $t0, %lo(__bss_start)
    lui $t1, %hi(__bss_end)
    addiu $t1, $t1, %lo(__bss_end)
1:  beq $t0, $t1, 2f
    nop
    sw $zero, 0($t0)
    b 1b
    addiu $t0, $t0, 4
2:  jal game_main
    nop
3:  b 3b
    nop
