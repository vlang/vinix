// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by the GPL v2 license in LICENSE.
// Native variadic ABI entry; serial-only output policy lives in kprint.
#include <stdarg.h>
#include "printf_v.h"

int printf_benchmark(const char *restrict format, ...) {
    va_list arguments;
    va_start(arguments, format);
    int result = vinix_printf_policy((char *)format, &arguments, 3);
    va_end(arguments);
    return result;
}
