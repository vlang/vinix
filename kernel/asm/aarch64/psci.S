// PSCI conduits. The function id arrives in x0 per the C ABI, which is also
// where PSCI expects it, so the call needs no marshalling. Returning normally
// means the conduit is not implemented; the caller then tries the other one.
.section .text

.globl vinix_psci_hvc
.type vinix_psci_hvc, %function
vinix_psci_hvc:
    hvc #0
    ret

.globl vinix_psci_smc
.type vinix_psci_smc, %function
vinix_psci_smc:
    smc #0
    ret
