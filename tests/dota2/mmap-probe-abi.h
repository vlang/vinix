/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_DOTA_MMAP_PROBE_ABI_H
#define VINIX_DOTA_MMAP_PROBE_ABI_H
void *mmap(void *, unsigned long, int, int, int, long);
void *mmap64(void *, unsigned long, int, int, int, long);
int munmap(void *, unsigned long);
int *__errno_location(void);
int printf(const char *, ...);
int puts(const char *);
int fflush(void *);
#ifdef VINIX_DOTA_BARE_FFI
extern void *stderr;
int fprintf(void *, const char *, ...);
#endif
#endif
