/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef VINIX_LINUXKPI
.section .text
.global vinix_linuxkpi_irq_probe
.type vinix_linuxkpi_irq_probe,@function
/* A runtime vector selects an immutable immediate-INT leaf. No exception
 * vector, reserved high vector or dynamically patched instruction is used.
 * Tail dispatch preserves the ordinary caller stack through INT and IRET. */
vinix_linuxkpi_irq_probe:
    sub $32, %edi
    cmp $207, %edi
    ja 1f
    lea .Lirq_probe_table(%rip), %rax
    mov (%rax,%rdi,8), %rax
    jmp __x86_indirect_thunk_rax
1:
    mov $-22, %eax
    ret
.size vinix_linuxkpi_irq_probe, .-vinix_linuxkpi_irq_probe

.altmacro
.macro IRQ_PROBE vector
.Lirq_probe_\vector:
    int $\vector
    xor %eax, %eax
    ret
.endm
.set irq_probe_vector, 32
.rept 208
IRQ_PROBE %irq_probe_vector
.set irq_probe_vector, irq_probe_vector + 1
.endr

.section .rodata
.balign 8
.Lirq_probe_table:
.macro IRQ_PROBE_POINTER vector
    .quad .Lirq_probe_\vector
.endm
.set irq_probe_vector, 32
.rept 208
IRQ_PROBE_POINTER %irq_probe_vector
.set irq_probe_vector, irq_probe_vector + 1
.endr
#endif
.section .note.GNU-stack,"",%progbits
