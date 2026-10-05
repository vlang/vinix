#ifndef VINIX_PRINTF_V_H
#define VINIX_PRINTF_V_H
#include <stdint.h>
#include <stddef.h>
/* Instruction-only variadic entries pass their native cursor to V. */
int vp_format(void (*put)(int, void *), void *context, char *format, void *arguments);
int vp_snprintf(char *, size_t, char *, void *);
char *vp_arg_string(void *arguments);
int vp_arg_int(void *arguments);
int vinix_printf_policy(char *format, void *arguments, int kind);
int vinix_fprintf_policy(char *format, void *arguments);
#endif
