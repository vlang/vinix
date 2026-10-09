/* SPDX-License-Identifier: GPL-2.0-or-later
 * Preserve every argument, including FP/HFA and indirect-result registers.
 * All runtime policy and framework methods live in V. */
#ifdef __APPLE__
#define SYM_(x) _##x
#define SYM(x) SYM_(x)
#else
#define SYM(x) x
#endif
.text
.p2align 2
/* LDXP alone need not be an atomic 16-byte snapshot. A successful exclusive
 * store of the same pair validates the load. Neither helper uses x18 or LSE,
 * so these also work on the baseline ARMv8 CPUs used by the guest. */
.global SYM(ios_atomic_pair_load)
SYM(ios_atomic_pair_load):
1:
    ldaxp x2, x3, [x0]
    stlxp w4, x2, x3, [x0]
    cbnz w4, 1b
    stp x2, x3, [x1]
    ret
.global SYM(ios_atomic_pair_exchange)
SYM(ios_atomic_pair_exchange):
    ldp x3, x4, [x1]
    ldp x5, x6, [x2]
1:
    ldaxp x7, x8, [x0]
    cmp x7, x3
    ccmp x8, x4, #0, eq
    b.ne 2f
    stlxp w9, x5, x6, [x0]
    cbnz w9, 1b
    mov w0, #1
    ret
2:
    /* Validate the mismatched pair too before returning it to the retry loop. */
    stlxp w9, x7, x8, [x0]
    cbnz w9, 1b
    stp x7, x8, [x1]
    mov w0, #0
    ret
.global SYM(ios_objc_msgsend)
SYM(ios_objc_msgsend):
    mov x16, #0
    b 1f
.global SYM(ios_objc_super)
SYM(ios_objc_super):
    mov x16, #1
    b 1f
.global SYM(ios_objc_builtin)
SYM(ios_objc_builtin):
    mov x16, #2
