// SPDX-License-Identifier: GPL-2.0-or-later
// Run against the actual preload library; the guest also checks ELF lookup.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

typedef int (*register_fn)(void (*)(void), void (*)(void), void (*)(void), void *);
static register_fn register_android;
static void (*finalize_android)(void *);
static char trace[512];
static size_t trace_size;
static int race_signal[2];
static int race_acknowledge[2];
static int race_dso;
static _Atomic int race_finalized;

static void record(char value)
{
    if (trace_size + 1 >= sizeof(trace)) {
        _exit(90);
    }
    trace[trace_size++] = value;
    trace[trace_size] = 0;
}

#define CALLBACKS(index, prepare_value, parent_value, child_value) \
    static void prepare_##index(void) { record(prepare_value); } \
    static void parent_##index(void) { record(parent_value); } \
    static void child_##index(void) { record(child_value); }
CALLBACKS(1, '1', 'a', 'A')
CALLBACKS(2, '2', 'b', 'B')
CALLBACKS(3, '3', 'c', 'C')
CALLBACKS(4, '4', 'd', 'D')
static void parent_5(void) { record('e'); }
static void child_5(void) { record('E'); }

static void prepare_race(void)
{
    char byte = 0;
    if (write(race_signal[1], &byte, 1) != 1 || read(race_acknowledge[0], &byte, 1) != 1) {
        _exit(93);
    }
    // The finalizer must wait for this slot's parent/child finish, releasing
    // the registry so fork can reach its first-registered prepare guard.
    usleep(30000);
    if (atomic_load(&race_finalized)) {
        _exit(94);
    }
}

static void *finalize_race(void *unused)
{
    (void)unused;
    char byte = 0;
    if (read(race_signal[0], &byte, 1) != 1 || write(race_acknowledge[1], &byte, 1) != 1) {
        _exit(95);
    }
    finalize_android(&race_dso);
    atomic_store(&race_finalized, 1);
    return NULL;
}

static void require(int condition, const char *reason)
{
    if (!condition) {
        fprintf(stderr, "ANDROID-ATFORK-FAIL %s\n", reason);
        exit(1);
    }
}

static void check_fork(const char *parent_expected, const char *child_expected)
{
    int output[2];
    require(pipe(output) == 0, "pipe");
    trace_size = 0;
    trace[0] = 0;
    pid_t child = fork();
    require(child >= 0, "fork");
    if (child == 0) {
        // A mutex inherited from a vanished registration/finalizer thread
        // would hang these calls. Capacity exhaustion is also a valid result
        // once the parent intentionally fills the bounded registry.
        alarm(5);
        int child_dso;
        int result = register_android(NULL, NULL, NULL, &child_dso);
        if (result != 0 && result != ENOMEM) {
            _exit(92);
        }
        finalize_android(&child_dso);
        close(output[0]);
        ssize_t size = write(output[1], trace, trace_size);
        close(output[1]);
        _exit(size == (ssize_t)trace_size ? 0 : 91);
    }
    close(output[1]);
    char child_trace[512];
    size_t used = 0;
    ssize_t count;
    while ((count = read(output[0], child_trace + used, sizeof(child_trace) - used - 1)) > 0) {
        used += (size_t)count;
    }
    close(output[0]);
    child_trace[used] = 0;
    int status;
    require(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0,
            "child exit");
    require(strcmp(trace, parent_expected) == 0, "parent registration order");
    require(strcmp(child_trace, child_expected) == 0, "child registration order");
}

int main(int argc, char **argv)
{
    alarm(20);
    if (argc == 2) {
        require(dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL) != NULL, "load compatibility library");
    }
    register_android = (register_fn)dlsym(RTLD_DEFAULT, "bionic___register_atfork");
    finalize_android = (void (*)(void *))dlsym(RTLD_DEFAULT, "bionic___cxa_finalize");
    require(register_android != NULL && finalize_android != NULL, "Android ABI exports");
    int dso_a, dso_b;
    require(pthread_atfork(prepare_1, parent_1, child_1) == 0, "first host registration");
    require(register_android(prepare_2, parent_2, child_2, &dso_a) == 0, "first Android registration");
    require(pthread_atfork(prepare_3, parent_3, child_3) == 0, "interleaved host registration");
    require(register_android(prepare_4, parent_4, child_4, &dso_b) == 0, "second Android registration");
    require(register_android(NULL, parent_5, child_5, &dso_a) == 0, "null prepare callback");
    check_fork("4321abcde", "4321ABCDE");
    finalize_android(&dso_a);
    check_fork("431acd", "431ACD");
    // NULL removes every Android handler, including registrations without a
    // DSO. Host handlers remain registered and keep their original ordering.
    finalize_android(NULL);
    check_fork("31ac", "31AC");

    require(pipe(race_signal) == 0 && pipe(race_acknowledge) == 0, "finalizer synchronization pipes");
    require(register_android(prepare_race, NULL, NULL, &race_dso) == 0, "concurrent finalizer registration");
    pthread_t finalizer;
    require(pthread_create(&finalizer, NULL, finalize_race, NULL) == 0, "concurrent finalizer thread");
    check_fork("31ac", "31AC");
    require(pthread_join(finalizer, NULL) == 0 && atomic_load(&race_finalized), "finalizer completes after fork");
    close(race_signal[0]);
    close(race_signal[1]);
    close(race_acknowledge[0]);
    close(race_acknowledge[1]);

    unsigned accepted = 0;
    int result;
    while ((result = register_android(NULL, NULL, NULL, &dso_b)) == 0 && accepted < 1024) {
        ++accepted;
    }
    require(result == ENOMEM && accepted == 124, "bounded registration capacity and error");
    finalize_android(&dso_b);
    // Finalized thunks stay inert, remain safe through repeated forks, and
    // cannot be reused while the host still retains their function pointers.
    check_fork("31ac", "31AC");
    require(register_android(NULL, NULL, NULL, &dso_a) == ENOMEM, "finalized slots cannot be reused");
    puts("ANDROID-ATFORK-PASS host-order=preserved dso-cleanup=verified child-registry=verified concurrent-finalize=verified slots=128");
    return 0;
}
