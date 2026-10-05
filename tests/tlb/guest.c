#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <setjmp.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/wait.h>
#include <unistd.h>

static size_t page;
static volatile uint64_t *shared;
static atomic_int phase, outcome, failed;
static sigjmp_buf fault;
static volatile sig_atomic_t expected_fault;

static void fail(const char *what) {
    printf("FAIL: TLB %s errno=%d\n", what, errno);
    fflush(stdout);
    _exit(1);
}
static void pin(int cpu) {
    cpu_set_t mask;
    CPU_ZERO(&mask);
    CPU_SET(cpu, &mask);
    if (sched_setaffinity(0, sizeof mask, &mask)) fail("affinity");
}
static void wait_phase(int wanted) {
    for (unsigned n = 0; atomic_load_explicit(&phase, memory_order_acquire) != wanted; n++) {
        if (n == 2000000) fail("worker coordination timeout");
        sched_yield();
    }
}
static void on_fault(int sig) {
    if (sig == SIGSEGV && expected_fault) {
        expected_fault = 0;
        siglongjmp(fault, 1);
    }
    fail("unexpected segmentation fault");
}
static void *worker(void *unused) {
    (void)unused;
    pin(1);
    for (unsigned round = 0; round < 100; round++) {
        wait_phase(1);
        if (*shared != round + 1) atomic_store(&failed, 1);
        *shared = round + 1000;
        atomic_store_explicit(&phase, 2, memory_order_release);
        wait_phase(3);
        atomic_store(&outcome, 0);
        if (sigsetjmp(fault, 1) == 0) {
            expected_fault = 1;
            *shared = 999999;
            expected_fault = 0;
        } else {
            atomic_store(&outcome, 1);
        }
        atomic_store_explicit(&phase, 4, memory_order_release);
        wait_phase(5);
        if (*shared != round + 2000) atomic_store(&failed, 1);
        atomic_store_explicit(&phase, 6, memory_order_release);
    }
    return NULL;
}
static void shared_protection(void) {
    shared = mmap(NULL, page, PROT_READ | PROT_WRITE,
                  MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (shared == MAP_FAILED) fail("shared mmap");
    pthread_t thread;
    if (pthread_create(&thread, NULL, worker, NULL)) fail("pthread_create");
    pin(0);
    for (unsigned round = 0; round < 100; round++) {
        *shared = round + 1;
        atomic_store_explicit(&phase, 1, memory_order_release);
        wait_phase(2);
        int protection = round % 2 ? PROT_NONE : PROT_READ;
        if (mprotect((void *)shared, page, protection)) fail("mprotect read/none");
        atomic_store_explicit(&phase, 3, memory_order_release);
        wait_phase(4);
        if (!atomic_load(&outcome)) fail("remote writable translation survived");
        if (protection == PROT_READ && *shared != round + 1000) fail("read-only page changed");
        if (munmap((void *)shared, page)) fail("munmap remote");
        /* Consume the just-freed frame before reusing the original address. */
        volatile uint64_t *filler = mmap(NULL, page, PROT_READ | PROT_WRITE,
                                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (filler == MAP_FAILED) fail("filler mmap");
        *filler = 0xdeadbeef;
        if (mmap((void *)shared, page, PROT_READ | PROT_WRITE,
                 MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0) != (void *)shared) fail("address reuse");
        *shared = round + 2000;
        atomic_store_explicit(&phase, 5, memory_order_release);
        wait_phase(6);
        if (munmap((void *)filler, page)) fail("filler munmap");
    }
    if (pthread_join(thread, NULL) || atomic_load(&failed)) fail("remote address reuse retained stale page");
    if (munmap((void *)shared, page)) fail("final shared munmap");
    puts("TLB: SMP protection and address reuse PASS");
}
static void check_child(pid_t child) {
    int status;
    if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status)) fail("child exit");
}
static void process_isolation(void) {
    volatile uint64_t *value = mmap(NULL, page, PROT_READ | PROT_WRITE,
                                    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (value == MAP_FAILED) fail("fork mmap");
    for (unsigned round = 0; round < 300; round++) {
        *value = round + 10;
        pid_t child = fork();
        if (child < 0) fail("fork");
        if (child == 0) {
            pin(1);
            if (*value != round + 10) fail("COW snapshot");
            *value = round + 900000;
            for (unsigned n = 0; n < 20; n++) {
                sched_yield();
                if (*value != round + 900000) fail("child ASID isolation");
            }
            _exit(0);
        }
        *value = round + 800000;
        for (unsigned n = 0; n < 20; n++) {
            sched_yield();
            if (*value != round + 800000) fail("parent ASID isolation");
        }
        check_child(child);
    }
    if (munmap((void *)value, page)) fail("fork cleanup");
    puts("TLB: fork COW and 300 map recycling cycles PASS");
}
static void exec_recycling(void) {
    for (unsigned round = 0; round < 32; round++) {
        pid_t child = fork();
        if (child < 0) fail("exec fork");
        if (child == 0) {
            char *argv[] = { "/sbin/init", "--exec-check", NULL };
            char *env[] = { NULL };
            execve(argv[0], argv, env);
            fail("execve");
        }
        check_child(child);
    }
    puts("TLB: exec replacement and tag reuse PASS");
}

struct switch_state { atomic_int turn, stop; };
static unsigned long slab_live(int fd, unsigned long live[2049]) {
    static char text[8192];
    memset(live, 0, 2049 * sizeof *live);
    if (lseek(fd, 0, SEEK_SET) < 0) fail("slab seek");
    ssize_t bytes = read(fd, text, sizeof text - 1);
    if (bytes <= 0) fail("slab read");
    text[bytes] = 0;
    unsigned long large = 0;
    unsigned classes = 0, saw_large = 0;
    for (char *line = text; line && *line;) {
        unsigned long size, objects, pages;
        if (sscanf(line, "size-%lu %*u %lu %lu", &size, &objects, &pages) == 3 && size <= 2048) {
            live[size] = objects;
            classes++;
        } else if (sscanf(line, "large - - %lu", &pages) == 1) {
            large = pages;
            saw_large = 1;
        }
        line = strchr(line, '\n');
        if (line) line++;
    }
    if (classes != 14 || !saw_large) fail("malformed slabinfo measurement");
    return large;
}
static void switch_pong(struct switch_state *state, unsigned rounds) {
    for (unsigned i = 0; i < rounds; i++) {
        atomic_store_explicit(&state->turn, 1, memory_order_release);
        while (atomic_load_explicit(&state->turn, memory_order_acquire)) sched_yield();
    }
}
static void switch_retention(void) {
    static unsigned long before[2049], after[2049];
    int fd = open("/proc/slabinfo", O_RDONLY);
    if (fd < 0 && mount("proc", "/proc", "proc", 0, NULL) == 0)
        fd = open("/proc/slabinfo", O_RDONLY);
    if (fd < 0) fail("slabinfo open");
    struct switch_state *state = mmap(NULL, page, PROT_READ | PROT_WRITE,
                                     MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (state == MAP_FAILED) fail("switch state");
    pid_t child = fork();
    if (child < 0) fail("switch fork");
    if (child == 0) {
        pin(0);
        while (!atomic_load_explicit(&state->stop, memory_order_acquire)) {
            if (atomic_load_explicit(&state->turn, memory_order_acquire))
                atomic_store_explicit(&state->turn, 0, memory_order_release);
            sched_yield();
        }
        _exit(0);
    }
    pin(0);
    switch_pong(state, 1000);
    slab_live(fd, before); /* Warm both the reader and the parsing path. */
    unsigned long before_large = slab_live(fd, before);
    switch_pong(state, 20000);
    unsigned long after_large = slab_live(fd, after);
    for (unsigned size = 1; size <= 2048; size++) {
        if (after[size] != before[size])
            printf("TLB-RETENTION: size=%u delta=%ld objects\n", size,
                   (long)after[size] - (long)before[size]);
    }
    printf("TLB-RETENTION: large_delta=%ld pages after 20000 context-switch rounds\n",
           (long)after_large - (long)before_large);
    /* Baseline slabinfo has a measured 48-byte Text wrapper observer leak.
     * Report it explicitly; no other class may grow on the switching path. */
    for (unsigned size = 1; size <= 2048; size++) {
        unsigned long observer = size == 48 ? 1 : 0;
        if (after[size] > before[size] + observer) fail("switching retained heap allocations");
    }
    if (after_large > before_large) fail("switching retained large allocations");
    atomic_store_explicit(&state->stop, 1, memory_order_release);
    check_child(child);
    close(fd);
    if (munmap(state, page)) fail("switch state cleanup");
    puts("TLB: repeated context switches retention PASS");
}
int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    page = (size_t)sysconf(_SC_PAGESIZE);
    if (argc > 1 && !strcmp(argv[1], "--exec-check")) {
        volatile uint64_t *p = mmap(NULL, page, PROT_READ | PROT_WRITE,
                                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED || *p != 0) fail("exec fresh address space");
        *p = 424242;
        for (unsigned i = 0; i < 50; i++) {
            sched_yield();
            if (*p != 424242) fail("exec translation");
        }
        _exit(0);
    }
    struct sigaction action = { .sa_handler = on_fault };
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGSEGV, &action, NULL)) fail("sigaction");
    shared_protection();
    process_isolation();
    exec_recycling();
    switch_retention();
    puts("TLB: ALL PASS");
    for (;;) pause();
}
