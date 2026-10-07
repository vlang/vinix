/* Native va_list capture only; every fixture body is V. */
#if defined(__aarch64__)
#include "../../kernel/asm/aarch64/varargs.inc"
#else
#include "../../kernel/asm/x86_64/varargs.inc"
#endif
.text
VINIX_VARIADIC ABI_SYMBOL(vmf_golden_bytes), ABI_SYMBOL(vmf_golden_entry), 3
VINIX_VARIADIC ABI_SYMBOL(vmf_nested), ABI_SYMBOL(vmf_nested_entry), 1
VINIX_VARIADIC ABI_SYMBOL(vmf_metadata), ABI_SYMBOL(vmf_metadata_entry), 4
VINIX_VARIADIC ABI_SYMBOL(vmf_nested_invalid), ABI_SYMBOL(vmf_nested_invalid_entry), 1
VINIX_VARIADIC ABI_SYMBOL(vmf_public_va), ABI_SYMBOL(vmf_public_entry), 1
VINIX_VARIADIC ABI_SYMBOL(vmf_libc), ABI_SYMBOL(vmf_libc_entry), 1
#ifndef __APPLE__
#if defined(__aarch64__)
.section .note.GNU-stack,"",%progbits
#else
.section .note.GNU-stack,"",@progbits
#endif
#endif
