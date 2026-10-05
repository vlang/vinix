/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native data symbols: two names address one cacheline-aligned tick word. */
#ifdef VINIX_LINUXKPI
#ifdef __APPLE__
.section __DATA,__data
.globl _jiffies
.globl _jiffies_64
.p2align 6
_jiffies:
_jiffies_64:
.quad 4294667296
#else
.section .data..cacheline_aligned,"aw",%progbits
.globl jiffies
.globl jiffies_64
.type jiffies,%object
.type jiffies_64,%object
.p2align 6
jiffies:
jiffies_64:
.quad 4294667296
.size jiffies,8
.size jiffies_64,8
.section .note.GNU-stack,"",%progbits
#endif
#endif
