#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { \
    printf("POSIX TIMER FAIL line=%d %s errno=%d\n", __LINE__, #x, errno); \
    _exit(1); \
} } while (0)

/* Musl reserves 32 for its SIGEV_THREAD helper, so use the raw syscall ABI
 * when testing that signal directly instead of its public sigset wrappers. */
struct kernel_event { uint64_t value; int signo, notify, tid; };
static const uint64_t timer_mask = UINT64_C(1) << 31;
static int callbacks;

static uint64_t monotonic_ns(void)
{
    struct timespec t;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &t) == 0);
    return (uint64_t)t.tv_sec * 1000000000 + (uint64_t)t.tv_nsec;
}

static void pause_ms(int ms)
{
    struct timespec t = {.tv_sec = ms / 1000, .tv_nsec = (ms % 1000) * 1000000};
    while (nanosleep(&t, &t) < 0) CHECK(errno == EINTR);
}

static void callback(union sigval v)
{
    if (v.sival_int == 0x5649) __atomic_add_fetch(&callbacks, 1, __ATOMIC_RELEASE);
}

static void thread_test(void)
{
    for (int round = 0; round < 20; round++) {
        timer_t timer;
        struct sigevent ev = {
            .sigev_notify = SIGEV_THREAD, .sigev_notify_function = callback,
            .sigev_value.sival_int = 0x5649,
        };
        __atomic_store_n(&callbacks, 0, __ATOMIC_RELEASE);
        CHECK(timer_create(CLOCK_MONOTONIC, &ev, &timer) == 0);
        struct itimerspec set = {.it_value.tv_nsec = 20000000};
        CHECK(timer_settime(timer, 0, &set, NULL) == 0);
        for (int i = 0; i < 100 && __atomic_load_n(&callbacks, __ATOMIC_ACQUIRE) == 0; i++)
            pause_ms(10);
        struct itimerspec now;
        CHECK(timer_gettime(timer, &now) == 0);
        printf("POSIX TIMER THREAD round=%d callbacks=%d remaining=%ld.%09ld\n",
            round, callbacks, now.it_value.tv_sec, now.it_value.tv_nsec);
        CHECK(__atomic_load_n(&callbacks, __ATOMIC_ACQUIRE) == 1);
        CHECK(now.it_value.tv_sec == 0 && now.it_value.tv_nsec == 0);
        CHECK(timer_getoverrun(timer) == 0);
        CHECK(timer_delete(timer) == 0);
        pause_ms(5);
    }
    /* Deleting before expiry wakes musl's helper with an ordinary signal, not
     * a timer notification: it must retire without invoking the callback. */
    timer_t timer;
    struct sigevent ev = {.sigev_notify = SIGEV_THREAD,
        .sigev_notify_function = callback, .sigev_value.sival_int = 0x5649};
    CHECK(timer_create(CLOCK_MONOTONIC, &ev, &timer) == 0);
    struct itimerspec set = {.it_value.tv_nsec = 200000000};
    CHECK(timer_settime(timer, 0, &set, NULL) == 0);
    CHECK(timer_delete(timer) == 0);
    pause_ms(250);
    CHECK(__atomic_load_n(&callbacks, __ATOMIC_ACQUIRE) == 1);
    puts("POSIX TIMER PASS: musl callback");
}

struct thread_state { int tid, result, code, value, timed; uint64_t elapsed; };
static void *receiver(void *p)
{
    struct thread_state *s = p;
    CHECK(syscall(SYS_rt_sigprocmask, SIG_BLOCK, &timer_mask, NULL, 8) == 0);
    __atomic_store_n(&s->tid, (int)syscall(SYS_gettid), __ATOMIC_RELEASE);
    siginfo_t si = {0};
    struct timespec timeout = {.tv_sec = 2};
    uint64_t start = monotonic_ns();
    s->result = (int)syscall(SYS_rt_sigtimedwait, &timer_mask, &si,
        s->timed ? &timeout : NULL, 8);
    s->elapsed = monotonic_ns() - start;
    s->code = si.si_code;
    s->value = si.si_value.sival_int;
    return NULL;
}

