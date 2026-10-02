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
struct sb_cap_data { uint32_t effective, permitted, inheritable; };

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
static int sb_verify_ambient(void)
{
	for (unsigned long cap = 0; cap <= 40; cap++)
		if (syscall(SYS_prctl, SB_PR_CAP_AMBIENT, 3UL, cap, 0UL, 0UL) != 0) return -1;
	return 0;
}
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

struct sb_config {
	const char *promises;
	const char *paths[SB_MAX_PATHS];
	const char *perms[SB_MAX_PATHS];
	char *env[SB_MAX_ENV + 2];
	size_t paths_count, env_count;
	uint32_t uid, gid;
	int has_uid, has_gid, command;
};

static int sb_error(const char *operation)
{
	fprintf(stderr, "vinix-sandbox: %s: %s\n", operation, strerror(errno));
	return 125;
}
static int sb_bad(const char *message)
{
	fprintf(stderr, "vinix-sandbox: %s\n", message);
	return 125;
}

static int sb_id(const char *text, uint32_t *id)
{
	uint32_t value = 0;
	if (!*text) return -1;
	for (; *text; text++) {
		if (*text < '0' || *text > '9') return -1;
		uint32_t digit = (uint32_t)(*text - '0');
		if (value > (UINT32_MAX - 1 - digit) / 10) return -1;
		value = value * 10 + digit;
	}
	/* Zero retains root identity; UINT32_MAX means "leave unchanged". */
	if (!value) return -1;
	*id = value;
	return 0;
}

static int sb_absolute(const char *path)
{
	return path[0] == '/' && strlen(path) < 4096;
}

static int sb_environment(const char *entry)
{
	const char *equals = strchr(entry, '=');
	if (!equals || equals == entry) return 0;
	for (const char *p = entry; p != equals; p++) {
		if ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') || *p == '_') continue;
		if (p != entry && *p >= '0' && *p <= '9') continue;
		return 0;
	}
	return 1;
}

static int sb_parse(int argc, char **argv, struct sb_config *config)
{
	for (int i = 1; i < argc; i++) {
		const char *option = argv[i];
		if (!strcmp(option, "--")) {
			config->command = i + 1;
			break;
		}
		if (!strcmp(option, "--promises")) {
			if (++i == argc || config->promises || strlen(argv[i]) >= 1024)
				return sb_bad("--promises needs one string shorter than 1024 bytes");
			config->promises = argv[i];
		} else if (!strcmp(option, "--uid") || !strcmp(option, "--gid")) {
			int is_uid = !strcmp(option, "--uid");
			int *seen = is_uid ? &config->has_uid : &config->has_gid;
			uint32_t *id = is_uid ? &config->uid : &config->gid;
			if (++i == argc || *seen || sb_id(argv[i], id))
				return sb_bad("UID and GID must be numeric nonzero IDs below 4294967295");
			*seen = 1;
		} else if (!strcmp(option, "--unveil")) {
			if (i + 2 >= argc || config->paths_count == SB_MAX_PATHS)
				return sb_bad("--unveil needs an absolute path and permissions (at most 127 paths)");
			const char *path = argv[++i], *perms = argv[++i];
			if (!sb_absolute(path) || strlen(perms) > 4 || strspn(perms, "rwxc") != strlen(perms))
				return sb_bad("unveil paths must be absolute; permissions contain only rwxc");
			for (size_t j = 0; j < config->paths_count; j++)
				if (!strcmp(path, config->paths[j])) return sb_bad("duplicate unveil path");
			config->paths[config->paths_count] = path;
			config->perms[config->paths_count++] = perms;
		} else if (!strcmp(option, "--env")) {
			if (++i == argc || config->env_count == SB_MAX_ENV || !sb_environment(argv[i]))
				return sb_bad("--env needs NAME=VALUE (at most 64 entries)");
			const char *equals = strchr(argv[i], '=');
			for (size_t j = 0; j < config->env_count; j++) {
				const char *previous = strchr(config->env[j], '=');
				if (equals - argv[i] == previous - config->env[j]
					&& !strncmp(argv[i], config->env[j], (size_t)(equals - argv[i])))
					return sb_bad("duplicate environment variable");
			}
			config->env[config->env_count++] = argv[i];
		} else {
			return sb_bad("unknown option; use --help for usage");
		}
	}
	if (!config->promises || config->command <= 0 || config->command >= argc
		|| !sb_absolute(argv[config->command]))
		return sb_bad("--promises and -- /absolute/program are required");
	if (config->has_uid != config->has_gid) return sb_bad("--uid and --gid must be supplied together");
	return 0;
}

