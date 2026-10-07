/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef __APPLE__
#define SYM(x) _##x
.section __TEXT,__text,regular,pure_instructions
#else
#define SYM(x) x
.text
#endif
.globl SYM(mock_prctl)
.p2align 2
#ifndef __APPLE__
.type mock_prctl,@function
#endif
SYM(mock_prctl):
.cfi_startproc
#ifdef __APPLE__
 ldr x1,[sp]
 ldr x2,[sp,#8]
 ldr x3,[sp,#16]
 ldr x4,[sp,#24]
#endif
 b SYM(vinix_mac_cli_capture)
.cfi_endproc
#ifndef __APPLE__
.size mock_prctl,.-mock_prctl
.section .note.GNU-stack,"",@progbits
#else
.subsections_via_symbols
#endif
