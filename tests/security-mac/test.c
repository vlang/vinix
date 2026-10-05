#define _GNU_SOURCE
#include <errno.h>
#include <elf.h>
#include <pthread.h>
#include <sys/file.h>
#include <sys/inotify.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <sys/xattr.h>
#include <unistd.h>

#define OLD_MAP ((void *)(uintptr_t)0x680000000000ULL)
#define MAC_PRCTL 0x56584d41
#define INSPECT 1U
#define READ 2U
#define WRITE 4U
#define EXECUTE 8U
#define CREATE 16U
#define REMOVE 32U
#define METADATA 64U
#define IOCTL 128U
#define SEARCH 256U
#define ALL 511U
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "SECURITY MAC FAIL line %d: %s (errno=%d %s)\n", __LINE__, #c, errno, strerror(errno)); return 1; } } while (0)
#define DENIED(call) do { errno = 0; CHECK((call) == -1 && (errno == EACCES || errno == EPERM)); } while (0)

static long control(unsigned command, unsigned domain, unsigned type, unsigned mask)
{
    return prctl(MAC_PRCTL, (unsigned long)command, (unsigned long)domain,
                 (unsigned long)type, (unsigned long)mask);
}

static int label(const char *path, const char *value)
{
    return setxattr(path, "security.vinix", value, strlen(value), 0);
}

static int contents(const char *path, const char *value)
{
    int fd = open(path, O_CREAT | O_RDWR | O_TRUNC, 0755);
    if (fd < 0) return -1;
    ssize_t result = write(fd, value, strlen(value));
    int saved = errno;
    close(fd);
    errno = saved;
    return result == (ssize_t)strlen(value) ? 0 : -1;
}

static unsigned long long slab_class_bytes(unsigned wanted_size)
{
    char text[4096];
    int fd = open("/proc/slabinfo", O_RDONLY);
    if (fd < 0) return ~0ULL;
    ssize_t length = read(fd, text, sizeof(text) - 1);
    close(fd);
    if (length <= 0) return ~0ULL;
    text[length] = 0;
    unsigned long long total = 0;
    char *line = strtok(text, "\n");
    while (line) {
        unsigned long long size, live, pages;
        if (sscanf(line, "size-%*u %llu %llu %llu", &size, &live, &pages) == 3
            && (wanted_size == 0 || size == wanted_size)) total += size * live;
        line = strtok(NULL, "\n");
    }
    return total;
}

static unsigned long long slab_bytes(void) { return slab_class_bytes(0); }

static void *blocked_thread(void *argument)
{
    int fd = *(int *)argument;
    char byte;
    (void)read(fd, &byte, 1);
    return NULL;
}

static int prepare_interpreter_test(void)
{
    unsigned char image[4096] = {0};
    Elf64_Ehdr header = {0};
    memcpy(header.e_ident, ELFMAG, SELFMAG);
    header.e_ident[EI_CLASS] = ELFCLASS64;
    header.e_ident[EI_DATA] = ELFDATA2LSB;
    header.e_ident[EI_VERSION] = EV_CURRENT;
    header.e_type = ET_EXEC;
#if defined(__aarch64__)
    header.e_machine = EM_AARCH64;
#else
    header.e_machine = EM_X86_64;
#endif
    header.e_version = EV_CURRENT;
    header.e_entry = 0x400800;
    header.e_phoff = sizeof(header);
    header.e_ehsize = sizeof(header);
    header.e_phentsize = sizeof(Elf64_Phdr);
    header.e_phnum = 2;
    Elf64_Phdr program[2] = {{0}};
    const char interpreter[] = "/mac-private/exec-denied";
    program[0].p_type = PT_INTERP;
    program[0].p_offset = sizeof(header) + sizeof(program);
    program[0].p_filesz = sizeof(interpreter);
    program[1].p_type = PT_LOAD;
    program[1].p_flags = PF_R | PF_X;
    program[1].p_vaddr = 0x400000;
    program[1].p_filesz = sizeof(image);
    program[1].p_memsz = 16384;
    program[1].p_align = 16384;
    memcpy(image, &header, sizeof(header));
    memcpy(image + sizeof(header), program, sizeof(program));
    memcpy(image + program[0].p_offset, interpreter, sizeof(interpreter));
    int fd = open("/mac-private/dynamic", O_CREAT | O_WRONLY, 0755);
    if (fd < 0) return -1;
    ssize_t result = write(fd, image, sizeof(image));
    close(fd);
    return result == (ssize_t)sizeof(image) ? 0 : -1;
}

