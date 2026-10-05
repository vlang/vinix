// SPDX-License-Identifier: GPL-2.0-or-later
// Run with PROD=false and strict SMAP/PAN: logging itself must not read userspace.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("SYSCALL DIAGNOSTICS FAIL: line=%d errno=%d\n", __LINE__, errno); return 1; } } while (0)
#define BAD_CALL(x) do { errno = 0; CHECK((x) == -1 && errno == EFAULT); } while (0)

int main(void)
{
    const char *bad = (const char *)(uintptr_t)1;
    char buffer[4096];
    struct stat st;
    uint64_t statx_buffer[32];
    BAD_CALL(unlinkat(AT_FDCWD, bad, 0));
    BAD_CALL(mkdirat(AT_FDCWD, bad, 0700));
    BAD_CALL(readlinkat(AT_FDCWD, bad, buffer, sizeof(buffer)));
    BAD_CALL(openat(AT_FDCWD, bad, O_RDONLY));
    BAD_CALL(syscall(SYS_faccessat, AT_FDCWD, bad, F_OK));
    BAD_CALL(fstatat(AT_FDCWD, bad, &st, 0));
    BAD_CALL(linkat(AT_FDCWD, bad, AT_FDCWD, "/tmp/no-link", 0));
    BAD_CALL(linkat(AT_FDCWD, "/dev/null", AT_FDCWD, bad, 0));
    BAD_CALL(chdir(bad));
    CHECK(stat("/", &st) == 0 && S_ISDIR(st.st_mode));
    CHECK(syscall(SYS_statx, AT_FDCWD, "/", 0, 0x7ff, statx_buffer) == 0);
    CHECK(getcwd(buffer, sizeof(buffer)) != NULL);

    // A failed status copy must leave an exited child observable for retry.
    pid_t child = fork();
    CHECK(child >= 0);
    if (child == 0) _exit(37);
    BAD_CALL(syscall(SYS_wait4, child, (void *)(uintptr_t)1, 0, NULL));
    int status;
    CHECK(waitpid(child, &status, 0) == child);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 37);
    puts("SYSCALL DIAGNOSTICS PASS");
    fflush(stdout);
    for (;;) pause();
}
