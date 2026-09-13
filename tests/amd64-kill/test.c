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
    CHECK(setsid()==getpid()); /* isolate actual group signals from init */
    CHECK(kill(getpid(),0)==0);CHECK(kill(0,0)==0);CHECK(kill(-getpid(),0)==0);
    errno=0;CHECK(kill(INT_MAX,0)==-1 && errno==ESRCH);
    errno=0;CHECK(kill(INT_MIN,0)==-1 && errno==ESRCH);
    errno=0;CHECK(kill(getpid(),-1)==-1 && errno==EINVAL);
    errno=0;CHECK(kill(getpid(),64)==-1 && errno==EINVAL);
    /* Linux callback dispatch is not wired to amd64 sigentry yet. Check
     * that the selected thread is queued and its wait is interrupted. */
    pid_t selectors[]={getpid(),0,-getpid()};
    for (unsigned i=0;i<sizeof(selectors)/sizeof(selectors[0]);i++) {
        CHECK(kill(selectors[i],SIGUSR1)==0);
        struct timespec delay={0,10000000};errno=0;
        CHECK(nanosleep(&delay,NULL)==-1 && errno==EINTR);
    }
    int gate[2];CHECK(pipe(gate)==0);pid_t child=fork();CHECK(child>=0);
    if(child==0){char c; if(read(gate[0],&c,1)!=1)_exit(1);_exit(0);}
    CHECK(kill(child,0)==0);CHECK(kill(-1,0)==0);
    CHECK(write(gate[1],"x",1)==1);
    usleep(50000); /* leave a zombie before waitpid */
    CHECK(kill(child,0)==0);CHECK(kill(child,SIGUSR1)==0);
    CHECK(reap(child)==0);errno=0;CHECK(kill(child,0)==-1 && errno==ESRCH);
    close(gate[0]);close(gate[1]);
    puts("TEST kill: signal-zero, PID/group wakeups, invalid selectors and zombies passed");
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
