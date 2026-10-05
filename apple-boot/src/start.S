// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Entry from iBoot. The image is loaded at an address it does not choose and
 * entered at +0x800 (`kmutil configure-boot --raw --entry-point 2048`) at EL2
 * with the MMU off and x0 pointing at the boot arguments. Everything here is
 * PC-relative until the relocations are applied. */

.section .init, "ax"

// The vector table occupies the first 2 KiB. The loader takes no interrupts;
// any synchronous exception or SError is a loader bug, reported on screen.
.align 11
.globl loader_vectors
loader_vectors:
.irp group, 0, 1, 2, 3
.irp kind, 0, 1, 2, 3
    .align 7
    mov x0, #(\group * 4 + \kind)
    b exception_entry
.endr
.endr

.org 0x800
.globl _start
_start:
    mov x19, x0 // boot arguments
    adr x20, loader_vectors // image base

    adrp x1, loader_stack_top
    add x1, x1, :lo12:loader_stack_top
    mov sp, x1

    msr daifset, #0xf

    // Apple cores run EL2 with HCR_EL2.E2H fixed at 1, so EL1 system-register
    // names reach the EL2 bank. Report exceptions from here on.
    msr vbar_el2, x20
    isb

    mov x0, x20
    adrp x1, loader_rela_start
    add x1, x1, :lo12:loader_rela_start
    adrp x2, loader_rela_end
    add x2, x2, :lo12:loader_rela_end
    bl apply_relocations

    mov x0, x19
    mov x1, x20
    bl loader_main
1:
    wfe
    b 1b

exception_entry:
    mrs x1, esr_el2
    mrs x2, elr_el2
    mrs x3, far_el2
    adrp x4, loader_stack_top
    add x4, x4, :lo12:loader_stack_top
    mov sp, x4
    bl loader_exception
2:
    wfe
    b 2b

// Relocations are R_AARCH64_RELATIVE only: *(base + offset) = base + addend.
.globl apply_relocations
apply_relocations:
1:
    cmp x1, x2
    b.hs 2f
    ldp x3, x4, [x1], #16 // r_offset, r_info
    ldr x5, [x1], #8 // r_addend
    cmp w4, #1027 // R_AARCH64_RELATIVE
    b.ne 1b
    add x5, x5, x0
    str x5, [x0, x3]
    b 1b
2:
    ret

// 128 KiB loader stack, inside the file (see apple-boot.ld).
.section .stack, "aw", %progbits
.align 4
.globl loader_stack_bottom
loader_stack_bottom:
    .space 0x20000
.globl loader_stack_top
loader_stack_top:

.section .text

// noreturn void enter_kernel(u64 entry, u64 stack, u64 sctlr, u64 mair,
//                            u64 tcr, u64 ttbr0, u64 ttbr1)
//
// Turns the MMU on with the kernel's tables and enters it the way Limine
// 12.8's enter_in_el2 does on a VHE CPU: EL2 with E2H and TGE set, counters
// untrapped, FP/SIMD trapped (the kernel enables it), on SP_EL0, with every
// exception masked. The caller has identity-mapped this code through TTBR0.
.globl enter_kernel
enter_kernel:
    msr daifset, #0xf

    // Make the EL1 names reach EL2 whatever the firmware left in HCR_EL2.
    mrs x8, hcr_el2
    orr x8, x8, #(1 << 34) // E2H
    orr x8, x8, #(1 << 27) // TGE
    msr hcr_el2, x8
    isb

    msr mair_el1, x3
    msr tcr_el1, x4
    msr ttbr0_el1, x5
    msr ttbr1_el1, x6
    isb
    tlbi alle2
    dsb ish
    ic iallu
    dsb ish
    isb

    msr sctlr_el1, x2
    isb

    msr vbar_el1, xzr

    mov x8, #3 // don't trap the counters
    msr cnthctl_el2, x8
    msr cntvoff_el2, xzr

    ldr x8, =0x488000002 // E2H + TGE + RW + SWIO
    msr hcr_el2, x8
    isb
    tlbi vmalle1
    dsb nsh
    isb

    msr cptr_el2, xzr // VHE layout: FP/SIMD/SVE trapped
    msr hstr_el2, xzr

    msr spsel, #0
    mov sp, x1

    mov x8, #0x3c8 // EL2t, D A I F masked
    msr spsr_el1, x8
    msr elr_el1, x0

    mov x0, xzr
    mov x1, xzr
    mov x2, xzr
    mov x3, xzr
    mov x4, xzr
    mov x5, xzr
    mov x6, xzr
    mov x7, xzr
    mov x8, xzr
    mov x9, xzr
    mov x10, xzr
    mov x11, xzr
    mov x12, xzr
    mov x13, xzr
    mov x14, xzr
    mov x15, xzr
    mov x16, xzr
    mov x17, xzr
    mov x18, xzr
    mov x19, xzr
    mov x20, xzr
    mov x21, xzr
    mov x22, xzr
    mov x23, xzr
    mov x24, xzr
    mov x25, xzr
    mov x26, xzr
    mov x27, xzr
    mov x28, xzr
    mov x29, xzr
    mov x30, xzr
    eret

