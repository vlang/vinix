#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#define PR_VINIX_STACK_POLICY 0x56490001
static int failures;
extern long stack_syscall_on(void *, long);
static void check(int valid, const char *name) {
    printf("STACK POLICY %s: %s (errno=%d)\n", valid ? "PASS" : "FAIL", name, errno);
    failures += !valid;
}
static int policy(long action) { return prctl(PR_VINIX_STACK_POLICY, action, 0L, 0L, 0L); }
static int wait_status(pid_t child) {
    int status; pid_t ret;
    do ret = waitpid(child, &status, 0); while (ret < 0 && errno == EINTR);
    return ret == child ? status : -1;
}
static int exited_ok(pid_t child) {
    int status = wait_status(child);
    return status >= 0 && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}
static int killed(pid_t child) {
    int status = wait_status(child);
    return status >= 0 && WIFSIGNALED(status) && WTERMSIG(status) == SIGSEGV;
}
static void caught(int sig) { (void)sig; _exit(99); }
int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--exec"))
        return policy(0) == 0 && policy(3) == 0 ? 0 : 1;
    int console = open("/dev/com1", O_WRONLY);
    if (console >= 0) { dup2(console, 1); dup2(console, 2); close(console); }
    setvbuf(stdout, NULL, _IONBF, 0);
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char *plain = mmap(NULL, 4 * page, PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
    unsigned char *tagged = mmap(NULL, 4 * page, PROT_NONE, MAP_ANONYMOUS | MAP_PRIVATE | MAP_STACK, -1, 0);
    check(plain != MAP_FAILED && tagged != MAP_FAILED, "allocate ordinary and reserved tagged stacks");
    if (plain == MAP_FAILED || tagged == MAP_FAILED) goto finish;
    check(mprotect(tagged + page, 2 * page, PROT_READ | PROT_WRITE) == 0, "tag survives protection split");
    errno = 0;
    check(mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED | MAP_STACK, -1, 0) == MAP_FAILED && errno == EINVAL,
          "shared stacks rejected");
    int fd = open("/sbin/init", O_RDONLY);
    errno = 0;
    check(fd >= 0 && mmap(NULL, page, PROT_READ, MAP_PRIVATE | MAP_STACK, fd, 0) == MAP_FAILED && errno == EINVAL,
          "file-backed stacks rejected");
    if (fd >= 0) close(fd);
    check(policy(0) == 0 && stack_syscall_on(plain + 3 * page - 16, SYS_getpid) == getpid(), "default Linux mode allows untagged stacks");
    check(policy(1) == 0 && policy(0) == 1, "audit mode retained");
    long before = policy(3);
    check(stack_syscall_on(plain + 3 * page - 16, SYS_getpid) == getpid() && policy(3) == before + 1,
          "audit counts untagged stack without rejecting syscall");
    before = policy(3);
    check(stack_syscall_on(tagged + 3 * page - 16, SYS_getpid) == getpid() && policy(3) == before,
          "tagged writable split passes audit");
    puts("STACK POLICY PASS: tagging and audit");
    pid_t child = fork();
    if (!child) {
        if (policy(0) != 1 || policy(3) != 0 || policy(2) || policy(0) != 2) _exit(2);
        if (stack_syscall_on(tagged + 3 * page - 16, SYS_getpid) != getpid()) _exit(3);
        errno = 0;
        if (policy(1) != -1 || errno != EPERM) _exit(4);
        _exit(0);
    }
    check(child > 0 && exited_ok(child), "fork inherits mode and can strengthen but not weaken it");
    child = fork();
    if (!child) {
        if (policy(2)) _exit(2);
        signal(SIGSEGV, caught);
        stack_syscall_on(plain + 3 * page - 16, SYS_getpid);
        _exit(3);
    }
    check(child > 0 && killed(child), "enforcement terminates invalid stack despite a handler");
    child = fork();
    if (!child) {
        if (policy(2) || mprotect(tagged + page, 2 * page, PROT_READ)) _exit(2);
        stack_syscall_on(tagged + 3 * page - 16, SYS_getpid);
        _exit(3);
    }
    check(child > 0 && killed(child), "tag alone cannot authorize read-only stack");
    child = fork();
    if (!child) {
        if (policy(2)) _exit(2);
        char *args[] = {argv[0], "--exec", NULL};
        execv(argv[0], args); _exit(3);
    }
    check(child > 0 && exited_ok(child), "exec resets image policy");
    unsigned char *moved = mremap(tagged + page, 2 * page, 3 * page, MREMAP_MAYMOVE);
    check(moved != MAP_FAILED, "tagged writable split remaps");
    if (moved != MAP_FAILED) {
        before = policy(3);
        check(stack_syscall_on(moved + 2 * page - 16, SYS_getpid) == getpid() && policy(3) == before,
              "remap preserves tag on writable split");
        munmap(moved, 3 * page);
    }
    munmap(tagged, 4 * page);
    munmap(plain, 4 * page);
    puts("STACK POLICY PASS: enforcement and inheritance");
finish:
    puts(failures ? "STACK POLICY GUEST: FAIL" : "STACK POLICY GUEST: PASS");
    for (;;) pause();
}