static void thread_id_test(void)
{
    for (int timed = 0; timed <= 1; timed++) {
        struct thread_state s = {.timed = timed};
        pthread_t t;
        CHECK(pthread_create(&t, NULL, receiver, &s) == 0);
        while (!__atomic_load_n(&s.tid, __ATOMIC_ACQUIRE)) sched_yield();
        struct kernel_event ev = {.value = 0x12345, .signo = 32,
            .notify = SIGEV_THREAD_ID, .tid = s.tid};
        int id;
        CHECK(syscall(SYS_timer_create, CLOCK_MONOTONIC, &ev, &id) == 0);
        struct itimerspec set = {.it_value.tv_nsec = 20000000};
        CHECK(syscall(SYS_timer_settime, id, 0, &set, NULL) == 0);
        CHECK(pthread_join(t, NULL) == 0);
        printf("POSIX TIMER THREAD-ID timed=%d result=%d code=%d value=%d elapsed_ns=%llu\n",
            timed, s.result, s.code, s.value, (unsigned long long)s.elapsed);
        CHECK(s.result == 32 && s.code == SI_TIMER && s.value == 0x12345);
        CHECK(s.elapsed < 1000000000); /* Must not wait for the two-second timeout. */
        CHECK(syscall(SYS_timer_delete, id) == 0);
    }
    puts("POSIX TIMER PASS: thread-id");
}

static void synchronous_test(void)
{
    int signo = SIGRTMIN;
    sigset_t set;
    sigemptyset(&set); sigaddset(&set, signo);
    CHECK(pthread_sigmask(SIG_BLOCK, &set, NULL) == 0);
    timer_t timer;
    struct sigevent ev = {.sigev_notify = SIGEV_SIGNAL, .sigev_signo = signo,
        .sigev_value.sival_int = 0x7788};
    CHECK(timer_create(CLOCK_MONOTONIC, &ev, &timer) == 0);
    struct itimerspec setting = {.it_value.tv_nsec = 20000000};
    CHECK(timer_settime(timer, 0, &setting, NULL) == 0);
    siginfo_t si;
    uint64_t start = monotonic_ns();
    CHECK(sigtimedwait(&set, &si, &(struct timespec){.tv_sec = 2}) == signo);
    CHECK(monotonic_ns() - start < 1000000000);
    CHECK(si.si_code == SI_TIMER && si.si_value.sival_int == 0x7788);

    /* A bad siginfo destination must preserve the pending timer and metadata. */
    CHECK(timer_settime(timer, 0, &setting, NULL) == 0);
    pause_ms(40);
    uint64_t mask = UINT64_C(1) << (signo - 1);
    struct timespec zero = {0};
    CHECK(syscall(SYS_rt_sigtimedwait, &mask, (void *)1, &zero, 8) == -1 && errno == EFAULT);
    CHECK(syscall(SYS_rt_sigtimedwait, &mask, &si, &zero, 8) == signo);
    CHECK(si.si_code == SI_TIMER && si.si_value.sival_int == 0x7788);
    CHECK(syscall(SYS_rt_sigtimedwait, &mask, &si, &zero, 8) == -1 && errno == EAGAIN);
    CHECK(timer_delete(timer) == 0);

    /* A periodic signal coalesces while blocked and still carries SI_TIMER. */
    CHECK(timer_create(CLOCK_MONOTONIC, &ev, &timer) == 0);
    setting.it_interval.tv_nsec = 10000000;
    setting.it_value.tv_nsec = 10000000;
    CHECK(timer_settime(timer, 0, &setting, NULL) == 0);
    pause_ms(70);
    CHECK(syscall(SYS_rt_sigtimedwait, &mask, &si, &zero, 8) == signo);
    CHECK(si.si_code == SI_TIMER && si.si_value.sival_int == 0x7788 && si.si_overrun >= 1);
    CHECK(timer_delete(timer) == 0);
    puts("POSIX TIMER PASS: synchronous");
}

