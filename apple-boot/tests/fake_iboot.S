// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* What iBoot does last before starting a custom kernel, for the QEMU test:
 * EL2 with HCR_EL2.E2H set (Apple cores fix it at 1), the MMU off, x0 at the
 * boot arguments, a jump to the image's entry point. The harness fills in the
 * two words at the end. */
.section .text
.globl _start
_start:
    mrs x0, hcr_el2
    orr x0, x0, #(1 << 34) // E2H
    orr x0, x0, #(1 << 31) // RW
    msr hcr_el2, x0
    isb
    ldr x0, boot_args
    ldr x1, entry
    br x1

.align 3
boot_args:
    .quad 0
entry:
    .quad 0
