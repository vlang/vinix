#ifndef VINIX_PRINTF_V_H
#define VINIX_PRINTF_V_H
#include <stdint.h>
#include <stddef.h>
/* Native va_list access stays in the C entry translation unit. */
int vp_format(void (*put)(int, void *), void *context, char *format, void *arguments);
char *vp_arg_string(void *arguments);
int vp_arg_int(void *arguments);
int vinix_printf_policy(char *format, void *arguments, int kind);
int vinix_fprintf_policy(char *format, void *arguments);
#endif
