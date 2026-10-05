/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_SANDBOX_V_H
#define VINIX_SANDBOX_V_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
struct sb_cap_data { uint32_t effective, permitted, inheritable; };
#ifndef VINIX_V_RUNTIME
int vksb_main(int, char **);
int vksb_verify_ambient_core(void);
#endif
int vksb_prctl(int, uint64_t);
int vksb_capget(void *);
int vksb_capset(void *);
int vksb_verify_ambient(void);
int vksb_ambient_cap(uint64_t);
int vksb_getids(uint32_t *, uint32_t *);
int vksb_setids(uint32_t, uint32_t);
int vksb_groups(int);
int vksb_close_fds(void);
int vksb_unveil(const char *, const char *);
int vksb_pledge(const char *, const char *);
int vksb_exec(const char *, char **, char **);
int vksb_errno(void);
void vksb_error(const char *);
void vksb_bad(const char *);
void vksb_help(const char *);
#endif
