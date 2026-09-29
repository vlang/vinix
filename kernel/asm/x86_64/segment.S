// Segment registers and descriptor tables, for the LDT modify_ldt(2) gives a
// process and the TLS descriptors set_thread_area(2) gives a thread; see
// sched/segments_amd64.v. Plain assembly, as V3 does not honour everything
// its inline assembly is asked for.

.section .text

// u32 x86_access_rights(u16 selector): the access rights LAR reads from the
// descriptor `selector` names, bits 8 to 23 of its high word, or 0 when LAR
// refuses it -- a null selector, one past the end of its table, a type LAR
// does not report, or a privilege the selector's RPL may not see. A code or
// data descriptor always has bit 12 set, so 0 is never a real answer.
.global x86_access_rights
x86_access_rights:
    xor %eax, %eax
    lar %di, %eax
    jz 1f
    xor %eax, %eax
1:
    ret

// bool x86_segment_limit(u16 selector, u32 *limit): LSL's limit of the
// segment `selector` names, in bytes, and whether LSL gave one.
.global x86_segment_limit
x86_segment_limit:
    lsl %di, %eax
    jnz 1f
    mov %eax, (%rsi)
    mov $1, %eax
    ret
1:
    xor %eax, %eax
    ret

.global x86_load_ldt
x86_load_ldt:
    lldt %di
    ret

.global x86_fs_selector
x86_fs_selector:
    xor %eax, %eax
    mov %fs, %ax
    ret

.global x86_gs_selector
x86_gs_selector:
    xor %eax, %eax
    mov %gs, %ax
    ret

// Loading FS takes its base from the descriptor, which the caller replaces
// if that is not what it wants.
.global x86_load_fs
x86_load_fs:
    mov %di, %fs
    ret

// Loading GS replaces the base GS has now, which in the kernel is the one
// that finds the CPU and thread: only the scheduler does it, before it sets
// both GS bases.
.global x86_load_gs
x86_load_gs:
    mov %di, %gs
    ret

// Load GS for userspace from inside a syscall, where the user's GS base is
// the one SWAPGS put aside: swapped in for the load, so that it is that base
// the descriptor replaces.
.global x86_load_user_gs
x86_load_user_gs:
    pushfq
    cli
    swapgs
    mov %di, %gs
    swapgs
    popfq
    ret

// SYSCALL from 32-bit code, installed in IA32_CSTAR. Only an LDT code segment
// makes that possible here, and only AMD CPUs come here with it: Intel ones
// refuse it with #UD. There is no way back to where it was made: SYSRET to
// 32-bit code takes its CS from STAR, the kernel's data segment in this GDT,
// and SYSCALL keeps no record of the CS it came from. So the program dies of
// the SIGILL the #UD gives it on Intel, from a frame built as syscall_entry
// builds one.
.global syscall32_entry
syscall32_entry:
    swapgs
    mov %rsp, %gs:32
    mov %gs:24, %rsp
    push $0x3b
    push %gs:32
    push %r11
    push $0x43
    push %rcx
    push $0
    push %r15
    push %r14
    push %r13
    push %r12
    push %r11
    push %r10
    push %r9
    push %r8
    push %rbp
    push %rdi
    push %rsi
    push %rdx
    push %rcx
    push %rbx
    push %rax
    mov %es, %eax
    push %rax
    mov %ds, %eax
    push %rax
    sti
    mov %rsp, %rdi
    call syscall32_refused
    ud2

.section .note.GNU-stack,"",%progbits
