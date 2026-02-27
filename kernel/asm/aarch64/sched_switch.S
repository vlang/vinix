// sched_switch_context(gpr_state *GPRState, kernel_stack u64)
// Restores ARM64 GPR state from the GPRState struct and returns via eret.
// GPRState layout: x0(0) x1(8) .. x28(224) x29(232) x30(240) sp(248) pc(256) pstate(264)
// Called with x0 = pointer to GPRState, x1 = kernel stack top. Does NOT return.

.global sched_switch_context
sched_switch_context:
    // x0 = GPRState pointer, x1 = kernel_stack

    // Restore ELR_EL1 (return PC) and SPSR_EL1 first
    ldr x2, [x0, #256]
    msr elr_el1, x2
    ldr x2, [x0, #264]
    msr spsr_el1, x2

    // Set the appropriate stack pointer based on target EL.
    // Check SPSR.M[3:0]: 0 = EL0t (user), 5 = EL1h (kernel)
    ldr x3, [x0, #264]         // pstate
    ands xzr, x3, #0xF
    b.ne .set_kernel_sp

    // User thread (EL0t):
    // 1. Set SP_EL1 to the kernel stack for exception handling.
    // 2. Set SP_EL0 to the user stack via SPSel trick.
    //    (`msr SP_EL0, xN` hangs under HVF, but SPSel works.)
    // ISB after SPSel ensures pipeline sees the new SP alias.
    mov sp, x1                  // SP_EL1 = kernel stack
    ldr x2, [x0, #248]         // x2 = user SP
    msr SPSel, #0               // now SP refers to SP_EL0
    isb
    mov sp, x2                  // SP_EL0 = user stack
    msr SPSel, #1               // back to SP_EL1 (= kernel stack)
    isb

    // Restore TPIDR_EL0 (user TLS pointer)
    ldr x2, [x0, #272]
    msr tpidr_el0, x2

    b .restore_gprs

.set_kernel_sp:
    // Kernel thread (EL1h): set SP_EL1 directly.
    // HVF workaround: eret may restore SP_EL0 instead of SP_EL1,
    // so set BOTH to the same value via SPSel trick.
    ldr x2, [x0, #248]
    msr SPSel, #0               // now SP refers to SP_EL0
    isb
    mov sp, x2                  // SP_EL0 = thread's SP
    msr SPSel, #1               // back to SP_EL1
    isb
    mov sp, x2                  // SP_EL1 = thread's SP

.restore_gprs:
    // Restore general purpose registers (from GPRState, not stack)
    ldp x2, x3, [x0, #16]
    ldp x4, x5, [x0, #32]
    ldp x6, x7, [x0, #48]
    ldp x8, x9, [x0, #64]
    ldp x10, x11, [x0, #80]
    ldp x12, x13, [x0, #96]
    ldp x14, x15, [x0, #112]
    ldp x16, x17, [x0, #128]
    ldp x18, x19, [x0, #144]
    ldp x20, x21, [x0, #160]
    ldp x22, x23, [x0, #176]
    ldp x24, x25, [x0, #192]
    ldp x26, x27, [x0, #208]
    ldr x28, [x0, #224]
    ldr x29, [x0, #232]
    ldr x30, [x0, #240]

    // Restore x0 and x1 last (x0 is the pointer itself)
    ldp x0, x1, [x0, #0]

    isb
    eret

// yield_dispatch(handler_fn_ptr)
// Saves the current kernel context into a GPRState on the stack, then calls
// the scheduler timer handler (x0 = handler fn ptr).
//
// If the scheduler switches to another thread (via sched_switch_context -> eret),
// this function "pauses". When the thread is later rescheduled, sched_switch_context
// is called with the saved GPRState (pstate=EL1h), which erets back to EL1h at
// the saved LR, effectively making this function return normally.
//
// If the scheduler has no thread to switch to, the handler returns and this
// function cleans up and returns normally.
.global yield_dispatch
yield_dispatch:
    // x0 = scheduler_timer_handler function pointer

    // Save all GPRs into a GPRState frame on the stack
    sub sp, sp, #288
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
    str x30, [sp, #240]

    // SP = original SP (before sub)
    add x2, sp, #288
    str x2, [sp, #248]

    // PC = LR (return address -> resumes at caller after eret)
    str x30, [sp, #256]

    // pstate = EL1h (0x5) -- tells sched_switch_context this is kernel context
    mov x2, #0x5
    str x2, [sp, #264]

    // Call handler(gpr_state_ptr): x0 = GPRState*, handler = saved x0
    mov x1, x0          // x1 = handler fn ptr
    mov x0, sp          // x0 = GPRState pointer
    blr x1

    // Handler returned (no context switch happened). Clean up.
    // Restore x30 (LR) from saved GPRState — blr clobbered it.
    ldr x30, [sp, #240]
    add sp, sp, #288
    ret
