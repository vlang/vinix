#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <unistd.h>

static int failures;
static void check(int valid, const char *name) {
    printf("SECURELEVEL %s: %s (errno=%d)\n", valid ? "PASS" : "FAIL", name, errno);
    failures += !valid;
}
static int level(int value) {
    char text[8];
    int length = snprintf(text, sizeof text, "%d\n", value);
    int fd = open("/proc/sys/kernel/securelevel", O_WRONLY);
    if (fd < 0) return -1;
    int error = write(fd, text, length) == length ? 0 : -1;
    int saved = errno;
    close(fd); errno = saved;
    return error;
}
static int read_level(void) {
    char text[16] = {0};
    int fd = open("/proc/sys/kernel/securelevel", O_RDONLY);
    if (fd < 0 || read(fd, text, sizeof text - 1) < 1) return -99;
    close(fd);
    return text[0] - '0';
}
static int wait_ok(pid_t child) {
    int status; pid_t ret;
    do ret = waitpid(child, &status, 0); while (ret < 0 && errno == EINTR);
    return ret == child && WIFEXITED(status) && !WEXITSTATUS(status);
}
static void *raise_level(void *value) {
    level((int)(long)value);
    return NULL;
}
int main(void) {
    int console = open("/dev/com1", O_WRONLY);
    if (console >= 0) { dup2(console, 1); dup2(console, 2); close(console); }
    setvbuf(stdout, NULL, _IONBF, 0);
    check(level(0) == 0, "init controls level");
    check(setdomainname("sealed.test", 11) == 0, "configure domain");
    check(mknod("/policy-disk", S_IFBLK | 0600, 0) == 0, "create disk policy fixture");
    int disk = open("/policy-disk", O_RDWR);
    check(disk >= 0, "insecure disk description opens");
    check(level(1) == 0, "raise to secure");
    errno = 0;
    check(setdomainname("changed.test", 12) == -1 && errno == EPERM, "established domain is sealed");
    errno = 0;
    check(setdomainname("", 0) == -1 && errno == EPERM, "sealed domain cannot be cleared");
    pid_t child = fork();
    if (!child) {
        if (level(0) != -1 || errno != EPERM) _exit(1);
        if (unshare(CLONE_NEWUTS) || setdomainname("private.test", 12)) _exit(2);
        _exit(0);
    }
    check(child > 0 && wait_ok(child), "non-init cannot lower level; private UTS can set its domain");
    puts("SECURELEVEL PASS: sealed domain and level transitions");
    check(level(2) == 0, "raise to highly secure");
    errno = 0;
    check(open("/policy-disk", O_WRONLY) == -1 && errno == EPERM, "new disk write opens are denied");
    int readable = open("/policy-disk", O_RDONLY);
    check(readable >= 0, "disk read open remains available");
    if (readable >= 0) close(readable);
    int path = open("/policy-disk", O_PATH);
    check(path >= 0, "O_PATH remains available");
    if (path >= 0) close(path);
    char byte = 'x';
    errno = 0;
    check(write(disk, &byte, 1) == -1 && errno == EPERM, "retained description cannot write");
    errno = 0;
    check(pwrite(disk, &byte, 1, 0) == -1 && errno == EPERM, "retained description cannot pwrite");
    struct iovec vector = {&byte, 1};
    errno = 0;
    check(writev(disk, &vector, 1) == -1 && errno == EPERM, "retained description cannot writev");
    close(disk);
    puts("SECURELEVEL PASS: existing disk descriptions are protected");
    int file = open("/root/securelevel-file", O_CREAT | O_WRONLY, 0600);
    check(file >= 0 && write(file, &byte, 1) == 1 && fsync(file) == 0, "filesystem writes and sync remain available");
    if (file >= 0) close(file);
    puts("SECURELEVEL PASS: ordinary filesystem writes remain available");
    check(level(0) == 0 && setdomainname("changed.test", 12) == 0, "init can restore single-user state");
    for (int i = 0; i < 50; i++) {
        if (level(0)) { check(0, "reset concurrent raise"); break; }
        child = fork();
        if (!child) {
            pthread_t a, b;
            if (pthread_create(&a, NULL, raise_level, (void *)1L) ||
                pthread_create(&b, NULL, raise_level, (void *)2L)) _exit(3);
            pthread_join(a, NULL); pthread_join(b, NULL);
            _exit(read_level() == 2 ? 0 : 4);
        }
        if (child < 0 || !wait_ok(child)) { check(0, "concurrent raises never lower policy"); break; }
    }
    puts(failures ? "SECURELEVEL GUEST: FAIL" : "SECURELEVEL GUEST: PASS");
    for (;;) pause();
}
