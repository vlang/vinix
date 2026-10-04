#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/auxv.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <unistd.h>

static int failures;
static void check(int valid, const char *name) {
    printf("DUMPABILITY %s: %s\n", valid ? "PASS" : "FAIL", name);
    failures += !valid;
}
static int layout(pid_t pid) {
    char path[80], byte;
    snprintf(path, sizeof(path), "/proc/%d/maps", pid);
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 0;
    int valid = read(fd, &byte, 1) == 1;
    close(fd);
    return valid;
}
int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--exec"))
        return prctl(PR_GET_DUMPABLE) == 1 && getauxval(AT_SECURE) == 0 ? 0 : 1;
    if (argc == 2 && !strcmp(argv[1], "--secure"))
        return prctl(PR_GET_DUMPABLE) == 0 && getauxval(AT_SECURE) == 1 &&
            getauxval(AT_UID) == getuid() && getauxval(AT_EUID) == geteuid() &&
            getauxval(AT_GID) == getgid() && getauxval(AT_EGID) == getegid() ? 0 : 1;
    int console = open("/dev/com1", O_WRONLY);
    if (console >= 0) { dup2(console, 1); dup2(console, 2); close(console); }
    setvbuf(stdout, NULL, _IONBF, 0);
    check(prctl(PR_GET_DUMPABLE) == 1, "initial state");
    check(prctl(PR_SET_DUMPABLE, 0L) == 0 && prctl(PR_GET_DUMPABLE) == 0,
          "state is retained");
    errno = 0;
    check(prctl(PR_SET_DUMPABLE, 2L) == -1 && errno == EINVAL &&
          prctl(PR_GET_DUMPABLE) == 0, "invalid setting rejected");
    pid_t child = fork();
    if (!child) _exit(prctl(PR_GET_DUMPABLE) == 0 ? 0 : 1);
    int status;
    check(child > 0 && waitpid(child, &status, 0) == child && WIFEXITED(status) &&
          !WEXITSTATUS(status), "fork inherits state");
    child = fork();
    if (!child) {
        char *args[] = {argv[0], "--exec", NULL};
        execv(argv[0], args);
        _exit(2);
    }
    check(child > 0 && waitpid(child, &status, 0) == child && WIFEXITED(status) &&
          !WEXITSTATUS(status), "ordinary exec resets state");
    for (int group = 0; group < 2; group++) {
        child = fork();
        if (!child) {
            if (group ? setregid(1000, 0) : setreuid(1000, 0)) _exit(2);
            char *args[] = {argv[0], "--secure", NULL};
            execv(argv[0], args);
            _exit(3);
        }
        check(child > 0 && waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              !WEXITSTATUS(status), group ? "mixed gids select secure loader and dump protection" :
              "mixed uids select secure loader and dump protection");
    }
    prctl(PR_SET_DUMPABLE, 1L);
    check(setgid(1000) == 0 && prctl(PR_GET_DUMPABLE) == 0, "effective gid change protects process");
    prctl(PR_SET_DUMPABLE, 1L);
    check(setuid(1000) == 0 && prctl(PR_GET_DUMPABLE) == 0, "effective uid change protects process");
    check(prctl(PR_SET_DUMPABLE, 1L) == 0, "unprivileged program can enable inspection");
    int to_child[2], from_child[2];
    check(!pipe(to_child) && !pipe(from_child), "control pipes");
    child = fork();
    if (!child) {
        close(to_child[1]); close(from_child[0]);
        char state;
        while (read(to_child[0], &state, 1) == 1) {
            if (prctl(PR_SET_DUMPABLE, (long)(state == '1'))) _exit(3);
            if (write(from_child[1], &state, 1) != 1) _exit(4);
        }
        _exit(0);
    }
    close(to_child[0]); close(from_child[1]);
    char state = '0', response;
    write(to_child[1], &state, 1);
    check(read(from_child[0], &response, 1) == 1 && !layout(child),
          "same uid cannot inspect nondumpable peer");
    check(layout(getpid()), "program can inspect itself");
    state = '1'; write(to_child[1], &state, 1);
    check(read(from_child[0], &response, 1) == 1 && layout(child),
          "same uid can inspect enabled peer");
    close(to_child[1]); close(from_child[0]);
    check(waitpid(child, &status, 0) == child && WIFEXITED(status) && !WEXITSTATUS(status),
          "peer exits normally");
    puts(failures ? "DUMPABILITY GUEST: FAIL" : "DUMPABILITY GUEST: PASS");
    /* This init dropped its reboot capability; runner terminates the VM. */
    for (;;) pause();
}
