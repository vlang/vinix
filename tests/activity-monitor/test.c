// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

static int failures;
int activity_metrics_checks(void);
static void check(int ok, const char *name) {
    if (!ok) { printf("ACTIVITY-CHECK FAIL %s errno=%d\n", name, errno); ++failures; }
}

struct shared { atomic_ulong ticks[3]; };
static void *spin(void *counter) {
    atomic_ulong *ticks = counter;
    for (;;) atomic_fetch_add_explicit(ticks, 1, memory_order_relaxed);
    return NULL;
}

static void *blocked(void *fd_pointer) {
    int fd = *(int *)fd_pointer;
    char byte;
    for (;;) (void)read(fd, &byte, 1);
    return NULL;
}

static int wait_change(pid_t child, int *status, int options) {
    for (int i = 0; i < 3000; ++i) {
        int got = waitpid(child, status, options | WNOHANG);
        if (got != 0) return got;
        usleep(1000);
    }
    errno = ETIMEDOUT;
    return -1;
}

static int wait_info(pid_t child, siginfo_t *info, int options) {
    for (int i = 0; i < 3000; ++i) {
        memset(info, 0, sizeof(*info));
        if (waitid(P_PID, (id_t)child, info, options | WNOHANG) != 0) return -1;
        if (info->si_pid == child) return 0;
        usleep(1000);
    }
    errno = ETIMEDOUT;
    return -1;
}

