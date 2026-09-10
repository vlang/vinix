/* Guest regression test: static Linux/musl x86_64 executable.
 * Can run as /sbin/init in an isolated Vinix VM or as a normal guest program. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#define CHECK(x) do { if (!(x)) { printf("FAIL line %d: %s errno=%d\n", __LINE__, #x, errno); return 1; } } while (0)
static int reap(pid_t child) {
    int status = -1;
    CHECK(waitpid(child, &status, 0) == child);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    return 0;
}
static int exec_child(int argc, char **argv) { (void)argc; (void)argv; return 1; }
static int run_test(void) {
    int fd = open("/dev/console", O_RDONLY | O_NONBLOCK);
    CHECK(fd >= 0);
    char data[16];
    CHECK(read(fd, data, 0) == 0);
    errno = 0;
    CHECK(read(fd, data, sizeof(data)) == -1 && errno == EAGAIN);
    CHECK(fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK) == 0);
    CHECK(read(fd, data, 0) == 0);
    CHECK(fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0);
    errno = 0;
    CHECK(read(fd, data, 1) == -1 && errno == EAGAIN);
    CHECK(close(fd) == 0);
    puts("TEST console: zero-length and nonblocking reads passed");
    return 0;
}

int main(int argc, char **argv) {
    setbuf(stdout, NULL);
    if (argc > 1) return exec_child(argc, argv);
    if (getpid() != 1) return run_test();
    int serial = open("/dev/com1", O_WRONLY);
    if (serial >= 0) { dup2(serial, 1); dup2(serial, 2); close(serial); }
    puts("TEST START");
    pid_t worker = fork();
    if (worker == 0) _exit(run_test());
    int failed = worker < 0 || reap(worker) != 0;
    printf("TEST RESULT: %s\n", failed ? "FAIL" : "PASS");
    for (;;) sleep(1);
}
