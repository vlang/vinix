// PSCI conduits. The function id arrives in x0 per the C ABI, which is also
// where PSCI expects it, so the call needs no marshalling. Returning normally
// means the conduit is not implemented; the caller then tries the other one.
.section .text

.globl vinix_psci_hvc
.type vinix_psci_hvc, %function
vinix_psci_hvc:
    hvc #0
    ret

.globl vinix_psci_smc
.type vinix_psci_smc, %function
vinix_psci_smc:
    smc #0
    ret

// Minimal EL1 vector table for early boot diagnosis. Every one of the sixteen
// entries does the same thing: reset the machine. Before this exists a fault
// anywhere in early boot is perfectly silent, so "faulted", "hung" and "never
// entered" are one indistinguishable black screen. Resetting on a fault, while
// a stage halt powers off, splits them apart: a reboot means the kernel ran and
// died, a power-off means it reached the stage, and a black screen means it
// hung or never started.
//
// Each entry must fit the architecture's 128-byte slot, so the function id is
// built with movz/movk rather than a literal pool load, which would need a
// constant island the slots have no room for.
.macro EARLY_FAULT_ENTRY
.align 7
    movz x0, #0x0009
    movk x0, #0x8400, lsl #16
    hvc #0
    smc #0
9:  b 9b
.endm

.align 11
.globl vinix_early_fault_vectors
vinix_early_fault_vectors:
    EARLY_FAULT_ENTRY   // EL1t: synchronous
    EARLY_FAULT_ENTRY   // EL1t: irq
    EARLY_FAULT_ENTRY   // EL1t: fiq
    EARLY_FAULT_ENTRY   // EL1t: serror
    EARLY_FAULT_ENTRY   // EL1h: synchronous
    EARLY_FAULT_ENTRY   // EL1h: irq
    EARLY_FAULT_ENTRY   // EL1h: fiq
    EARLY_FAULT_ENTRY   // EL1h: serror
    EARLY_FAULT_ENTRY   // EL0 aarch64: synchronous
    EARLY_FAULT_ENTRY   // EL0 aarch64: irq
    EARLY_FAULT_ENTRY   // EL0 aarch64: fiq
    EARLY_FAULT_ENTRY   // EL0 aarch64: serror
    EARLY_FAULT_ENTRY   // EL0 aarch32: synchronous
    EARLY_FAULT_ENTRY   // EL0 aarch32: irq
    EARLY_FAULT_ENTRY   // EL0 aarch32: fiq
    EARLY_FAULT_ENTRY   // EL0 aarch32: serror

.globl vinix_install_early_fault_vectors
.type vinix_install_early_fault_vectors, %function
vinix_install_early_fault_vectors:
    adrp x0, vinix_early_fault_vectors
    add  x0, x0, :lo12:vinix_early_fault_vectors
    msr  vbar_el1, x0
    isb
    ret