static void job_control(void) {
    struct shared *shared = mmap(NULL, sizeof(*shared), PROT_READ | PROT_WRITE,
                                MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (shared == MAP_FAILED) { check(0, "shared counters"); return; }
    memset(shared, 0, sizeof(*shared));
    int pipefd[2];
    if (pipe(pipefd) != 0) { check(0, "blocked sibling pipe"); return; }
    pid_t child = fork();
    if (child == 0) {
        sigset_t mask;
        sigemptyset(&mask);
        sigaddset(&mask, SIGCONT);
        sigaddset(&mask, SIGSTOP); // cannot actually block SIGSTOP
        if (sigprocmask(SIG_BLOCK, &mask, NULL)) _exit(10);
        pthread_t threads[3];
        if (pthread_create(&threads[0], NULL, spin, &shared->ticks[1]) ||
            pthread_create(&threads[1], NULL, spin, &shared->ticks[2]) ||
            pthread_create(&threads[2], NULL, blocked, &pipefd[0])) _exit(11);
        spin(&shared->ticks[0]);
        _exit(12);
    }
    check(child > 0, "fork threaded target");
    if (child <= 0) return;
    for (int i = 0; i < 3000 && (!atomic_load(&shared->ticks[0]) ||
         !atomic_load(&shared->ticks[1]) || !atomic_load(&shared->ticks[2])); ++i) usleep(1000);
    check(atomic_load(&shared->ticks[0]) && atomic_load(&shared->ticks[1]) &&
          atomic_load(&shared->ticks[2]), "all CPU siblings run before stop");
    check(setpriority(PRIO_PROCESS, (id_t)child, 7) == 0 &&
          getpriority(PRIO_PROCESS, (id_t)child) == 7, "selected process nice is retained");
    for (int iteration = 0; iteration < 3; ++iteration) {
        check(kill(child, SIGSTOP) == 0, "SIGSTOP accepts threaded process");
        siginfo_t info;
        check(wait_info(child, &info, WSTOPPED | WNOWAIT) == 0 &&
              info.si_code == CLD_STOPPED && info.si_status == SIGSTOP,
              "waitid reports STOP without reaping");
        int status = 0;
        check(wait_change(child, &status, WUNTRACED) == child && WIFSTOPPED(status) &&
              WSTOPSIG(status) == SIGSTOP, "wait4 reports STOP once");
        check(waitpid(child, &status, WUNTRACED | WNOHANG) == 0, "STOP consumed once");
        usleep(50000); // every CPU reaches its safe boundary
        unsigned long before[3];
        for (int i = 0; i < 3; ++i) before[i] = atomic_load(&shared->ticks[i]);
        usleep(80000);
        for (int i = 0; i < 3; ++i)
            check(before[i] == atomic_load(&shared->ticks[i]), "STOP pauses every busy sibling");
        check(kill(child, SIGCONT) == 0, "blocked SIGCONT resumes process");
        check(wait_change(child, &status, WCONTINUED) == child && WIFCONTINUED(status),
              "wait4 reports continued without reaping");
        for (int i = 0; i < 3000 && atomic_load(&shared->ticks[0]) == before[0]; ++i) usleep(1000);
        check(atomic_load(&shared->ticks[0]) > before[0], "CONT preserves runnable context");
    }
    check(kill(child, SIGSTOP) == 0, "final STOP");
    int status = 0;
    check(wait_change(child, &status, WUNTRACED) == child, "final STOP observed");
    check(kill(child, SIGKILL) == 0, "KILL reaches stopped process");
    check(wait_change(child, &status, 0) == child && WIFSIGNALED(status) &&
          WTERMSIG(status) == SIGKILL, "KILL tears down stopped and blocked siblings");
    close(pipefd[0]); close(pipefd[1]); munmap(shared, sizeof(*shared));
    puts("ACTIVITY-CHECK PASS process-wide stop/continue, wait4/waitid, nice and stopped kill");
}

static volatile sig_atomic_t terminating;
static void graceful(int signal) { (void)signal; terminating = 1; }
static void graceful_quit(void) {
    int ready[2];
    if (pipe(ready)) { check(0, "graceful ready pipe"); return; }
    pid_t child = fork();
    if (child == 0) {
        struct sigaction action = {.sa_handler = graceful};
        sigemptyset(&action.sa_mask);
        if (sigaction(SIGTERM, &action, NULL)) _exit(1);
        if (write(ready[1], "r", 1) != 1) _exit(2);
        while (!terminating) pause();
        _exit(42);
    }
    check(child > 0, "fork graceful target");
    if (child <= 0) return;
    char byte;
    check(read(ready[0], &byte, 1) == 1, "graceful handler installed");
    check(kill(child, SIGTERM) == 0, "SIGTERM sent");
    int status = 0;
    check(wait_change(child, &status, 0) == child && WIFEXITED(status) &&
          WEXITSTATUS(status) == 42, "SIGTERM allows application cleanup");
    close(ready[0]); close(ready[1]);
    puts("ACTIVITY-CHECK PASS graceful termination handler");
}

static void permissions(void) {
    if (getuid() != 0) {
        puts("ACTIVITY-CHECK SKIP credential-drop permissions require root");
        return;
    }
    pid_t target = fork();
    if (target == 0) { for (;;) pause(); }
    check(target > 0, "fork protected target");
    if (target <= 0) return;
    pid_t caller = fork();
    if (caller == 0) {
        if (setuid(1000)) _exit(1);
        errno = 0;
        if (kill(target, SIGTERM) != -1 || errno != EPERM) _exit(2);
        errno = 0;
        if (kill(target, 0) != -1 || errno != EPERM) _exit(3);
        errno = 0;
        if (setpriority(PRIO_PROCESS, (id_t)target, 10) != -1 || errno != EPERM) _exit(4);
        _exit(0);
    }
    int status = 0;
    check(caller > 0 && wait_change(caller, &status, 0) == caller &&
          WIFEXITED(status) && WEXITSTATUS(status) == 0, "unprivileged controls report EPERM");
    kill(target, SIGKILL); wait_change(target, &status, 0);
    puts("ACTIVITY-CHECK PASS signal and priority permissions");
}

static void *release_child(void *fd_pointer) {
    usleep(50000);
    int fd = *(int *)fd_pointer;
    (void)write(fd, "x", 1);
    return NULL;
}

static void many_children(void) {
    pid_t children[40];
    int release[2];
    if (pipe(release)) { check(0, "many-child release pipe"); return; }
    int count = 0;
    for (; count < 40; ++count) {
        children[count] = fork();
        if (children[count] == 0) {
            if (count == 39) { char byte; (void)read(release[0], &byte, 1); _exit(77); }
            for (;;) pause();
        }
        if (children[count] < 0) break;
    }
    check(count == 40, "fork beyond event-list capacity");
    pthread_t releaser;
    int threaded = count == 40 && pthread_create(&releaser, NULL, release_child, &release[1]) == 0;
    check(threaded, "schedule last child's exit");
    if (threaded) {
        int status = 0;
        check(waitpid(-1, &status, 0) == children[39] && WIFEXITED(status) &&
              WEXITSTATUS(status) == 77, "blocking wait reaches child beyond max_events");
        pthread_join(releaser, NULL);
    }
    for (int i = 0; i < count; ++i) {
        kill(children[i], SIGKILL);
        int status;
        wait_change(children[i], &status, 0);
    }
    close(release[0]); close(release[1]);
    puts("ACTIVITY-CHECK PASS waits reach every child");
}

struct waiter { pid_t target; int got; int error; int status; };
static void *wait_same_child(void *pointer) {
    struct waiter *waiter = pointer;
    waiter->got = waitpid(waiter->target, &waiter->status, 0);
    waiter->error = errno;
    return NULL;
}

static void concurrent_reap(void) {
    int release[2];
    if (pipe(release)) { check(0, "concurrent reap release pipe"); return; }
    pid_t child = fork();
    if (child == 0) { char byte; (void)read(release[0], &byte, 1); _exit(78); }
    check(child > 0, "fork concurrent reap target");
    if (child <= 0) return;
    struct waiter waiters[2] = {{.target = child}, {.target = child}};
    pthread_t threads[2];
    int first = pthread_create(&threads[0], NULL, wait_same_child, &waiters[0]) == 0;
    int second = pthread_create(&threads[1], NULL, wait_same_child, &waiters[1]) == 0;
    check(first && second, "start concurrent waiters");
    usleep(30000);
    (void)write(release[1], "x", 1);
    if (first) pthread_join(threads[0], NULL);
    if (second) pthread_join(threads[1], NULL);
    if (first && second) {
        int reaped = 0, gone = 0;
        for (int i = 0; i < 2; ++i) {
            reaped += waiters[i].got == child && WIFEXITED(waiters[i].status) &&
                      WEXITSTATUS(waiters[i].status) == 78;
            gone += waiters[i].got == -1 && waiters[i].error == ECHILD;
        }
        check(reaped == 1 && gone == 1, "concurrent reap wakes stale waiter with ECHILD");
    }
    close(release[0]); close(release[1]);
    puts("ACTIVITY-CHECK PASS concurrent wait result lifetime");
}

static int run_tests(void) {
    job_control(); graceful_quit(); permissions(); many_children(); concurrent_reap();
    failures += activity_metrics_checks();
    printf("ACTIVITY-CHECK DONE failures=%d\n", failures);
    return failures ? 1 : 0;
}

int main(void) {
    setbuf(stdout, NULL); setbuf(stderr, NULL);
    if (getpid() != 1) return run_tests();
    int console = open("/dev/com1", O_WRONLY);
    if (console < 0) console = open("/dev/console", O_WRONLY);
    if (console >= 0) { dup2(console, 1); dup2(console, 2); close(console); }
    pid_t child = fork();
    if (child == 0) _exit(run_tests());
    int status;
    if (child <= 0 || waitpid(child, &status, 0) != child) puts("ACTIVITY-CHECK FAIL worker");
    for (;;) sleep(1);
}