static int sb_harden(struct sb_config *config)
{
	uint32_t uid[3], gid[3];
	struct sb_cap_data caps[2] = { { 0, 0, 0 }, { 0, 0, 0 } };
	if (sb_getids(uid, gid)) return sb_error("read credentials");
	if (!config->has_uid) {
		if (!uid[0] || !uid[1] || !uid[2] || !gid[0] || !gid[1] || !gid[2])
			return sb_bad("root credentials require explicit --uid and --gid");
		config->uid = uid[1];
		config->gid = gid[1];
	}
	if (sb_prctl(SB_PR_SET_NO_NEW_PRIVS, 1)) return sb_error("set no_new_privs");
	if (sb_prctl(SB_PR_GET_NO_NEW_PRIVS, 0) != 1) return sb_bad("no_new_privs was not enforced");
	if (sb_capget(caps)) return sb_error("read capabilities");
	if (sb_prctl(SB_PR_CAP_AMBIENT, SB_PR_CAP_AMBIENT_CLEAR_ALL)) return sb_error("clear ambient capabilities");
	/* Ordinary users cannot change the bounding set. Empty permitted and
 * inheritable sets plus no_new_privs still prevent gaining exec privileges.
 * A privileged launcher also clears every supported bounding capability. */
	if (caps[0].effective & (1U << SB_CAP_SETPCAP)) {
		int cap;
		for (cap = 0; cap < 64; cap++) {
			int present = sb_prctl(SB_PR_CAPBSET_READ, (unsigned long)cap);
			if (present == -1 && errno == EINVAL) break;
			if (present < 0) return sb_error("read capability bounding set");
			if (present && sb_prctl(SB_PR_CAPBSET_DROP, (unsigned long)cap))
				return sb_error("drop bounding capability");
		}
		if (cap == 64) return sb_bad("unsupported capability bounding set width");
	}
	int groups = sb_groups(0);
	if (groups < 0) return sb_error("read supplementary groups");
	if (groups && sb_groups(1)) return sb_error("clear supplementary groups");
	if (sb_groups(0) != 0) return sb_bad("supplementary groups were not cleared");
	if (sb_prctl(SB_PR_SET_KEEPCAPS, 0)) return sb_error("disable keepcaps");
	if (sb_setids(config->uid, config->gid)) return sb_error("drop credentials");
	if (sb_getids(uid, gid)) return sb_error("verify credentials");
	for (size_t i = 0; i < 3; i++)
		if (uid[i] != config->uid || gid[i] != config->gid)
			return sb_bad("credential drop was not enforced");
	memset(caps, 0, sizeof(caps));
	if (sb_capset(caps)) return sb_error("clear capabilities");
	if (sb_capget(caps)) return sb_error("verify capabilities");
	for (size_t i = 0; i < 2; i++)
		if (caps[i].effective || caps[i].permitted || caps[i].inheritable)
			return sb_bad("capability drop was not enforced");
	if (sb_verify_ambient()) return sb_bad("ambient capability drop was not enforced");
	if (sb_close_fds()) return sb_error("close inherited descriptors");
	return 0;
}

int vinix_sandbox_main(int argc, char **argv)
{
	if (argc == 2 && !strcmp(argv[1], "--help")) {
		puts("Usage: vinix-sandbox --promises 'stdio ...' [--uid UID --gid GID]\n"
		     "       [--unveil /path rwxc]... [--env NAME=VALUE]... -- /program [args...]\n"
		     "Drops capabilities, supplementary groups and inherited FDs >=3; sets\n"
		     "no_new_privs, locks unveil and keeps the target promises across exec.\n"
		     "Root must choose nonzero UID/GID. Environment is empty unless --env\n"
		     "is supplied. The program is automatically unveiled rx; shared library\n"
		     "and data paths must be explicitly unveiled. Setup failure exits 125.");
		return 0;
	}
	struct sb_config config = { 0 };
	int result = sb_parse(argc, argv, &config);
	if (result) return result;
	if ((result = sb_harden(&config))) return result;
	const char *program = argv[config.command];
	if (sb_unveil(program, "rx")) return sb_error("unveil program");
	for (size_t i = 0; i < config.paths_count; i++)
		if (sb_unveil(config.paths[i], config.perms[i])) return sb_error("unveil path");
	if (sb_unveil(NULL, NULL)) return sb_error("lock unveil");
	/* Explicit execpromises are essential: NULL would discard both pledge and
 * unveil on exec. The launcher itself only needs to report errors and exec. */
	if (sb_pledge("stdio rpath exec", config.promises)) return sb_error("pledge");
	sb_exec(program, &argv[config.command], config.env);
	return sb_error("exec program");
}

#ifndef VINIX_SANDBOX_NO_MAIN
int main(int argc, char **argv) { return vinix_sandbox_main(argc, argv); }
#endif
