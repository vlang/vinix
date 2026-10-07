/* SPDX-License-Identifier: MIT */
/* Instruction-only EE ordering boundary. */
.set noreorder
.text
.globl ps2_ee_sync
ps2_ee_sync:
    sync
    jr $ra
    nop
