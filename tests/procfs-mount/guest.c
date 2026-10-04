#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#define REQUIRE(condition) do { if (!(condition)) { \
    printf("PROC MOUNT FAIL: line=%d errno=%d\n", __LINE__, errno); return 1; \
} } while (0)

static char content[131072], before_mounts[131072];

static ssize_t read_file(const char *path, char *buffer, size_t capacity) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    size_t length = 0;
    while (length < capacity - 1) {
        ssize_t count = read(fd, buffer + length, capacity - 1 - length);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) { close(fd); return -1; }
        if (!count) break;
        length += count;
    }
    if (close(fd) || length == capacity - 1) return -1;
    buffer[length] = 0;
    return (ssize_t)length;
}

static long slab_kib(void) {
    if (read_file("/proc/meminfo", content, sizeof content) < 0) return -1;
    char *line = content;
    do {
        long value;
        if (sscanf(line, "Slab: %ld kB", &value) == 1) return value;
        line = strchr(line, '\n');
    } while (line && *++line);
    return -1;
}

static int deny_mount(const char *target, const char *kind) {
    errno = 0;
    int result = mount("proc", target, kind, 0, "");
    if (result == -1 && errno == EBUSY) return 0;
    printf("PROC MOUNT UNEXPECTED: target=%s type=%s result=%d errno=%d\n",
        target, kind, result, errno);
    errno = 0;
    ssize_t length = read_file("/proc/self/mountinfo", content, sizeof content);
    printf("PROC MOUNT GRAPH: mountinfo_result=%zd errno=%d\n", length, errno);
    char path[128];
    snprintf(path, sizeof path, "%s/meminfo", target);
    errno = 0;
    length = read_file(path, content, sizeof content);
    printf("PROC MOUNT GRAPH: target_meminfo_result=%zd errno=%d\n", length, errno);
    return -1;
}

static int refuse_self_mounts(const char *where, int count) {
    int held = open("/proc/meminfo", O_RDONLY);
    REQUIRE(held >= 0);
    for (int i = 0; i < 20; i++) {
        REQUIRE(deny_mount("/proc", i % 2 ? "procfs" : "proc") == 0);
    }
    REQUIRE(read_file("/proc/self/mountinfo", before_mounts, sizeof before_mounts) > 0);
    REQUIRE(deny_mount("/proc/sys", "proc") == 0);
    REQUIRE(deny_mount("/proc/sys", "procfs") == 0);
    long before = slab_kib();
    REQUIRE(before >= 0);
    for (int i = 0; i < count; i++) {
        REQUIRE(deny_mount("/proc", i % 2 ? "procfs" : "proc") == 0);
    }
    long after = slab_kib();
    REQUIRE(after >= 0 && after <= before + 16);
    REQUIRE(read_file("/proc/self/mountinfo", content, sizeof content) > 0);
    REQUIRE(strcmp(content, before_mounts) == 0);
    REQUIRE(read(held, content, sizeof content - 1) > 0 && close(held) == 0);
    REQUIRE(read_file("/proc/meminfo", content, sizeof content) > 0);
    REQUIRE(read_file("/proc/self/stat", content, sizeof content) > 0);
    printf("PROC MOUNT RETAINED: %s denials=%d slab_kib=%ld -> %ld\n", where, count, before, after);
    return 0;
}

static int namespace_init(void) {
    REQUIRE(getpid() == 1);
    // The inherited /proc belongs to the parent PID namespace. This mount
    // must create this namespace's first view, rather than reject the path.
    REQUIRE(mount("proc", "/proc", "proc", 0, "") == 0);
    char link[32];
    ssize_t length = readlink("/proc/self", link, sizeof link);
    REQUIRE(length == 7 && memcmp(link, "/proc/1", 7) == 0);
    REQUIRE(refuse_self_mounts("pid-namespace", 1000) == 0);
    return 0;
}

