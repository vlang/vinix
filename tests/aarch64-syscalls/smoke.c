// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <poll.h>
#include <sched.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/resource.h>
#include <sys/sendfile.h>
#include <sys/shm.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <sys/xattr.h>
#include <sys/membarrier.h>
#include <sys/mount.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <sys/prctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#ifndef AT_EMPTY_PATH
#define AT_EMPTY_PATH 0x1000
#endif

#ifndef SYS_epoll_pwait2
#define SYS_epoll_pwait2 441
#endif

struct open_how_abi {
    uint64_t flags;
    uint64_t mode;
    uint64_t resolve;
};

static int failures;
static volatile sig_atomic_t saw_sigchld;
static volatile sig_atomic_t saw_context_redirect;
static volatile sig_atomic_t saw_segv_accerr;
static void *protected_page;

static void sigchld_handler(int signal_number) {
    (void)signal_number;
    saw_sigchld = 1;
}

static void redirect_segv_handler(int signal_number, siginfo_t *info,
                                  void *context_argument) {
    ucontext_t *context = context_argument;
    if (signal_number == SIGSEGV && info->si_addr == protected_page) {
        saw_context_redirect = 1;
        saw_segv_accerr = info->si_code == SEGV_ACCERR;
        context->uc_mcontext.pc += 4;
    }
}

static void check(int condition, const char *description) {
    printf("%-42s %s\n", description, condition ? "ok" : "FAIL");
    fflush(stdout);
    if (!condition)
        failures++;
}

static int failed_with_errno(long result, int expected, const char *operation) {
    if (result == -1 && errno == expected)
        return 1;
    printf("%s: result=%ld errno=%d (expected %d)\n",
           operation, result, errno, expected);
    fflush(stdout);
    return 0;
}

static int denied_operations(void) {
    const void *invalid = (const void *)(uintptr_t)1;
    return failed_with_errno(sethostname("untrusted", 9), EPERM, "sethostname") &&
           failed_with_errno(syscall(SYS_setdomainname, "bad.test", 8), EPERM, "setdomainname") &&
           failed_with_errno(syscall(SYS_mount, "", "/tmp", "unknownfs", 0, NULL), EPERM, "mount") &&
           failed_with_errno(syscall(SYS_umount2, "/tmp", 0), EPERM, "umount2") &&
           failed_with_errno(syscall(SYS_reboot, 0, 0, 0, NULL), EPERM, "reboot") &&
           failed_with_errno(syscall(SYS_sethostname, invalid, 1), EPERM, "sethostname invalid pointer") &&
           failed_with_errno(syscall(SYS_setdomainname, invalid, 1), EPERM, "setdomainname invalid pointer") &&
           failed_with_errno(syscall(SYS_mount, invalid, invalid, invalid, 0, NULL), EPERM, "mount invalid pointers") &&
           failed_with_errno(syscall(SYS_umount2, invalid, 0), EPERM, "umount invalid pointer");
}

