/* SPDX-License-Identifier: GPL-2.0-or-later */
.text

/* Abandon the bootstrap/current stack and enter the permanent idle stack.
 * The tail transfer keeps the same compiler-independent retpoline. */
.global vinix_enter_idle
.type vinix_enter_idle, @function
vinix_enter_idle:
    cli
    mov %rdi, %rsp
    and $-16, %rsp
    sub $8, %rsp
    movq $0, (%rsp)
    mov %rdx, %rdi
    jmp __x86_indirect_thunk_rsi
.size vinix_enter_idle, .-vinix_enter_idle

/* Opt-in recovery recognizes only the exact PC and address of each probe. */
.global vinix_guard_probe_read
.type vinix_guard_probe_read, @function
vinix_guard_probe_read:
.global vinix_guard_read_fault
vinix_guard_read_fault:
    movb (%rdi), %al
.global vinix_guard_read_resume
vinix_guard_read_resume:
    mov $1, %eax
    ret
.size vinix_guard_probe_read, .-vinix_guard_probe_read

.global vinix_guard_probe_write
.type vinix_guard_probe_write, @function
vinix_guard_probe_write:
.global vinix_guard_write_fault
vinix_guard_write_fault:
    movb $0, (%rdi)
.global vinix_guard_write_resume
vinix_guard_write_resume:
    mov $1, %eax
    ret
.size vinix_guard_probe_write, .-vinix_guard_probe_write

.global vinix_guard_probe_stack
.type vinix_guard_probe_stack, @function
vinix_guard_probe_stack:
    mov %rsp, %r11
    mov %rdi, %rsp
.global vinix_guard_stack_fault
vinix_guard_stack_fault:
    pushq $0
.global vinix_guard_stack_resume
vinix_guard_stack_resume:
    mov %r11, %rsp
    mov $1, %eax
    ret
.size vinix_guard_probe_stack, .-vinix_guard_probe_stack
