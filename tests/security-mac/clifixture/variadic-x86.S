/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef __APPLE__
#define SYM(x) _##x
.section __TEXT,__text,regular,pure_instructions
#else
#define SYM(x) x
.text
#endif
.globl SYM(mock_prctl)
.p2align 4
#ifndef __APPLE__
.type mock_prctl,@function
#endif
SYM(mock_prctl):
.cfi_startproc
 jmp SYM(vinix_mac_cli_capture)
.cfi_endproc
#ifndef __APPLE__
.size mock_prctl,.-mock_prctl
.section .note.GNU-stack,"",@progbits
#else
.subsections_via_symbols
#endif
