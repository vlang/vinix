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

// Report the exception level the kernel is running at. Apple Silicon has no
// EL3 and m1n1 commonly leaves the kernel at EL2, which changes both of the
// mechanisms below, so neither may assume EL1.
.globl vinix_current_el
.type vinix_current_el, %function
vinix_current_el:
    mrs x0, CurrentEL
    lsr x0, x0, #2
    ret

// Install the fault vectors at whichever level is current. Writing VBAR_EL1
// while running at EL2 installs them where nothing will ever look: exceptions
// would be taken to VBAR_EL2, the table would never run, and a deliberate
// fault would look like PSCI being unavailable rather than a vector installed
// at the wrong level.
.globl vinix_install_early_fault_vectors
.type vinix_install_early_fault_vectors, %function
vinix_install_early_fault_vectors:
    adrp x1, vinix_early_fault_vectors
    add  x1, x1, :lo12:vinix_early_fault_vectors
    mrs  x0, CurrentEL
    lsr  x0, x0, #2
    cmp  x0, #2
    b.lt 2f
    msr  vbar_el2, x1
    isb
    ret
2:  msr  vbar_el1, x1
    isb
    ret

// Set SP_EL1 from EL1 while running on SP_EL0. Used to give early boot (which
// Limine leaves at EL1t, on SP_EL0) a valid exception stack, so a fault taken
// to EL1 -- where the CPU switches to SP_EL1 -- lands on real memory instead of
// an uninitialised pointer.
//
// `msr SP_EL1, x0` faults under HVF (EC=0, "unknown reason"), the same quirk the
// scheduler documents for `msr SP_EL0`. Set it the way the rest of the kernel
// does: select SP_EL1 with SPSel, write it with `mov sp`, then switch back to
// SP_EL0 (the running stack, left untouched). This leaf function spills nothing
// to the stack, so it is safe across the SPSel change.
.globl vinix_set_sp_el1
.type vinix_set_sp_el1, %function
vinix_set_sp_el1:
    msr spsel, #1
    isb
    mov sp, x0
    msr spsel, #0
    isb
    ret
