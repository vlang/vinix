#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    printf("SIGNAL-RETURN-INIT pid=%ld\n", (long)getpid());
    pid_t child = fork();
    if (child == 0) {
        execl("/lib/ld-musl-aarch64.so.1", "ld-musl-aarch64.so.1",
              "--library-path", "/lib", "/bin/signal-return-probe", (char *)NULL);
        perror("FAIL: SIGNAL-RETURN exec");
        _exit(127);
    }
    if (child < 0) perror("FAIL: SIGNAL-RETURN fork");
    else {
        int status = 0;
        pid_t reaped;
        do { reaped = waitpid(child, &status, 0); } while (reaped < 0 && errno == EINTR);
        if (reaped != child) perror("FAIL: SIGNAL-RETURN waitpid");
        else if (WIFEXITED(status) && WEXITSTATUS(status) == 0)
            printf("SIGNAL-RETURN-CHILD-EXIT status=0\n");
        else if (WIFSIGNALED(status))
            printf("FAIL: SIGNAL-RETURN-CHILD signal=%d raw-status=%d\n", WTERMSIG(status), status);
        else
            printf("FAIL: SIGNAL-RETURN-CHILD exit=%d raw-status=%d\n", WEXITSTATUS(status), status);
    }
    /* Keep PID 1 alive so the controller observes the real child status rather
     * than a panic caused by the test init exiting. */
    for (;;) pause();
}
