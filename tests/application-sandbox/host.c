/* SPDX-License-Identifier: GPL-2.0-or-later */
#define VINIX_SANDBOX_TEST
#define VINIX_SANDBOX_NO_MAIN
#include "../../tools/sandbox/vinix-sandbox.c"
#include <assert.h>

static int calls, fail_at, execs, groups, lying_nnp, lying_caps, lying_ids, lying_groups, lying_ambient;
static uint32_t uids[3], gids[3];
static struct sb_cap_data current_caps[2];
static const char *exec_path, *target_promises, *launcher_promises;
static char *exec_argv[8], *exec_env[SB_MAX_ENV + 2];
static int unveiled, locked;
static int step(void)
{
	if (++calls == fail_at) { errno = EPERM; return -1; }
	return 0;
}
static void reset(void)
{
	calls = fail_at = execs = unveiled = locked = 0;
	groups = 2;
	lying_nnp = lying_caps = lying_ids = lying_groups = lying_ambient = 0;
	for (int i = 0; i < 3; i++) uids[i] = gids[i] = 0;
	memset(current_caps, 0xff, sizeof(current_caps));
	exec_path = target_promises = launcher_promises = NULL;
	memset(exec_argv, 0, sizeof(exec_argv));
	memset(exec_env, 0, sizeof(exec_env));
}
static int sb_prctl(int option, unsigned long arg)
{
	if (step()) return -1;
	if (option == SB_PR_GET_NO_NEW_PRIVS) return lying_nnp ? 0 : 1;
	if (option == SB_PR_CAPBSET_READ) {
		if (arg > 40) { errno = EINVAL; return -1; }
		return 1;
	}
	return 0;
}
static int sb_capget(struct sb_cap_data data[2])
{
	if (step()) return -1;
	memcpy(data, current_caps, sizeof(current_caps));
	return 0;
}
static int sb_capset(struct sb_cap_data data[2])
{
	if (step()) return -1;
	if (!lying_caps) memcpy(current_caps, data, sizeof(current_caps));
	return 0;
}
static int sb_verify_ambient(void)
{
	if (step()) return -1;
	return lying_ambient ? -1 : 0;
}
static int sb_getids(uint32_t uid[3], uint32_t gid[3])
{
	if (step()) return -1;
	memcpy(uid, uids, sizeof(uids));
	memcpy(gid, gids, sizeof(gids));
	return 0;
}
static int sb_setids(uint32_t uid, uint32_t gid)
{
	if (step()) return -1;
	if (!lying_ids) for (int i = 0; i < 3; i++) { uids[i] = uid; gids[i] = gid; }
	return 0;
}
static int sb_groups(int clear)
{
	if (step()) return -1;
	if (clear && !lying_groups) groups = 0;
	return clear ? 0 : groups;
}
static int sb_close_fds(void) { return step(); }
static int sb_unveil(const char *path, const char *perms)
{
	if (step()) return -1;
	if (!path) { assert(!perms); locked = 1; }
	else {
		assert(!locked);
		if (!unveiled) { assert(!strcmp(path, "/sbin/probe")); assert(!strcmp(perms, "rx")); }
		unveiled++;
	}
	return 0;
}
static int sb_pledge(const char *promises, const char *execpromises)
{
	if (step()) return -1;
	assert(locked);
	launcher_promises = promises;
	target_promises = execpromises;
	return 0;
}
static int sb_exec(const char *path, char *const argv[], char *const envp[])
{
	assert(locked && target_promises);
	execs++;
	assert(!current_caps[0].effective && !current_caps[1].effective);
	exec_path = path;
	for (size_t i = 0; argv[i]; i++) { assert(i < 7); exec_argv[i] = argv[i]; }
	for (size_t i = 0; envp[i]; i++) { assert(i < SB_MAX_ENV + 1); exec_env[i] = envp[i]; }
	errno = ENOENT;
	return -1;
}

#define ARGS(...) (char *[]){ __VA_ARGS__, NULL }
static int run(char **argv)
{
	int argc = 0;
	while (argv[argc]) argc++;
	return vinix_sandbox_main(argc, argv);
}
static void bad(char **argv)
{
	reset();
	assert(run(argv) == 125);
	assert(calls == 0 && execs == 0);
}

