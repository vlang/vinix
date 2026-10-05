#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mount.h>
#include <sys/wait.h>
#include <unistd.h>
int main(void) {
    setbuf(stdout, NULL); setbuf(stderr, NULL);
    int terminal = open("/dev/console", O_WRONLY);
    if (terminal >= 0) { dup2(terminal, 1); dup2(terminal, 2); close(terminal); }
    (void)mount("proc", "/proc", "proc", 0, NULL);
    static const char *programs[] = {
        "/tests/clock",
        "/tests/verify-optimized-dynamic",
        "/tests/verify-all-classes-optimized-dynamic",
        "/tests/verify-optimized-static",
        "/tests/verify-all-classes-optimized-static",
        "/tests/verify-disabled-dynamic",
        "/tests/verify-all-classes-disabled-dynamic",
        "/tests/verify-disabled-static",
        "/tests/verify-all-classes-disabled-static"
    };
    for (size_t i = 0; i < sizeof programs / sizeof programs[0]; ++i) {
        printf("UALLOC-ARM-BEGIN program=%s\n", programs[i]);
        pid_t child = fork();
        if (!child) { execl(programs[i], programs[i], (char *)NULL); perror("exec"); _exit(127); }
        int status;
        if (child < 0 || waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status)) {
            printf("UALLOC-ARM-FAIL program=%s status=%d\n", programs[i], child < 0 ? -1 : status);
            continue;
        }
        printf("UALLOC-ARM-PASS program=%s\n", programs[i]);
    }
    puts("UALLOC-ARM-DONE");
    for (;;) sleep(1);
}
