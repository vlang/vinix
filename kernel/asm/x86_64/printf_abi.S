#include "varargs.inc"
.text
VINIX_VARIADIC printf, vinix_printf_entry, 1
VINIX_VARIADIC printf_panic, vinix_panic_entry, 1
VINIX_VARIADIC kprintf, vinix_kprintf_entry, 1
VINIX_VARIADIC printf_benchmark, vinix_benchmark_entry, 1
VINIX_VARIADIC fprintf, vinix_fprintf_entry, 2
.global vp_format
.type vp_format, @function
vp_format:
    jmp npf_vpprintf
.size vp_format, .-vp_format
.global vp_snprintf
.type vp_snprintf, @function
vp_snprintf:
    jmp npf_vsnprintf
.size vp_snprintf, .-vp_snprintf
.data
.balign 8
.global stderr
.type stderr, @object
stderr:
    .quad .Lstderr_file
.size stderr, 8
.Lstderr_file:
    .quad 0
.section .note.GNU-stack,"",@progbits
