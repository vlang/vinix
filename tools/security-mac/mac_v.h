/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_MAC_V_H
#define VINIX_MAC_V_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#ifdef VINIX_SECURITY_FIXTURE
int mock_prctl(int, ...);
int mock_lsetxattr(const char *, const char *, const void *, size_t, int);
int mock_execvp(const char *, char *const *);
#endif
#ifndef VINIX_V_RUNTIME
int64_t vm_prctl(uint64_t, uint64_t, uint64_t, uint64_t);
int vm_lsetxattr(const char *, const char *, const void *, size_t, int);
int vm_execvp(const char *, char **);
void vm_error(const char *);
void vm_usage(const char *);
void vm_status(int64_t, int64_t);
int vm_number(const char *, unsigned, unsigned *);
int vm_permissions(const char *, unsigned *);
int vm_main(int, char **);
#endif
#endif
