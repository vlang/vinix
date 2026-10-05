/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_SANDBOX_V_H
#define VINIX_SANDBOX_V_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
enum {
 SB_PR_SET_KEEPCAPS = 8, SB_PR_CAPBSET_READ = 23, SB_PR_CAPBSET_DROP = 24,
 SB_PR_SET_NO_NEW_PRIVS = 38, SB_PR_GET_NO_NEW_PRIVS = 39, SB_PR_CAP_AMBIENT = 47,
 SB_PR_CAP_AMBIENT_CLEAR_ALL = 4, SB_CAP_SETPCAP = 8, SB_MAX_PATHS = 127, SB_MAX_ENV = 64
};
struct sb_cap_data { uint32_t effective, permitted, inheritable; };
#ifdef VINIX_SECURITY_FIXTURE
int sb_prctl(int, unsigned long);
int sb_capget(struct sb_cap_data *);
int sb_capset(struct sb_cap_data *);
int sb_verify_ambient(void);
int sb_getids(uint32_t *, uint32_t *);
int sb_setids(uint32_t, uint32_t);
int sb_groups(int);
int sb_close_fds(void);
int sb_unveil(const char *, const char *);
int sb_pledge(const char *, const char *);
int sb_exec(const char *, char *const *, char *const *);
#endif
#ifndef VINIX_V_RUNTIME
int vksb_main(int, char **);
int vksb_verify_ambient_core(void);
#endif
#ifndef VINIX_V_RUNTIME
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
#endif
