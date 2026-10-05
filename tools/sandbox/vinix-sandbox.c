/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef VINIX_SANDBOX_TEST
#include <sys/syscall.h>
#if !defined(__linux__)
#error "Build vinix-sandbox against a Linux ABI sysroot"
#endif
#if defined(__aarch64__)
#define SB_SYS_PLEDGE 248
#define SB_SYS_UNVEIL 249
#elif defined(__x86_64__)
#define SB_SYS_PLEDGE 501
#define SB_SYS_UNVEIL 502
#else
#error "Unsupported Vinix architecture"
#endif
#endif

enum {
	SB_PR_SET_KEEPCAPS = 8,
	SB_PR_CAPBSET_READ = 23,
	SB_PR_CAPBSET_DROP = 24,
	SB_PR_SET_NO_NEW_PRIVS = 38,
	SB_PR_GET_NO_NEW_PRIVS = 39,
	SB_PR_CAP_AMBIENT = 47,
	SB_PR_CAP_AMBIENT_CLEAR_ALL = 4,
	SB_CAP_SETPCAP = 8,
	SB_MAX_PATHS = 127,
	SB_MAX_ENV = 64,
};
struct sb_cap_header { uint32_t version; int32_t pid; };
#include "sandbox_v.h"
_Static_assert(sizeof(struct sb_cap_data) == 12 && SB_MAX_PATHS == 127 && SB_MAX_ENV == 64,
               "V sandbox capability and bounded parser ABI");

/* These small adapters also let host tests inject failures without invoking
 * Vinix syscall numbers on a different operating system. */
static int sb_prctl(int option, unsigned long arg);
static int sb_capget(struct sb_cap_data data[2]);
static int sb_capset(struct sb_cap_data data[2]);
static int sb_verify_ambient(void);
static int sb_getids(uint32_t uid[3], uint32_t gid[3]);
static int sb_setids(uint32_t uid, uint32_t gid);
static int sb_groups(int clear);
static int sb_close_fds(void);
static int sb_unveil(const char *path, const char *perms);
static int sb_pledge(const char *promises, const char *execpromises);
static int sb_exec(const char *path, char *const argv[], char *const envp[]);

#ifndef VINIX_SANDBOX_TEST
static int sb_prctl(int option, unsigned long arg)
{
	return (int)syscall(SYS_prctl, option, arg, 0UL, 0UL, 0UL);
}
static int sb_capget(struct sb_cap_data data[2])
{
	struct sb_cap_header header = { 0x20080522, 0 };
	return (int)syscall(SYS_capget, &header, data);
}
static int sb_capset(struct sb_cap_data data[2])
{
	struct sb_cap_header header = { 0x20080522, 0 };
	return (int)syscall(SYS_capset, &header, data);
}
static int sb_verify_ambient(void) { return vksb_verify_ambient_core(); }
int vksb_ambient_cap(uint64_t cap) { return (int)syscall(SYS_prctl, SB_PR_CAP_AMBIENT, 3UL, (unsigned long)cap, 0UL, 0UL); }

static int sb_getids(uint32_t uid[3], uint32_t gid[3])
{
	if (syscall(SYS_getresuid, &uid[0], &uid[1], &uid[2])) return -1;
	return (int)syscall(SYS_getresgid, &gid[0], &gid[1], &gid[2]);
}
static int sb_setids(uint32_t uid, uint32_t gid)
{
	if (syscall(SYS_setresgid, gid, gid, gid)) return -1;
	return (int)syscall(SYS_setresuid, uid, uid, uid);
}
static int sb_groups(int clear)
{
	return (int)syscall(clear ? SYS_setgroups : SYS_getgroups, 0, NULL);
}
static int sb_close_fds(void)
{
	return (int)syscall(SYS_close_range, 3U, UINT_MAX, 0U);
}
static int sb_unveil(const char *path, const char *perms)
{
	return (int)syscall(SB_SYS_UNVEIL, path, perms);
}
static int sb_pledge(const char *promises, const char *execpromises)
{
	return (int)syscall(SB_SYS_PLEDGE, promises, execpromises);
}
static int sb_exec(const char *path, char *const argv[], char *const envp[])
{
	return execve(path, argv, envp);
}
#endif

#ifdef VINIX_SANDBOX_TEST
int vksb_ambient_cap(uint64_t cap) { (void)cap; return 0; }
#endif
/* Typed ABI adapters also preserve unchanged include-C failure fixtures. */
int vksb_prctl(int option, uint64_t arg) { return sb_prctl(option, (unsigned long)arg); }
int vksb_capget(void *data) { return sb_capget(data); }
int vksb_capset(void *data) { return sb_capset(data); }
int vksb_verify_ambient(void) { return sb_verify_ambient(); }
int vksb_getids(uint32_t *uid, uint32_t *gid) { return sb_getids(uid, gid); }
int vksb_setids(uint32_t uid, uint32_t gid) { return sb_setids(uid, gid); }
int vksb_groups(int clear) { return sb_groups(clear); }
int vksb_close_fds(void) { return sb_close_fds(); }
int vksb_unveil(const char *path, const char *perms) { return sb_unveil(path, perms); }
int vksb_pledge(const char *promises, const char *execpromises) { return sb_pledge(promises, execpromises); }
int vksb_exec(const char *path, char **argv, char **env) { return sb_exec(path, argv, env); }
int vksb_errno(void) { return errno; }
void vksb_error(const char *operation) { fprintf(stderr, "vinix-sandbox: %s: %s\n", operation, strerror(errno)); }
void vksb_bad(const char *message) { fprintf(stderr, "vinix-sandbox: %s\n", message); }
void vksb_help(const char *text) { puts(text); }
int vinix_sandbox_main(int argc, char **argv) { return vksb_main(argc, argv); }
#ifndef VINIX_SANDBOX_NO_MAIN
int main(int argc, char **argv) { return vinix_sandbox_main(argc, argv); }
#endif