// void cache_invalidate_range(u64 start, u64 end): discard any line the
// firmware left over memory the loader wrote with the caches off, so the
// kernel's first cacheable read sees DRAM.
.globl cache_invalidate_range
cache_invalidate_range:
    mrs x3, ctr_el0
    ubfx x3, x3, #16, #4 // DminLine: log2(words)
    mov x2, #4
    lsl x2, x2, x3
    sub x3, x2, #1
    bic x0, x0, x3
1:
    cmp x0, x1
    b.hs 2f
    dc ivac, x0
    add x0, x0, x2
    b 1b
2:
    dsb sy
    isb
    ret

// void quiesce_fiq_sources(void): what m1n1's exception_initialize does
// before it unmasks FIQs, since iBoot may leave any of these asserted and the
// kernel's FIQ handler only knows the timer. Every timer is disabled and
// masked; on Apple cores the PMU's FIQ mode is turned off and a pending fast
// IPI acknowledged.
.globl quiesce_fiq_sources
quiesce_fiq_sources:
    msr oslar_el1, xzr // release the OS lock, as m1n1 does
    mov x0, #2 // ENABLE=0, IMASK=1
    msr cntp_ctl_el0, x0
    msr cntv_ctl_el0, x0
    mrs x1, hcr_el2
    tbz x1, #34, 1f
    msr S3_5_C14_C2_1, x0 // CNTP_CTL_EL02: the EL1 timers, under E2H
    msr S3_5_C14_C3_1, x0 // CNTV_CTL_EL02
1:
    mrs x1, midr_el1
    lsr x1, x1, #24
    cmp x1, #0x61 // implementer 'a': Apple
    b.ne 2f
    mrs x1, S3_1_C15_C0_0 // PMCR0
    bic x1, x1, #0xf00 // IACT, IMODE
    msr S3_1_C15_C0_0, x1
    mov x1, #1
    msr S3_5_C15_C1_1, x1 // IPI_SR_EL1: acknowledge a pending fast IPI
2:
    isb
    ret

.globl read_id_aa64mmfr0
read_id_aa64mmfr0:
    mrs x0, id_aa64mmfr0_el1
    ret

.globl read_current_el
read_current_el:
    mrs x0, CurrentEL
    lsr x0, x0, #2
    ret

.globl read_midr
read_midr:
    mrs x0, midr_el1
    ret

.globl halt_forever
halt_forever:
    msr daifset, #0xf
1:
    wfe
    b 1b

/* Narrow MMIO instruction unavailable in the V compiler's ARM operands. */
.globl apple_mmio_write32
apple_mmio_write32:
    str w1, [x0]
    ret
