/* SPDX-License-Identifier: MIT */
/* Instruction-only native ordering boundary. */
.set noreorder
.text
.globl n64_sync
n64_sync:
    sync
    jr $ra
    nop
