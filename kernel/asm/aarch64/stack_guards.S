/* SPDX-License-Identifier: GPL-2.0-or-later */
/* These leaf probes recover only at exact PC/address pairs in opt-in kernels.
 * Keep their fault/resume labels adjacent to the faulting instruction. */
.text

.macro GUARD_REGISTERS
    mov x15, #0x1357
    movk x15, #0x2468, lsl #16
    movk x15, #0x9abc, lsl #32
    movk x15, #0xdef0, lsl #48
    mov x16, x15
    mov x17, x15
    mov x2, x15
.endm

.macro GUARD_VERIFY
    cmp x15, x2
    cset x0, eq
    cmp x16, x2
    cset x1, eq
    and x0, x0, x1
    cmp x17, x2
    cset x1, eq
    and x0, x0, x1
    ret
.endm

.global vinix_guard_probe_read
.type vinix_guard_probe_read, %function
vinix_guard_probe_read:
    GUARD_REGISTERS
.global vinix_guard_read_fault
vinix_guard_read_fault:
    ldrb w1, [x0]
.global vinix_guard_read_resume
vinix_guard_read_resume:
    GUARD_VERIFY
.size vinix_guard_probe_read, .-vinix_guard_probe_read

.global vinix_guard_probe_write
.type vinix_guard_probe_write, %function
vinix_guard_probe_write:
    GUARD_REGISTERS
.global vinix_guard_write_fault
vinix_guard_write_fault:
    strb wzr, [x0]
.global vinix_guard_write_resume
vinix_guard_write_resume:
    GUARD_VERIFY
.size vinix_guard_probe_write, .-vinix_guard_probe_write

.global vinix_guard_probe_stack
.type vinix_guard_probe_stack, %function
vinix_guard_probe_stack:
    stp x19, x20, [sp, #-32]!
    stp x21, x30, [sp, #16]
    mov x19, sp
    mrs x20, spsel
    msr spsel, #1
    mov x21, sp
    mov sp, x0
.global vinix_guard_stack_fault
vinix_guard_stack_fault:
    stp xzr, xzr, [sp, #-16]!
.global vinix_guard_stack_resume
vinix_guard_stack_resume:
    mov sp, x21
    cbnz x20, 1f
    msr spsel, #0
1:
    mov sp, x19
    ldp x21, x30, [sp, #16]
    ldp x19, x20, [sp], #32
    mov x0, #1
    ret
.size vinix_guard_probe_stack, .-vinix_guard_probe_stack
