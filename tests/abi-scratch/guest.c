#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static int failures;
static volatile sig_atomic_t interrupted;
static void signal_handler(int number) { interrupted = number; }
static void check(int ok, const char *name) {
    printf("ABI SCRATCH %s: %s errno=%d\n", ok ? "OK" : "FAIL", name, errno);
    failures += !ok;
}
static long slab_kb(void) {
    char text[8192]; int fd = open("/proc/meminfo", O_RDONLY);
    if (fd < 0) return -1;
    ssize_t length = read(fd, text, sizeof(text) - 1); close(fd);
    if (length <= 0) return -1;
    text[length] = 0; char *value = strstr(text, "Slab:");
    return value ? strtol(value + 5, NULL, 10) : -1;
}
static void tracking(void) {
    int fd = open("/proc/allocstart", O_RDONLY); char byte;
    if (fd >= 0) { (void)read(fd, &byte, 1); close(fd); }
}
static void sites(void) {
    char text[65536]; int fd = open("/proc/allocsites", O_RDONLY);
    if (fd < 0) return;
    ssize_t length = read(fd, text, sizeof(text) - 1); close(fd);
    if (length > 0) { text[length] = 0; printf("ABI SCRATCH ALLOCATION SITES\n%s\n", text); }
}
static long raw_poll(struct pollfd *fds, unsigned count, const struct timespec *timeout, uint64_t *mask) {
    return syscall(SYS_ppoll, fds, count, timeout, mask, 8);
}
static int legacy_ready(struct pollfd *fds) {
#ifdef SYS_poll
    return syscall(SYS_poll,fds,1,0)==1 && (fds->revents & POLLIN);
#else
    (void)fds;return 1;
#endif
}
static int all_records(int fd) {
    struct stat value; struct statx extended;
    return syscall(SYS_fstat, fd, &value) == 0 && value.st_size == 64
        && fstatat(AT_FDCWD, "/root/scratch-stat", &value, 0) == 0 && value.st_size == 64
        && fstatat(AT_FDCWD, "/root/scratch-link", &value, AT_SYMLINK_NOFOLLOW) == 0 && S_ISLNK(value.st_mode)
        && syscall(SYS_statx, fd, "", AT_EMPTY_PATH, STATX_BASIC_STATS, &extended) == 0
        && extended.stx_size == 64 && (extended.stx_mask & STATX_SIZE) && S_ISREG(extended.stx_mode);
}
int main(void) {
    int console = open("/dev/com1", O_WRONLY);
    if (console >= 0) { dup2(console, 1); dup2(console, 2); close(console); }
    setvbuf(stdout, NULL, _IONBF, 0);
    int fd = open("/root/scratch-stat", O_RDWR | O_CREAT | O_TRUNC, 0640);
    char bytes[64]; memset(bytes, 's', sizeof(bytes));
    check(fd >= 0 && write(fd, bytes, sizeof(bytes)) == sizeof(bytes)
          && symlink("scratch-stat", "/root/scratch-link") == 0, "stat fixture");
    check(all_records(fd), "fstat/fstatat/statx records retain native layouts");
    errno = 0; check(syscall(SYS_fstat, fd, (void *)128) == -1 && errno == EFAULT, "fstat bad output");
    errno = 0; check(syscall(SYS_newfstatat, AT_FDCWD, "/root/scratch-stat", (void *)128, 0) == -1
                      && errno == EFAULT, "fstatat bad output");
    errno = 0; check(syscall(SYS_statx, AT_FDCWD, "/root/scratch-stat", 0, STATX_BASIC_STATS, (void *)128) == -1
                      && errno == EFAULT, "statx bad output");
    struct stat stat_buffer;
    errno = 0; check(fstatat(AT_FDCWD, "/root/does-not-exist", &stat_buffer, 0) == -1 && errno == ENOENT,
                     "stat failure leaves caller frame intact");
    puts("ABI SCRATCH PASS: stat records and errors");

    int pipefd[2]; check(pipe(pipefd) == 0 && write(pipefd[1], "r", 1) == 1, "poll fixture");
    struct pollfd polled = { .fd = pipefd[0], .events = POLLIN };
    struct timespec zero = {0}, invalid = { .tv_nsec = 1000000000 };
    uint64_t mask = UINT64_C(1) << (SIGUSR1 - 1);
    check(raw_poll(&polled, 1, &zero, &mask) == 1 && (polled.revents & POLLIN), "ppoll readiness with temporary mask");
    sigset_t observed; sigprocmask(SIG_SETMASK, NULL, &observed);
    check(!sigismember(&observed, SIGUSR1), "ppoll restores mask after immediate readiness");
    check(raw_poll(NULL, 0, &zero, NULL) == 0, "ppoll zero-duration empty wait");
#ifdef SYS_poll
    check(legacy_ready(&polled), "SYS_poll zero-timeout readiness");
    check(syscall(SYS_poll,&polled,1,UINT64_C(0xdeadbeefffffffff))==1 && (polled.revents & POLLIN),
          "SYS_poll signed low-int infinite readiness");
    check(syscall(SYS_poll,NULL,0,0)==0 && syscall(SYS_poll,NULL,0,2)==0,
          "SYS_poll zero and finite empty waits");
    errno=0;check(syscall(SYS_poll,(void *)128,1,0)==-1 && errno==EFAULT,"SYS_poll bad array rejected");
    errno=0;check(syscall(SYS_poll,NULL,4097,0)==-1 && errno==EINVAL,"SYS_poll excessive count rejected");
#endif
    errno = 0; check(raw_poll(&polled, 1, &invalid, NULL) == -1 && errno == EINVAL, "invalid timeout rejected");
    errno = 0; check(raw_poll(&polled, 1, (void *)128, NULL) == -1 && errno == EFAULT, "bad timeout pointer rejected");
    errno = 0; check(raw_poll(&polled, 1, &zero, (void *)128) == -1 && errno == EFAULT, "bad mask pointer rejected");
    char byte; (void)read(pipefd[0], &byte, 1);
    struct sigaction action; memset(&action, 0, sizeof(action));
    action.sa_handler = signal_handler; sigemptyset(&action.sa_mask); sigaction(SIGUSR2, &action, NULL);
    pid_t child = fork();
    if (!child) { usleep(50000); kill(getppid(), SIGUSR2); _exit(0); }
    struct timespec second = { .tv_sec = 1 };
    errno = 0; check(child > 0 && raw_poll(&polled, 1, &second, &mask) == -1 && errno == EINTR
                    && interrupted == SIGUSR2, "ppoll stack inputs survive interrupted blocking wait");
    int status; check(waitpid(child, &status, 0) == child && WIFEXITED(status) && !WEXITSTATUS(status), "signal sender exits");
    sigprocmask(SIG_SETMASK, NULL, &observed);
    check(!sigismember(&observed, SIGUSR1), "ppoll restores mask after caught signal");
#ifdef SYS_poll
    interrupted=0;child=fork();
    if(!child) { usleep(50000);kill(getppid(),SIGUSR2);_exit(0); }
    errno=0;check(child>0 && syscall(SYS_poll,&polled,1,-1)==-1 && errno==EINTR && interrupted==SIGUSR2,
                  "SYS_poll infinite wait interrupted by caught signal");
    check(waitpid(child,&status,0)==child && WIFEXITED(status) && !WEXITSTATUS(status),"poll signal sender exits");
#endif
    puts("ABI SCRATCH PASS: poll readiness and signals");
    (void)write(pipefd[1], "r", 1);
    for (int i = 0; i < 50; ++i) { (void)all_records(fd); (void)raw_poll(&polled, 1, &zero, &mask); (void)legacy_ready(&polled); }
    tracking(); long before = slab_kb(); int loops = 1;
    for (int i = 0; i < 1000; ++i) {
        if (!all_records(fd) || raw_poll(&polled, 1, &zero, &mask) != 1 || !legacy_ready(&polled)) { loops = 0; break; }
    }
    long after = slab_kb(); printf("ABI SCRATCH SLAB before=%ld after=%ld KiB loops=1000\n", before, after);
    if (after > before + 8) sites();
    check(loops && before >= 0 && after >= 0 && after <= before + 8, "1000 stat/poll operations retain bounded allocations");
    puts("ABI SCRATCH PASS: allocation loops");
    close(fd); close(pipefd[0]); close(pipefd[1]); unlink("/root/scratch-link"); unlink("/root/scratch-stat");
    puts(failures ? "ABI SCRATCH GUEST: FAIL" : "ABI SCRATCH GUEST: PASS");
    for (;;) pause();
}
