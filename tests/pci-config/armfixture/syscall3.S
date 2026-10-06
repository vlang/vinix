/* Instruction-only native Linux AArch64 syscall register boundary. */
.text
.global vinix_pci_fixture_syscall3
.type vinix_pci_fixture_syscall3,%function
vinix_pci_fixture_syscall3:
    mov x8, x0
    mov x0, x1
    mov x1, x2
    mov x2, x3
    svc #0
    ret
.size vinix_pci_fixture_syscall3,.-vinix_pci_fixture_syscall3
.section .note.GNU-stack,"",%progbits
