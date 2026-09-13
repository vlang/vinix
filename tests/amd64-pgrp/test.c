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
static int exec_child(int argc, char **argv) {
    CHECK(argc == 4);
    int ready=atoi(argv[2]), gate=atoi(argv[3]);
    CHECK(write(ready,"x",1)==1);
    char c; CHECK(read(gate,&c,1)==1);
    /* A process may still set its own group after exec. */
    CHECK(setpgid(0,0)==0 && getpgrp()==getpid());
    int sync[2]; CHECK(pipe(sync)==0);
    pid_t child=fork(); CHECK(child>=0);
    if(child==0){ char c; if(read(sync[0],&c,1)!=1)_exit(1);_exit(getpgrp()==getpid()?0:1); }
    /* The child must not inherit our successful-exec marker. */
    CHECK(setpgid(child,child)==0); CHECK(write(sync[1],"x",1)==1);
    CHECK(reap(child)==0); close(sync[0]); close(sync[1]);
    return 0;
}
static int run_test(void) {
    CHECK(getpgrp() > 0); CHECK(getpgrp() == getpgid(0)); CHECK(getpgid(getpid()) == getpgrp());
    errno=0; CHECK(getpgid(INT_MAX)==-1 && errno==ESRCH);
    errno=0; CHECK(getpgid(-1)==-1 && errno==ESRCH);
    errno=0; CHECK(setpgid(-1,0)==-1 && errno==EINVAL);
    errno=0; CHECK(setpgid(0,-1)==-1 && errno==EINVAL);
    errno=0; CHECK(setpgid(0,INT_MAX)==-1 && errno==EPERM);
    errno=0; CHECK(setpgid(getppid(),0)==-1 && errno==ESRCH);
    int ready[2], gate[2]; CHECK(pipe(ready)==0 && pipe(gate)==0);
    pid_t child=fork(); CHECK(child>=0);
    if(child==0){
        char a[24], b[24]; snprintf(a,sizeof(a),"%d",ready[1]);snprintf(b,sizeof(b),"%d",gate[0]);
        char *args[]={"/sbin/init","exec",a,b,NULL};execv(args[0],args);_exit(1);
    }
    char c; CHECK(read(ready[0],&c,1)==1);
    errno=0; CHECK(setpgid(child,child)==-1 && errno==EACCES);
    CHECK(write(gate[1],"x",1)==1); CHECK(reap(child)==0);
    close(ready[0]);close(ready[1]);close(gate[0]);close(gate[1]);
    /* Fork resets the exec marker, so the parent can assign a new group. */
    CHECK(pipe(gate)==0);child=fork();CHECK(child>=0);
    if(child==0){ char c; if(read(gate[0],&c,1)!=1)_exit(1);_exit(getpgrp()==getpid()?0:1); }
    CHECK(setpgid(child,0)==0); CHECK(getpgid(child)==child);
    CHECK(setpgid(0,child)==0); CHECK(getpgrp()==child);
    CHECK(write(gate[1],"x",1)==1); CHECK(reap(child)==0);
    close(gate[0]);close(gate[1]);
    CHECK(setsid()==getpid());
    errno=0;CHECK(setpgid(0,0)==-1 && errno==EPERM);
    puts("TEST pgrp: queries, parent/child groups, sessions and exec checks passed");
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
