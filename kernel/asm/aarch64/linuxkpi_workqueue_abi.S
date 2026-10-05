/* SPDX-License-Identifier: GPL-2.0-only */
/* Native integer variadic capture; queue/name policy lives in headercore V. */
#ifdef VINIX_LINUXKPI
#include "varargs.inc"
.text
VINIX_VARIADIC ABI_SYMBOL(alloc_workqueue), ABI_SYMBOL(vinix_linuxkpi_alloc_workqueue_entry), 3
#ifndef __APPLE__
.section .note.GNU-stack,"",%progbits
#endif
#endif
