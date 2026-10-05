/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_DOTA_MMAP32_ABI_H
#define VINIX_DOTA_MMAP32_ABI_H
/* Native Linux LP64 API declarations only. */
void *dlsym(void *, const char *);
int *__errno_location(void);
int munmap(void *, unsigned long);
int open(const char *, int, ...);
long read(int, void *, unsigned long);
int close(int);
void *memmove(void *, const void *, unsigned long);
#ifdef VINIX_DOTA_BARE_FFI
extern void *stderr;
int fprintf(void *, const char *, ...);
#endif
#endif