static int mount_rejects_bad_strings(void) {
    const void *invalid = (const void *)(uintptr_t)1;
    int valid = failed_with_errno(syscall(SYS_mount, invalid, "/tmp", "tmpfs", 0, NULL),
                                  EFAULT, "mount source invalid pointer") &&
                failed_with_errno(syscall(SYS_mount, "", invalid, "tmpfs", 0, NULL),
                                  EFAULT, "mount target invalid pointer") &&
                failed_with_errno(syscall(SYS_mount, "", "/tmp", invalid, 0, NULL),
                                  EFAULT, "mount type invalid pointer") &&
                failed_with_errno(syscall(SYS_mount, NULL, "/tmp", "tmpfs", 0, NULL),
                                  EFAULT, "mount null source");

    char overlong[4096];
    memset(overlong, 'x', sizeof(overlong));
    valid &= failed_with_errno(syscall(SYS_mount, overlong, "/tmp", "tmpfs", 0, NULL),
                               ENAMETOOLONG, "mount unterminated source");

    char *pages = mmap(NULL, 8192, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (pages == MAP_FAILED || mprotect(pages + 4096, 4096, PROT_NONE) != 0) {
        if (pages != MAP_FAILED)
            munmap(pages, 8192);
        return 0;
    }
    pages[4095] = '\0';
    valid &= failed_with_errno(syscall(SYS_mount, pages + 4095, "/tmp", "unknownfs", 0, NULL),
                               ENODEV, "mount terminator at page boundary");
    pages[4095] = 'x';
    valid &= failed_with_errno(syscall(SYS_mount, pages + 4095, "/tmp", "tmpfs", 0, NULL),
                               EFAULT, "mount string crosses into unmapped page");
    munmap(pages, 8192);
    return valid;
}

static int security_child_succeeded(pid_t child) {
    int status = 0;
    pid_t waited = -1;
    if (child > 0) {
        do {
            waited = waitpid(child, &status, 0);
        } while (waited == -1 && errno == EINTR);
    }
    if (child > 0 && waited == child && WIFEXITED(status) && WEXITSTATUS(status) == 0)
        return 1;
    printf("security child pid=%d waited=%d status=0x%x errno=%d\n",
           (int)child, (int)waited, status, errno);
    fflush(stdout);
    return 0;
}

// Extended attributes on tmpfs, as Docker's overlay2 driver and archive
// extractors use them.
static int xattr_operations(void) {
    const char *xattr_file = "/tmp/aarch64-syscall-xattr";
    const char *xattr_dir = "/tmp/aarch64-syscall-xattr-dir";
    const char *xattr_link = "/tmp/aarch64-syscall-xattr-link";
    char value[16] = {0};
    char names[128] = {0};
    unlink(xattr_file);
    unlink(xattr_link);
    rmdir(xattr_dir);
    int xattr_fd = open(xattr_file, O_CREAT | O_RDWR, 0644);
    if (xattr_fd < 0 || mkdir(xattr_dir, 0755) != 0 || symlink(xattr_file, xattr_link) != 0)
        return 0;
    int valid = setxattr(xattr_file, "user.test", "hello", 5, 0) == 0 &&
                getxattr(xattr_file, "user.test", NULL, 0) == 5 &&
                getxattr(xattr_file, "user.test", value, sizeof(value)) == 5 &&
                !memcmp(value, "hello", 5) &&
                failed_with_errno(getxattr(xattr_file, "user.test", value, 2), ERANGE,
                                  "getxattr small buffer") &&
                failed_with_errno(setxattr(xattr_file, "user.test", "x", 1, XATTR_CREATE),
                                  EEXIST, "setxattr XATTR_CREATE") &&
                failed_with_errno(setxattr(xattr_file, "user.none", "x", 1, XATTR_REPLACE),
                                  ENODATA, "setxattr XATTR_REPLACE") &&
                setxattr(xattr_file, "user.test", "hi", 2, XATTR_REPLACE) == 0 &&
                fgetxattr(xattr_fd, "user.test", value, sizeof(value)) == 2 &&
                !memcmp(value, "hi", 2) &&
                fsetxattr(xattr_fd, "user.second", "", 0, 0) == 0 &&
                listxattr(xattr_file, NULL, 0) == 22 &&
                listxattr(xattr_file, names, sizeof(names)) == 22 &&
                !memcmp(names, "user.test\0user.second\0", 22) &&
                removexattr(xattr_file, "user.test") == 0 &&
                failed_with_errno(getxattr(xattr_file, "user.test", value, sizeof(value)),
                                  ENODATA, "getxattr removed") &&
                fremovexattr(xattr_fd, "user.second") == 0 &&
                listxattr(xattr_file, names, sizeof(names)) == 0 &&
                setxattr(xattr_dir, "trusted.overlay.opaque", "y", 1, 0) == 0 &&
                getxattr(xattr_dir, "trusted.overlay.opaque", value, sizeof(value)) == 1 &&
                value[0] == 'y' &&
                failed_with_errno(setxattr(xattr_file, "system.posix_acl_access", "x", 1, 0),
                                  EOPNOTSUPP, "setxattr system namespace") &&
                failed_with_errno(lsetxattr(xattr_link, "user.test", "x", 1, 0), EPERM,
                                  "lsetxattr user namespace on symlink") &&
                failed_with_errno(setxattr("/proc/self/status", "user.test", "x", 1, 0),
                                  EOPNOTSUPP, "setxattr on procfs");

    pid_t unprivileged = fork();
    if (unprivileged == 0) {
        if (setresuid(1000, 1000, 1000) != 0)
            _exit(1);
        char seen[16];
        if (!failed_with_errno(getxattr(xattr_dir, "trusted.overlay.opaque", seen, sizeof(seen)),
                               ENODATA, "unprivileged getxattr trusted") ||
            listxattr(xattr_dir, seen, sizeof(seen)) != 0 ||
            !failed_with_errno(setxattr(xattr_dir, "trusted.other", "x", 1, 0), EPERM,
                               "unprivileged setxattr trusted"))
            _exit(2);
        _exit(0);
    }
    valid = valid && security_child_succeeded(unprivileged);

    close(xattr_fd);
    unlink(xattr_file);
    unlink(xattr_link);
    rmdir(xattr_dir);
    return valid;
}

// Nodes mknod(2) makes are numbered like the files around them. Go's
// directory reader skips an entry whose inode number is 0, so Docker could
// neither pack an overlay whiteout into an image layer nor remove one.
static int special_node_numbers(void) {
    const char *dir = "/tmp/aarch64-syscall-special";
    const char *fifo = "/tmp/aarch64-syscall-special/fifo";
    const char *device = "/tmp/aarch64-syscall-special/whiteout";
    struct stat dir_stat, fifo_stat, device_stat;
    mkdir(dir, 0755);
    int valid = mkfifo(fifo, 0644) == 0 && mknod(device, S_IFCHR, 0) == 0 &&
                stat(dir, &dir_stat) == 0 && lstat(fifo, &fifo_stat) == 0 &&
                lstat(device, &device_stat) == 0 && fifo_stat.st_ino != 0 &&
                device_stat.st_ino != 0 && fifo_stat.st_ino != device_stat.st_ino &&
                fifo_stat.st_dev == dir_stat.st_dev && device_stat.st_dev == dir_stat.st_dev &&
                S_ISCHR(device_stat.st_mode) && device_stat.st_rdev == 0;
    unlink(fifo);
    unlink(device);
    rmdir(dir);
    return valid;
}

static int write_text(const char *path, const char *text) {
    int fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0644);
    if (fd < 0)
        return 0;
    ssize_t length = (ssize_t)strlen(text);
    int valid = write(fd, text, (size_t)length) == length;
    close(fd);
    return valid;
}

