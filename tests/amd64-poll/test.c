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
static long elapsed_ms(struct timespec a, struct timespec b) {
    return (b.tv_sec-a.tv_sec)*1000 + (b.tv_nsec-a.tv_nsec)/1000000;
}
static int run_test(void) {
    CHECK(poll(NULL, 0, 0) == 0);
    struct timespec a, b;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &a) == 0);
    CHECK(poll(NULL, 0, 40) == 0);
    CHECK(clock_gettime(CLOCK_MONOTONIC, &b) == 0);
    CHECK(elapsed_ms(a,b) >= 30);
    struct pollfd f = {.fd=-1, .events=POLLIN, .revents=123};
    CHECK(poll(&f, 1, 0) == 0 && f.revents == 0);
    f.fd=INT_MAX;
    CHECK(poll(&f, 1, 0) == 1 && (f.revents & POLLNVAL));
    errno=0;
    CHECK(syscall(SYS_poll, (void *)1, 1, 0) == -1 && errno == EFAULT);
    errno=0;
    CHECK(syscall(SYS_poll, NULL, 4097, 0) == -1 && errno == EINVAL);
    int p[2]; CHECK(pipe(p) == 0);
    struct pollfd pair[2] = {{.fd=p[0], .events=POLLIN}, {.fd=p[0], .events=POLLIN}};
    CHECK(poll(pair, 2, 0) == 0);
    CHECK(poll(pair, 2, 10) == 0); /* duplicate event must not deadlock */
    pid_t child=fork(); CHECK(child>=0);
    if (child==0) { usleep(50000); _exit(write(p[1], "x", 1)==1 ? 0 : 1); }
    CHECK(poll(pair, 2, -1) == 2);
    CHECK((pair[0].revents & POLLIN) && (pair[1].revents & POLLIN));
    CHECK(reap(child) == 0);
    char c; CHECK(read(p[0], &c, 1) == 1 && c == 'x');
    close(p[1]); f.fd=p[0]; f.events=0;
    CHECK(poll(&f, 1, 0) == 1 && (f.revents & POLLHUP));
    close(p[0]);
    int pipes[33][2]; struct pollfd many[33];
    for(int i=0;i<33;i++){ CHECK(pipe(pipes[i])==0); many[i]=(struct pollfd){.fd=pipes[i][0],.events=POLLIN}; }
    CHECK(poll(many,33,0)==0);
    errno=0; CHECK(poll(many,33,1)==-1 && errno==EINVAL);
    for(int i=0;i<33;i++){close(pipes[i][0]);close(pipes[i][1]);}
    puts("TEST poll: timeouts, readiness, duplicate FDs, HUP and invalid inputs passed");
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
