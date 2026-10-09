/* SPDX-License-Identifier: GPL-2.0-or-later */
.text
.p2align 2
.global _arc_register_probe
_arc_register_probe:
    stp x29, x30, [sp, #-16]!
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    stp x27, x28, [sp, #-16]!
    sub sp, sp, #96
    stp x0, x1, [sp]
    str x2, [sp, #16]
    stp d8, d9, [sp, #32]
    stp d10, d11, [sp, #48]
    stp d12, d13, [sp, #64]
    stp d14, d15, [sp, #80]
    mov x29, x3
    .macro ARG reg
    mov x\reg, #(0x100 + \reg)
    .endm
    ARG 0
    ARG 1
    ARG 2
    ARG 3
    ARG 4
    ARG 5
    ARG 6
    ARG 7
    ARG 8
    ARG 9
    ARG 10
    ARG 11
    ARG 12
    ARG 13
    ARG 14
    ARG 15
    ARG 19
    ARG 20
    ARG 21
    ARG 22
    ARG 23
    ARG 24
    ARG 25
    ARG 26
    ARG 27
    ARG 28
    ldr x17, [sp, #16]
    .macro OBJECT reg
    cmp x17, #\reg
    b.ne 1f
    ldr x\reg, [sp]
    1:
    .endm
    OBJECT 0
    OBJECT 1
    OBJECT 2
    OBJECT 3
    OBJECT 4
    OBJECT 5
    OBJECT 6
    OBJECT 7
    OBJECT 8
    OBJECT 9
    OBJECT 10
    OBJECT 11
    OBJECT 12
    OBJECT 13
    OBJECT 14
    OBJECT 15
    OBJECT 19
    OBJECT 20
    OBJECT 21
    OBJECT 22
    OBJECT 23
    OBJECT 24
    OBJECT 25
    OBJECT 26
    OBJECT 27
    OBJECT 28
    movi v0.16b, #0x10
    movi v1.16b, #0x11
    movi v2.16b, #0x12
    movi v3.16b, #0x13
    movi v4.16b, #0x14
    movi v5.16b, #0x15
    movi v6.16b, #0x16
    movi v7.16b, #0x17
    movi v8.16b, #0x18
    movi v9.16b, #0x19
    movi v10.16b, #0x1a
    movi v11.16b, #0x1b
    movi v12.16b, #0x1c
    movi v13.16b, #0x1d
    movi v14.16b, #0x1e
    movi v15.16b, #0x1f
    ldr x16, [sp, #8]
    blr x16
    stp x0, x1, [x29]
    stp x2, x3, [x29, #16]
    stp x4, x5, [x29, #32]
    stp x6, x7, [x29, #48]
    stp x8, x9, [x29, #64]
    stp x10, x11, [x29, #80]
    stp x12, x13, [x29, #96]
    stp x14, x15, [x29, #112]
    str x19, [x29, #152]
    stp x20, x21, [x29, #160]
    stp x22, x23, [x29, #176]
    stp x24, x25, [x29, #192]
    stp x26, x27, [x29, #208]
    str x28, [x29, #224]
    stp d8, d9, [x29, #256]
    stp d10, d11, [x29, #272]
    stp d12, d13, [x29, #288]
    stp d14, d15, [x29, #304]
    ldp d8, d9, [sp, #32]
    ldp d10, d11, [sp, #48]
    ldp d12, d13, [sp, #64]
    ldp d14, d15, [sp, #80]
    add sp, sp, #96
    ldp x27, x28, [sp], #16
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
