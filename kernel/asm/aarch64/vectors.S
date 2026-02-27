// AArch64 exception vector table for Vinix kernel
// Each vector entry is 128 bytes (0x80), table is 2048 bytes (0x800)
// 4 groups: Current EL SP0, Current EL SPx, Lower EL AArch64, Lower EL AArch32
//
// IMPORTANT: Each 0x80-byte entry contains ONLY a branch to the actual handler.
// The full handlers (save/restore + call) are placed AFTER the vector table.

.section .text

// Size of saved register frame (x0-x30 + sp + pc + pstate = 34 * 8 = 272, aligned to 288)
.equ FRAME_SIZE, 288

// PL011 UART MMIO addresses (HHDM-mapped)
.equ UART_BASE, 0xffff000009000000
.equ UART_DR,   0xffff000009000000  // Data Register

// HVF workaround is now in syscall__leave (V code).
// Kept as a no-op macro for non-SVC lower-EL return paths.
.macro HVF_SYNC_BARRIER
.endm

.macro SAVE_REGS
    // Make room on stack
    sub sp, sp, #FRAME_SIZE

    // Save x0-x29
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]
    stp x8, x9, [sp, #64]
    stp x10, x11, [sp, #80]
    stp x12, x13, [sp, #96]
    stp x14, x15, [sp, #112]
    stp x16, x17, [sp, #128]
    stp x18, x19, [sp, #144]
    stp x20, x21, [sp, #160]
    stp x22, x23, [sp, #176]
    stp x24, x25, [sp, #192]
    stp x26, x27, [sp, #208]
    stp x28, x29, [sp, #224]

    // Save x30 (LR)
    str x30, [sp, #240]

    // Save SP (the original SP before we decremented)
    add x0, sp, #FRAME_SIZE
    str x0, [sp, #248]

    // Save ELR_EL1 (return address / PC)
    mrs x0, elr_el1
    str x0, [sp, #256]

    // Save SPSR_EL1 (saved program status)
    mrs x0, spsr_el1
    str x0, [sp, #264]

    // Save TPIDR_EL0 (user TLS pointer)
    mrs x0, tpidr_el0
    str x0, [sp, #272]
.endm

.macro RESTORE_REGS
    // Restore SPSR_EL1
    ldr x0, [sp, #264]
    msr spsr_el1, x0

    // Restore ELR_EL1
    ldr x0, [sp, #256]
    msr elr_el1, x0

    // Restore x30 (LR)
    ldr x30, [sp, #240]

    // Restore x0-x29
    ldp x28, x29, [sp, #224]
    ldp x26, x27, [sp, #208]
    ldp x24, x25, [sp, #192]
    ldp x22, x23, [sp, #176]
    ldp x20, x21, [sp, #160]
    ldp x18, x19, [sp, #144]
    ldp x16, x17, [sp, #128]
    ldp x14, x15, [sp, #112]
    ldp x12, x13, [sp, #96]
    ldp x10, x11, [sp, #80]
    ldp x8, x9, [sp, #64]
    ldp x6, x7, [sp, #48]
    ldp x4, x5, [sp, #32]
    ldp x2, x3, [sp, #16]
    ldp x0, x1, [sp, #0]

    // Restore stack pointer
    add sp, sp, #FRAME_SIZE

    // ISB forces pipeline sync before eret. Under HVF, MSR to ELR_EL1/SPSR_EL1
    // traps to EL2; without ISB, HVF may not sequence register updates before eret.
    isb

    eret
.endm

// Like RESTORE_REGS but also restores SP_EL0 from the saved frame.
// Used for return-to-EL0 paths (lower EL exception handlers) where
// sched_switch_context may have corrupted SP_EL0 with a kernel address
// (HVF workaround sets SP_EL0 = SP_EL1 for EL1h eret).
.macro RESTORE_REGS_TO_EL0
    // Restore SPSR_EL1
    ldr x0, [sp, #264]
    msr spsr_el1, x0

    // Restore ELR_EL1
    ldr x0, [sp, #256]
    msr elr_el1, x0

    // Restore TPIDR_EL0 (user TLS pointer)
    ldr x0, [sp, #272]
    msr tpidr_el0, x0

    // Restore SP_EL0 from saved frame.
    // `msr SP_EL0, xN` hangs under HVF, so use SPSel trick.
    // ISB after each SPSel change ensures pipeline sees the new SP alias.
    ldr x0, [sp, #248]
    msr SPSel, #0              // now 'sp' refers to SP_EL0
    isb
    mov sp, x0                 // SP_EL0 = saved user stack pointer
    msr SPSel, #1              // back to SP_EL1 (kernel stack intact)
    isb

    // Restore x30 (LR)
    ldr x30, [sp, #240]

    // Restore x0-x29
    ldp x28, x29, [sp, #224]
    ldp x26, x27, [sp, #208]
    ldp x24, x25, [sp, #192]
    ldp x22, x23, [sp, #176]
    ldp x20, x21, [sp, #160]
    ldp x18, x19, [sp, #144]
    ldp x16, x17, [sp, #128]
    ldp x14, x15, [sp, #112]
    ldp x12, x13, [sp, #96]
    ldp x10, x11, [sp, #80]
    ldp x8, x9, [sp, #64]
    ldp x6, x7, [sp, #48]
    ldp x4, x5, [sp, #32]
    ldp x2, x3, [sp, #16]
    ldp x0, x1, [sp, #0]

    // Restore kernel stack pointer (SP_EL1)
    add sp, sp, #FRAME_SIZE

    isb

    eret
.endm

// =============================================================================
// Exception Vector Table
// Must be aligned to 0x800 (2048 bytes)
// Each entry is exactly 0x80 bytes -- contains ONLY a branch to the handler.
// =============================================================================

.global exception_vectors
.balign 0x800
exception_vectors:

// --- Current EL with SP_EL0 (not used in kernel, we use SP_ELx) ---
.balign 0x80    // 0x000: Synchronous
    b .
.balign 0x80    // 0x080: IRQ
    b .
.balign 0x80    // 0x100: FIQ
    b .
.balign 0x80    // 0x180: SError
    b .

// --- Current EL with SP_ELx (kernel exceptions) ---
.balign 0x80    // 0x200: Synchronous
    b handle_spx_sync
.balign 0x80    // 0x280: IRQ
    b handle_spx_irq
.balign 0x80    // 0x300: FIQ
    b handle_spx_fiq
.balign 0x80    // 0x380: SError
    b handle_spx_serror

// --- Lower EL using AArch64 (userspace exceptions) ---
.balign 0x80    // 0x400: Synchronous
    b handle_lower64_sync
.balign 0x80    // 0x480: IRQ
    b handle_lower64_irq
.balign 0x80    // 0x500: FIQ
    b handle_lower64_fiq
.balign 0x80    // 0x580: SError
    b handle_lower64_serror

// --- Lower EL using AArch32 (not supported) ---
.balign 0x80    // 0x600: Synchronous
    b .
.balign 0x80    // 0x680: IRQ
    b .
.balign 0x80    // 0x700: FIQ
    b .
.balign 0x80    // 0x780: SError
    b .

// =============================================================================
// Out-of-line exception handlers (no size constraint)
// =============================================================================

handle_spx_sync:
    SAVE_REGS
    mrs x0, esr_el1        // arg0: ESR
    mrs x1, far_el1        // arg1: FAR
    mov x2, sp             // arg2: pointer to GPRState on stack
    bl exception__sync_handler
    RESTORE_REGS

handle_spx_irq:
    SAVE_REGS
    mov x0, sp             // arg0: pointer to GPRState on stack
    bl exception__irq_handler
    RESTORE_REGS

handle_spx_fiq:
    SAVE_REGS
    mov x0, sp             // arg0: pointer to GPRState on stack
    bl exception__irq_handler
    RESTORE_REGS

handle_spx_serror:
    SAVE_REGS
    mrs x0, esr_el1
    mrs x1, far_el1
    mov x2, sp
    bl exception__sync_handler
    RESTORE_REGS

handle_lower64_sync:
    SAVE_REGS
    // Fix SP: SAVE_REGS saved SP_EL1 (kernel stack) at [sp,#248],
    // but for lower EL exceptions we need SP_EL0 (user stack).
    mrs x9, SP_EL0
    str x9, [sp, #248]
    mrs x9, esr_el1
    lsr x10, x9, #26          // EC field (bits [31:26])
    cmp x10, #0x15             // SVC from AArch64?
    b.eq handle_svc
    // Not SVC: generic sync handler (page faults, etc.)
    mov x0, x9                 // arg0: ESR
    mrs x1, far_el1            // arg1: FAR
    mov x2, sp                 // arg2: GPRState pointer
    bl exception__sync_handler
    HVF_SYNC_BARRIER
    RESTORE_REGS_TO_EL0

handle_svc:
    // Syscall dispatch. Saved GPRState is on stack (sp points to x0 slot).
    // Load syscall number from saved x8 (offset 8*8=64)
    ldr x9, [sp, #64]
    // Load original x0-x5 as C args x1-x6 (shift by one for GPRState* in x0)
    ldp x1, x2, [sp, #0]      // original x0 -> x1, original x1 -> x2
    ldp x3, x4, [sp, #16]     // original x2 -> x3, original x3 -> x4
    ldp x5, x6, [sp, #32]     // original x4 -> x5, original x5 -> x6
    mov x0, sp                 // first C arg = GPRState pointer

    // Trace syscall entry
    stp x9, x30, [sp, #-16]!
    bl syscall_trace
    ldp x9, x30, [sp], #16

    // Reload args (trace clobbered them)
    ldp x1, x2, [sp, #0]
    ldp x3, x4, [sp, #16]
    ldp x5, x6, [sp, #32]
    mov x0, sp

    // Bounds check syscall number (Linux aarch64 numbers, max 300)
    cmp x9, #300
    b.ge .svc_invalid
    // Dispatch via syscall_table[x9]
    adrp x10, syscall_table
    add x10, x10, :lo12:syscall_table
    ldr x10, [x10, x9, lsl #3]
    blr x10

    // Trace syscall return
    stp x0, x1, [sp, #-16]!
    bl syscall_trace_ret
    ldp x0, x1, [sp], #16

    // Convert Vinix (result, errno) to Linux ABI: x0 = result or -errno.
    // Linux aarch64 preserves x1-x7 across syscalls. We must NOT clobber
    // x1 in the saved frame -- musl keeps live pointers in x1 across syscalls.
    cbz x1, .svc_no_err
    neg x0, x1                 // x0 = -errno
.svc_no_err:
    str x0, [sp, #0]          // Only store x0, preserve original x1
    // Check for pending signals before returning to userspace
    mov x0, sp
    bl syscall__leave
    HVF_SYNC_BARRIER
    RESTORE_REGS_TO_EL0

.svc_invalid:
    movn x0, #37               // x0 = -38 = -ENOSYS
    str x0, [sp, #0]
    HVF_SYNC_BARRIER
    RESTORE_REGS_TO_EL0

handle_lower64_irq:
    SAVE_REGS
    mrs x9, SP_EL0
    str x9, [sp, #248]
    mov x0, sp
    bl exception__irq_handler
    HVF_SYNC_BARRIER
    RESTORE_REGS_TO_EL0

handle_lower64_fiq:
    SAVE_REGS
    mrs x9, SP_EL0
    str x9, [sp, #248]
    mov x0, sp
    bl exception__irq_handler
    HVF_SYNC_BARRIER
    RESTORE_REGS_TO_EL0

handle_lower64_serror:
    SAVE_REGS
    mrs x9, SP_EL0
    str x9, [sp, #248]
    mrs x0, esr_el1
    mrs x1, far_el1
    mov x2, sp
    bl exception__sync_handler
    HVF_SYNC_BARRIER
    RESTORE_REGS_TO_EL0

.section .note.GNU-stack,"",%progbits
