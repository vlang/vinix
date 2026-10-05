#ifdef VINIX_LINUXKPI
#include "varargs.inc"
.text
VINIX_VARIADIC ABI_SYMBOL(snprintf), ABI_SYMBOL(vinix_linuxkpi_snprintf_entry), 3
VINIX_VARIADIC ABI_SYMBOL(scnprintf), ABI_SYMBOL(vinix_linuxkpi_scnprintf_entry), 3
VINIX_VARIADIC ABI_SYMBOL(sprintf), ABI_SYMBOL(vinix_linuxkpi_sprintf_entry), 2
VINIX_VARIADIC ABI_SYMBOL(_printk), ABI_SYMBOL(vinix_linuxkpi_printk_entry), 1
VINIX_VARIADIC ABI_SYMBOL(_printk_deferred), ABI_SYMBOL(vinix_linuxkpi_printk_deferred_entry), 1
VINIX_VARIADIC ABI_SYMBOL(vinix_linuxkpi_warn_format), ABI_SYMBOL(vinix_linuxkpi_warn_entry), 3
#ifndef __APPLE__
.section .note.GNU-stack,"",%progbits
#endif
#endif
