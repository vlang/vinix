// Hand-written amd64 SYSCALL entry point.
//
// This has to be genuinely, guaranteed prologue-free: the CPU hands control
// here with the live *user* stack pointer still active (SYSCALL does not
// switch stacks the way an interrupt gate does -- switching to a kernel
// stack is this code's own job, done explicitly below), so any instruction
// that touches the stack before that switch touches the user's own stack.
//
// This used to be a V function marked @[_naked], with the entry sequence
// written as an inline asm block. V 0.5.2's C backend does not actually
// emit any naked/no-prologue marker for that attribute at all -- the
// generated C was a completely ordinary `void syscall__syscall_entry(void)`
// with no attribute whatsoever, so whether a prologue got emitted ahead of
// the asm block was purely incidental to the C compiler's own general
// heuristics (frame-pointer handling, in particular), not something V's
// @[_naked] controlled. Confirmed live: Clang emitted `push rbp; mov rsp,
// rbp` here; a reduced host-C probe with the same function shape and flags
// showed GCC 14.2 emits no prologue at all for it. A `pop rbp` patch to
// compensate for Clang's prologue only worked for that one compiler, and
// even then only repaired the register state -- the phantom `push rbp`
// still permanently overwrote whatever the user stack held at [rsp-8]
// (observed to be a live return address a few frames up in musl's own
// dlstart) with the old rbp value; popping it back off restores rsp and
// rbp, not the stack memory content that push clobbered. A real .S file
// is not "one more instruction sequence some compiler happens to emit" --
// nothing runs here before the code below except the CPU's own SYSCALL
// microcode, unconditionally, on every build.
.intel_syntax noprefix

.global syscall_entry
.type syscall_entry, @function
syscall_entry:
    swapgs // Save user stack
    mov gs:[32], rsp // Switch to kernel stack
    mov rsp, gs:[24]
    push 0x3b
    push gs:[32]
    push r11
    push 0x43
    push rcx
    push 0
    push r15
    push r14
    push r13
    push r12
    push r11
    push r10
    push r9
    push r8
    push rbp
    push rdi
    push rsi
    push rdx
    push rcx
    push rbx
    push rax
    mov eax, es
    push rax
    mov eax, ds
    push rax
    sti
    call syscall_is_linux
    test rax, rax
    jnz 1f

    // Native Vinix ABI: rdi is the syscall number and arguments start in
    // rsi. Reload everything because syscall_is_linux() may clobber it.
    xor r12, r12
    mov rbx, [rsp + 56]
    cmp rbx, 66
    jae 2f
    mov rsi, [rsp + 48]
    mov rdx, [rsp + 40]
    mov rcx, [rsp + 88]
    mov r8, [rsp + 72]
    mov r9, [rsp + 80]
    mov rdi, rsp
    lea rax, [rip + syscall_table]
    call [rax + rbx * 8 + 0]
    jmp 4f

    // Linux x86-64 ABI: rax is the number, followed by
    // rdi,rsi,rdx,r10,r8,r9. Vinix handlers take the saved GPR frame as
    // their first argument, so shift the six Linux arguments right once;
    // the last one is passed on the C stack.
1:
    mov r12, 1
    mov r13, [rsp + 16]
    cmp r13, 512
    jae 3f
    mov rax, rsp
    sub rsp, 16
    mov rdi, rax
    mov rsi, [rax + 56]
    mov rdx, [rax + 48]
    mov rcx, [rax + 40]
    mov r8, [rax + 88]
    mov r9, [rax + 72]
    mov rbx, [rax + 80]
    mov [rsp], rbx
    lea rbx, [rip + linux_syscall_table]
    call [rbx + r13 * 8 + 0]
    add rsp, 16
    jmp 4f

2:
    xor r12, r12
    mov rax, 0xffffffffffffffff
    mov rdx, 38
    jmp 4f

3:
    mov r12, 1
    mov rax, 38
    neg rax
    xor rdx, rdx

4:
    // Native calls return (result, errno) in rax/rdx. Linux encodes errno
    // as a negative result and otherwise preserves the caller's rdx.
    test r12, r12
    jz 5f
    test rdx, rdx
    jz 6f
    neg rdx
    mov rax, rdx
6:
    mov [rsp + 16], rax
    jmp 7f
5:
    mov [rsp + 16], rax
    mov [rsp + 40], rdx
7:
    mov rdi, rsp
    call syscall__leave
    pop rax
    mov ds, eax
    pop rax
    mov es, eax
    pop rax
    pop rbx
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop rbp
    pop r8
    pop r9
    pop r10
    pop r11
    pop r12
    pop r13
    pop r14
    pop r15 // Restore user stack
    mov rsp, gs:[32]
    swapgs
    sysretq

.att_syntax
.section .note.GNU-stack,"",%progbits
