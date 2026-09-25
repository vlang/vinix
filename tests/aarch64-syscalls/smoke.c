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
#include <sys/un.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <sys/xattr.h>
#include <sys/membarrier.h>
#include <sys/mount.h>
#include <linux/audit.h>
#include <linux/capability.h>
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

// A socket bound in an overlay directory is a socket in the upper layer too,
// and files made after it survive its unlink, as postgres's data directory
// has to when it removes its socket on the way out.
static int overlay_bound_socket(const char *dir, const char *upper) {
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    char upper_path[sizeof(address.sun_path)], later_path[sizeof(address.sun_path)];
    struct stat merged_stat, upper_stat;
    snprintf(address.sun_path, sizeof(address.sun_path), "%s/sock", dir);
    snprintf(upper_path, sizeof(upper_path), "%s/sock", upper);
    snprintf(later_path, sizeof(later_path), "%s/later", dir);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0)
        return 0;
    int valid = bind(fd, (struct sockaddr *)&address, sizeof(address)) == 0 &&
                lstat(address.sun_path, &merged_stat) == 0 && S_ISSOCK(merged_stat.st_mode) &&
                lstat(upper_path, &upper_stat) == 0 && S_ISSOCK(upper_stat.st_mode);
    close(fd);
    valid = valid && write_text(later_path, "later") && unlink(address.sun_path) == 0 &&
            has_text(later_path, "later");
    unlink(later_path);
    return valid;
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
                has_text("/tmp/aarch64-syscall-ovl/upper/n/x", "x") &&
                overlay_bound_socket("/tmp/aarch64-syscall-ovl/merged",
                                     "/tmp/aarch64-syscall-ovl/upper");
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

// A pipe is a FIFO to stat(2), and can be opened again through
// /proc/self/fd, which is where /dev/stdout and /dev/stderr lead.
static int pipe_reopen(void) {
    int ends[2];
    int sockets[2];
    char path[64];
    char link[64] = {0};
    char byte = 0;
    struct stat info;
    if (pipe(ends) != 0 || socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0)
        return 0;
    int valid = fstat(ends[0], &info) == 0 && S_ISFIFO(info.st_mode);
    snprintf(path, sizeof(path), "/proc/self/fd/%d", ends[0]);
    valid = valid && stat(path, &info) == 0 && S_ISFIFO(info.st_mode) &&
            readlink(path, link, sizeof(link) - 1) > 0 && !strncmp(link, "pipe:[", 6);
    snprintf(path, sizeof(path), "/proc/self/fd/%d", ends[1]);
    int writer = open(path, O_WRONLY);
    valid = valid && writer >= 0 && write(writer, "x", 1) == 1 &&
            read(ends[0], &byte, 1) == 1 && byte == 'x';
    // Both write ends count: EOF only once the reopened one closes as well.
    close(ends[1]);
    valid = valid && write(writer, "y", 1) == 1 && read(ends[0], &byte, 1) == 1 && byte == 'y';
    if (writer >= 0)
        close(writer);
    valid = valid && read(ends[0], &byte, 1) == 0;
    snprintf(path, sizeof(path), "/proc/self/fd/%d", sockets[0]);
    valid = valid && failed_with_errno(open(path, O_RDWR), ENXIO, "reopen a socket");
    close(ends[0]);
    close(sockets[0]);
    close(sockets[1]);
    return valid;
}

// A handler installed without SA_RESTORER, as glibc installs every one on
// AArch64, with whatever its stack held left in sa_restorer: it returns
// through the kernel's rt_sigreturn trampoline.
static volatile sig_atomic_t saw_plain_handler;

static void plain_handler(int signal_number) {
    (void)signal_number;
    saw_plain_handler = 1;
}

// Giving up root while keeping capabilities, then setting the group ids
// with CAP_SETGID raised again, as setpriv --reuid --regid --clear-groups
// does. Without the capability the group ids stay put.
static int kept_capability_child(void) {
    struct __user_cap_header_struct header = {.version = _LINUX_CAPABILITY_VERSION_3};
    struct __user_cap_data_struct data[2];
    if (prctl(PR_SET_KEEPCAPS, 1, 0, 0, 0) != 0 || setresuid(1000, 1000, 1000) != 0 ||
        geteuid() != 1000)
        return 1;
    if (!failed_with_errno(setresgid(1000, 1000, 1000), EPERM, "setresgid without CAP_SETGID"))
        return 2;
    if (syscall(SYS_capget, &header, data) != 0 ||
        !(data[0].permitted & (1u << CAP_SETGID)))
        return 3;
    data[0].effective |= 1u << CAP_SETGID;
    if (syscall(SYS_capset, &header, data) != 0)
        return 4;
    gid_t none = 0;
    if (setresgid(1000, 1000, 1000) != 0 || getgid() != 1000 || getegid() != 1000 ||
        setgroups(0, &none) != 0 || getgroups(0, NULL) != 0)
        return 5;
    if (!failed_with_errno(setresuid(0, 0, 0), EPERM, "setresuid without CAP_SETUID"))
        return 6;
    return 0;
}