static int has_text(const char *path, const char *text) {
    char buffer[64] = {0};
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return 0;
    ssize_t length = read(fd, buffer, sizeof(buffer) - 1);
    close(fd);
    return length == (ssize_t)strlen(text) && !memcmp(buffer, text, (size_t)length);
}

// An overlay of one directory tree on another, as Docker's overlay2 driver
// mounts every container.
static int overlay_semantics(void) {
    const char *merged = "/tmp/aarch64-syscall-ovl/merged";
    struct stat whiteout_stat;
    mkdir("/tmp/aarch64-syscall-ovl", 0755);
    mkdir("/tmp/aarch64-syscall-ovl/lower", 0755);
    mkdir("/tmp/aarch64-syscall-ovl/lower/d", 0755);
    mkdir("/tmp/aarch64-syscall-ovl/lower2", 0755);
    mkdir("/tmp/aarch64-syscall-ovl/upper", 0755);
    mkdir("/tmp/aarch64-syscall-ovl/work", 0755);
    mkdir(merged, 0755);
    if (!write_text("/tmp/aarch64-syscall-ovl/lower/a", "lower") ||
        !write_text("/tmp/aarch64-syscall-ovl/lower/keep", "keep") ||
        !write_text("/tmp/aarch64-syscall-ovl/lower/d/f", "f") ||
        !write_text("/tmp/aarch64-syscall-ovl/lower/hidden", "hidden") ||
        mknod("/tmp/aarch64-syscall-ovl/lower2/hidden", S_IFCHR, 0) != 0)
        return 0;
    const char *options = "lowerdir=/tmp/aarch64-syscall-ovl/lower2:/tmp/aarch64-syscall-ovl/lower,"
                          "upperdir=/tmp/aarch64-syscall-ovl/upper,workdir=/tmp/aarch64-syscall-ovl/work";
    if (mount("overlay", merged, "overlay", 0, options) != 0) {
        printf("overlay mount: errno=%d\n", errno);
        return 0;
    }
    int valid = has_text("/tmp/aarch64-syscall-ovl/merged/a", "lower") &&
                failed_with_errno(access("/tmp/aarch64-syscall-ovl/merged/hidden", F_OK), ENOENT,
                                  "whiteout in a lower layer") &&
                write_text("/tmp/aarch64-syscall-ovl/merged/a", "upper") &&
                has_text("/tmp/aarch64-syscall-ovl/merged/a", "upper") &&
                has_text("/tmp/aarch64-syscall-ovl/upper/a", "upper") &&
                has_text("/tmp/aarch64-syscall-ovl/lower/a", "lower") &&
                unlink("/tmp/aarch64-syscall-ovl/merged/keep") == 0 &&
                failed_with_errno(access("/tmp/aarch64-syscall-ovl/merged/keep", F_OK), ENOENT,
                                  "removed lower file") &&
                lstat("/tmp/aarch64-syscall-ovl/upper/keep", &whiteout_stat) == 0 &&
                S_ISCHR(whiteout_stat.st_mode) && whiteout_stat.st_rdev == 0 &&
                has_text("/tmp/aarch64-syscall-ovl/lower/keep", "keep") &&
                failed_with_errno(rename("/tmp/aarch64-syscall-ovl/merged/d",
                                         "/tmp/aarch64-syscall-ovl/merged/e"),
                                  EXDEV, "rename of a lower directory") &&
                failed_with_errno(rmdir("/tmp/aarch64-syscall-ovl/merged/d"), ENOTEMPTY,
                                  "rmdir of a merged directory") &&
                mkdir("/tmp/aarch64-syscall-ovl/merged/n", 0755) == 0 &&
                write_text("/tmp/aarch64-syscall-ovl/merged/n/x", "x") &&
                has_text("/tmp/aarch64-syscall-ovl/upper/n/x", "x");
    valid = umount("/tmp/aarch64-syscall-ovl/merged") == 0 && valid;

    if (mount("overlay", merged, "overlay", 0,
              "lowerdir=/tmp/aarch64-syscall-ovl/upper:/tmp/aarch64-syscall-ovl/lower") != 0)
        return 0;
    valid = valid && has_text("/tmp/aarch64-syscall-ovl/merged/a", "upper") &&
            failed_with_errno(open("/tmp/aarch64-syscall-ovl/merged/new", O_CREAT | O_WRONLY, 0644),
                              EROFS, "create in a read-only overlay");
    valid = umount("/tmp/aarch64-syscall-ovl/merged") == 0 && valid;
    return valid;
}

