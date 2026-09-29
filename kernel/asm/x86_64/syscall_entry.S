// The x86-64 SYSCALL entry point, installed in IA32_LSTAR.
//
// SYSCALL does not switch stacks, so nothing may touch the stack before the
// switch below. This used to be a V function marked @[_naked], but V3 does not
// honour that attribute: the C compiler gave it a normal prologue, whose
// `push rbp` ran on the user stack before the swap. The saved user RSP was then
// 8 bytes low, so every syscall returned to userspace with its stack pointer
// moved and the next `ret` jumped into the stack. Plain assembly cannot grow a
// prologue.
//
// Only the Linux x86-64 convention is spoken, as on arm64: rax holds the
// number, rdi, rsi, rdx, r10, r8 and r9 the arguments, and the result comes
// back in rax, a negative errno on failure. syscall_trace() answers which
// table slot runs the call, as arm64's does; see syscall/table.

.section .text

.global syscall_entry
syscall_entry:
    swapgs
    // Save the user stack in Thread.user_stack and switch to Thread.kernel_stack.
    mov %rsp, %gs:32
    mov %gs:24, %rsp
    // Build a GPRState: the iretq frame, the error code slot, then the GPRs.
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
    // syscall_trace() answers the table slot to run: the call's number, or
    // the stand-in returning the errno seccomp or pledge(2) refused it with.
    mov %rsp, %rdi
    call syscall_trace
    mov %rax, %r13
    cmp $512, %r13
    jae 3f

    // Vinix handlers take the saved GPR frame as their first argument, so
    // shift the six Linux arguments right once; the last one is passed on the
    // C stack.
    mov %rsp, %rax
    sub $16, %rsp
    mov %rax, %rdi
    mov 56(%rax), %rsi
    mov 48(%rax), %rdx
    mov 40(%rax), %rcx
    mov 88(%rax), %r8
    mov 72(%rax), %r9
    mov 80(%rax), %rbx
    mov %rbx, (%rsp)
    lea syscall_table(%rip), %rbx
    call *(%rbx, %r13, 8)
    add $16, %rsp
    jmp 4f

3:
    mov $0xffffffffffffffff, %rax
    mov $38, %rdx

4:
    // Handlers return (result, errno) in rax/rdx. Linux encodes an errno as a
    // negative result and otherwise preserves the caller's rdx.
    mov %rax, %r12
    mov %rdx, %r13
    mov %rax, %rdi
    mov %rdx, %rsi
    call syscall_trace_ret
    mov %r12, %rax
    test %r13, %r13
    jz 6f
    mov %r13, %rax
    neg %rax
6:
    mov %rax, 16(%rsp)
    mov %rsp, %rdi
    call syscall_leave
    // A data segment the syscall's thread lost while it was in the kernel
    // faults here, and the fault handler has it loaded null; see isr.v.
    pop %rax
.global syscall_exit_load_ds
syscall_exit_load_ds:
    mov %eax, %ds
    pop %rax
.global syscall_exit_load_es
syscall_exit_load_es:
    mov %eax, %es
    pop %rax
    pop %rbx
    pop %rcx
    pop %rdx
    pop %rsi
    pop %rdi
    pop %rbp
    pop %r8
    pop %r9
    pop %r10
    pop %r11
    pop %r12
    pop %r13
    pop %r14
    pop %r15
    // Restore the user stack. sysretq takes RIP from rcx and RFLAGS from r11.
    mov %gs:32, %rsp
    swapgs
    sysretq

.section .note.GNU-stack,"",%progbits
