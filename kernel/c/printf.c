#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>

#define NANOPRINTF_IMPLEMENTATION
#define NANOPRINTF_USE_FIELD_WIDTH_FORMAT_SPECIFIERS 1
#define NANOPRINTF_USE_PRECISION_FORMAT_SPECIFIERS 1
#define NANOPRINTF_USE_FLOAT_FORMAT_SPECIFIERS 0
#define NANOPRINTF_USE_LARGE_FORMAT_SPECIFIERS 1
#define NANOPRINTF_USE_BINARY_FORMAT_SPECIFIERS 1
#define NANOPRINTF_USE_WRITEBACK_FORMAT_SPECIFIERS 1
#include <nanoprintf.h>

#include "printf_v.h"

int vp_format(void (*put)(int, void *), void *context, char *format, void *arguments) {
    return npf_vpprintf(put, context, format, *(va_list *)arguments);
}
char *vp_arg_string(void *arguments) { return va_arg(*(va_list *)arguments, char *); }
int vp_arg_int(void *arguments) { return va_arg(*(va_list *)arguments, int); }

int printf(const char *restrict format, ...) {
#ifdef PROD
    (void)format;
    return 0;
#else
    va_list arguments;
    va_start(arguments, format);
    int result = vinix_printf_policy((char *)format, &arguments, 0);
    va_end(arguments);
    return result;
#endif
}

int printf_panic(char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    int result = vinix_printf_policy(format, &arguments, 1);
    va_end(arguments);
    return result;
}

int kprintf(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    int result = vinix_printf_policy((char *)format, &arguments, 2);
    va_end(arguments);
    return result;
}

static struct __file _stderr_file;
FILE *stderr = &_stderr_file;

int fprintf(FILE *restrict stream, const char *restrict format, ...) {
    (void)stream;
    va_list arguments;
    va_start(arguments, format);
    int result = vinix_fprintf_policy((char *)format, &arguments);
    va_end(arguments);
    return result;
}
