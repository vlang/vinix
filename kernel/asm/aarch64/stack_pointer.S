/* Instruction-only leaf: BL preserves the caller's SP on AArch64. */
.text
.global read_current_sp
.type read_current_sp,%function
read_current_sp:
    mov x0, sp
    ret
.size read_current_sp,.-read_current_sp
.section .note.GNU-stack,"",%progbits
