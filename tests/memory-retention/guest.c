#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("RETENTION FAIL line=%d errno=%d: %s\n", __LINE__, errno, #x); _exit(1); } } while (0)
struct slab { unsigned long size, objects; };
static int slabs(struct slab *out) {
    FILE *file = fopen("/proc/slabinfo", "r"); CHECK(file != NULL);
    char line[256]; int count = 0;
    while (fgets(line, sizeof line, file)) {
        unsigned long size, objects, pages;
        if (sscanf(line, "size-%*u %lu %lu %lu", &size, &objects, &pages) == 3) {
            CHECK(count < 32); out[count++] = (struct slab){size, objects};
        }
    }
    CHECK(fclose(file) == 0); return count;
}
static void track(int report) {
    FILE *file = fopen(report ? "/proc/allocsites" : "/proc/allocstart", "r");
    if (!file) return;
    char line[512];
    while (fgets(line, sizeof line, file)) if (report) printf("PERF-SITE retention %s", line);
    fclose(file);
}
static void wait_ok(pid_t pid) {
    int status; CHECK(waitpid(pid, &status, 0) == pid);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
}
static void dot(int fd) {
    struct stat st; CHECK(fstatat(fd, ".", &st, 0) == 0 && S_ISDIR(st.st_mode));
    int parent = openat(fd, "..", O_RDONLY | O_DIRECTORY); CHECK(parent >= 0); close(parent);
    errno = 0; CHECK(openat(fd, "new", O_CREAT | O_RDWR, 0600) == -1 && errno == ENOENT);
    errno = 0; CHECK(linkat(AT_FDCWD, "/sbin/init", fd, "link", 0) == -1 && errno == ENOENT);
    errno = 0; CHECK(symlinkat("/tmp", fd, "symlink") == -1 && errno == ENOENT);
    errno = 0; CHECK(mkdirat(fd, "directory", 0700) == -1 && errno == ENOENT);
    errno = 0; CHECK(mknodat(fd, "fifo", S_IFIFO | 0600, 0) == -1 && errno == ENOENT);
}
static void lifetimes(void) {
	/* A final direct device reference can itself remove another pathname.
	 * Run both unlink and rename-overwrite with the master already closed. */
	for (int replace = 0; replace < 2; ++replace) {
		int master = posix_openpt(O_RDWR | O_NOCTTY); CHECK(master >= 0);
		CHECK(grantpt(master) == 0 && unlockpt(master) == 0);
		char slave[128]; CHECK(ptsname_r(master, slave, sizeof slave) == 0);
		CHECK(link(slave, "/dev/pts/retention-alias") == 0); close(master);
		if (replace) {
			CHECK(symlink("/tmp", "/dev/pts/retention-source") == 0);
			CHECK(rename("/dev/pts/retention-source", "/dev/pts/retention-alias") == 0);
		}
		CHECK(unlink("/dev/pts/retention-alias") == 0); sleep(7);
		struct stat st; CHECK(lstat(slave, &st) == -1 && errno == ENOENT);
	}
    puts("RETENTION pty-hardlink-unlink-rename-callback PASS");
    CHECK(mkdir("/tmp/held", 0700) == 0);
    int dir = open("/tmp/held", O_RDONLY | O_DIRECTORY); CHECK(dir >= 0);
    CHECK(rmdir("/tmp/held") == 0); sleep(7); dot(dir);
    CHECK(fchdir(dir) == 0); close(dir); sleep(7);
    int cwd = open(".", O_RDONLY | O_DIRECTORY); CHECK(cwd >= 0); dot(cwd); close(cwd);
    CHECK(chdir("/tmp") == 0);

    CHECK(mkdir("/tmp/parent", 0700) == 0);
    int file = open("/tmp/parent/file", O_CREAT | O_RDWR, 0600); CHECK(file >= 0);
    CHECK(unlink("/tmp/parent/file") == 0 && rmdir("/tmp/parent") == 0);
    sleep(7);
    char path[64], target[128]; snprintf(path, sizeof path, "/proc/self/fd/%d", file);
    ssize_t length = readlink(path, target, sizeof target - 1); CHECK(length > 0);
    target[length] = 0; CHECK(strstr(target, "/tmp/parent/file") != NULL);
    CHECK(write(file, "kept", 4) == 4); close(file);

    CHECK(mkdir("/tmp/source", 0700) == 0 && mkdir("/tmp/destination", 0700) == 0);
    dir = open("/tmp/destination", O_RDONLY | O_DIRECTORY); CHECK(dir >= 0);
    CHECK(rename("/tmp/source", "/tmp/destination") == 0);
    sleep(7); dot(dir); close(dir); CHECK(rmdir("/tmp/destination") == 0);

    CHECK(mkdir("/tmp/tree", 0700) == 0 && mkdir("/tmp/tree/leaf", 0700) == 0);
    int ready[2], release[2]; CHECK(pipe(ready) == 0 && pipe(release) == 0);
    pid_t child = fork(); CHECK(child >= 0);
    if (!child) {
        close(ready[0]); close(release[1]); CHECK(chdir("/tmp/tree/leaf") == 0);
        CHECK(write(ready[1], "x", 1) == 1); char byte; CHECK(read(release[0], &byte, 1) == 1);
        CHECK(chdir("..") == 0); int fd = open(".", O_RDONLY | O_DIRECTORY); CHECK(fd >= 0);
        dot(fd); close(fd); CHECK(chdir("..") == 0); _exit(0);
    }
    close(ready[1]); close(release[0]); char byte; CHECK(read(ready[0], &byte, 1) == 1);
    CHECK(rmdir("/tmp/tree/leaf") == 0 && rmdir("/tmp/tree") == 0);
    sleep(7); CHECK(write(release[1], "x", 1) == 1); wait_ok(child);
    close(ready[0]); close(release[1]); sleep(18);
    puts("RETENTION directory-fd-cwd-child-parent-rename PASS");
}
static void operations(const char *base, int count) {
    char a[128], b[128], file[160];
    snprintf(a, sizeof a, "%s/a", base); snprintf(b, sizeof b, "%s/b", base);
    for (int i = 0; i < count; ++i) {
        CHECK(mkdir(a, 0700) == 0 && mkdir(b, 0700) == 0);
        CHECK(rename(a, b) == 0);
        snprintf(file, sizeof file, "%s/file", b);
        int fd = open(file, O_CREAT | O_RDWR, 0600); CHECK(fd >= 0);
        char renamed[160]; snprintf(renamed, sizeof renamed, "%s/renamed", b);
        CHECK(link(file, renamed) == 0 && unlink(renamed) == 0);
        CHECK(symlink("file", renamed) == 0 && unlink(renamed) == 0);
        CHECK(rename(file, renamed) == 0 && unlink(renamed) == 0 && rmdir(b) == 0);
        CHECK(write(fd, "x", 1) == 1); close(fd);
    }
}
static void *worker(void *argument) {
    long id = (long)argument; char base[64]; snprintf(base, sizeof base, "/tmp/worker-%ld", id);
    CHECK(mkdir(base, 0700) == 0);
    CHECK(unshare(CLONE_FS) == 0 && chdir(base) == 0);
    for (int i = 0; i < 32; ++i) {
        int fd = open("/tmp/open-race", O_CREAT | O_RDWR, 0600); CHECK(fd >= 0); close(fd);
    }
    operations(base, 100); CHECK(rmdir(base) == 0);
    return NULL;
}
static void concurrent(void) {
    pthread_t workers[4];
    for (long i = 0; i < 4; ++i) CHECK(pthread_create(&workers[i], NULL, worker, (void *)i) == 0);
    for (int i = 0; i < 4; ++i) CHECK(pthread_join(workers[i], NULL) == 0);
    CHECK(unlink("/tmp/open-race") == 0);
}
static void cohort(void) {
    operations("/tmp", 200); concurrent();
    for (int i = 0; i < 100; ++i) {
        pid_t child = fork(); CHECK(child >= 0);
        if (!child) { char *argv[] = {"/sbin/init", "--exit", NULL}; execv(argv[0], argv); _exit(99); }
        wait_ok(child);
    }
    /* An orphaned child can retire after its removed parent. Allow both
     * grace periods and the final writeback-worker scan to finish. */
    sleep(13);
}
int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc > 1 && !strcmp(argv[1], "--exit")) return 0;
    CHECK(sysconf(_SC_NPROCESSORS_ONLN) >= 2);
    lifetimes();
    /* Warm diagnostics too: their first access belongs to the warmup. */
    track(0); cohort();
    struct slab before[32], after[32]; int count = slabs(before); CHECK(count > 0);
    CHECK(slabs(after) == count); long control[32];
    for (int i = 0; i < count; ++i) control[i] = (long)after[i].objects - (long)before[i].objects;
    memcpy(before, after, sizeof before); track(0);
    for (int batch = 0; batch < 3; ++batch) {
        cohort(); CHECK(slabs(after) == count);
        for (int i = 0; i < count; ++i) {
            long delta = (long)after[i].objects - (long)before[i].objects;
            printf("RETENTION SLAB batch=%d class=%lu delta=%ld control=%ld\n", batch + 1, after[i].size, delta, control[i]);
            if (delta > (control[i] > 0 ? control[i] : 0)) track(1);
            CHECK(delta <= (control[i] > 0 ? control[i] : 0));
        }
        memcpy(before, after, sizeof before);
    }
    track(1); puts("RETENTION PASS"); sync(); reboot(RB_POWER_OFF); return 0;
}
