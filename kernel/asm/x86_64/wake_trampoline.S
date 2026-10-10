// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// From real mode to the kernel: where a processor starts after a suspend to
// RAM, and where the other processors are started again after it.
//
// Firmware that resumes from S3 jumps to the address in the FACS waking
// vector in real mode, and a processor that is sent a startup IPI begins in
// real mode at the page the IPI names. Both land on the first byte below. The
// code is assembled here, kept in the kernel's read-only data, and copied at
// boot to a page under 1 MiB that the kernel reserved for it
// (x86/wake/trampoline.v), so nothing in it may depend on where it was
// linked: real-mode code addresses its data through CS, which the entry sets
// to the page, and the two far jumps go through vectors the kernel fills in
// with the page's address.
//
// The climb is the shortest there is:
//
//   real mode       load the page's own GDT, set CR0.PE
//   protected mode  set CR4.PAE (and LA57), load a page table that maps this
//                   page onto itself and the kernel where it always is, set
//                   EFER (long mode, no-execute, SYSCALL), set CR0.PG
//   long mode       load the stack and the argument the kernel left in the
//                   header and jump to the kernel's entry
//
// Everything else a processor needs -- its own GDT, IDT, task register, the
// rest of CR4, its model-specific registers -- is put back by the kernel code
// this ends in: x86_wake_resume for the processor that slept
// (wake_context.S), x86_wake_secondary for one being started again.
//
// Between uses the header names no entry, and a processor that arrives then
// halts in real mode.
//
// With `trace` set in the header each stage writes a letter to the first
// serial port: R, P, L. A machine that stops in between says how far it got.

#define AT(label) ((label) - x86_wake_trampoline)

.section .rodata
.balign 16
.global x86_wake_trampoline
.global x86_wake_trampoline_end
x86_wake_trampoline:
.code16
    cli
    cld
    // Over the header; two bytes whatever the assembler would choose.
    .byte 0xeb, wake_real - 1f
1:
    .balign 8

// The header, at offset 8: x86/wake/trampoline.v has the same layout.
wake_header:
    .long 0x454b4157                // "WAKE"
wake_trace:
    .long 0
wake_cr3:
    .long 0
wake_cr4:
    .long 0
wake_cr0:
    .long 0
    .long 0
wake_efer:
    .quad 0
wake_entry:
    .quad 0
wake_stack:
    .quad 0
wake_argument:
    .quad 0
// Far pointers as LJMP reads them: offset, then selector.
wake_protected_vector:
    .long 0
    .word 0x08
    .word 0
wake_long_vector:
    .long 0
    .word 0x18
    .word 0
wake_gdt_pointer:
    .word wake_gdt_end - wake_gdt - 1
    .long 0
    .word 0
// No interrupt can be taken on the way: a table of no entries makes one a
// shutdown instead of a jump through whatever real mode left behind.
wake_idt_pointer:
    .word 0
    .long 0
    .word 0
    .balign 8
wake_gdt:
    .quad 0
    .quad 0x00cf9a000000ffff        // 0x08: 32-bit code
    .quad 0x00cf92000000ffff        // 0x10: data
    .quad 0x00af9a000000ffff        // 0x18: 64-bit code
wake_gdt_end:

.macro WAKE_TRACE16 letter
    cmpl $0, AT(wake_trace)
    je 9f
    movw $0x3f8, %dx
    movb $\letter, %al
    outb %al, %dx
9:
.endm

.macro WAKE_TRACE letter, base
    cmpl $0, AT(wake_trace)(\base)
    je 9f
    movw $0x3f8, %dx
    movb $\letter, %al
    outb %al, %dx
9:
.endm

wake_real:
    // CS is the page; make the data segments the same, so that an offset
    // into the page is an address.
    movw %cs, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    xorl %esp, %esp
    // The page's address, which protected and long mode find their data by.
    xorl %ebx, %ebx
    movw %cs, %bx
    shll $4, %ebx
    WAKE_TRACE16 'R'
    // Nowhere to go: the kernel is not expecting a processor to start. This
    // one stops here rather than run with what the last start left behind.
    movl AT(wake_entry), %eax
    orl AT(wake_entry) + 4, %eax
    jnz 2f
1:
    hlt
    jmp 1b
2:
    lidtl AT(wake_idt_pointer)
    lgdtl AT(wake_gdt_pointer)
    // Protection on, and nothing else: a processor that was reset comes with
    // its caches disabled in CR0, which the value loaded below undoes.
    movl $0x00000011, %eax
    movl %eax, %cr0
    ljmpl *AT(wake_protected_vector)

.code32
wake_protected:
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    xorl %eax, %eax
    movw %ax, %fs
    movw %ax, %gs
    WAKE_TRACE 'P', %ebx
    movl AT(wake_cr4)(%ebx), %eax
    movl %eax, %cr4
    movl AT(wake_cr3)(%ebx), %eax
    movl %eax, %cr3
    movl $0xc0000080, %ecx
    movl AT(wake_efer)(%ebx), %eax
    movl AT(wake_efer) + 4(%ebx), %edx
    wrmsr
    // Paging on with EFER.LME set is long mode, still running 32-bit code.
    movl AT(wake_cr0)(%ebx), %eax
    movl %eax, %cr0
    ljmpl *AT(wake_long_vector)(%ebx)

.code64
wake_long:
    WAKE_TRACE 'L', %rbx
    movq AT(wake_stack)(%rbx), %rsp
    movq AT(wake_argument)(%rbx), %rdi
    movq AT(wake_entry)(%rbx), %rax
    jmpq *%rax

x86_wake_trampoline_end:

// Where the two far jumps go, as offsets into the page.
.balign 4
.global x86_wake_protected_offset
x86_wake_protected_offset:
    .long AT(wake_protected)
.global x86_wake_long_offset
x86_wake_long_offset:
    .long AT(wake_long)

.section .note.GNU-stack,"",%progbits