int main(void)
{
	char **valid = ARGS("vinix-sandbox", "--promises", "stdio rpath error", "--uid", "1000", "--gid", "1000",
		"--unveil", "/tmp/data", "r", "--env", "TOKEN=$(id);touch /tmp/unsafe",
		"--", "/sbin/probe", "literal;argument", "--uid");
	reset();
	assert(run(valid) == 125 && execs == 1);
	assert(!strcmp(exec_path, "/sbin/probe"));
	assert(!strcmp(exec_argv[1], "literal;argument") && !strcmp(exec_argv[2], "--uid") && !exec_argv[3]);
	assert(!strcmp(exec_env[0], "TOKEN=$(id);touch /tmp/unsafe") && !exec_env[1]);
	assert(!strcmp(launcher_promises, "stdio rpath exec"));
	assert(!strcmp(target_promises, "stdio rpath error") && unveiled == 2);
	int setup_calls = calls;
	/* Every failed setup syscall must prevent exec, including unavailable
 * pledge/unveil or a denied credential/descriptor operation. */
	for (int i = 1; i <= setup_calls; i++) {
		reset(); fail_at = i;
		assert(run(valid) == 125 && execs == 0);
	}
	for (int i = 0; i < 5; i++) {
		reset();
		if (i == 0) lying_nnp = 1;
		if (i == 1) lying_caps = 1;
		if (i == 2) lying_ids = 1;
		if (i == 3) lying_groups = 1;
		if (i == 4) lying_ambient = 1;
		assert(run(valid) == 125 && execs == 0);
	}
	bad(ARGS("vinix-sandbox"));
	bad(ARGS("vinix-sandbox", "--promises", "stdio", "--", "relative"));
	bad(ARGS("vinix-sandbox", "--promises", "stdio", "--uid", "1000", "--", "/sbin/probe"));
	bad(ARGS("vinix-sandbox", "--promises", "stdio", "--uid", "-1", "--gid", "1000", "--", "/sbin/probe"));
	bad(ARGS("vinix-sandbox", "--promises", "stdio", "--uid", "4294967295", "--gid", "1000", "--", "/sbin/probe"));
	bad(ARGS("vinix-sandbox", "--promises", "stdio", "--uid", "4294967296", "--gid", "1000", "--", "/sbin/probe"));
	bad(ARGS("vinix-sandbox", "--promises", "stdio", "--uid", "0", "--gid", "1000", "--", "/sbin/probe"));
	bad(ARGS("vinix-sandbox", "--promises", "stdio", "--gid", "1000", "--gid", "1001", "--", "/sbin/probe"));
	bad(ARGS("vinix-sandbox", "--promises", "stdio", "--unveil", "/tmp", "rZ", "--", "/sbin/probe"));
	bad(ARGS("vinix-sandbox", "--promises", "stdio", "--unveil", "tmp", "r", "--", "/sbin/probe"));
	bad(ARGS("vinix-sandbox", "--promises", "stdio", "--unveil", "/tmp", "r", "--unveil", "/tmp", "rw", "--", "/sbin/probe"));
	bad(ARGS("vinix-sandbox", "--promises", "stdio", "--env", "1TOKEN=x", "--", "/sbin/probe"));
	bad(ARGS("vinix-sandbox", "--promises", "stdio", "--env", "TOKEN=x", "--env", "TOKEN=y", "--", "/sbin/probe"));
	bad(ARGS("vinix-sandbox", "--promises", "stdio", "--promises", "rpath", "--", "/sbin/probe"));
	bad(ARGS("vinix-sandbox", "--unknown", "--promises", "stdio", "--", "/sbin/probe"));
	reset();
	assert(run(ARGS("vinix-sandbox", "--promises", "stdio", "--", "/sbin/probe")) == 125 && execs == 0);
	reset();
	groups = 0;
	memset(current_caps, 0, sizeof(current_caps));
	for (int i = 0; i < 3; i++) uids[i] = gids[i] = 1000;
	assert(run(ARGS("vinix-sandbox", "--promises", "stdio", "--", "/sbin/probe")) == 125 && execs == 1);
	assert(!exec_env[0]);
	puts("APPLICATION SANDBOX HOST PASS");
	return 0;
}