static void ordinary_and_filtered_signals(void)
{
    uint64_t blocked = timer_mask | (UINT64_C(1) << (SIGUSR1 - 1));
    CHECK(syscall(SYS_rt_sigprocmask, SIG_BLOCK, &blocked, NULL, 8) == 0);
    /* An unrelated blocked signal must neither shorten nor spin a timed wait. */
    CHECK(syscall(SYS_tgkill, getpid(), syscall(SYS_gettid), SIGUSR1) == 0);
    siginfo_t si;
    struct timespec timeout = {.tv_nsec = 40000000};
    uint64_t start = monotonic_ns();
    CHECK(syscall(SYS_rt_sigtimedwait, &timer_mask, &si, &timeout, 8) == -1 && errno == EAGAIN);
    uint64_t elapsed = monotonic_ns() - start;
    CHECK(elapsed >= 30000000 && elapsed < 1000000000);
    uint64_t usr_mask = UINT64_C(1) << (SIGUSR1 - 1);
    struct timespec zero = {0};
    CHECK(syscall(SYS_rt_sigtimedwait, &usr_mask, &si, &zero, 8) == SIGUSR1);
    CHECK(si.si_code == SI_USER);

    struct thread_state s = {0};
    pthread_t t;
    CHECK(pthread_create(&t, NULL, receiver, &s) == 0);
    while (!__atomic_load_n(&s.tid, __ATOMIC_ACQUIRE)) sched_yield();
    pause_ms(20);
    CHECK(syscall(SYS_tgkill, getpid(), s.tid, 32) == 0);
    CHECK(pthread_join(t, NULL) == 0);
    CHECK(s.result == 32 && s.code == SI_USER && s.value == 0 && s.elapsed < 1000000000);
    puts("POSIX TIMER PASS: ordinary signals");
}

static void ownership_test(void)
{
    struct kernel_event ev = {.notify = SIGEV_THREAD_ID, .signo = 32,
        .tid = (int)syscall(SYS_gettid)};
    int id;
    CHECK(syscall(SYS_timer_create, CLOCK_MONOTONIC, &ev, &id) == 0);
    int pipefd[2];
    CHECK(pipe(pipefd) == 0);
    pid_t child = fork();
    CHECK(child >= 0);
    if (child == 0) {
        close(pipefd[1]);
        struct itimerspec now;
        CHECK(syscall(SYS_timer_gettime, id, &now) == -1 && errno == EINVAL);
        CHECK(syscall(SYS_timer_delete, id) == -1 && errno == EINVAL);
        char c; CHECK(read(pipefd[0], &c, 1) == 1); _exit(0);
    }
    close(pipefd[0]);
    ev.tid = child;
    int foreign;
    CHECK(syscall(SYS_timer_create, CLOCK_MONOTONIC, &ev, &foreign) == -1 && errno == EINVAL);
    CHECK(write(pipefd[1], "x", 1) == 1 && close(pipefd[1]) == 0);
    int status; CHECK(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK(syscall(SYS_timer_delete, id) == 0);
    puts("POSIX TIMER PASS: ownership");
}

int main(void)
{
#if defined(__x86_64__)
    int console = open("/dev/com1", O_WRONLY | O_NOCTTY);
    CHECK(console >= 0 && dup2(console, 1) == 1 && dup2(console, 2) == 2 && close(console) == 0);
#endif
    setvbuf(stdout, NULL, _IONBF, 0);
    puts("POSIX TIMER BEGIN");
    thread_test(); thread_id_test(); synchronous_test();
    ordinary_and_filtered_signals(); ownership_test();
    puts("POSIX TIMER GUEST: PASS");
    for (;;) pause();
}
