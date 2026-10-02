// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

enum { reader_count = 2, thread_rounds = 128, fork_rounds = 32 };
static int stop_readers, readers_ready, failures;
static pid_t inspected_child, observed_child;
static unsigned long snapshots, process_clocks;
static pid_t owner_pid;

static void fail(const char *message) {
    printf("FAIL: proc thread lock: %s (errno=%d)\n", message, errno);
    __atomic_add_fetch(&failures, 1, __ATOMIC_RELAXED);
}

static int has_failed(void) {
    return __atomic_load_n(&failures, __ATOMIC_RELAXED) != 0;
}

static int read_proc(pid_t pid, const char *suffix, int required) {
    char path[96], text[2048];
    snprintf(path, sizeof(path), "/proc/%d/%s", pid, suffix);
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        if (required) fail("open own process information");
        return 0;
    }
    ssize_t count = read(fd, text, sizeof(text) - 1);
    int read_error = errno;
    close(fd);
    if (count <= 0) {
        if (required) {
            errno = read_error;
            fail("read own process information");
        }
        return 0;
    }
    text[count] = 0;
    if (required && strcmp(suffix, "status") == 0 && !strstr(text, "State:\t"))
        fail("own status keeps its state field during thread creation");
    __atomic_add_fetch(&snapshots, 1, __ATOMIC_RELAXED);
    return 1;
}

static void *reader(void *unused) {
    (void)unused;
    char comm[64];
    snprintf(comm, sizeof(comm), "task/%d/comm", owner_pid);
    clockid_t process_clock;
    if (clock_getcpuclockid(owner_pid, &process_clock)) {
        fail("obtain explicit process CPU clock");
        return NULL;
    }
    __atomic_add_fetch(&readers_ready, 1, __ATOMIC_RELEASE);
    while (!__atomic_load_n(&stop_readers, __ATOMIC_ACQUIRE)) {
        read_proc(owner_pid, "stat", 1);
        read_proc(owner_pid, "status", 1);
        read_proc(owner_pid, comm, 1);
        struct timespec stamp;
        // An explicit pid clock, read by a sibling, takes the process-table
        // and thread-list locks just like /proc inspection does.
        if (clock_gettime(process_clock, &stamp)) fail("read process CPU clock");
        else __atomic_add_fetch(&process_clocks, 1, __ATOMIC_RELAXED);
        pid_t child = __atomic_load_n(&inspected_child, __ATOMIC_ACQUIRE);
        if (child > 0) {
            int got_stat = read_proc(child, "stat", 0);
            int got_status = read_proc(child, "status", 0);
            if (got_stat && got_status)
                __atomic_store_n(&observed_child, child, __ATOMIC_RELEASE);
        }
        // Let the creator run while both inspectors are waiting. On x86 TCG,
        // always-runnable inspectors can starve creation despite yielding.
#if defined(__x86_64__)
        const struct timespec pause = { .tv_nsec = 1000000 };
        nanosleep(&pause, NULL);
#else
        sched_yield();
#endif
    }
    return NULL;
}

static void *short_thread(void *unused) {
    (void)unused;
    return NULL;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--child") == 0) return 0;
    setvbuf(stdout, NULL, _IONBF, 0);
    alarm(120);
    owner_pid = getpid();
    if (prctl(PR_SET_NAME, "proc-lock-test")) fail("name the inspected main thread");
    puts("proc thread lock: starting concurrent inspection and thread churn");
    pthread_t readers[reader_count];
    int started = 0;
    for (; started < reader_count; ++started) {
        int error = pthread_create(&readers[started], NULL, reader, NULL);
        if (error) {
            errno = error;
            fail("start process inspector");
            break;
        }
    }
    while (__atomic_load_n(&readers_ready, __ATOMIC_ACQUIRE) < started && !has_failed())
        sched_yield();
    for (int i = 0; i < thread_rounds && !has_failed(); ++i) {
        pthread_t thread;
        int error = pthread_create(&thread, NULL, short_thread, NULL);
        if (!error) error = pthread_join(thread, NULL);
        if (error) {
            errno = error;
            fail("create and reap a thread during process inspection");
        }
    }
    if (!has_failed()) puts("PASS: process inspection completes during sibling thread churn");
    for (int i = 0; i < fork_rounds && !has_failed(); ++i) {
        int gate[2];
        if (pipe(gate)) {
            fail("create child exec gate");
            break;
        }
        pid_t child = fork();
        if (child == 0) {
            close(gate[1]);
            char command;
            if (read(gate[0], &command, 1) != 1) _exit(126);
            close(gate[0]);
            execl("/sbin/init", "init", "--child", (char *)NULL);
            _exit(127);
        }
        close(gate[0]);
        if (child < 0) {
            close(gate[1]);
            fail("fork child during process inspection");
            break;
        }
        __atomic_store_n(&inspected_child, child, __ATOMIC_RELEASE);
        // Require an inspector to see the child before letting exec replace
        // its main thread. The same readers keep sampling its status during
        // that replacement, targeting the original bind_tid lock inversion.
        while (__atomic_load_n(&observed_child, __ATOMIC_ACQUIRE) != child && !has_failed())
            sched_yield();
        if (!has_failed() && write(gate[1], "X", 1) != 1) fail("release child exec gate");
        close(gate[1]);
        int status;
        if (waitpid(child, &status, 0) != child ||
            !WIFEXITED(status) || WEXITSTATUS(status) != 0)
            fail("fork, exec and reap during child process inspection");
        __atomic_store_n(&inspected_child, 0, __ATOMIC_RELEASE);
    }
    __atomic_store_n(&stop_readers, 1, __ATOMIC_RELEASE);
    for (int i = 0; i < started; ++i)
        if (pthread_join(readers[i], NULL)) fail("join process inspector");
    if (snapshots < 100 || process_clocks < 10) fail("inspectors made concurrent progress");
    printf("proc thread lock: %lu snapshots, %lu process CPU clocks\n", snapshots, process_clocks);
    if (!failures) puts("VINIX PROC THREAD LOCK: PASS");
    if (owner_pid != 1) return failures ? 1 : 0;
    sync();
    reboot(RB_POWER_OFF);
    for (;;) pause();
}
