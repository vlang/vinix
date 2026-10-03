/* Test-only native AArch64 PID 1: run the same x86 test under two libc pins. */
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static long seconds_now(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now)) return -1;
    return now.tv_sec;
}

static int run_variant(const char *variant, const char *runtime, const char *libraries)
{
    printf("VINIX-DOTA2-ENV-PAIR-BEGIN: %s\n", variant);
    pid_t child = fork();
    if (child < 0) {
        puts("VINIX-DOTA2-ENV-PAIR-FAIL: native fork");
        return -1;
    }
    if (!child) {
        char *const arguments[] = {"qemu-x86_64", "-B", "0x100000000", "-L",
            (char *)runtime, "-E", (char *)libraries, "/usr/bin/env-test", NULL};
        /* Explicit test-owned environment; no account or host profile data. */
        char *const environment[] = {"PATH=/usr/bin:/bin", "HOME=/root", "USER=root",
            "QEMU_CPU=Haswell", "TZ=UTC", "VINIX_ALLOW_WX=1", NULL};
        execve("/usr/bin/qemu-x86_64", arguments, environment);
        puts("VINIX-DOTA2-ENV-PAIR-FAIL: native exec");
        _exit(127);
    }
    long beginning = seconds_now();
    int status = 0, killed = 0;
    const struct timespec delay = {.tv_nsec = 100000000};
    for (;;) {
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child) break;
        if (result < 0 && errno != EINTR) {
            puts("VINIX-DOTA2-ENV-PAIR-FAIL: native wait");
            return -1;
        }
        long current = seconds_now();
        if (!killed && (beginning < 0 || current < 0 || current - beginning >= 110)) {
            /* Independent native watchdog preserves a bounded stalled child. */
            kill(child, SIGKILL);
            killed = 1;
        }
        nanosleep(&delay, NULL);
    }
    int exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    int signal_number = WIFSIGNALED(status) ? WTERMSIG(status) : 0;
    printf("VINIX-DOTA2-ENV-PAIR-RESULT: variant=%s exit=%d signal=%d watchdog=%d\n",
        variant, exit_code, signal_number, killed);
    return 0;
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    puts("VINIX-DOTA2-ENV-PAIR-START");
    if (run_variant("old", "/opt/glibc-old", "LD_LIBRARY_PATH=/opt/glibc-old/lib") ||
        run_variant("new", "/opt/glibc-new", "LD_LIBRARY_PATH=/opt/glibc-new/lib")) {
        puts("VINIX-DOTA2-ENV-PAIR-ABORT");
    } else puts("VINIX-DOTA2-ENV-PAIR-END");
    for (;;) pause();
}
