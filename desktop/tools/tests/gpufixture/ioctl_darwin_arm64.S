/* SPDX-License-Identifier: BSD-2-Clause */
/* Darwin's first unnamed int argument lives in the incoming stack slot. */
.text
.globl _gpf_ioctl
.p2align 2
_gpf_ioctl:
    ldr w2, [sp]
    b _gpf_ioctl_body
