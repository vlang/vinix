/* Run as PID 1 in an isolated x86_64 guest with a temporary initramfs. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <ucontext.h>
#include <unistd.h>
#define CHECK(x) do { if (!(x)) { printf("EXCEPTION TEST: FAIL line %d: %s errno=%d\n", __LINE__, #x, errno); return 1; } } while (0)
static int gate[2];
static atomic_uint handled;
static atomic_int failed;
static void catch_fault(int signal, siginfo_t *info, void *context) {
    (void)info;
    char byte;
    if (read(gate[0], &byte, 1) != 1) atomic_store(&failed, 1);
    if (signal == SIGILL) ((ucontext_t *)context)->uc_mcontext.gregs[REG_RIP] += 2;
    atomic_fetch_add(&handled, 1);
}
static void *fault_worker(void *arg) {
    (void)arg;
    for (int i = 0; i < 64; i++) {
        __asm__ volatile("int3");
        __asm__ volatile("ud2");
    }
    return NULL;
}
static void *release_handlers(void *arg) {
    (void)arg;
    for (int i = 0; i < 256; i++) {
        usleep(100);
        if (write(gate[1], "x", 1) != 1) atomic_store(&failed, 1);
    }
    return NULL;
}
static int run_test(void) {
    /* A fatal user exception tears down open file, pipe and socket descriptors.
     * A second runnable child must enter on its own stack during that interval. */
    char payload[4096];memset(payload, 0x5a, sizeof(payload));
    for (int round = 0; round < 24; round++) {
        pid_t children[2];int pairs[2][2];
        for (int worker = 0; worker < 2; worker++) {
            CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, pairs[worker]) == 0);
            children[worker] = fork();CHECK(children[worker] >= 0);
            if (children[worker] == 0) {
                close(pairs[worker][0]);
                for(int old=0;old<worker;old++) close(pairs[old][0]);
                int pipefds[2];if(pipe(pipefds)) _exit(99);
                char path[80];snprintf(path, sizeof(path), "/tmp/fault-%d-%d", round, worker);
                int fd = open(path, O_CREAT | O_TRUNC | O_WRONLY, 0600);
                if (fd < 0) _exit(100);
                for (int page = 0; page < 32; page++)
                    if (write(fd, payload, sizeof(payload)) != sizeof(payload)) _exit(101);
                if(write(pairs[worker][1], "z", 1)!=1) _exit(103);
                __asm__ volatile("ud2");
                _exit(102);
            }
            close(pairs[worker][1]);
        }
        for (int worker = 0; worker < 2; worker++) {
            int status;CHECK(waitpid(children[worker], &status, 0) == children[worker]);
            CHECK(WIFSIGNALED(status) && WTERMSIG(status) == SIGILL);
            char byte;CHECK(read(pairs[worker][0], &byte, 1)==1 && byte=='z');
            CHECK(read(pairs[worker][0], &byte, 1)==0);close(pairs[worker][0]);
            char path[80];snprintf(path, sizeof(path), "/tmp/fault-%d-%d", round, worker);
            CHECK(unlink(path) == 0);
        }
    }
    puts("EXCEPTION TEST: file, pipe and socket fatal teardown passed (48 children)");
    CHECK(pipe(gate) == 0);
    struct sigaction action = {.sa_sigaction=catch_fault,.sa_flags=SA_SIGINFO};
    sigemptyset(&action.sa_mask);
    CHECK(sigaction(SIGILL, &action, NULL) == 0);
    CHECK(sigaction(SIGTRAP, &action, NULL) == 0);
    pthread_t threads[3];
    CHECK(pthread_create(&threads[0], NULL, fault_worker, NULL) == 0);
    CHECK(pthread_create(&threads[1], NULL, fault_worker, NULL) == 0);
    CHECK(pthread_create(&threads[2], NULL, release_handlers, NULL) == 0);
    for (int i = 0; i < 3; i++) CHECK(pthread_join(threads[i], NULL) == 0);
    CHECK(atomic_load(&handled) == 256 && !atomic_load(&failed));
    close(gate[0]);close(gate[1]);
    puts("EXCEPTION TEST: returning handlers and blocked peers passed (256 faults)");
    return 0;
}
int main(void) {
    setbuf(stdout, NULL);
    int serial = open("/dev/com1", O_WRONLY);
    if (serial >= 0) {dup2(serial, 1);dup2(serial, 2);close(serial);}
    int result = run_test();
    printf("EXCEPTION TEST: %s\n", result ? "FAIL" : "PASS");
    for (;;) pause();
}
