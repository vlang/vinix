#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/timex.h>
#include <sys/timerfd.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { \
    printf("CLOCK CONTROL FAIL line %d: %s errno=%d\n", __LINE__, #x, errno); \
    return 1; } } while (0)

static int set_level(const char *value)
{
    int fd = open("/proc/sys/kernel/securelevel", O_WRONLY);
    if (fd < 0) return -1;
    ssize_t result = write(fd, value, strlen(value));
    close(fd);
    return result == (ssize_t)strlen(value) ? 0 : -1;
}

static int tests(void)
{
    _Static_assert(sizeof(struct timex) == 208, "Linux timex ABI");
    _Static_assert(offsetof(struct timex, time) == 72, "Linux timeval offset");
    struct timespec mono, after, wall = {1800000000, 123000000};
    CHECK(clock_gettime(CLOCK_MONOTONIC, &mono) == 0);
    CHECK(mono.tv_sec >= 0 && mono.tv_sec < 300);
    CHECK(clock_settime(CLOCK_REALTIME, &wall) == 0);
    CHECK(clock_gettime(CLOCK_REALTIME, &after) == 0);
    CHECK(after.tv_sec == wall.tv_sec);
    CHECK(clock_gettime(CLOCK_MONOTONIC, &after) == 0);
    CHECK(after.tv_sec >= mono.tv_sec && after.tv_sec < mono.tv_sec + 2);
    struct timeval tv = {1800000001, 500000};
    CHECK(settimeofday(&tv, NULL) == 0);
    CHECK(gettimeofday(&tv, NULL) == 0 && tv.tv_sec == 1800000001);
    puts("CLOCK CONTROL PASS: wall steps preserve uptime");

    wall.tv_nsec = 1000000000;
    CHECK(clock_settime(CLOCK_REALTIME, &wall) == -1 && errno == EINVAL);
    CHECK(syscall(SYS_clock_settime, CLOCK_REALTIME, (void *)1) == -1 && errno == EFAULT);
    wall.tv_nsec = 0;
    CHECK(clock_settime(CLOCK_MONOTONIC, &wall) == -1 && errno == EINVAL);
    struct timex tx = {.modes = ADJ_FREQUENCY, .freq = 500 * 65536};
    CHECK(adjtimex(&tx) == TIME_ERROR && tx.freq == 500 * 65536);
    CHECK(tx.status == STA_UNSYNC);
    memset(&tx, 0, sizeof(tx));
    CHECK(clock_adjtime(CLOCK_REALTIME, &tx) == TIME_ERROR && tx.freq == 500 * 65536);
    tx.modes = ADJ_FREQUENCY; tx.freq++;
    CHECK(adjtimex(&tx) == -1 && errno == EINVAL);
    tx.modes = ADJ_OFFSET;
    CHECK(adjtimex(&tx) == -1 && errno == EOPNOTSUPP);
    memset(&tx, 0, sizeof(tx));
    tx.modes = ADJ_OFFSET_SINGLESHOT; tx.offset = 2000000;
    CHECK(adjtimex(&tx) == TIME_ERROR);
    memset(&tx, 0, sizeof(tx)); tx.modes = ADJ_OFFSET_SS_READ;
    CHECK(adjtimex(&tx) == TIME_ERROR && tx.offset > 1000000 && tx.offset <= 2000000);
    memset(&tx, 0, sizeof(tx)); tx.modes = ADJ_OFFSET_SINGLESHOT;
    CHECK(adjtimex(&tx) == TIME_ERROR); // cancel the phase adjustment
    memset(&tx, 0, sizeof(tx)); tx.modes = ADJ_FREQUENCY;
    CHECK(adjtimex(&tx) == TIME_ERROR);
    puts("CLOCK CONTROL PASS: discipline ABI validates modes and bounds");

    pid_t child = fork();
    CHECK(child >= 0);
    if (child == 0) {
        if (setuid(1000) != 0) _exit(2);
        if (clock_settime(CLOCK_REALTIME, &wall) != -1 || errno != EPERM) _exit(3);
        struct timex request = {.modes = ADJ_FREQUENCY};
        if (adjtimex(&request) != -1 || errno != EPERM) _exit(4);
        memset(&request, 0, sizeof(request));
        if (adjtimex(&request) != TIME_ERROR) _exit(5);
        _exit(0);
    }
    int status;
    CHECK(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK(set_level("2\n") == 0);
    wall.tv_sec = 1700000000;
    CHECK(clock_settime(CLOCK_REALTIME, &wall) == -1 && errno == EPERM);
    wall.tv_sec = 1900000000;
    CHECK(clock_settime(CLOCK_REALTIME, &wall) == 0);
    CHECK(set_level("0\n") == 0);
    puts("CLOCK CONTROL PASS: privilege and securelevel guard changes");

    int fd = timerfd_create(CLOCK_REALTIME, TFD_NONBLOCK);
    CHECK(fd >= 0);
    wall.tv_sec = 1800000000;
    CHECK(clock_settime(CLOCK_REALTIME, &wall) == 0);
    struct itimerspec deadline = {.it_value = {1800000100, 0}};
    CHECK(timerfd_settime(fd, TFD_TIMER_ABSTIME, &deadline, NULL) == 0);
    wall.tv_sec = 1800000200;
    CHECK(clock_settime(CLOCK_REALTIME, &wall) == 0);
    struct pollfd pfd = {.fd = fd, .events = POLLIN};
    CHECK(poll(&pfd, 1, 500) == 1);
    unsigned long long count;
    CHECK(read(fd, &count, sizeof(count)) == sizeof(count) && count == 1);
    deadline.it_value.tv_sec = 1800000210;
    CHECK(timerfd_settime(fd, TFD_TIMER_ABSTIME, &deadline, NULL) == 0);
    wall.tv_sec = 1800000100;
    CHECK(clock_settime(CLOCK_REALTIME, &wall) == 0);
    struct itimerspec remaining;
    CHECK(timerfd_gettime(fd, &remaining) == 0 && remaining.it_value.tv_sec >= 109);
    CHECK(timerfd_settime(fd, TFD_TIMER_ABSTIME | TFD_TIMER_CANCEL_ON_SET, &deadline, NULL) == 0);
    wall.tv_sec++;
    CHECK(clock_settime(CLOCK_REALTIME, &wall) == 0);
    CHECK(read(fd, &count, sizeof(count)) == -1 && errno == ECANCELED);
    CHECK(close(fd) == 0);

    timer_t timer;
    struct sigevent ev = {.sigev_notify = SIGEV_NONE};
    CHECK(timer_create(CLOCK_REALTIME, &ev, &timer) == 0);
    CHECK(timer_settime(timer, TIMER_ABSTIME, &deadline, NULL) == 0);
    wall.tv_sec -= 100;
    CHECK(clock_settime(CLOCK_REALTIME, &wall) == 0);
    CHECK(timer_gettime(timer, &remaining) == 0 && remaining.it_value.tv_sec >= 200);
    wall.tv_sec = 1800000300;
    CHECK(clock_settime(CLOCK_REALTIME, &wall) == 0);
    CHECK(timer_gettime(timer, &remaining) == 0 && remaining.it_value.tv_sec == 0);
    CHECK(timer_delete(timer) == 0);

    int ready[2];
    CHECK(pipe(ready) == 0);
    child = fork();
    CHECK(child >= 0);
    if (child == 0) {
        close(ready[0]);
        struct timespec until = {1800003900, 0};
        if (write(ready[1], "x", 1) != 1) _exit(10);
        _exit(clock_nanosleep(CLOCK_REALTIME, TIMER_ABSTIME, &until, NULL) == 0 ? 0 : 11);
    }
    close(ready[1]);
    char byte;
    CHECK(read(ready[0], &byte, 1) == 1);
    close(ready[0]);
    struct timespec settle = {0, 50000000};
    CHECK(nanosleep(&settle, NULL) == 0);
    wall.tv_sec = 1800004000;
    CHECK(clock_settime(CLOCK_REALTIME, &wall) == 0);
    pid_t waited = 0;
    for (int i = 0; i < 100 && waited == 0; i++) {
        waited = waitpid(child, &status, WNOHANG);
        if (waited == 0) nanosleep(&settle, NULL);
    }
    CHECK(waited == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    puts("CLOCK CONTROL PASS: realtime steps adjust sleeps and absolute timers");
    return 0;
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    int result = tests();
    puts(result ? "VINIX CLOCK CONTROL: FAIL" : "VINIX CLOCK CONTROL: PASS");
    for (;;) pause();
}