// seccomp filters, as a container runtime installs Docker's default profile.
static int install_filter(struct sock_filter *program, unsigned short length) {
    struct sock_fprog prog = {.len = length, .filter = program};
    return (int)syscall(SYS_seccomp, SECCOMP_SET_MODE_FILTER, 0, &prog);
}

static int seccomp_child(void) {
    struct sock_filter program[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_AARCH64, 1, 0),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_getppid, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | 77),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_getuid, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0 ||
        install_filter(program, sizeof(program) / sizeof(program[0])) != 0)
        return 1;
    if (syscall(SYS_getppid) != -1 || errno != 77 || getpid() <= 0 ||
        prctl(PR_GET_SECCOMP, 0, 0, 0, 0) != 2)
        return 2;
    char status[2048] = {0};
    int fd = open("/proc/self/status", O_RDONLY);
    if (fd < 0 || read(fd, status, sizeof(status) - 1) <= 0 ||
        !strstr(status, "Seccomp:\t2\nSeccomp_filters:\t1\n"))
        return 3;
    close(fd);
    pid_t grandchild = fork();
    if (grandchild == 0)
        _exit(syscall(SYS_getppid) == -1 && errno == 77 ? 0 : 1);
    int status_code = 0;
    if (waitpid(grandchild, &status_code, 0) != grandchild || !WIFEXITED(status_code) ||
        WEXITSTATUS(status_code) != 0)
        return 4;
    syscall(SYS_getuid);
    return 5;
}

