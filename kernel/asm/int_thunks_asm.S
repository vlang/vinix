.altmacro

.macro THUNK num
.global interrupt_thunk_\num
interrupt_thunk_\num:
.if \num != 8 && \num != 10 && \num != 11 && \num != 12 && \num != 13 && \num != 14 && \num != 17 && \num != 30
    push $0
.endif

    // From userspace: any code segment of privilege 3, as an LDT's code
    // segments are as well as the GDT's.
    testb $3, 16(%rsp)
    jz 1f
    swapgs

1:
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

    cld

    mov $0x30, %eax
    mov %eax, %ds
    mov %eax, %es
    mov %eax, %ss

    // SMAP holds only while AC is clear, and an interrupt leaves AC as the
    // interrupted code had it: userspace can set it. SYSCALL clears it through
    // the flags mask. CLAC is an invalid opcode on a CPU without SMAP.
    cmpb $0, smap_enabled(%rip)
    je 5f
    clac
5:

    mov %rsp, %rdi
    call interrupt_enter
    mov $\num, %rdi
    mov $(\num * 8), %rax
    lea interrupt_table(%rip), %rbx
    add %rax, %rbx
    mov %rsp, %rsi
    xor %rbp, %rbp
    call *(%rbx)
    jmp interrupt_thunk_exit
.endm

.macro thunkaddr num
    .quad interrupt_thunk_\num
.endm

.section .data

.global interrupt_thunks
.align 8
interrupt_thunks:
.set i,0
.rept 256
    thunkaddr %i
    .set i,i+1
.endr

.section .text

.set i,0
.rept 256
    THUNK %i
    .set i,i+1
.endr

// Every thunk goes back through here.
interrupt_thunk_exit:
    // Back to userspace: a signal to take, or an exit a sibling asked for,
    // sends the thread into the kernel first; see userland.interrupt_return().
    // Interrupts stay off from here to the IRETQ: interrupt_leave() checks
    // the segments it goes back to against this CPU's GDT and LDT, which a
    // switch to another thread would change.
    testb $3, 152(%rsp)
    jz 2f
    cli
    mov %rsp, %rdi
    call interrupt_leave
2:
    // A data segment that went while the thread was away -- another thread
    // took its LDT entry, or it came back on a CPU with a newer LDT -- faults
    // here, and the fault handler has it loaded null; see isr.v.
    pop %rax
.global interrupt_exit_load_ds
interrupt_exit_load_ds:
    mov %eax, %ds
    pop %rax
.global interrupt_exit_load_es
interrupt_exit_load_es:
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
    add $8, %rsp

    testb $3, 8(%rsp) // if user
    jz 1f
    swapgs

1:
    iretq

.section .note.GNU-stack,"",%progbits
