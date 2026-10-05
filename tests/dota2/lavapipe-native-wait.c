/* Test-only native AArch64 PID 1: run the x86 Lavapipe probe for each
 * "driver mode" line of /etc/vinix-lavapipe-plan, one process at a time. */
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

enum { watchdog_seconds = 180 };

static long seconds_now(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now)) return -1;
    return now.tv_sec;
}

static int run_variant(const char *driver, const char *mode)
{
    char icd[128];
    snprintf(icd, sizeof icd, "VK_ICD_FILENAMES=/runtime/icd/%s.json", driver);
    printf("VINIX-DOTA2-LVP-PAIR-BEGIN: driver=%s mode=%s\n", driver, mode);
    pid_t child = fork();
    if (child < 0) {
        puts("VINIX-DOTA2-LVP-PAIR-FAIL: native fork");
        return -1;
    }
    if (!child) {
        char *const arguments[] = {"qemu-x86_64", "-B", "0x100000000", "-L", "/runtime",
            "-E", "LD_LIBRARY_PATH=/runtime/lib", "-E", icd,
            "-E", "MESA_SHADER_CACHE_DISABLE=true",
            "/usr/bin/lavapipe-null-sets", (char *)mode, NULL};
        /* Explicit test-owned environment; no account or host profile data. */
        char *const environment[] = {"PATH=/usr/bin:/bin", "HOME=/root", "USER=root",
            "QEMU_CPU=Haswell", "TZ=UTC", "VINIX_ALLOW_WX=1", NULL};
        execve("/usr/bin/qemu-x86_64", arguments, environment);
        puts("VINIX-DOTA2-LVP-PAIR-FAIL: native exec");
        _exit(127);
    }
    long beginning = seconds_now();
    int status = 0, killed = 0;
    const struct timespec delay = {.tv_nsec = 100000000};
    for (;;) {
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child) break;
        if (result < 0 && errno != EINTR) {
            puts("VINIX-DOTA2-LVP-PAIR-FAIL: native wait");
            return -1;
        }
        long current = seconds_now();
        if (!killed && (beginning < 0 || current < 0 || current - beginning >= watchdog_seconds)) {
            /* Independent native watchdog bounds a stalled translated driver. */
            kill(child, SIGKILL);
            killed = 1;
        }
        nanosleep(&delay, NULL);
    }
    int exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    int signal_number = WIFSIGNALED(status) ? WTERMSIG(status) : 0;
    printf("VINIX-DOTA2-LVP-PAIR-RESULT: driver=%s mode=%s exit=%d signal=%d watchdog=%d\n",
        driver, mode, exit_code, signal_number, killed);
    return 0;
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    puts("VINIX-DOTA2-LVP-PAIR-START");
    FILE *plan = fopen("/etc/vinix-lavapipe-plan", "r");
    char line[128], driver[48], mode[48];
    int failed = !plan;
    while (!failed && fgets(line, sizeof line, plan)) {
        if (sscanf(line, "%47s %47s", driver, mode) != 2) failed = 1;
        else if (run_variant(driver, mode)) failed = 1;
    }
    puts(failed ? "VINIX-DOTA2-LVP-PAIR-ABORT" : "VINIX-DOTA2-LVP-PAIR-END");
    for (;;) pause();
}