static int seccomp_filters(void) {
    struct sock_filter bad_jump[] = {
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, 0, 5, 0),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    struct sock_filter no_return[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, 0),
    };
    unsigned int log_action = SECCOMP_RET_LOG;
    int valid = failed_with_errno(install_filter(bad_jump, 2), EINVAL, "seccomp jump out of range") &&
                failed_with_errno(install_filter(no_return, 1), EINVAL, "seccomp without return") &&
                syscall(SYS_seccomp, SECCOMP_GET_ACTION_AVAIL, 0, &log_action) == 0 &&
                prctl(PR_GET_SECCOMP, 0, 0, 0, 0) == 0;

    pid_t child = fork();
    if (child == 0)
        _exit(seccomp_child());
    int status = 0;
    valid = valid && waitpid(child, &status, 0) == child && WIFSIGNALED(status) &&
            WTERMSIG(status) == SIGSYS;
    if (!valid)
        printf("seccomp child status=0x%x\n", status);

    pid_t unprivileged = fork();
    if (unprivileged == 0) {
        struct sock_filter allow[] = {BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW)};
        if (setresuid(1000, 1000, 1000) != 0)
            _exit(1);
        _exit(failed_with_errno(install_filter(allow, 1), EACCES,
                                "seccomp without no_new_privs") ? 0 : 2);
    }
    return valid && security_child_succeeded(unprivileged);
}

static void *eventfd_writer(void *argument) {
    int fd = *(int *)argument;
    struct timespec delay = {.tv_nsec = 10000000};
    nanosleep(&delay, NULL);
    eventfd_write(fd, 11);
    return NULL;
}

