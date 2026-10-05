#ifndef VINIX_VARARGS_ABI_H
#define VINIX_VARARGS_ABI_H
#include <stdint.h>
/* Native ABI layouts, with no implementation statements. */
#if defined(__APPLE__) && defined(__aarch64__)
#define VINIX_VA_ABI 1
#elif defined(__aarch64__)
#define VINIX_VA_ABI 2
#elif defined(__x86_64__)
#define VINIX_VA_ABI 3
#else
#error "Unsupported native variadic ABI"
#endif
struct vinix_va_aapcs64 {
    void *stack, *gr_top, *vr_top;
    int32_t gr_offs, vr_offs;
};
struct vinix_va_sysv64 {
    uint32_t gp_offset, fp_offset;
    void *overflow_arg_area, *reg_save_area;
};
#endif
