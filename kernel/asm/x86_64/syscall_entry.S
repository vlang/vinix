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
// The x86-64 port predates Vinix's Linux-compatible arm64 ABI, so its native
// libc puts the syscall number in rdi and receives errno in rdx. Alpine uses
// the Linux register convention instead; syscall_is_linux() says which one the
// current process speaks.

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
    call syscall_is_linux
    test %rax, %rax
    jnz 1f

    // Native Vinix ABI: rdi is the syscall number and arguments start in rsi.
    // Reload everything because syscall_is_linux() may clobber it.
    xor %r12, %r12
    mov 56(%rsp), %rbx
    cmp $66, %rbx
    jae 2f
    mov 48(%rsp), %rsi
    mov 40(%rsp), %rdx
    mov 88(%rsp), %rcx
    mov 72(%rsp), %r8
    mov 80(%rsp), %r9
    mov %rsp, %rdi
    lea syscall_table(%rip), %rax
    call *(%rax, %rbx, 8)
    jmp 4f

    // Linux x86-64 ABI: rax is the number, followed by rdi, rsi, rdx, r10, r8,
    // r9. Vinix handlers take the saved GPR frame as their first argument, so
    // shift the six Linux arguments right once; the last one is passed on the
    // C stack.
1:
    mov $1, %r12
    mov 16(%rsp), %r13
    cmp $512, %r13
    jae 3f
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
    lea linux_syscall_table(%rip), %rbx
    call *(%rbx, %r13, 8)
    add $16, %rsp
    jmp 4f

2:
    xor %r12, %r12
    mov $0xffffffffffffffff, %rax
    mov $38, %rdx
    jmp 4f

3:
    mov $1, %r12
    mov $38, %rax
    neg %rax
    xor %rdx, %rdx

4:
    // Native calls return (result, errno) in rax/rdx. Linux encodes errno as a
    // negative result and otherwise preserves the caller's rdx.
    test %r12, %r12
    jz 5f
    test %rdx, %rdx
    jz 6f
    neg %rdx
    mov %rdx, %rax
6:
    mov %rax, 16(%rsp)
    jmp 7f
5:
    mov %rax, 16(%rsp)
    mov %rdx, 40(%rsp)
7:
    mov %rsp, %rdi
    call syscall_leave
    pop %rax
    mov %eax, %ds
    pop %rax
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
