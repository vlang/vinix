// stdio.h: Standard I/O function definitions.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

#ifndef _STDIO_H
#define _STDIO_H

#include <stdarg.h>
#include <stddef.h>

struct __file {
    void *ptr;
};

typedef struct __file FILE;

int printf(const char *restrict format, ...);
int fprintf(FILE *restrict stream, const char *restrict format, ...);
int printf_panic(const char *restrict format, ...);

#endif
