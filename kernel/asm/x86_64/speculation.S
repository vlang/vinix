/* SPDX-License-Identifier: GPL-2.0-or-later */
.section .text

/* Handwritten syscall/interrupt dispatch uses RAX as the target. The inner
 * call poisons its own return prediction with the speculation trap, while
 * replacing the architectural return address with the actual target. */
.global vinix_indirect_thunk_rax
.type vinix_indirect_thunk_rax,@function
vinix_indirect_thunk_rax:
    call 2f
1:
    pause
    lfence
    jmp 1b
2:
    mov %rax, (%rsp)
    ret
.size vinix_indirect_thunk_rax, .-vinix_indirect_thunk_rax

/* Populate 32 return-predictor entries before restoring another thread.
 * Stack accounting restores every pushed address; only caller-saved RAX/RCX
 * are touched. A return from this routine uses the original caller address. */
.global vinix_speculation_fill_rsb
.type vinix_speculation_fill_rsb,@function
vinix_speculation_fill_rsb:
    mov $16, %ecx
3:
    call 5f
4:
    pause
    lfence
    jmp 4b
5:
    call 7f
6:
    pause
    lfence
    jmp 6b
7:
    dec %ecx
    jnz 3b
    add $256, %rsp
    lfence
    ret
.size vinix_speculation_fill_rsb, .-vinix_speculation_fill_rsb
.section .note.GNU-stack,"",%progbits
