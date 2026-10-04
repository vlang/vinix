#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <unistd.h>

static int failures;
static long memory_kib(const char *key) {
    FILE *file = fopen("/proc/meminfo", "r");
    if (!file) return -1;
    char line[256], name[32]; long value = -1, candidate;
    while (fgets(line, sizeof(line), file))
        if (sscanf(line, "%31s %ld kB", name, &candidate) == 2 && !strcmp(name, key)) {
            value = candidate; break;
        }
    fclose(file); return value;
}
static void allocations(int dump) {
    FILE *file = fopen(dump ? "/proc/allocsites" : "/proc/allocstart", "r");
    if (!file) return;
    char line[1024];
    while (fgets(line, sizeof(line), file))
        if (dump) printf("PERF-SITE stack-retirement %s", line);
    fclose(file);
}
static void *worker(void *unused) {
    (void)unused;
    for (;;) {
        int pair[2];
        if (pipe(pair)) _exit(91);
        if (write(pair[1], "x", 1) != 1) _exit(92);
        char byte; if (read(pair[0], &byte, 1) != 1 || byte != 'x') _exit(93);
        close(pair[0]); close(pair[1]);
        usleep(1000);
    }
    return NULL;
}
static int cycle(void) {
    int ready[2]; if (pipe(ready)) return 0;
    pid_t child = fork();
    if (child < 0) { close(ready[0]); close(ready[1]); return 0; }
    if (!child) {
        close(ready[0]); pthread_t threads[8];
        for (int i = 0; i < 8; ++i)
            if (pthread_create(&threads[i], NULL, worker, NULL)) _exit(94);
        if (write(ready[1], "r", 1) != 1) _exit(95);
        close(ready[1]); for (;;) pause();
    }
    close(ready[1]); char byte; int valid = read(ready[0], &byte, 1) == 1;
    close(ready[0]); int status = 0;
    valid &= kill(child, SIGSTOP) == 0;
    valid &= waitpid(child, &status, WUNTRACED) == child && WIFSTOPPED(status);
    valid &= kill(child, SIGCONT) == 0;
    valid &= waitpid(child, &status, WCONTINUED) == child && WIFCONTINUED(status);
    valid &= kill(child, SIGKILL) == 0;
    valid &= waitpid(child, &status, 0) == child && WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL;
    return valid;
}
static void settle(void) {
    // Process retirement is deliberately delayed. Drive another reap after
    // its grace period without introducing a different retained last corpse.
    usleep(3000000); pid_t probe = fork();
    if (!probe) _exit(0);
    if (probe > 0) waitpid(probe, NULL, 0);
    usleep(100000);
}
int main(void) {
#if defined(__x86_64__)
    int serial = open("/dev/com1", O_WRONLY);
    if (serial >= 0) { dup2(serial, STDOUT_FILENO); dup2(serial, STDERR_FILENO); close(serial); }
#endif
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("STACK-GUARD GUEST start\n");
    for (int i = 0; i < 5; ++i) { printf("STACK-GUARD GUEST warmup=%d\n", i); failures += !cycle(); }
    settle(); allocations(0);
    long before = memory_kib("MemFree:"), slab_before = memory_kib("Slab:");
    for (int batch = 0; batch < 2; ++batch) {
        for (int i = 0; i < 5; ++i) { printf("STACK-GUARD GUEST batch=%d cycle=%d\n", batch+1, i); failures += !cycle(); }
        settle(); long after = memory_kib("MemFree:"), slab_after = memory_kib("Slab:");
        printf("STACK-GUARD GUEST pages batch=%d before=%ld after=%ld retained=%ld KiB\n",
               batch + 1, before, after, before - after);
        if (before < 0 || after < 0 || before - after > 2048) failures++;
        printf("STACK-GUARD GUEST slab batch=%d before=%ld after=%ld retained=%ld KiB\n",
               batch + 1, slab_before, slab_after, slab_after - slab_before);
        if (slab_before < 0 || slab_after < 0 || slab_after - slab_before > 128) failures++;
        before = after;
        slab_before = slab_after;
    }
    allocations(1);
    printf("STACK-GUARD GUEST: %s failures=%d\n", failures ? "FAIL" : "PASS", failures);
    sync(); reboot(RB_POWER_OFF); return failures != 0;
}