1:
    sub sp, sp, #224
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]
    stp x8, x30, [sp, #64]
    stp q0, q1, [sp, #80]
    stp q2, q3, [sp, #112]
    stp q4, q5, [sp, #144]
    stp q6, q7, [sp, #176]
    add x17, sp, #224
    str x17, [sp, #208]
    mov x0, sp
    mov x1, x16
    bl SYM(ios_dispatch)
    mov x16, x0
    ldp x0, x1, [sp, #0]
    ldp x2, x3, [sp, #16]
    ldp x4, x5, [sp, #32]
    ldp x6, x7, [sp, #48]
    ldp x8, x30, [sp, #64]
    ldp q0, q1, [sp, #80]
    ldp q2, q3, [sp, #112]
    ldp q4, q5, [sp, #144]
    ldp q6, q7, [sp, #176]
    add sp, sp, #224
    cbz x16, 2f
    br x16
2:
    ret
/* Register-specific ARC entries still use ordinary caller/callee clobber
 * rules. Retain returns its result in x0. Ownership remains in V. */
.macro ARC_ENTRY reg
.global SYM(ios_arc_retain_x\reg)
SYM(ios_arc_retain_x\reg):
    mov x0, x\reg
    b SYM(ios_arc_retain)
.global SYM(ios_arc_release_x\reg)
SYM(ios_arc_release_x\reg):
    mov x0, x\reg
    b SYM(ios_arc_release)
.endm
ARC_ENTRY 0
ARC_ENTRY 1
ARC_ENTRY 2
ARC_ENTRY 3
ARC_ENTRY 4
ARC_ENTRY 5
ARC_ENTRY 6
ARC_ENTRY 7
ARC_ENTRY 8
ARC_ENTRY 9
ARC_ENTRY 10
ARC_ENTRY 11
ARC_ENTRY 12
ARC_ENTRY 13
ARC_ENTRY 14
ARC_ENTRY 15
ARC_ENTRY 19
ARC_ENTRY 20
ARC_ENTRY 21
ARC_ENTRY 22
ARC_ENTRY 23
ARC_ENTRY 24
ARC_ENTRY 25
ARC_ENTRY 26
ARC_ENTRY 27
ARC_ENTRY 28
/* Darwin ARM64 variadic doubles arrive in stack slots; the V adapter has a
 * fixed signature, so the host compiler supplies its own libc varargs ABI. */
.global SYM(ios_snprintf)
SYM(ios_snprintf):
    mov x3, sp
    b SYM(ios_snprintf_stack)
.global SYM(ios_printf)
SYM(ios_printf):
    mov x1, sp
    b SYM(ios_printf_stack)
.global SYM(ios_cxx_verbose_abort)
SYM(ios_cxx_verbose_abort):
    mov x1, sp
    b SYM(ios_cxx_verbose_abort_stack)
.global SYM(ios_fprintf)
SYM(ios_fprintf):
    mov x2, sp
    b SYM(ios_fprintf_stack)
.global SYM(ios_sprintf)
SYM(ios_sprintf):
    mov x2, sp
    b SYM(ios_sprintf_stack)
.global SYM(ios_sscanf)
SYM(ios_sscanf):
    mov x2, sp
    b SYM(ios_sscanf_stack)
.global SYM(ios_asprintf)
SYM(ios_asprintf):
    mov x2, sp
    b SYM(ios_asprintf_stack)
.global SYM(ios_open)
SYM(ios_open):
    mov x2, sp
    b SYM(ios_open_stack)
.global SYM(ios_snprintf_checked)
SYM(ios_snprintf_checked):
    mov x5, sp
    b SYM(ios_snprintf_checked_stack)
.global SYM(ios_sprintf_checked)
SYM(ios_sprintf_checked):
    mov x4, sp
    b SYM(ios_sprintf_checked_stack)
.global SYM(ios_nslog)
SYM(ios_nslog):
    mov x1, sp
    b SYM(ios_nslog_stack)
/* CGImageCreate's last arguments are packed as pointer/bool/uint32 on
 * Darwin's stack. Linux AAPCS64 gives each argument an eight-byte slot. */
.global SYM(ios_cg_image_create)
SYM(ios_cg_image_create):
#ifdef __APPLE__
    b SYM(ios_cg_image_create_native)
#else
    sub sp, sp, #48
    ldr x9, [sp, #48]
    ldrb w10, [sp, #56]
    ldr w11, [sp, #60]
    stp x9, x10, [sp, #0]
    str w11, [sp, #16]
    str x30, [sp, #32]
    bl SYM(ios_cg_image_create_native)
    ldr x30, [sp, #32]
    add sp, sp, #48
    ret
#endif
/* Darwin's TLV thunk preserves argument registers: a compiler may resolve
 * TLS after preparing the arguments to another call. Only x0 is the result. */
.global SYM(ios_tlv_get_addr)
SYM(ios_tlv_get_addr):
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
    str x30, [sp, #144]
    stp q0, q1, [sp, #160]
    stp q2, q3, [sp, #192]
    stp q4, q5, [sp, #224]
    stp q6, q7, [sp, #256]
    bl SYM(ios_tlv_address)
    ldr x1, [sp, #8]
    ldp x2, x3, [sp, #16]
    ldp x4, x5, [sp, #32]
    ldp x6, x7, [sp, #48]
    ldp x8, x9, [sp, #64]
    ldp x10, x11, [sp, #80]
    ldp x12, x13, [sp, #96]
    ldp x14, x15, [sp, #112]
    ldp x16, x17, [sp, #128]
    ldr x30, [sp, #144]
    ldp q0, q1, [sp, #160]
    ldp q2, q3, [sp, #192]
    ldp q4, q5, [sp, #224]
    ldp q6, q7, [sp, #256]
    add sp, sp, #288
    ret
/* A per-import thunk supplies its index in x16. Resolve without disturbing
 * integer, HFA/vector, indirect-result, stack or link-register arguments. */
.global SYM(ios_lazy_entry)
SYM(ios_lazy_entry):
    sub sp, sp, #224
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]
    stp x8, x30, [sp, #64]
    stp q0, q1, [sp, #80]
    stp q2, q3, [sp, #112]
    stp q4, q5, [sp, #144]
    stp q6, q7, [sp, #176]
    mov x0, x16
    bl SYM(ios_lazy_resolve)
    mov x16, x0
    ldp x0, x1, [sp, #0]
    ldp x2, x3, [sp, #16]
    ldp x4, x5, [sp, #32]
    ldp x6, x7, [sp, #48]
    ldp x8, x30, [sp, #64]
    ldp q0, q1, [sp, #80]
    ldp q2, q3, [sp, #112]
    ldp q4, q5, [sp, #144]
    ldp q6, q7, [sp, #176]
    add sp, sp, #224
    br x16
#ifndef __APPLE__
.section .note.GNU-stack,"",%progbits
#endif
