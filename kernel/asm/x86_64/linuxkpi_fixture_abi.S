/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Instruction-only SIMD test and native per-CPU initial storage. */
#ifdef VINIX_LINUXKPI
#ifdef VINIX_LINUXKPI_HOST_TEST
#ifdef __APPLE__
.section __DATA,vinixpcpu
.p2align 6
.globl _vinix_linuxkpi_fixture_percpu_probe
_vinix_linuxkpi_fixture_percpu_probe:
.quad 17
#else
.section vinixpcpu,"aw",%progbits
.p2align 6
.globl vinix_linuxkpi_fixture_percpu_probe
.type vinix_linuxkpi_fixture_percpu_probe,%object
vinix_linuxkpi_fixture_percpu_probe:
.quad 17
.size vinix_linuxkpi_fixture_percpu_probe,8
.section .note.GNU-stack,"",%progbits
#endif
#else
.section .data..percpu..shared_aligned,"aw",%progbits
.p2align 6
.globl vinix_linuxkpi_fixture_percpu_probe
.type vinix_linuxkpi_fixture_percpu_probe,%object
vinix_linuxkpi_fixture_percpu_probe:
.quad 17
.size vinix_linuxkpi_fixture_percpu_probe,8
.text
.globl vinix_linuxkpi_fixture_xmm_save
.type vinix_linuxkpi_fixture_xmm_save,%function
vinix_linuxkpi_fixture_xmm_save:
movdqu %xmm0,(%rdi)
stmxcsr (%rsi)
ret
.size vinix_linuxkpi_fixture_xmm_save,.-vinix_linuxkpi_fixture_xmm_save
.globl vinix_linuxkpi_fixture_xmm_set
.type vinix_linuxkpi_fixture_xmm_set,%function
vinix_linuxkpi_fixture_xmm_set:
movdqu (%rdi),%xmm0
ldmxcsr (%rsi)
ret
.size vinix_linuxkpi_fixture_xmm_set,.-vinix_linuxkpi_fixture_xmm_set
.globl vinix_linuxkpi_fixture_xmm_clear
.type vinix_linuxkpi_fixture_xmm_clear,%function
vinix_linuxkpi_fixture_xmm_clear:
pxor %xmm0,%xmm0
ret
.size vinix_linuxkpi_fixture_xmm_clear,.-vinix_linuxkpi_fixture_xmm_clear
.section .note.GNU-stack,"",%progbits
#endif

#endif