static int ids_with_kept_capabilities(void) {
    fflush(stdout);
    pid_t child = fork();
    if (child == 0)
        _exit(kept_capability_child());
    return security_child_succeeded(child);
}

// The line of /proc/self/maps or smaps whose mapping holds `address`, and
// with `field` the value of that field of it in smaps; -1 when not found.
static long mapping_line(const char *file, unsigned long address, char *line, size_t size,
                         const char *field) {
    FILE *maps = fopen(file, "r");
    if (!maps)
        return -1;
    int inside = 0;
    long value = -1;
    char buffer[512];
    while (fgets(buffer, sizeof(buffer), maps)) {
        unsigned long from, to;
        if (sscanf(buffer, "%lx-%lx", &from, &to) == 2) {
            if (inside && !field)
                break;
            inside = from <= address && address < to;
            if (inside && line)
                snprintf(line, size, "%s", buffer);
            if (inside && !field) {
                value = 0;
                break;
            }
        } else if (inside && field && !strncmp(buffer, field, strlen(field))) {
            sscanf(buffer + strlen(field), "%ld", &value);
            break;
        }
    }
    fclose(maps);
    return value;
}

// The page redis looks at before it starts: written, then shared with a
// child by fork, it has to count as shared and dirty in the child's smaps.
static int smaps_shared_dirty_child(char *page) {
    long shared = mapping_line("/proc/self/smaps", (unsigned long)page, NULL, 0, "Shared_Dirty:");
    long rss = mapping_line("/proc/self/smaps", (unsigned long)page, NULL, 0, "Rss:");
    if (shared != 4 || rss != 4) {
        printf("child smaps: Shared_Dirty=%ld Rss=%ld\n", shared, rss);
        fflush(stdout);
        return 1;
    }
    return 0;
}

