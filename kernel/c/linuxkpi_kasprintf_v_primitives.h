/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_KASPRINTF_V_PRIMITIVES_H
#define VINIX_LINUXKPI_KASPRINTF_V_PRIMITIVES_H
#include <stdint.h>
#include <stdarg.h>
#include "varargs_abi.h"
/* Native compiler va_list and data-only parameter address; no Linux headers. */
typedef va_list vkf_native_va;
#if VINIX_VA_ABI == 3
#define vkf_va_parameter(ap) ((void *)(ap))
#else
#define vkf_va_parameter(ap) ((void *)&(ap))
#endif
/* Canonical cursor views only; algorithms and cursor copying remain V. */
void *vkf_kvasprintf(uint32_t, void *, void *);
void *vkf_kvasprintf_const(uint32_t, void *, void *);
void *vinix_linuxkpi_kasprintf_entry(uint32_t, void *, void *);
void vinix_linuxkpi_warn_format(const char *, int, const char *, ...);
#endif
