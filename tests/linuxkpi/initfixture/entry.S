/* Instruction-only ELF entry: establish the native C call stack alignment. */
.text
.global _start
.type _start,@function
_start:
    xor %ebp, %ebp
    and $-16, %rsp
    call vinix_linuxkpi_guest_start
    ud2
.size _start,.-_start
.section .note.GNU-stack,"",@progbits
