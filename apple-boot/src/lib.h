// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Freestanding helpers for the Apple loader. The loader runs with the MMU off,
 * where every access is Device memory and an unaligned one faults, so these
 * never widen an access past the alignment of its operands. The host tests
 * build the same sources against the C library instead. */
#ifndef APPLE_BOOT_LIB_H
#define APPLE_BOOT_LIB_H

#include <stddef.h>
#include <stdint.h>

#ifdef APPLE_BOOT_HOST
#include <string.h>
#else
void *memcpy(void *dest, const void *src, size_t count);
void *memmove(void *dest, const void *src, size_t count);
void *memset(void *dest, int value, size_t count);
int memcmp(const void *left, const void *right, size_t count);
size_t strlen(const char *text);
int strcmp(const char *left, const char *right);
#endif

size_t lib_strnlen(const char *text, size_t limit);

uint32_t load_le32(const void *pointer);
uint64_t load_le64(const void *pointer);
void store_be32(void *pointer, uint32_t value);
uint32_t load_be32(const void *pointer);
uint64_t align_up(uint64_t value, uint64_t alignment);

#endif