int main(void) {
    const char *path = "/tmp/aarch64-syscall-smoke";
    const char *copy_path = "/tmp/aarch64-syscall-copy";
    mkdir("/tmp", 0777);
    unlink(path);
    unlink(copy_path);

    int fd = open(path, O_CREAT | O_TRUNC | O_RDWR | O_CLOEXEC, 0600);
    check(fd >= 0, "open test file");
    if (fd < 0)
        return 1;

    struct stat file_stat;
    check(fstat(fd, &file_stat) == 0 && (file_stat.st_mode & 07777) == 0600,
          "open O_CREAT preserves file mode");

    check(pwrite(fd, "scalar", 6, 0) == 6, "pwrite64");
    char scalar[7] = {0};
    check(pread(fd, scalar, 6, 0) == 6 && !strcmp(scalar, "scalar"), "pread64");

    struct iovec write_iov[] = {
        {.iov_base = (void *)"vector", .iov_len = 6},
        {.iov_base = (void *)" write", .iov_len = 6},
    };
    lseek(fd, 7, SEEK_SET);
    check(pwritev(fd, write_iov, 2, 32) == 12, "pwritev split-offset ABI");
    char left[7] = {0};
    char right[7] = {0};
    struct iovec read_iov[] = {
        {.iov_base = left, .iov_len = 6},
        {.iov_base = right, .iov_len = 6},
    };
    check(preadv(fd, read_iov, 2, 32) == 12 && !strcmp(left, "vector") &&
              !strcmp(right, " write") && lseek(fd, 0, SEEK_CUR) == 7,
          "preadv preserves shared offset");

    uint64_t positioned_offset = 64;
    check(syscall(SYS_pwritev2, fd, write_iov, 2,
                  (uint32_t)positioned_offset, positioned_offset >> 32, 0) == 12,
          "pwritev2 Linux ABI");
    memset(left, 0, sizeof(left));
    memset(right, 0, sizeof(right));
    check(syscall(SYS_preadv2, fd, read_iov, 2,
                  (uint32_t)positioned_offset, positioned_offset >> 32, 0) == 12 &&
              !strcmp(left, "vector") && !strcmp(right, " write"),
          "preadv2 Linux ABI");

    errno = 0;
    check(readv(-1, NULL, 0) == -1 && errno == EBADF,
          "readv validates fd with zero vectors");

    check(posix_fallocate(fd, 0, 128) == 0, "fallocate");
    check(fstat(fd, &file_stat) == 0 && file_stat.st_size >= 128,
          "fallocate extends file");

    FILE *stream = fopen(path, "rb");
    char stream_data[128] = {0};
    check(stream != NULL && fread(stream_data, 1, sizeof(stream_data), stream) ==
              sizeof(stream_data) && !memcmp(stream_data, "scalar", 6),
          "fread buffered readv path");
    if (stream != NULL)
        fclose(stream);

    check(posix_fadvise(fd, 0, 0, POSIX_FADV_NORMAL) == 0, "fadvise64");
    check(sync_file_range(fd, 0, 128, SYNC_FILE_RANGE_WRITE) == 0,
          "sync_file_range");

    int copy_fd = open(copy_path, O_CREAT | O_TRUNC | O_RDWR | O_CLOEXEC, 0600);
    off_t send_offset = 32;
    check(copy_fd >= 0 && sendfile(copy_fd, fd, &send_offset, 12) == 12 &&
              send_offset == 44 && lseek(fd, 0, SEEK_CUR) == 7,
          "sendfile positioned input");
    char copied[13] = {0};
    check(pread(copy_fd, copied, 12, 0) == 12 && !strcmp(copied, "vector write"),
          "sendfile contents");
    close(copy_fd);

    int counter = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    int epoll = epoll_create1(EPOLL_CLOEXEC);
    struct epoll_event interest = {.events = EPOLLIN, .data.u64 = 0x56494e4958ULL};
    struct epoll_event ready = {0};
    check(counter >= 0 && epoll >= 0 && epoll_ctl(epoll, EPOLL_CTL_ADD, counter,
                                                   &interest) == 0,
          "eventfd and epoll setup");
    errno = 0;
    eventfd_t value = 0;
    check(eventfd_read(counter, &value) == -1 && errno == EAGAIN,
          "eventfd nonblocking empty read");
    check(eventfd_write(counter, 7) == 0 &&
              syscall(SYS_epoll_pwait2, epoll, &ready, 1,
                      &(struct timespec){.tv_sec = 1}, NULL, 8) == 1 &&
              ready.data.u64 == interest.data.u64 &&
              eventfd_read(counter, &value) == 0 && value == 7,
          "eventfd readiness via epoll_pwait2");
    close(epoll);
    close(counter);

    int blocking_counter = eventfd(0, EFD_CLOEXEC);
    pthread_t writer;
    struct pollfd blocking_poll = {
        .fd = blocking_counter,
        .events = POLLIN,
    };
    check(blocking_counter >= 0 &&
              pthread_create(&writer, NULL, eventfd_writer, &blocking_counter) == 0 &&
              ppoll(&blocking_poll, 1, &(struct timespec){.tv_sec = 1}, NULL) == 1 &&
              (blocking_poll.revents & POLLIN) != 0 &&
              eventfd_read(blocking_counter, &value) == 0 && value == 11 &&
              pthread_join(writer, NULL) == 0,
          "ppoll cross-thread wakeup");
    close(blocking_counter);

    struct sigaction child_action = {
        .sa_handler = sigchld_handler,
    };
    sigemptyset(&child_action.sa_mask);
    check(sigaction(SIGCHLD, &child_action, NULL) == 0,
          "install SIGCHLD handler");
    pid_t child = fork();
    if (child == 0)
        _exit(23);
    int child_status = 0;
    pid_t waited = child > 0 ? waitpid(child, &child_status, 0) : -1;
    check(child > 0 && waited == child && WIFEXITED(child_status) &&
              WEXITSTATUS(child_status) == 23 && saw_sigchld,
          "waitpid event plus SIGCHLD wakeup");

    struct sigaction fault_action = {
        .sa_sigaction = redirect_segv_handler,
        .sa_flags = SA_SIGINFO,
    };
    sigemptyset(&fault_action.sa_mask);
    protected_page = mmap(NULL, 4096, PROT_NONE,
                          MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    check(protected_page != MAP_FAILED &&
              sigaction(SIGSEGV, &fault_action, NULL) == 0,
          "install SIGSEGV context handler");
    if (protected_page != MAP_FAILED) {
        __asm__ volatile("ldr xzr, [%0]" : : "r"(protected_page) : "memory");
        check(saw_context_redirect && saw_segv_accerr,
              "SIGSEGV ucontext PC redirect");
        munmap(protected_page, 4096);
    }

    errno = 0;
    check(syscall(SYS_ppoll, (void *)1, 1, NULL, NULL, 8) == -1 &&
              errno == EFAULT,
          "ppoll rejects invalid poll array");

    struct open_how_abi how = {.flags = O_RDONLY | O_CLOEXEC};
    int opened = syscall(SYS_openat2, AT_FDCWD, path, &how, sizeof(how));
    check(opened >= 0, "openat2");
    if (opened >= 0)
        close(opened);
    check(syscall(SYS_faccessat, AT_FDCWD, path, F_OK) == 0,
          "legacy faccessat ABI");
    check(syscall(SYS_faccessat2, fd, "", F_OK, AT_EMPTY_PATH) == 0,
          "faccessat2 AT_EMPTY_PATH");
    check(fchmodat(AT_FDCWD, path, 0751, 0) == 0 &&
              stat(path, &file_stat) == 0 && (file_stat.st_mode & 07777) == 0751,
          "fchmodat updates file mode");

    struct rlimit limit;
    check(syscall(SYS_getrlimit, RLIMIT_NOFILE, &limit) == 0 &&
              limit.rlim_cur > 0 && limit.rlim_max >= limit.rlim_cur,
          "getrlimit");
    unsigned cpu = UINT32_MAX;
    unsigned node = UINT32_MAX;
    check(syscall(SYS_getcpu, &cpu, &node, NULL) == 0 && node == 0,
          "getcpu");
    struct timespec interval;
    // The test process uses SCHED_OTHER, which has no round-robin quantum.
    check(sched_rr_get_interval(0, &interval) == 0 && interval.tv_sec == 0 &&
              interval.tv_nsec == 0, "sched_rr_get_interval non-RR policy");
    check(membarrier(MEMBARRIER_CMD_QUERY, 0) == 0,
          "membarrier feature query");

    struct sockaddr_storage peer_address;
    socklen_t peer_length = sizeof(peer_address);
    errno = 0;
    check(getpeername(STDERR_FILENO, (struct sockaddr *)&peer_address,
                      &peer_length) == -1 && errno == ENOTSOCK,
          "getpeername rejects non-sockets with ENOTSOCK");

    __asm__ volatile("wfe");
    check(1, "trapped userspace WFE resumes");

    int shmid = shmget(IPC_PRIVATE, 4096, IPC_CREAT | 0600);
    char *shared = shmid >= 0 ? shmat(shmid, NULL, 0) : (void *)-1;
    if (shared != (void *)-1)
        strcpy(shared, "parent");
    int shm_removed = shared != (void *)-1 ? shmctl(shmid, IPC_RMID, NULL) : -1;
    pid_t shm_child = shm_removed == 0 ? fork() : -1;
    if (shm_child == 0) {
        char *second = shmat(shmid, NULL, 0);
        if (second == (void *)-1 || strcmp(second, "parent"))
            _exit(1);
        strcpy(second, "child");
        _exit(shmdt(second) == 0 ? 0 : 2);
    }
    int shm_status = 0;
    struct shmid_ds shm_info;
    check(shmid >= 0 && shared != (void *)-1 && shm_child > 0 &&
              waitpid(shm_child, &shm_status, 0) == shm_child &&
              WIFEXITED(shm_status) && WEXITSTATUS(shm_status) == 0 &&
              !strcmp(shared, "child") &&
              shmctl(shmid, IPC_STAT, &shm_info) == 0 &&
              shm_info.shm_segsz == 4096 && shmdt(shared) == 0,
          "System V shared memory after IPC_RMID");

    check(sethostname("syscall-smoke", 13) == 0, "sethostname");
    check(syscall(SYS_setdomainname, "vinix.test", 10) == 0, "setdomainname");
    struct utsname uts;
    check(uname(&uts) == 0 && !strcmp(uts.machine, "aarch64") &&
              !strcmp(uts.nodename, "syscall-smoke") &&
              !strcmp(uts.domainname, "vinix.test"),
          "uname hostname and domainname");

    const char *mount_dir = "/tmp/aarch64-syscall-mount";
    int mount_ready = mkdir(mount_dir, 0700) == 0 &&
                      syscall(SYS_mount, "", mount_dir, "tmpfs", 0, NULL) == 0;
    check(mount_ready, "root mount accepts copied strings");
    if (mount_ready) {
        int mounted_file = open("/tmp/aarch64-syscall-mount/probe", O_CREAT | O_RDWR, 0600);
        check(mounted_file >= 0, "mounted tmpfs remains usable");
        if (mounted_file >= 0)
            close(mounted_file);
    }

    check(mount_rejects_bad_strings(), "root mount checks userspace strings");

    pid_t security_child = fork();
    if (security_child == 0) {
        if (setuid(1000) != 0 || geteuid() != 1000) {
            printf("security child: setuid failed, euid=%u errno=%d\n",
                   (unsigned)geteuid(), errno);
            fflush(stdout);
            _exit(1);
        }
        if (!failed_with_errno(setuid(0), EPERM, "regain root after setuid") ||
            getuid() != 1000 || geteuid() != 1000)
            _exit(2);
        _exit(denied_operations() ? 0 : 3);
    }
    check(security_child_succeeded(security_child),
          "privileged selectors deny non-root callers");

    pid_t effective_child = fork();
    if (effective_child == 0) {
        if (setresuid((uid_t)-1, 1000, (uid_t)-1) != 0 ||
            getuid() != 0 || geteuid() != 1000)
            _exit(1);
        _exit(denied_operations() ? 0 : 2);
    }
    check(security_child_succeeded(effective_child),
          "real root with non-root euid is denied");
    check(uname(&uts) == 0 && !strcmp(uts.nodename, "syscall-smoke") &&
              !strcmp(uts.domainname, "vinix.test"),
          "denied name changes leave system state intact");

    pid_t root_effective_child = fork();
    if (root_effective_child == 0) {
        if (setresuid(1000, 0, 0) != 0 || getuid() != 1000 || geteuid() != 0)
            _exit(1);
        if (sethostname("syscall-smoke", 13) != 0 ||
            syscall(SYS_setdomainname, "vinix.test", 10) != 0 ||
            (mount_ready && syscall(SYS_umount2, mount_dir, 0) != 0) ||
            !failed_with_errno(syscall(SYS_reboot, 0, 0, 0, NULL), EINVAL, "root reboot invalid magic"))
            _exit(2);
        _exit(0);
    }
    check(security_child_succeeded(root_effective_child),
          "non-root real uid with root euid is allowed");
    if (mount_ready)
        check(access("/tmp/aarch64-syscall-mount/probe", F_OK) != 0,
              "root umount2 detaches the mount");

    // A directory removed while it is the working directory is still there
    // to stand in: it has no links and nothing can be made in it.
    const char *removed_dir = "/tmp/aarch64-syscall-removed";
    char previous_cwd[256];
    struct stat removed_stat;
    int removed_ok = getcwd(previous_cwd, sizeof(previous_cwd)) != NULL &&
                     mkdir(removed_dir, 0755) == 0 && chdir(removed_dir) == 0 &&
                     rmdir(removed_dir) == 0;
    removed_ok = removed_ok && stat(".", &removed_stat) == 0 &&
                 removed_stat.st_nlink == 0;
    removed_ok = removed_ok &&
                 failed_with_errno(open("file", O_CREAT | O_WRONLY, 0644), ENOENT,
                                   "create in removed directory") &&
                 failed_with_errno(mkdir("dir", 0755), ENOENT,
                                   "mkdir in removed directory");
    check(removed_ok, "removed working directory stays usable");
    check(xattr_operations(), "extended attributes on tmpfs");
    check(special_node_numbers(), "mknod nodes have inode numbers");
    check(overlay_semantics(), "overlay mount");
    check(seccomp_filters(), "seccomp filters");
    if (chdir(previous_cwd) != 0)
        chdir("/");

    close(fd);
    unlink(path);
    unlink(copy_path);
    printf("AARCH64 SYSCALL SMOKE %s (%d failures)\n",
           failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
