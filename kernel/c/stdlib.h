// stdlib.h: C standard library function definitions.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

#ifndef _STDLIB_H
#define _STDLIB_H

int atexit(void (*func)(void));
void qsort(void* ptr, size_t count, size_t size,
           int (*comp)(const void*, const void*));

#endif
