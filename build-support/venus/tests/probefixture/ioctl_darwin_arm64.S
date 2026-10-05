/* SPDX-License-Identifier: GPL-2.0-or-later */
.text
.globl _vhs_ioctl
.p2align 2
_vhs_ioctl:
    ldr x2, [sp]
    b _vhs_ioctl_body