static int namespace_parent(void) {
    REQUIRE(unshare(CLONE_NEWNS) == 0);
    REQUIRE(unshare(CLONE_NEWPID) == 0);
    pid_t child = fork();
    REQUIRE(child >= 0);
    if (!child) _exit(namespace_init());
    int status;
    while (waitpid(child, &status, 0) < 0) REQUIRE(errno == EINTR);
    REQUIRE(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    return 0;
}

static int reaped(pid_t child) {
    int status;
    while (waitpid(child, &status, 0) < 0) REQUIRE(errno == EINTR);
    REQUIRE(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    return 0;
}

static int stale_namespace_init(int phase, int ready, int gate) {
    REQUIRE(getpid() == 1);
    char link[32];
    if (phase == 0) {
        REQUIRE(mount("proc", "/tmp/proc-stale", "proc", 0, "") == 0);
        REQUIRE(readlink("/tmp/proc-stale/self", link, sizeof link) == 7 &&
            memcmp(link, "/proc/1", 7) == 0);
        return 0;
    }
    if (phase == 2) {
        REQUIRE(mount("proc", "/tmp/proc-fresh", "procfs", 0, "") == 0);
        REQUIRE(readlink("/tmp/proc-fresh/self", link, sizeof link) == 7 &&
            memcmp(link, "/proc/1", 7) == 0);
        // The old alias reaches the actual reused root, now retargeted only
        // by this successful mount at a different covered directory.
        REQUIRE(readlink("/tmp/proc-stale/self", link, sizeof link) == 7 &&
            memcmp(link, "/proc/1", 7) == 0);
        return 0;
    }
    REQUIRE(write(ready, "r", 1) == 1);
    REQUIRE(read(gate, link, 1) == 1);
    errno = 0;
    REQUIRE(readlink("/tmp/proc-stale/self", link, sizeof link) == -1 && errno == ENOENT);
    REQUIRE(read_file("/proc/self/mountinfo", before_mounts, sizeof before_mounts) > 0);
    for (int i = 0; i < 128; i++) {
        REQUIRE(deny_mount("/tmp/proc-stale", i % 2 ? "procfs" : "proc") == 0);
        REQUIRE(deny_mount("/tmp/proc-stale/sys", i % 2 ? "procfs" : "proc") == 0);
    }
    errno = 0;
    REQUIRE(readlink("/tmp/proc-stale/self", link, sizeof link) == -1 && errno == ENOENT);
    REQUIRE(read_file("/tmp/proc-stale/meminfo", content, sizeof content) > 0);
    REQUIRE(read_file("/tmp/proc-stale/sys/kernel/ostype", content, sizeof content) > 0);
    REQUIRE(read_file("/proc/self/mountinfo", content, sizeof content) > 0 &&
        strcmp(content, before_mounts) == 0);
    return 0;
}

static pid_t spawn_stale_namespace(int phase, int ready, int gate) {
    pid_t helper = fork();
    if (helper != 0) return helper;
    if (unshare(CLONE_NEWPID)) _exit(1);
    pid_t init = fork();
    if (init < 0) _exit(2);
    if (!init) _exit(stale_namespace_init(phase, ready, gate));
    _exit(reaped(init));
}

static int stale_view_test(void) {
    // These children intentionally share the parent's mount namespace, so
    // the first view's root remains mounted after all its PID members exit.
    REQUIRE(mkdir("/tmp/proc-stale", 0755) == 0);
    REQUIRE(mkdir("/tmp/proc-fresh", 0755) == 0);
    pid_t first = spawn_stale_namespace(0, -1, -1);
    REQUIRE(first > 0 && reaped(first) == 0);
    int ready[2], gate[2];
    REQUIRE(pipe(ready) == 0 && pipe(gate) == 0);
    pid_t peers[4];
    for (int i = 0; i < 4; i++) {
        peers[i] = spawn_stale_namespace(1, ready[1], gate[0]);
        REQUIRE(peers[i] > 0);
    }
    char byte;
    for (int i = 0; i < 4; i++) REQUIRE(read(ready[0], &byte, 1) == 1);
    REQUIRE(write(gate[1], "gggg", 4) == 4);
    for (int i = 0; i < 4; i++) REQUIRE(reaped(peers[i]) == 0);
    REQUIRE(close(ready[0]) == 0 && close(ready[1]) == 0);
    REQUIRE(close(gate[0]) == 0 && close(gate[1]) == 0);
    pid_t allowed = spawn_stale_namespace(2, -1, -1);
    REQUIRE(allowed > 0 && reaped(allowed) == 0);
    REQUIRE(umount("/tmp/proc-fresh") == 0 && umount("/tmp/proc-stale") == 0);
    REQUIRE(rmdir("/tmp/proc-fresh") == 0 && rmdir("/tmp/proc-stale") == 0);
    puts("PROC MOUNT PASS: inactive view reuse rejects self edges before retarget, concurrently");
    return 0;
}

static int run_tests(void) {
#ifdef PROC_MOUNT_REUSE_ONLY
    return stale_view_test();
#endif
    REQUIRE(refuse_self_mounts("initial", 3000) == 0);
    puts("PROC MOUNT PASS: self mounts fail without damaging proc paths or mountinfo");
    REQUIRE(mkdir("/tmp/proc-alias", 0755) == 0);
    REQUIRE(mount("proc", "/tmp/proc-alias", "proc", 0, "") == 0);
    REQUIRE(read_file("/tmp/proc-alias/meminfo", content, sizeof content) > 0);
    errno = 0;
    REQUIRE(mount("proc", "/tmp/proc-alias", "proc", 0, "") == -1 && errno == EBUSY);
    REQUIRE(mount("none", "/tmp/proc-alias", NULL, MS_REMOUNT | MS_RDONLY, "") == 0);
    REQUIRE(read_file("/proc/meminfo", content, sizeof content) > 0);
    REQUIRE(umount("/tmp/proc-alias") == 0 && rmdir("/tmp/proc-alias") == 0);
    REQUIRE(mkdir("/tmp/proc-bind", 0755) == 0);
    REQUIRE(mount("/proc", "/tmp/proc-bind", NULL, MS_BIND, NULL) == 0);
    REQUIRE(read_file("/tmp/proc-bind/meminfo", content, sizeof content) > 0);
    REQUIRE(umount("/tmp/proc-bind") == 0 && rmdir("/tmp/proc-bind") == 0);
    puts("PROC MOUNT PASS: independent aliases and remounts remain usable");
    REQUIRE(stale_view_test() == 0);
    fflush(stdout);
    pid_t child = fork();
    REQUIRE(child >= 0);
    if (!child) _exit(namespace_parent());
    int status;
    while (waitpid(child, &status, 0) < 0) REQUIRE(errno == EINTR);
    REQUIRE(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    REQUIRE(read_file("/proc/meminfo", content, sizeof content) > 0);
    puts("PROC MOUNT PASS: fresh PID namespace views remain mountable and reject cycles");
    puts("PROC MOUNT PASS: cached roots cannot cover their own descendants");
    return 0;
}

int main(void) {
#if defined(__x86_64__)
    int serial = open("/dev/com1", O_WRONLY | O_NOCTTY);
    if (serial < 0 || dup2(serial, 1) < 0 || dup2(serial, 2) < 0) return 1;
    if (serial > 2) close(serial);
#endif
    setvbuf(stdout, NULL, _IONBF, 0);
    puts("PROC MOUNT START");
    int result = run_tests();
    puts(result ? "PROC MOUNT GUEST: FAIL" : "PROC MOUNT GUEST: PASS");
    sync();
    reboot(RB_POWER_OFF);
    return result;
}
