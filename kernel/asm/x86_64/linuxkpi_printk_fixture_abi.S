// SPDX-License-Identifier: GPL-2.0-only
// Original fixture's producer-owned native va_list stays live through V entry.
#ifdef VINIX_LINUXKPI
#include "varargs.inc"
VINIX_VARIADIC ABI_SYMBOL(vinix_linuxkpi_fixture_nested_format), ABI_SYMBOL(vinix_linuxkpi_fixture_nested_format_entry), 1
VINIX_VARIADIC ABI_SYMBOL(vinix_linuxkpi_fixture_nested_emit), ABI_SYMBOL(vinix_linuxkpi_fixture_nested_emit_entry), 1
#endif
#ifndef __APPLE__
.section .note.GNU-stack,"",@progbits
#endif
