/* SPDX-License-Identifier: MIT */
/* Original, emulator-oriented IPL3. No Nintendo boot code is included. */
.set noreorder
.set noat
.text
.globl _start
_start:
    mtc0 $zero, $12
    lui $t0, 0xa460
    ori $t1, $zero, 0x0400
    sw $t1, 0($t0)             /* RDRAM destination. */
    lui $t1, 0x1000
    ori $t1, $t1, 0x1000
    sw $t1, 4($t0)             /* Cartridge source. */
    lui $t1, 0x000f
    ori $t1, $t1, 0xefff
    sw $t1, 12($t0)            /* Copy the ROM payload through PI. */
1:  lw $t1, 16($t0)
    andi $t1, $t1, 3
    bnez $t1, 1b
    nop
    lui $t0, 0xa000
    lui $t1, 0x0080
    sw $t1, 0x0318($t0)        /* Installed emulator RAM: 8 MiB. */
    lui $t0, 0x8000
    ori $t0, $t0, 0x0400
    jr $t0
    nop
