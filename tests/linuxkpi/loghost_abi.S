/* Native va_list capture only; every fixture body is V. */
#if defined(__aarch64__)
#include "../../kernel/asm/aarch64/varargs.inc"
#else
#include "../../kernel/asm/x86_64/varargs.inc"
#endif
.text
VINIX_VARIADIC ABI_SYMBOL(vml_logger_emit), ABI_SYMBOL(vml_logger_emit_entry), 4
VINIX_VARIADIC ABI_SYMBOL(vml_logger_nested), ABI_SYMBOL(vml_logger_nested_entry), 1
#ifndef __APPLE__
#if defined(__aarch64__)
.section .note.GNU-stack,"",%progbits
#else
.section .note.GNU-stack,"",@progbits
#endif
#endif
