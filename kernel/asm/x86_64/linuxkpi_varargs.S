#ifdef VINIX_LINUXKPI
#include "varargs.inc"
.text
VINIX_VARIADIC snprintf, vinix_linuxkpi_snprintf_entry, 3
VINIX_VARIADIC scnprintf, vinix_linuxkpi_scnprintf_entry, 3
VINIX_VARIADIC sprintf, vinix_linuxkpi_sprintf_entry, 2
VINIX_VARIADIC _printk, vinix_linuxkpi_printk_entry, 1
VINIX_VARIADIC _printk_deferred, vinix_linuxkpi_printk_deferred_entry, 1
VINIX_VARIADIC vinix_linuxkpi_warn_format, vinix_linuxkpi_warn_entry, 3
.section .note.GNU-stack,"",@progbits
#endif
