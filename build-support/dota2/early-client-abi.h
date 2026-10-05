/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_DOTA_EARLY_CLIENT_ABI_H
#define VINIX_DOTA_EARLY_CLIENT_ABI_H
/* Native Linux LP64 declarations only. */
char *getenv(const char *);
int unsetenv(const char *);
void *dlopen(const char *, int);
char *dlerror(void);
long write(int, const void *, unsigned long);
void _exit(int);
#ifdef VINIX_DOTA_BARE_FFI
/* Unused V compiler diagnostic scaffolding needs native stdio declarations. */
extern void *stderr;
int fprintf(void *, const char *, ...);
#endif
void *memmove(void *, const void *, unsigned long);
#endif