static int copy_program_to_memfd(void)
{
    int source = open("/sbin/init", O_RDONLY);
    if (source < 0) return -1;
    int target = syscall(SYS_memfd_create, "mac-program", MFD_CLOEXEC);
    if (target < 0) { close(source); return -1; }
    char bytes[4096];
    ssize_t length;
    while ((length = read(source, bytes, sizeof(bytes))) > 0) {
        if (write(target, bytes, (size_t)length) != length) { close(source); close(target); return -1; }
    }
    close(source);
    if (length < 0 || fchmod(target, 0755) != 0) { close(target); return -1; }
    return target;
}

static void *close_exec_descriptor(void *argument)
{
    int descriptor = *(int *)argument;
    // Let lookup enter the loader, then close its only userspace reference
    // while the ELF headers/segments are still being prepared.
    usleep(50);
    close(descriptor);
    return NULL;
}

static int test_exec_descriptor_close(void)
{
    int successful = 0;
    for (int iteration = 0; iteration < 16; iteration++) {
        pid_t child = fork();
        CHECK(child >= 0);
        if (child == 0) {
            int descriptor = copy_program_to_memfd();
            if (descriptor < 0 || control(3, 1, 0, 0) != 0) _exit(3);
            pthread_t closer;
            if (pthread_create(&closer, NULL, close_exec_descriptor, &descriptor) != 0) _exit(4);
            char *arguments[] = {"/sbin/init", "exec-race", NULL};
            syscall(SYS_execveat, descriptor, "", arguments, NULL, AT_EMPTY_PATH);
            int saved = errno;
            if (pthread_join(closer, NULL) != 0) _exit(5);
            // Closing before lookup is valid EBADF; a lookup that succeeds
            // must keep the image alive until its replacement mappings own it.
            _exit(saved == EBADF && control(0, 0, 0, 0) == 0 ? 2 : 6);
        }
        int status;
        CHECK(waitpid(child, &status, 0) == child && WIFEXITED(status));
        CHECK(WEXITSTATUS(status) == 0 || WEXITSTATUS(status) == 2);
        successful += WEXITSTATUS(status) == 0;
    }
    CHECK(successful > 0);
    printf("SECURITY MAC EXEC concurrent_close_successes=%d\n", successful);
    return 0;
}

struct mac_sched_attr {
    uint32_t size, policy;
    uint64_t flags;
    int32_t nice;
    uint32_t priority;
    uint64_t runtime, deadline, period;
};

static int denied_kernel_read(const char *path)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0) return errno == EACCES || errno == EPERM;
    char bytes[16];
    errno = 0;
    int denied = read(fd, bytes, sizeof(bytes)) == -1 && (errno == EACCES || errno == EPERM);
    close(fd);
    return denied;
}

static int send_fd(int channel, int descriptor)
{
    char byte = 'F';
    struct iovec vec = { &byte, 1 };
    union { struct cmsghdr align; unsigned char bytes[CMSG_SPACE(sizeof(int))]; } raw;
    memset(&raw, 0, sizeof(raw));
    struct msghdr message = {0};
    message.msg_iov = &vec;
    message.msg_iovlen = 1;
    message.msg_control = raw.bytes;
    message.msg_controllen = sizeof(raw.bytes);
    struct cmsghdr *c = CMSG_FIRSTHDR(&message);
    c->cmsg_level = SOL_SOCKET;
    c->cmsg_type = SCM_RIGHTS;
    c->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(c), &descriptor, sizeof(descriptor));
    return sendmsg(channel, &message, 0) == 1 ? 0 : -1;
}

static int receive_fd(int channel)
{
    char byte;
    struct iovec vec = { &byte, 1 };
    union { struct cmsghdr align; unsigned char bytes[CMSG_SPACE(sizeof(int))]; } raw;
    memset(&raw, 0, sizeof(raw));
    struct msghdr message = {0};
    message.msg_iov = &vec;
    message.msg_iovlen = 1;
    message.msg_control = raw.bytes;
    message.msg_controllen = sizeof(raw.bytes);
    if (recvmsg(channel, &message, 0) != 1) return -1;
    struct cmsghdr *c = CMSG_FIRSTHDR(&message);
    if (!c || c->cmsg_type != SCM_RIGHTS || c->cmsg_len != CMSG_LEN(sizeof(int))) return -1;
    int descriptor;
    memcpy(&descriptor, CMSG_DATA(c), sizeof(descriptor));
    return descriptor;
}

