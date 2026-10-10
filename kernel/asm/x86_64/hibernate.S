// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The last instructions of a kernel that has loaded an image of another from
// a disk and is about to become it (hibernate/resume_amd64.v).
//
// Every page of the image is in memory by now. Most are in the frames they
// were saved from; the rest could not be put there, because this kernel was
// using those frames, and wait in frames the image has no use for. What is
// left is to copy those into place -- over this kernel's own data, stacks
// and page tables -- and to jump into the image. So nothing from here on may
// depend on any of that: the code that copies, the list it copies from, its
// stack, the page table it runs under and the block of values below are all
// in frames the image does not want, and are found through the direct map,
// which the page table made for this maps the same way the kernel's does.
//
// The block, at its direct-map address:

#define JUMP_CR3     0
#define JUMP_CR4     8
#define JUMP_STACK   16
#define JUMP_COPY    24
#define JUMP_LIST    32
#define JUMP_DIRECT  40
#define JUMP_ENTRY   48
#define JUMP_CONTEXT 56

.section .text

// void x86_hibernate_enter(Jump *block)
//
// In the kernel's own text, which the new page table maps where the old one
// did, so that the instruction after the switch is still this code.
// Interrupts off, every other processor stopped. Does not return.
.global x86_hibernate_enter
.type x86_hibernate_enter, @function
x86_hibernate_enter:
    cli
    movq %rdi, %rbx
    movq JUMP_CR3(%rbx), %rax
    movq %rax, %cr3
    // Global pages and tagged address spaces off: with them goes every
    // translation the processor has cached, under any tag. What the image's
    // kernel finds cached must be nothing, as after power-on; it believes
    // its own record of which address spaces are still cached, and that
    // record is from before the machine was switched off.
    movq JUMP_CR4(%rbx), %rax
    movq %rax, %cr4
    movq JUMP_STACK(%rbx), %rsp
    movq JUMP_COPY(%rbx), %rax
    jmpq *%rax
.size x86_hibernate_enter, .-x86_hibernate_enter

// Copied to a frame of its own and entered there with the block in %rbx.
// Position-independent, and uses no memory but the block, the list and the
// pages the list names.
//
// The list is a chain of pages: the physical address of the next (0 at the
// end), how many words follow, then pairs of words -- the physical address a
// page belongs at, and the one it is waiting at.
.global x86_hibernate_copy
.type x86_hibernate_copy, @function
x86_hibernate_copy:
    cld
    movq JUMP_LIST(%rbx), %r8
    movq JUMP_DIRECT(%rbx), %r9
1:
    testq %r8, %r8
    jz 3f
    leaq (%r8, %r9), %r10
    movq 0(%r10), %r8
    movq 8(%r10), %r11
    shrq $1, %r11
    addq $16, %r10
2:
    testq %r11, %r11
    jz 1b
    movq 0(%r10), %rdi
    movq 8(%r10), %rsi
    addq %r9, %rdi
    addq %r9, %rsi
    movl $512, %ecx
    rep movsq
    addq $16, %r10
    decq %r11
    jmp 2b
3:
    // Every page of the image is where it belongs. Its kernel's text is the
    // text this was called from, at the same address; the entry is the one a
    // processor woken from a suspend to RAM arrives at, and takes it from
    // here: its own page table first.
    movq JUMP_CONTEXT(%rbx), %rdi
    movq JUMP_ENTRY(%rbx), %rax
    jmpq *%rax
.global x86_hibernate_copy_end
x86_hibernate_copy_end:
.size x86_hibernate_copy, .-x86_hibernate_copy

.section .note.GNU-stack,"",%progbits