static int process_maps(void) {
    long page = sysconf(_SC_PAGESIZE);
    char line[512];
    char *pages = mmap(NULL, 3 * page, PROT_READ, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (pages == MAP_FAILED || mprotect(pages + page, page, PROT_READ | PROT_WRITE) != 0)
        return 0;
    int stack_variable = 0;
    int valid = mapping_line("/proc/self/maps", (unsigned long)pages, line, sizeof(line), NULL) == 0 &&
                strstr(line, " r--p 00000000 00:00 0 ") != NULL;
    valid = valid &&
            mapping_line("/proc/self/maps", (unsigned long)(pages + page), line, sizeof(line), NULL) == 0 &&
            strstr(line, " rw-p ") != NULL;
    valid = valid &&
            mapping_line("/proc/self/maps", (unsigned long)&stack_variable, line, sizeof(line), NULL) == 0 &&
            strstr(line, "[stack]") != NULL;
    valid = valid &&
            mapping_line("/proc/self/maps", (unsigned long)process_maps, line, sizeof(line), NULL) == 0 &&
            strstr(line, "r-xp") != NULL && strstr(line, "syscall-smoke") != NULL;
    if (!valid)
        printf("maps line: %s", line);

    pages[page] = 1;
    long own = mapping_line("/proc/self/smaps", (unsigned long)(pages + page), NULL, 0, "Private_Dirty:");
    if (own != 4)
        printf("own smaps: Private_Dirty=%ld\n", own);
    valid = valid && own == 4;
    fflush(stdout);
    pid_t child = fork();
    if (child == 0)
        _exit(smaps_shared_dirty_child(pages + page));
    valid = security_child_succeeded(child) && valid;
    munmap(pages, 3 * page);
    return valid;
}

// Two datagrams sent with one sendmmsg(2) and taken with one recvmmsg(2),
// as glibc's resolver can send its A and AAAA queries.
static int multiple_messages(void) {
    int pair[2] = {socket(AF_INET, SOCK_DGRAM, 0), socket(AF_INET, SOCK_DGRAM, 0)};
    struct sockaddr_in address = {.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    socklen_t length = sizeof(address);
    if (pair[0] < 0 || pair[1] < 0 ||
        bind(pair[1], (struct sockaddr *)&address, sizeof(address)) != 0 ||
        getsockname(pair[1], (struct sockaddr *)&address, &length) != 0 ||
        connect(pair[0], (struct sockaddr *)&address, sizeof(address)) != 0) {
        printf("mmsg: udp setup errno=%d\n", errno);
        return 0;
    }
    char first[] = "first", second[] = "second-one";
    struct iovec out[2] = {{first, sizeof(first)}, {second, sizeof(second)}};
    struct mmsghdr sent[2];
    memset(sent, 0, sizeof(sent));
    sent[0].msg_hdr.msg_iov = &out[0];
    sent[0].msg_hdr.msg_iovlen = 1;
    sent[1].msg_hdr.msg_iov = &out[1];
    sent[1].msg_hdr.msg_iovlen = 1;
    int valid = sendmmsg(pair[0], sent, 2, 0) == 2 && sent[0].msg_len == sizeof(first) &&
                sent[1].msg_len == sizeof(second);
    char in_first[32] = {0}, in_second[32] = {0};
    struct iovec in[2] = {{in_first, sizeof(in_first)}, {in_second, sizeof(in_second)}};
    struct mmsghdr got[3];
    memset(got, 0, sizeof(got));
    got[0].msg_hdr.msg_iov = &in[0];
    got[0].msg_hdr.msg_iovlen = 1;
    got[1].msg_hdr.msg_iov = &in[1];
    got[1].msg_hdr.msg_iovlen = 1;
    got[2].msg_hdr.msg_iov = &in[1];
    got[2].msg_hdr.msg_iovlen = 1;
    int received = valid ? recvmmsg(pair[1], got, 3, MSG_WAITFORONE, NULL) : -1;
    valid = valid && received == 2 && got[0].msg_len == sizeof(first) &&
            got[1].msg_len == sizeof(second) && !strcmp(in_first, first) &&
            !strcmp(in_second, second);
    if (!valid)
        printf("mmsg: received=%d errno=%d lens=%u,%u\n", received, errno, got[0].msg_len,
               got[1].msg_len);
    close(pair[0]);
    close(pair[1]);
    return valid;
}

// futimens(2) is utimensat(2) with a null path, and a descriptor argument
// is an int whose register may hold anything above its low 32 bits: GNU tar
// relies on both when it extracts.
static int descriptor_arguments(void) {
    const char *dir = "/tmp/aarch64-syscall-fdcwd";
    const char *file = "/tmp/aarch64-syscall-futimens";
    rmdir(dir);
    long zero_extended = (long)(unsigned int)AT_FDCWD;
    int valid = syscall(SYS_mkdirat, zero_extended, dir, 0755) == 0 && access(dir, F_OK) == 0;
    rmdir(dir);
    int fd = open(file, O_CREAT | O_WRONLY | O_TRUNC, 0644);
    struct timespec times[2] = {{.tv_sec = 1000000000}, {.tv_sec = 1234567890}};
    struct stat st;
    valid = valid && fd >= 0 && futimens(fd, times) == 0 && fstat(fd, &st) == 0 &&
            st.st_mtim.tv_sec == 1234567890 && st.st_atim.tv_sec == 1000000000;
    if (!valid)
        printf("descriptor arguments: errno=%d\n", errno);
    if (fd >= 0)
        close(fd);
    unlink(file);
    return valid;
}

// mremap(2) moving an anonymous mapping into one that is filled in only as
// it is touched, and out of one with pages it never had, as apt grows its
// package cache. Mappings this large are not filled in up front.
static int mremap_sparse(void) {
    size_t small = 4096, large = 64 << 20;
    char *page = mmap(NULL, small, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (page == MAP_FAILED)
        return 0;
    page[0] = 42;
    char *grown = mremap(page, small, large, MREMAP_MAYMOVE);
    int valid = grown != MAP_FAILED && grown[0] == 42 && grown[large - 1] == 0;
    if (!valid) {
        printf("mremap into a sparse mapping: errno=%d\n", errno);
        return 0;
    }
    grown[large / 2] = 7;
    char *again = mremap(grown, large, large + small, MREMAP_MAYMOVE);
    valid = again != MAP_FAILED && again[0] == 42 && again[large / 2] == 7 && again[4096] == 0;
    if (!valid)
        printf("mremap out of a sparse mapping: errno=%d\n", errno);
    munmap(again != MAP_FAILED ? again : grown, again != MAP_FAILED ? large + small : large);
    return valid;
}

// SOCK_DGRAM sockets keep each datagram whole and send by address alone, as
// a syslog client does to /dev/log: a socketpair, a bound receiver an
// unbound sender reaches with sendto(2), and a sender connect(2) aims at it.
static int unix_datagrams(void) {
    const char *receiver_path = "/tmp/aarch64-syscall-dgram-receiver";
    const char *sender_path = "/tmp/aarch64-syscall-dgram-sender";
    char buffer[64];
    int pair[2];
    unlink(receiver_path);
    unlink(sender_path);
    if (socketpair(AF_UNIX, SOCK_DGRAM, 0, pair) != 0)
        return 0;
    int valid = send(pair[0], "a", 1, 0) == 1 && send(pair[0], "bb", 2, 0) == 2 &&
                recv(pair[1], buffer, sizeof(buffer), 0) == 1 && buffer[0] == 'a' &&
                recv(pair[1], buffer, sizeof(buffer), 0) == 2 && !memcmp(buffer, "bb", 2) &&
                send(pair[0], "", 0, 0) == 0 &&
                recv(pair[1], buffer, sizeof(buffer), MSG_DONTWAIT) == 0 &&
                failed_with_errno(recv(pair[1], buffer, sizeof(buffer), MSG_DONTWAIT), EAGAIN,
                                  "empty datagram queue");
    close(pair[0]);
    close(pair[1]);

    struct sockaddr_un receiver_address = {.sun_family = AF_UNIX};
    struct sockaddr_un sender_address = {.sun_family = AF_UNIX};
    snprintf(receiver_address.sun_path, sizeof(receiver_address.sun_path), "%s", receiver_path);
    snprintf(sender_address.sun_path, sizeof(sender_address.sun_path), "%s", sender_path);
    int receiver = socket(AF_UNIX, SOCK_DGRAM, 0);
    int anonymous = socket(AF_UNIX, SOCK_DGRAM, 0);
    int named = socket(AF_UNIX, SOCK_DGRAM, 0);
    struct sockaddr_un from;
    socklen_t from_length = sizeof(from);
    valid = valid && receiver >= 0 && anonymous >= 0 && named >= 0 &&
            bind(receiver, (struct sockaddr *)&receiver_address, sizeof(receiver_address)) == 0 &&
            sendto(anonymous, "hello", 5, 0, (struct sockaddr *)&receiver_address,
                   sizeof(receiver_address)) == 5 &&
            recvfrom(receiver, buffer, sizeof(buffer), 0, (struct sockaddr *)&from, &from_length) == 5 &&
            !memcmp(buffer, "hello", 5) && from_length == sizeof(sa_family_t);
    from_length = sizeof(from);
    struct sockaddr_un peer;
    socklen_t peer_length = sizeof(peer);
    valid = valid &&
            bind(named, (struct sockaddr *)&sender_address, sizeof(sender_address)) == 0 &&
            connect(named, (struct sockaddr *)&receiver_address, sizeof(receiver_address)) == 0 &&
            getpeername(named, (struct sockaddr *)&peer, &peer_length) == 0 &&
            !strcmp(peer.sun_path, receiver_path) && send(named, "x", 1, 0) == 1 &&
            recvfrom(receiver, buffer, sizeof(buffer), 0, (struct sockaddr *)&from, &from_length) == 1 &&
            !strcmp(from.sun_path, sender_path);
    if (receiver >= 0)
        close(receiver);
    valid = valid && failed_with_errno(send(named, "y", 1, 0), ECONNREFUSED,
                                       "datagram to a closed socket");
    if (!valid)
        printf("unix datagrams: errno=%d\n", errno);
    if (anonymous >= 0)
        close(anonymous);
    if (named >= 0)
        close(named);
    unlink(receiver_path);
    unlink(sender_path);
    return valid;
}

// The argument and environment strings lie as Linux lays them out: from
// argv[0] up, each right after the one before, the environment after the
// arguments. libuv sizes node's process title from this.
static int initial_strings(int argc, char **argv, char **envp) {
    char *expected = argv[0];
    for (int i = 0; i < argc; i++) {
        if (argv[i] != expected) {
            printf("argv[%d] at %p, expected %p\n", i, (void *)argv[i], (void *)expected);
            return 0;
        }
        expected += strlen(argv[i]) + 1;
    }
    for (int i = 0; envp[i]; i++) {
        if (envp[i] != expected) {
            printf("envp[%d] at %p, expected %p\n", i, (void *)envp[i], (void *)expected);
            return 0;
        }
        expected += strlen(envp[i]) + 1;
    }
    return 1;
}

static void *sigterm_waiter(void *result) {
    sigset_t set;
    sigemptyset(&set);
    sigaddset(&set, SIGTERM);
    int signal = 0;
    *(int *)result = sigwait(&set, &signal) == 0 ? signal : -1;
    return NULL;
}

// A blocked signal stays pending whatever its disposition, for sigwait(2)
// or signalfd(2) to take: SIGCHLD, ignored by default, and SIGUSR1 set to
// SIG_IGN. And one sent to the whole process reaches the thread that waits
// for it, as MariaDB stops its signal thread with kill(getpid(), SIGTERM)
// while every thread blocks SIGTERM.
static int blocked_ignored_signals(void) {
    sigset_t set, old;
    sigemptyset(&set);
    sigaddset(&set, SIGCHLD);
    sigaddset(&set, SIGUSR1);
    struct sigaction ignore = {.sa_handler = SIG_IGN}, previous_usr1, previous_chld;
    struct sigaction deflt = {.sa_handler = SIG_DFL};
    sigemptyset(&ignore.sa_mask);
    sigemptyset(&deflt.sa_mask);
    sigaction(SIGUSR1, &ignore, &previous_usr1);
    sigaction(SIGCHLD, &deflt, &previous_chld);
    sigprocmask(SIG_BLOCK, &set, &old);
    struct timespec wait = {.tv_sec = 5};
    raise(SIGUSR1);
    int valid = sigtimedwait(&set, NULL, &wait) == SIGUSR1;
    pid_t child = fork();
    if (child == 0)
        _exit(0);
    valid = valid && child > 0 && sigtimedwait(&set, NULL, &wait) == SIGCHLD;
    if (child > 0)
        waitpid(child, NULL, 0);

    sigset_t term;
    sigemptyset(&term);
    sigaddset(&term, SIGTERM);
    sigprocmask(SIG_BLOCK, &term, NULL);
    int received = 0;
    pthread_t waiter;
    if (valid && pthread_create(&waiter, NULL, sigterm_waiter, &received) == 0) {
        for (int i = 0; i < 50 && received == 0; i++) {
            kill(getpid(), SIGTERM);
            usleep(20000);
        }
        pthread_join(waiter, NULL);
        valid = received == SIGTERM;
        // A SIGTERM sent after the waiter took one is still pending here,
        // and would end the test once unblocked.
        struct timespec none = {0};
        while (sigtimedwait(&term, NULL, &none) == SIGTERM) {
        }
    } else {
        valid = 0;
    }
    if (!valid)
        printf("blocked ignored signals: errno=%d\n", errno);
    sigprocmask(SIG_SETMASK, &old, NULL);
    sigaction(SIGUSR1, &previous_usr1, NULL);
    sigaction(SIGCHLD, &previous_chld, NULL);
    return valid;
}

static int handler_without_restorer(void) {
    struct {
        void (*handler)(int);
        unsigned long flags;
        void *restorer;
        unsigned long mask;
    } action = {plain_handler, 0, (void *)(uintptr_t)0x1234, 0};
    if (syscall(SYS_rt_sigaction, SIGUSR2, &action, NULL, 8) != 0)
        return 0;
    saw_plain_handler = 0;
    raise(SIGUSR2);
    int valid = saw_plain_handler == 1;
    signal(SIGUSR2, SIG_DFL);
    return valid;
}

static void *eventfd_writer(void *argument) {
    int fd = *(int *)argument;
    struct timespec delay = {.tv_nsec = 10000000};
    nanosleep(&delay, NULL);
    eventfd_write(fd, 11);
    return NULL;
}

int main(int argc, char **argv, char **envp) {
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
    check(pipe_reopen(), "pipe reopened through /proc/self/fd");
    check(handler_without_restorer(), "signal handler without SA_RESTORER");
    check(ids_with_kept_capabilities(), "group ids set with CAP_SETGID after setuid");
    check(process_maps(), "/proc/self/maps and smaps");
    check(multiple_messages(), "sendmmsg and recvmmsg");
    check(descriptor_arguments(), "futimens and a zero-extended AT_FDCWD");
    check(mremap_sparse(), "mremap with pages not filled in");
    check(unix_datagrams(), "unix datagram sockets");
    check(initial_strings(argc, argv, envp), "argument and environment strings in order");
    check(blocked_ignored_signals(), "blocked signals kept whatever their disposition");
    int no_family[2];
    check(failed_with_errno(socket(AF_INET6, SOCK_STREAM, 0), EAFNOSUPPORT, "IPv6 socket") &&
              failed_with_errno(socketpair(AF_INET, SOCK_STREAM, 0, no_family), EOPNOTSUPP,
                                "IPv4 socketpair"),
          "socket families without sockets");
    if (chdir(previous_cwd) != 0)
        chdir("/");

    close(fd);
    unlink(path);
    unlink(copy_path);
    printf("AARCH64 SYSCALL SMOKE %s (%d failures)\n",
           failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