static int ipc_worker(int source, int sink)
{
    CHECK(control(0, 0, 0, 0) == 2);
    char bytes[4];
    DENIED(read(source, bytes, sizeof(bytes)));
    DENIED(write(sink, "bad!", 4));
    DENIED(syscall(SYS_tee, source, sink, 4, 0));
    struct iovec vector = {(void *)"bad!", 4};
    DENIED(syscall(SYS_vmsplice, sink, &vector, 1, 0));
    return 0;
}

static int test_pipe_transfer_policy(void)
{
    int source[2], sink[2];
    CHECK(pipe(source) == 0 && pipe2(sink, O_NONBLOCK) == 0);
    CHECK(write(source[1], "data", 4) == 4);
    pid_t child = fork();
    CHECK(child >= 0);
    if (child == 0) {
        char input[32], output[32];
        snprintf(input, sizeof(input), "%d", source[0]);
        snprintf(output, sizeof(output), "%d", sink[1]);
        char *arguments[] = {"/sbin/init", "ipc-worker", input, output, NULL};
        if (control(3, 2, 0, 0) != 0) _exit(2);
        execv("/sbin/init", arguments);
        _exit(3);
    }
    int status;
    CHECK(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    char bytes[4];
    CHECK(read(source[0], bytes, 4) == 4 && !memcmp(bytes, "data", 4));
    errno = 0; CHECK(read(sink[0], bytes, 4) == -1 && errno == EAGAIN);
    close(source[0]); close(source[1]); close(sink[0]); close(sink[1]);
    puts("SECURITY MAC IPC pipe transfers denied");
    return 0;
}

static int worker(int secret_fd, int readonly_fd, int channel, pid_t parent, uintptr_t address, int repeated)
{
    CHECK(geteuid() == 0);
    CHECK(control(0, 0, 0, 0) == 1);
    CHECK(control(4, 0, 0, 0) == 1);
    unsigned char resident;
    errno = 0; CHECK(mincore(OLD_MAP, 16384, &resident) == -1 && errno == ENOMEM);
    DENIED(control(1, 1, 2, ALL));
    DENIED(control(3, 2, 0, 0));
    DENIED(control(2, 0, 0, 0));
    DENIED(label("/mac-private", "0"));
    DENIED(removexattr("/mac-private", "security.vinix"));

    char buffer[16];
    struct stat metadata;
    DENIED(read(secret_fd, buffer, sizeof(buffer)));
    DENIED(pread(secret_fd, buffer, sizeof(buffer), 0));
    DENIED(write(secret_fd, "bad", 3));
    DENIED(pwrite(secret_fd, "bad", 3, 0));
    DENIED(ftruncate(secret_fd, 0));
    DENIED(fchmod(secret_fd, 0777));
    DENIED(fchown(secret_fd, 0, 0));
    DENIED(fstat(secret_fd, &metadata));
    DENIED(fstatat(secret_fd, "", &metadata, AT_EMPTY_PATH));
    DENIED(lseek(secret_fd, 0, SEEK_END));
    DENIED(flock(secret_fd, LOCK_EX | LOCK_NB));
    DENIED(fgetxattr(secret_fd, "security.vinix", buffer, sizeof(buffer)));
    DENIED(flistxattr(secret_fd, buffer, sizeof(buffer)));
    DENIED(fsetxattr(secret_fd, "user.x", "x", 1, 0));
    DENIED(futimens(secret_fd, NULL));
    int flags = 0;
    DENIED(ioctl(secret_fd, 0x80086601UL, &flags));
    errno = 0;
    CHECK(mmap(NULL, 16384, PROT_NONE, MAP_PRIVATE, secret_fd, 0) == MAP_FAILED && errno == EACCES);
    int duplicate = dup(secret_fd);
    CHECK(duplicate >= 0);
    DENIED(read(duplicate, buffer, 1));
    close(duplicate);
    DENIED(open("/mac-private/secret-alias", O_RDONLY));
    DENIED(open("/mac-bind/secret", O_RDONLY));
    DENIED(open("/mac-private/secret-symlink", O_RDONLY));
    DENIED(open("/mac-private/denied-link", O_RDONLY));
    DENIED(readlink("/mac-private/denied-link", buffer, sizeof(buffer)));
    DENIED(open("/mac-private/denied-directory/public", O_RDONLY));
    DENIED(link("/mac-private/secret-alias", "/mac-private/linked"));
    DENIED(unlink("/mac-private/secret-alias"));
    DENIED(rename("/mac-private/secret-alias", "/mac-private/moved"));
    DENIED(rename("/mac-private/replace", "/mac-private/secret-alias"));
    DENIED(access("/mac-private/secret-alias", R_OK));
    DENIED(open("/mac-secret/new", O_CREAT | O_WRONLY, 0600));

    CHECK(pread(readonly_fd, buffer, 6, 0) == 6 && memcmp(buffer, "public", 6) == 0);
    CHECK(fstat(readonly_fd, &metadata) == 0);
    DENIED(write(readonly_fd, "bad", 3));
    DENIED(pwrite(readonly_fd, "bad", 3, 0));
    DENIED(ftruncate(readonly_fd, 0));
    DENIED(fchmod(readonly_fd, 0777));
    DENIED(open("/mac-readonly/public", O_TRUNC | O_WRONLY));
    DENIED(unlink("/mac-readonly/public"));
    DENIED(link("/mac-readonly/public", "/mac-private/ro-linked"));
    void *mapped = mmap(NULL, 16384, PROT_READ, MAP_SHARED, readonly_fd, 0);
    CHECK(mapped != MAP_FAILED);
    DENIED(mprotect(mapped, 16384, PROT_READ | PROT_WRITE));
    DENIED(mprotect(mapped, 16384, PROT_READ | PROT_EXEC));
    CHECK(munmap(mapped, 16384) == 0);
    mapped = mmap(NULL, 16384, PROT_READ | PROT_WRITE, MAP_PRIVATE, readonly_fd, 0);
    CHECK(mapped != MAP_FAILED);
    CHECK(munmap(mapped, 16384) == 0);

    int output = open("/mac-private/output", O_CREAT | O_RDWR | O_TRUNC, 0600);
    CHECK(output >= 0);
    CHECK(write(output, "owned", 5) == 5);
    CHECK(getxattr("/mac-private/output", "security.vinix", buffer, sizeof(buffer)) == 1 && buffer[0] == '1');
    CHECK(mkdir("/mac-private/created", 0700) == 0 || errno == EEXIST);
    CHECK(getxattr("/mac-private/created", "security.vinix", buffer, sizeof(buffer)) == 1 && buffer[0] == '1');
    CHECK(link("/mac-private/output", "/mac-private/outlink") == 0 || errno == EEXIST);
    CHECK(rename("/mac-private/outlink", "/mac-private/movedlink") == 0);
    CHECK(unlink("/mac-private/movedlink") == 0);
    CHECK(symlink("output", "/mac-private/symlink") == 0 || errno == EEXIST);
    CHECK(lgetxattr("/mac-private/symlink", "security.vinix", buffer, sizeof(buffer)) == 1 && buffer[0] == '1');

    int overlay = open("/mac-overlay/owned", O_RDWR);
    CHECK(overlay >= 0 && write(overlay, "up", 2) == 2);
    CHECK(fgetxattr(overlay, "security.vinix", buffer, sizeof(buffer)) == 1 && buffer[0] == '1');
    close(overlay);
    DENIED(open("/mac-overlay/secret", O_RDWR));
    errno = 0; CHECK(open("/mac-upper/secret", O_RDONLY) == -1 && errno == ENOENT);

    off_t from = 0, to = 0;
    DENIED(syscall(SYS_copy_file_range, secret_fd, &from, output, &to, 3, 0));
    from = to = 0;
    DENIED(syscall(SYS_copy_file_range, readonly_fd, &from, secret_fd, &to, 3, 0));
    int pipes[2];
    CHECK(pipe(pipes) == 0);
    DENIED(fstat(pipes[0], &metadata));
    char anonymous_path[64];
    snprintf(anonymous_path, sizeof(anonymous_path), "/proc/self/fd/%d", pipes[0]);
    DENIED(stat(anonymous_path, &metadata));
    from = 0;
    DENIED(splice(secret_fd, &from, pipes[1], NULL, 3, 0));
    CHECK(write(pipes[1], "bad", 3) == 3);
    to = 0;
    DENIED(splice(pipes[0], NULL, readonly_fd, &to, 3, 0));
    close(pipes[0]); close(pipes[1]); close(output);

    CHECK(kill(parent, 0) == -1 && errno == EPERM);
    char proc_path[64];
    snprintf(proc_path, sizeof(proc_path), "/proc/%d/maps", (int)parent);
    int proc_fd = open(proc_path, O_RDONLY);
    if (proc_fd >= 0) { DENIED(read(proc_fd, buffer, sizeof(buffer))); close(proc_fd); }
    else CHECK(errno == EACCES || errno == EPERM);
    struct iovec local = { buffer, 1 }, remote = { (void *)address, 1 };
    DENIED(process_vm_readv(parent, &local, 1, &remote, 1, 0));
    DENIED(mount("tmpfs", "/mac-private", "tmpfs", 0, NULL));
    DENIED(mknod("/mac-private/device", S_IFBLK | 0600, 0));
    DENIED(open("/mac-private/raw", O_RDONLY));
    char *bad_argv[] = { "/mac-private/exec-denied", NULL };
    DENIED(execv("/mac-private/exec-denied", bad_argv));
    DENIED(execv("/mac-private/shebang", bad_argv));
    DENIED(execv("/mac-private/dynamic", bad_argv));
    DENIED(execv("/mac-private/denied-executable", bad_argv));
    DENIED(sethostname("confined", 8));
    CHECK(denied_kernel_read("/proc/security_audit"));
    struct rlimit limit = {128, 128}, old_limit;
    DENIED(prlimit(parent, RLIMIT_NOFILE, NULL, &old_limit));
    DENIED(prlimit(parent, RLIMIT_NOFILE, &limit, NULL));
    DENIED(setpriority(PRIO_PROCESS, (id_t)parent, 0));
    DENIED(getpriority(PRIO_PROCESS, (id_t)parent));
    CHECK(prlimit(0, RLIMIT_NOFILE, NULL, &old_limit) == 0);
    errno = 0; CHECK(getpriority(PRIO_PROCESS, 0) == 0 && errno == 0);
    CHECK(setpriority(PRIO_PROCESS, 0, 0) == 0);
    struct sched_param parameters = {0};
    DENIED(syscall(SYS_sched_getscheduler, parent));
    DENIED(syscall(SYS_sched_getparam, parent, &parameters));
    DENIED(syscall(SYS_sched_setscheduler, parent, SCHED_OTHER, &parameters));
    DENIED(syscall(SYS_sched_setparam, parent, &parameters));
    CHECK(syscall(SYS_sched_getscheduler, 0) == SCHED_OTHER);
    CHECK(syscall(SYS_sched_getparam, 0, &parameters) == 0);
    CHECK(syscall(SYS_sched_setscheduler, 0, SCHED_OTHER, &parameters) == 0);
    struct mac_sched_attr scheduling = {.size = sizeof(scheduling)};
    DENIED(syscall(SYS_sched_getattr, parent, &scheduling, sizeof(scheduling), 0));
    DENIED(syscall(SYS_sched_setattr, parent, &scheduling, 0));
    scheduling.policy = 6; scheduling.runtime = 1000; scheduling.deadline = 1000000; scheduling.period = 1000000;
    DENIED(syscall(SYS_sched_setattr, parent, &scheduling, 0));
    cpu_set_t affinity;
    CPU_ZERO(&affinity); CPU_SET(0, &affinity);
    DENIED(sched_getaffinity(parent, sizeof(affinity), &affinity));
    DENIED(sched_setaffinity(parent, sizeof(affinity), &affinity));
    CHECK(sched_getaffinity(0, sizeof(affinity), &affinity) == 0);
    CHECK(sched_setaffinity(0, sizeof(affinity), &affinity) == 0);
    void *robust_head;
    size_t robust_length;
    DENIED(syscall(SYS_get_robust_list, parent, &robust_head, &robust_length));
    CHECK(syscall(SYS_get_robust_list, 0, &robust_head, &robust_length) == 0);
    DENIED(getpgid(parent));
    DENIED(setpgid(parent, parent));
    CHECK(getpgid(0) >= 0);

    if (!repeated) {
        int passed = receive_fd(channel);
        CHECK(passed >= 0);
        DENIED(read(passed, buffer, 1));
        close(passed);
        passed = receive_fd(channel);
        CHECK(passed >= 0);
        DENIED(read(passed, buffer, sizeof(buffer)));
        DENIED(inotify_rm_watch(passed, 1));
        DENIED(inotify_add_watch(passed, "/mac-private", IN_CREATE));
        close(passed);
        passed = receive_fd(channel);
        CHECK(passed >= 0);
        char *memfd_arguments[] = {"mac-denied", NULL};
        DENIED(syscall(SYS_execveat, passed, "", memfd_arguments, NULL, AT_EMPTY_PATH));
        close(passed);
        passed = receive_fd(channel);
        CHECK(passed >= 0 && lseek(passed, 0, SEEK_SET) == 0);
        DENIED(read(passed, buffer, sizeof(buffer)));
        close(passed);
        for (int i = 0; i < 20; i++) CHECK(slab_bytes() != ~0ULL);
        unsigned long long before = slab_bytes();
        for (int i = 0; i < 1000; i++) {
            int repeated_fd = open("/mac-private/output", O_RDONLY);
            CHECK(repeated_fd >= 0 && read(repeated_fd, buffer, 5) == 5);
            close(repeated_fd);
            DENIED(pread(secret_fd, buffer, 1, 0));
            CHECK(pread(readonly_fd, buffer, 6, 0) == 6);
            DENIED(prlimit(parent, RLIMIT_NOFILE, NULL, &old_limit));
            CHECK(prlimit(0, RLIMIT_NOFILE, NULL, &old_limit) == 0);
            DENIED(syscall(SYS_get_robust_list, parent, &robust_head, &robust_length));
            CHECK(syscall(SYS_sched_getscheduler, 0) == SCHED_OTHER);
        }
        unsigned long long after = slab_bytes();
        printf("SECURITY MAC OPS retained_bytes=%lld\n", (long long)(after - before));
        CHECK(after <= before + 1024);
        // FIFO destruction releases its one stored Resource interface box.
        // The pre-existing unretired FIFO VFS node belongs to another class;
        // this specifically detects allocating an orphan second box per FIFO.
        for (int i = 0; i < 20; i++) {
            CHECK(mkfifo("/mac-private/temporary-fifo", 0600) == 0);
            CHECK(unlink("/mac-private/temporary-fifo") == 0);
        }
        before = slab_class_bytes(512);
        for (int i = 0; i < 200; i++) {
            CHECK(mkfifo("/mac-private/temporary-fifo", 0600) == 0);
            CHECK(unlink("/mac-private/temporary-fifo") == 0);
        }
        after = slab_class_bytes(512);
        printf("SECURITY MAC FIFO interface_bytes=%lld\n", (long long)(after - before));
        CHECK(after <= before + 512);
        pid_t nested = fork();
        CHECK(nested >= 0);
        if (nested == 0) {
            if (control(0, 0, 0, 0) != 1 || pread(secret_fd, buffer, 1, 0) != -1 || errno != EACCES) _exit(1);
            _exit(0);
        }
        int status;
        CHECK(waitpid(nested, &status, 0) == nested && WIFEXITED(status) && WEXITSTATUS(status) == 0);
        // Re-exec keeps the domain and old denied descriptors.
        char a[32], b[32], c[32], d[32], e[32];
        snprintf(a, sizeof(a), "%d", secret_fd);
        snprintf(b, sizeof(b), "%d", readonly_fd);
        snprintf(c, sizeof(c), "%d", channel);
        snprintf(d, sizeof(d), "%d", (int)parent);
        snprintf(e, sizeof(e), "%llu", (unsigned long long)address);
        char *args[] = { "/sbin/init", "worker-again", a, b, c, d, e, NULL };
        execv("/sbin/init", args);
        CHECK(0);
    }
    close(secret_fd); close(readonly_fd); close(channel);
    return 0;
}

int main(int argc, char **argv)
{
    setbuf(stdout, NULL);
    if (argc == 4 && !strcmp(argv[1], "ipc-worker")) _exit(ipc_worker(atoi(argv[2]), atoi(argv[3])));
    if (argc == 2 && !strcmp(argv[1], "exec-race")) _exit(control(0, 0, 0, 0) == 1 ? 0 : 1);
    if (argc == 7 && (!strcmp(argv[1], "worker") || !strcmp(argv[1], "worker-again"))) {
        int result = worker(atoi(argv[2]), atoi(argv[3]), atoi(argv[4]), (pid_t)atoi(argv[5]),
                            (uintptr_t)strtoull(argv[6], NULL, 10), !strcmp(argv[1], "worker-again"));
        _exit(result);
    }
    CHECK(control(0, 0, 0, 0) == 0);
    CHECK(control(4, 0, 0, 0) == 0);
    DENIED(control(3, 1, 0, 0));
    CHECK(mkdir("/mac-private", 0700) == 0);
    CHECK(mkdir("/mac-secret", 0700) == 0);
    CHECK(mkdir("/mac-readonly", 0700) == 0);
    CHECK(mkdir("/mac-bind", 0700) == 0);
    CHECK(label("/mac-private", "1") == 0);
    CHECK(label("/mac-secret", "2") == 0);
    CHECK(label("/mac-readonly", "3") == 0);
    errno = 0; CHECK(label("/mac-private", "01") == -1 && errno == EINVAL);
    errno = 0; CHECK(label("/mac-private", "31") == -1 && errno == EINVAL);
    errno = 0; CHECK(label("/mac-private", "malformed") == -1 && errno == EINVAL);
    CHECK(contents("/mac-secret/secret", "secret") == 0);
    CHECK(contents("/mac-readonly/public", "public") == 0);
    CHECK(contents("/mac-private/replace", "replace") == 0);
    CHECK(contents("/mac-private/exec-denied", "not an executable") == 0);
    CHECK(label("/mac-private/exec-denied", "4") == 0);
    CHECK(contents("/mac-private/shebang", "#!/mac-private/exec-denied\n") == 0);
    CHECK(prepare_interpreter_test() == 0);
    CHECK(mknod("/mac-private/raw", S_IFBLK | 0600, 0) == 0);
    CHECK(link("/mac-secret/secret", "/mac-private/secret-alias") == 0);
    CHECK(symlink("/mac-secret/secret", "/mac-private/secret-symlink") == 0);
    CHECK(symlink("/mac-readonly/public", "/mac-private/denied-link") == 0);
    CHECK(symlink("/mac-readonly", "/mac-private/denied-directory") == 0);
    CHECK(symlink("/sbin/init", "/mac-private/denied-executable") == 0);
    CHECK(lsetxattr("/mac-private/denied-link", "security.vinix", "2", 1, 0) == 0);
    CHECK(lsetxattr("/mac-private/denied-directory", "security.vinix", "2", 1, 0) == 0);
    CHECK(lsetxattr("/mac-private/denied-executable", "security.vinix", "2", 1, 0) == 0);
    CHECK(mount("/mac-secret", "/mac-bind", NULL, MS_BIND, NULL) == 0);
    CHECK(mkdir("/mac-lower", 0700) == 0);
    CHECK(mkdir("/mac-upper", 0700) == 0);
    CHECK(mkdir("/mac-work", 0700) == 0);
    CHECK(mkdir("/mac-overlay", 0700) == 0);
    CHECK(label("/mac-lower", "1") == 0);
    CHECK(label("/mac-upper", "1") == 0);
    CHECK(label("/mac-work", "1") == 0);
    CHECK(contents("/mac-lower/owned", "lower") == 0);
    CHECK(contents("/mac-lower/secret", "secret") == 0);
    CHECK(label("/mac-lower/secret", "2") == 0);
    CHECK(mount("overlay", "/mac-overlay", "overlay", 0,
                "lowerdir=/mac-lower,upperdir=/mac-upper,workdir=/mac-work") == 0);

    pid_t userns = fork();
    CHECK(userns >= 0);
    if (userns == 0) {
        if (unshare(CLONE_NEWUSER) != 0) _exit(2);
        errno = 0;
        if (label("/mac-private", "0") != -1 || errno != EPERM) _exit(3);
        errno = 0;
        if (control(1, 1, 2, ALL) != -1 || errno != EPERM) _exit(4);
        _exit(0);
    }
    int status;
    CHECK(waitpid(userns, &status, 0) == userns && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK(control(1, 1, 0, INSPECT | READ | EXECUTE | SEARCH) == 0);
    CHECK(control(1, 1, 1, ALL) == 0);
    CHECK(control(1, 1, 3, INSPECT | READ | SEARCH) == 0);
    CHECK(control(1, 1, 29, ALL & ~INSPECT) == 0);
    CHECK(control(1, 1, 30, INSPECT | READ | WRITE | IOCTL) == 0);
    CHECK(control(1, 1, 31, INSPECT | READ | SEARCH) == 0);
    CHECK(control(1, 2, 0, INSPECT | READ | EXECUTE | SEARCH) == 0);
    CHECK(control(1, 2, 30, INSPECT | READ | WRITE | IOCTL) == 0);
    CHECK(control(1, 2, 31, INSPECT | READ | SEARCH) == 0);
    int denied_memfd = syscall(SYS_memfd_create, "mac-denied", 0);
    CHECK(denied_memfd >= 0 && write(denied_memfd, "not ELF", 7) == 7 && fchmod(denied_memfd, 0755) == 0);
    CHECK(fsetxattr(denied_memfd, "security.vinix", "4", 1, 0) == 0);
    int executable_memfd = copy_program_to_memfd();
    CHECK(executable_memfd >= 0);
    int audit_fd = open("/proc/security_audit", O_RDONLY);
    char audit_header[16];
    CHECK(audit_fd >= 0 && read(audit_fd, audit_header, sizeof(audit_header)) > 0);
    CHECK(control(2, 0, 0, 0) == 0);
    DENIED(control(1, 1, 2, ALL));
    DENIED(label("/mac-private", "0"));
    DENIED(removexattr("/mac-secret", "security.vinix"));
    CHECK(test_exec_descriptor_close() == 0);
    CHECK(test_pipe_transfer_policy() == 0);
    int secret = open("/mac-secret/secret", O_RDWR);
    int readonly = open("/mac-readonly/public", O_RDWR);
    CHECK(secret >= 0 && readonly >= 0);
    int watch = inotify_init1(IN_NONBLOCK);
    CHECK(watch >= 0 && inotify_add_watch(watch, "/mac-secret", IN_CREATE) >= 0);
    CHECK(contents("/mac-secret/event", "hidden") == 0);
    CHECK(mmap(OLD_MAP, 16384, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED_NOREPLACE, secret, 0) == OLD_MAP);
    int pipes_for_thread[2];
    CHECK(pipe(pipes_for_thread) == 0);
    pthread_t extra;
    CHECK(pthread_create(&extra, NULL, blocked_thread, &pipes_for_thread[0]) == 0);
    errno = 0; CHECK(control(3, 1, 0, 0) == -1 && errno == EBUSY);
    CHECK(write(pipes_for_thread[1], "x", 1) == 1 && pthread_join(extra, NULL) == 0);
    close(pipes_for_thread[0]); close(pipes_for_thread[1]);
    int channels[2];
    CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, channels) == 0);
    char parent_data = 'S';
    pid_t child = fork();
    CHECK(child >= 0);
    if (child == 0) {
        close(channels[0]);
        if (control(3, 1, 0, 0) != 0) _exit(5);
        if (control(0, 0, 0, 0) != 0) _exit(6);
        char *denied_args[] = { "/mac-private/exec-denied", NULL };
        errno = 0;
        if (execv("/mac-private/exec-denied", denied_args) != -1 || errno != EACCES || control(0, 0, 0, 0) != 0) _exit(8);
        char a[32], b[32], c[32], d[32], e[32];
        snprintf(a, sizeof(a), "%d", secret);
        snprintf(b, sizeof(b), "%d", readonly);
        snprintf(c, sizeof(c), "%d", channels[1]);
        snprintf(d, sizeof(d), "%d", (int)getppid());
        snprintf(e, sizeof(e), "%llu", (unsigned long long)(uintptr_t)&parent_data);
        char *args[] = { "/sbin/init", "worker", a, b, c, d, e, NULL };
        syscall(SYS_execveat, executable_memfd, "", args, NULL, AT_EMPTY_PATH);
        fprintf(stderr, "SECURITY MAC FAIL exec: %s\n", strerror(errno));
        _exit(7);
    }
    struct rlimit held_limit;
    CHECK(prlimit(child, RLIMIT_NOFILE, NULL, &held_limit) == 0);
    CHECK(prlimit(child, RLIMIT_NOFILE, &held_limit, NULL) == 0);
    errno = 0; CHECK(prlimit(child, RLIMIT_NOFILE, NULL, (struct rlimit *)(uintptr_t)1) == -1 && errno == EFAULT);
    close(channels[1]);
    close(executable_memfd);
    CHECK(send_fd(channels[0], secret) == 0);
    CHECK(send_fd(channels[0], watch) == 0);
    CHECK(send_fd(channels[0], denied_memfd) == 0);
    CHECK(send_fd(channels[0], audit_fd) == 0);
    CHECK(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    char original[8];
    CHECK(pread(secret, original, 6, 0) == 6 && memcmp(original, "secret", 6) == 0);
    CHECK(pread(readonly, original, 6, 0) == 6 && memcmp(original, "public", 6) == 0);
    CHECK(munmap(OLD_MAP, 16384) == 0);
    close(secret); close(readonly); close(channels[0]); close(watch); close(denied_memfd); close(audit_fd);
    puts("SECURITY MAC PASS");
    return 0;
}
