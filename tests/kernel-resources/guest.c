/* Exhaust user-created kernel resources; failure must leave close/unmap/exit
 * usable and the next workload must succeed. All storage is disposable. */
#define _GNU_SOURCE
#include <errno.h>
#include <elf.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdint.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/inotify.h>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/msg.h>
#include <sys/syscall.h>
#include <sys/resource.h>
#include <sys/sem.h>
#include <sys/shm.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/xattr.h>
#include <unistd.h>

#define MAX 16384
static int ids[MAX];
static void *maps[MAX];
static size_t page;
static void check(int ok, const char *why) {
    if (ok) return;
    printf("KRES FAIL %s errno=%d\n", why, errno); fflush(stdout); _exit(1);
}
static void denied(const char *why) {
    check(errno == ENOMEM || errno == ENOSPC || errno == EMFILE || errno == ENFILE || errno == EAGAIN || errno == ENOBUFS, why);
}
static void descriptors(void) {
    struct rlimit limit = {1048576, 1048576};
    check(setrlimit(RLIMIT_NOFILE, &limit) == 0, "raise descriptor limit");
    int fd = open("/dev/null", O_RDONLY); check(fd >= 0, "open null");
    int n = 0, next = fd + 1;
    for (; n < 65536; ++n) {
        int copy = fcntl(fd, F_DUPFD, next);
        if (copy < 0) { denied("descriptor exhaustion"); break; }
        next = copy + 1;
    }
    check(n > 0 && n < 65536, "descriptor bound reached");
    for (int copy = fd + 1; copy < next; ++copy) check(close(copy) == 0, "close descriptor at limit");
    close(fd);
}
static void mappings(void) {
    unsigned char *split = mmap(NULL, page * 3, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    check(split != MAP_FAILED, "split quota setup"); split[0] = 51; split[page * 2] = 52;
    int n = 0;
    for (; n < MAX; ++n) {
        maps[n] = mmap(NULL, page, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (maps[n] == MAP_FAILED) { denied("mapping exhaustion"); break; }
    }
    check(n > 0 && n < MAX, "mapping bound reached");
    check(mprotect(split + page, page, PROT_READ) != 0 && errno == ENOMEM, "denied protection split");
    split[0] = 61; split[page] = 62; split[page * 2] = 63;
    check(split[0] == 61 && split[page * 2] == 63, "denied split preserves permissions and contents");
    for (int i = 0; i < n; ++i) check(munmap(maps[i], page) == 0, "unmap at limit");
    check(munmap(split, page * 3) == 0, "release quota split");
    unsigned char *p = mmap(NULL, page * 3, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    check(p != MAP_FAILED, "mapping recovery"); p[0] = 41; p[page * 2] = 42;
    check(mprotect(p + page, page, PROT_READ) == 0, "split protections");
    check(p[0] == 41 && p[page * 2] == 42, "split contents");
    check(munmap(p, page * 3) == 0, "release split mappings");
}
static void files(void) {
    char path[80]; int n = 0;
    for (; n < MAX; ++n) {
        snprintf(path, sizeof path, "/tmp/budget-%d-%d", getpid(), n);
        int fd = open(path, O_CREAT | O_EXCL | O_WRONLY, 0600);
        if (fd < 0) { denied("file exhaustion"); unlink(path); break; }
        close(fd);
    }
    check(n > 0 && n < MAX, "file bound reached");
    for (int i = 0; i < n; ++i) {
        snprintf(path, sizeof path, "/tmp/budget-%d-%d", getpid(), i);
        check(unlink(path) == 0, "unlink at limit");
    }
}
static void sockets(void) {
    int n = 0;
    struct rlimit limit = {65536, 1048576}; check(setrlimit(RLIMIT_NOFILE, &limit) == 0, "socket fd limit");
    for (; n < MAX; ++n) {
        ids[n] = socket(AF_UNIX, SOCK_DGRAM, 0);
        if (ids[n] < 0) { denied("socket exhaustion"); break; }
    }
    check(n > 0 && n < MAX, "socket bound reached");
    for (int i = 0; i < n; ++i) check(close(ids[i]) == 0, "close sockets at limit");
}
static void records(void) {
    int pair[2]; check(socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_NONBLOCK, 0, pair) == 0, "record pair");
    int n = 0;
    for (; n < MAX; ++n) if (send(pair[0], "", 0, 0) < 0) { denied("empty record exhaustion"); break; }
    check(n > 0 && n < MAX, "empty records bounded");
    for (int i = 0; i < n; ++i) check(recv(pair[1], ids, sizeof(int), 0) == 0, "consume empty record");
    check(send(pair[0], "x", 1, 0) == 1, "record capacity reused");
    check(recv(pair[1], ids, sizeof(int), 0) == 1, "record recovery");
    close(pair[0]); close(pair[1]);
}
static void semaphores(void) {
    int n = 0;
    for (; n < MAX; ++n) {
        ids[n] = semget(IPC_PRIVATE, 32, IPC_CREAT | 0600);
        if (ids[n] < 0) { denied("semaphore exhaustion"); break; }
    }
    check(n > 0 && n < MAX, "semaphore bound reached");
    for (int i = 0; i < n; ++i) check(semctl(ids[i], 0, IPC_RMID) == 0, "remove semaphores");
}
static void shared_memory(void) {
    int id = shmget(IPC_PRIVATE, page * 3, IPC_CREAT | 0600); check(id >= 0, "shared segment");
    unsigned char *p = shmat(id, NULL, 0); check(p != (void *)-1, "attach segment");
    p[0] = 73;
    check(shmctl(id, IPC_RMID, NULL) == 0, "remove attached segment");
    check(p[0] == 73, "removed segment remains mapped");
    check(shmdt(p) == 0, "final shared detach");
    int n = 0;
    for (; n < MAX; ++n) {
        ids[n] = shmget(IPC_PRIVATE, page, IPC_CREAT | 0600);
        if (ids[n] < 0) { denied("shared memory exhaustion"); break; }
    }
    check(n > 0 && n < MAX, "shared memory bound reached");
    for (int i = 0; i < n; ++i) check(shmctl(ids[i], IPC_RMID, NULL) == 0, "remove shared segments");
}
static void messages(void) {
    int id = msgget(IPC_PRIVATE, IPC_CREAT | 0600); check(id >= 0, "message queue");
    struct { long kind; unsigned char data[8192]; } msg = { .kind = 1 };
    for (int i = 0; i < 2; ++i) check(msgsnd(id, &msg, sizeof msg.data, IPC_NOWAIT) == 0, "enqueue message");
    check(msgsnd(id, &msg, 1, IPC_NOWAIT) < 0 && errno == EAGAIN, "full queue failure");
    check(msgrcv(id, &msg, sizeof msg.data, 0, IPC_NOWAIT) == (ssize_t)sizeof msg.data, "receive queued message");
    check(msgctl(id, IPC_RMID, NULL) == 0, "remove nonempty queue");
}
static void attributes(void) {
    char name[64];
    int fd = open("/tmp/budget-xattrs", O_CREAT | O_RDWR | O_TRUNC, 0600); check(fd >= 0, "attribute file");
    int n = 0;
    for (; n < MAX; ++n) {
        snprintf(name, sizeof name, "user.attribute%d", n);
        if (fsetxattr(fd, name, "value", 5, 0) != 0) { denied("attribute exhaustion"); break; }
    }
    check(n > 0 && n < MAX, "attributes bounded");
    for (int i = 0; i < n; ++i) {
        snprintf(name, sizeof name, "user.attribute%d", i); check(fremovexattr(fd, name) == 0, "remove attribute");
    }
    close(fd); check(unlink("/tmp/budget-xattrs") == 0, "unlink attributes");
}
static void watches(void) {
    int n = 0;
    for (; n < MAX; ++n) {
        ids[n] = inotify_init1(IN_NONBLOCK);
        if (ids[n] < 0) { denied("inotify exhaustion"); break; }
    }
    check(n > 0 && n < MAX, "inotify bound reached");
    for (int i = 0; i < n; ++i) close(ids[i]);
    int ep = epoll_create1(0), pair[2]; check(ep >= 0 && pipe(pair) == 0, "epoll recovery");
    struct epoll_event ev = { .events = EPOLLIN };
    for (int i = 0; i < 200; ++i) {
        check(epoll_ctl(ep, EPOLL_CTL_ADD, pair[0], &ev) == 0, "epoll add");
        check(epoll_ctl(ep, EPOLL_CTL_DEL, pair[0], NULL) == 0, "epoll del");
    }
    close(pair[0]); close(pair[1]); close(ep);
}
static volatile int release_threads;
static void *worker(void *unused) { (void)unused; while (!release_threads) usleep(10000); return NULL; }
static void threads(void) {
    pthread_t workers[2048]; int n = 0;
    for (; n < 2048; ++n) {
        int error = pthread_create(&workers[n], NULL, worker, NULL);
        if (error) { check(error == EAGAIN || error == ENOMEM, "thread exhaustion errno"); break; }
    }
    check(n > 0 && n < 2048, "threads bounded"); release_threads = 1;
    for (int i = 0; i < n; ++i) check(pthread_join(workers[i], NULL) == 0, "join threads at limit");
}
static void processes(void) {
    int n = 0;
    for (; n < 512; ++n) {
        int pid = fork();
        if (pid < 0) { denied("process exhaustion"); break; }
        if (!pid) { for (;;) pause(); }
        ids[n] = pid;
    }
    check(n > 0 && n < 512, "processes bounded");
    for (int i = 0; i < n; ++i) { kill(ids[i], SIGKILL); check(waitpid(ids[i], NULL, 0) == ids[i], "reap at limit"); }
}


static void exec_failures(void) {
    Elf64_Ehdr header = { .e_type = ET_EXEC, .e_version = EV_CURRENT, .e_entry = 0x200000,
        .e_phoff = sizeof(Elf64_Ehdr), .e_ehsize = sizeof(Elf64_Ehdr), .e_phentsize = sizeof(Elf64_Phdr), .e_phnum = 1 };
    memcpy(header.e_ident, ELFMAG, SELFMAG); header.e_ident[EI_CLASS] = ELFCLASS64; header.e_ident[EI_DATA] = ELFDATA2LSB; header.e_ident[EI_VERSION] = EV_CURRENT;
#ifdef __aarch64__
    header.e_machine = EM_AARCH64;
#else
    header.e_machine = EM_X86_64;
#endif
    Elf64_Phdr segment = { .p_type = PT_LOAD, .p_flags = PF_R | PF_X, .p_offset = 0x10000000,
        .p_vaddr = 0x200000, .p_filesz = 4096, .p_memsz = 4096, .p_align = 4096 };
    int fd = open("/tmp/budget-bad-elf", O_CREAT | O_WRONLY | O_TRUNC, 0755); check(fd >= 0, "bad ELF fixture");
    check(write(fd, &header, sizeof header) == sizeof header && write(fd, &segment, sizeof segment) == sizeof segment, "write bad ELF"); close(fd);
    for (int i = 0; i < 30; ++i) {
        int child = fork(); check(child >= 0, "failed exec child");
        if (!child) { char *args[] = { "bad ELF", NULL }; execv("/tmp/budget-bad-elf", args); check(errno == ENOEXEC || errno == ENOMEM, "ELF rejection"); _exit(0); }
        int status; check(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0, "failed exec rollback");
    }
    check(unlink("/tmp/budget-bad-elf") == 0, "remove bad ELF");
}
static void write_script(const char *path, const char *text, size_t len) {
    int fd = open(path, O_CREAT | O_TRUNC | O_WRONLY, 0755); check(fd >= 0, "script fixture");
    check(write(fd, text, len) == (ssize_t)len, "write script"); close(fd);
}
static void scripts(void) {
    const char eof[] = "#!/sbin/init --shebang-ok";
    const char cycle[] = "#!/tmp/budget-cycle";
    char long_header[300]; memset(long_header, 'x', sizeof long_header); memcpy(long_header, "#!/", 3);
    write_script("/tmp/budget-eof", eof, sizeof eof - 1);
    write_script("/tmp/budget-cycle", cycle, sizeof cycle - 1);
    write_script("/tmp/budget-long", long_header, sizeof long_header);
    const char *paths[] = {"/tmp/budget-eof", "/tmp/budget-cycle", "/tmp/budget-long"};
    for (int i = 0; i < 3; ++i) {
        int child = fork(); check(child >= 0, "script child");
        if (!child) {
            char *args[] = {(char *)paths[i], NULL}; execv(paths[i], args);
            check(i > 0 && errno == (i == 1 ? ELOOP : ENOEXEC), "bounded script rejection"); _exit(0);
        }
        int status; check(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0, "script EOF and recursion");
        check(unlink(paths[i]) == 0, "remove script");
    }
}
static void fifo_lifetimes(void) {
    for (int i = 0; i < 30; ++i) {
        check(mkfifo("/tmp/budget-fifo", 0600) == 0, "FIFO fixture");
        int ready[2]; check(pipe(ready) == 0, "FIFO coordination");
        int child = fork(); check(child >= 0, "FIFO child");
        if (!child) {
            close(ready[0]); check(write(ready[1], "r", 1) == 1, "FIFO reader ready"); close(ready[1]);
            int fd = open("/tmp/budget-fifo", O_RDONLY); check(fd >= 0, "blocking FIFO open");
            char byte; check(read(fd, &byte, 1) == 1 && byte == 'f', "unlinked FIFO contents"); close(fd); _exit(0);
        }
        close(ready[1]); char byte; check(read(ready[0], &byte, 1) == 1, "FIFO reader starts"); close(ready[0]); usleep(20000);
        int fd = open("/tmp/budget-fifo", O_WRONLY); check(fd >= 0, "FIFO writer open");
        check(unlink("/tmp/budget-fifo") == 0, "unlink during FIFO open");
        check(write(fd, "f", 1) == 1, "unlinked FIFO write"); close(fd);
        int status; check(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0, "FIFO reader exits");
    }
}
static void pty_lifetimes(void) {
    for (int i = 0; i < 20; ++i) {
        int master = posix_openpt(O_RDWR | O_NOCTTY);
        check(master >= 0 && unlockpt(master) == 0, "PTY master");
        char path[64], alias[64];
        check(ptsname_r(master, path, sizeof path) == 0, "PTY pathname");
        snprintf(alias, sizeof alias, "/tmp/budget-pty-%d", i);
        struct stat st; check(stat(path, &st) == 0, "PTY identity");
        check(mknod(alias, S_IFCHR | 0600, st.st_rdev) == 0, "dynamic slave alias");
        int slave = open(alias, O_RDWR | O_NOCTTY); check(slave >= 0, "open dynamic alias");
        if (i & 1) check(unlink(path) == 0, "detach named slave with backing pin");
        check(close(master) == 0, "hang up aliased slave");
        check(open(alias, O_RDWR | O_NOCTTY) < 0 && errno == EIO, "closed alias cannot resurrect pair");
        char byte; check(read(slave, &byte, 1) == 0, "aliased slave hangup");
        check(unlink(alias) == 0 && close(slave) == 0, "release alias origin and description");
    }
    // Failed opens may leave the last temporary reference after master close.
    // Repeat the race while numeric PTY paths are recycled.
    for (int i = 0; i < 8; ++i) {
        int master = posix_openpt(O_RDWR | O_NOCTTY);
        check(master >= 0 && unlockpt(master) == 0, "racing PTY master");
        char path[64]; check(ptsname_r(master, path, sizeof path) == 0, "racing PTY pathname");
        int ready[2]; check(pipe(ready) == 0, "PTY race coordination");
        int child = fork(); check(child >= 0, "PTY opener child");
        if (!child) {
            close(master); close(ready[0]);
            check(write(ready[1], "r", 1) == 1, "PTY opener ready"); close(ready[1]);
            for (int attempt = 0; attempt < 32; ++attempt) {
                int slave = open(path, O_RDWR | O_NOCTTY);
                if (slave >= 0) close(slave);
                else check(errno == EIO || errno == ENOENT, "PTY failed-open race");
            }
            _exit(0);
        }
        close(ready[1]); char byte;
        check(read(ready[0], &byte, 1) == 1, "PTY race starts"); close(ready[0]); close(master);
        int status; check(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0, "PTY race completes");
        check(access(path, F_OK) < 0 && errno == ENOENT, "last lookup removes closed PTY name");
    }
    sleep(12); // Backing pin release and subsequent pair retirement each wait.
    int master = posix_openpt(O_RDWR | O_NOCTTY); check(master >= 0, "PTY reuse after retirement"); close(master);
}
struct accounting { unsigned long long bytes, accounts, objects[8], charged[8]; };
static struct accounting accounting(void) {
    int fd = open("/proc/kernel-resources", O_RDONLY); check(fd >= 0, "accounting view");
    char text[2048]; int n = read(fd, text, sizeof text - 1); check(n > 0, "accounting read"); text[n] = 0; close(fd);
    char *bytes = strstr(text, "Charged:"), *accounts = strstr(text, "Accounts:");
    check(bytes && accounts, "accounting totals");
    struct accounting result = { .bytes = strtoull(bytes + 8, NULL, 10), .accounts = strtoull(accounts + 9, NULL, 10) };
    const char *names[] = { "file ", "descriptor ", "socket ", "ipc ", "mapping ", "process ", "thread ", "scratch " };
    for (int i = 0; i < 8; ++i) { char *row = strstr(text, names[i]); check(row && sscanf(row + strlen(names[i]), "%llu %llu", &result.objects[i], &result.charged[i]) == 2, "class accounting"); }
    return result;
}
static void creator_lifetimes(void) {
    int done[2], pair[2]; check(pipe(done) == 0 && socketpair(AF_UNIX, SOCK_DGRAM, 0, pair) == 0, "creator channels");
    int creator = fork(); check(creator >= 0, "creator fork");
    if (!creator) {
        close(done[0]); close(pair[0]);
        unsigned char *shared = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
        check(shared != MAP_FAILED, "lazy shared mapping");
        int child = fork(); check(child >= 0, "shared survivor fork");
        if (!child) {
            close(pair[1]); sleep(8);
            shared[0] = 97; check(shared[0] == 97, "shared refault after creator exits");
            check(write(done[1], "s", 1) == 1, "shared completion"); munmap(shared, page); close(done[1]); _exit(0);
        }
        check(write(done[1], &child, sizeof child) == sizeof child, "survivor pid");
        int fd = syscall(SYS_memfd_create, "creator-rights", 0); check(fd >= 0, "creator memfd");
        check(write(fd, "alive", 5) == 5, "creator contents");
        char byte = 'f', control[CMSG_SPACE(sizeof(int))]; memset(control, 0, sizeof control);
        struct iovec io = { &byte, 1 }; struct msghdr msg = { .msg_iov = &io, .msg_iovlen = 1, .msg_control = control, .msg_controllen = sizeof control };
        struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg); cmsg->cmsg_level = SOL_SOCKET; cmsg->cmsg_type = SCM_RIGHTS; cmsg->cmsg_len = CMSG_LEN(sizeof fd); memcpy(CMSG_DATA(cmsg), &fd, sizeof fd);
        check(sendmsg(pair[1], &msg, 0) == 1, "queue creator descriptor"); close(fd); close(pair[1]); close(done[1]); _exit(0);
    }
    close(done[1]); close(pair[1]); int survivor, status;
    check(read(done[0], &survivor, sizeof survivor) == sizeof survivor, "receive survivor pid");
    check(waitpid(creator, &status, 0) == creator && WIFEXITED(status) && WEXITSTATUS(status) == 0, "creator exit");
    sleep(8);
    char byte, control[CMSG_SPACE(sizeof(int))]; struct iovec io = { &byte, 1 };
    struct msghdr msg = { .msg_iov = &io, .msg_iovlen = 1, .msg_control = control, .msg_controllen = sizeof control };
    check(recvmsg(pair[0], &msg, 0) == 1, "receive after creator exit");
    struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg); check(cmsg && cmsg->cmsg_type == SCM_RIGHTS, "received descriptor");
    int fd; memcpy(&fd, CMSG_DATA(cmsg), sizeof fd); char data[5];
    check(pread(fd, data, sizeof data, 0) == sizeof data && memcmp(data, "alive", 5) == 0, "received file remains alive");
    close(fd); close(pair[0]); check(read(done[0], &byte, 1) == 1 && byte == 's', "shared survivor completes"); close(done[0]);
    check(waitpid(survivor, &status, 0) == survivor && WIFEXITED(status) && WEXITSTATUS(status) == 0, "survivor reaped");
    printf("KRES creator-lifetimes PASS\n"); fflush(stdout); sleep(7);
}
static void run(const char *name, void (*work)(void)) {
    struct accounting before = accounting();
    int pid = fork(); check(pid >= 0, "start resource test");
    if (!pid) { work(); _exit(0); }
    int status; check(waitpid(pid, &status, 0) == pid, "wait resource test");
    check(WIFEXITED(status) && WEXITSTATUS(status) == 0, name);
    printf("KRES %s PASS\n", name); fflush(stdout);
    sleep(12); // A five-second grace and the periodic reaper both need to run.
    struct accounting after = accounting();
    printf("KRES accounting %s before=%llu/%llu after=%llu/%llu\n", name, before.bytes, before.accounts, after.bytes, after.accounts); fflush(stdout);
    if (after.accounts != before.accounts || after.bytes > before.bytes + 65536) {
        int fd = open("/proc/kernel-resources", O_RDONLY); char view[2048]; int len = read(fd, view, sizeof view - 1); if (len > 0) { view[len] = 0; printf("%s", view); fflush(stdout); } close(fd);
    }
    // The existing scheduler keeps one last dead stack per CPU until the next
    // death there. Count that bounded retention; every other resource returns.
    unsigned long long cpus = sysconf(_SC_NPROCESSORS_ONLN); if (cpus < 1) cpus = 1;
    for (int i = 0; i < 8; ++i) {
        if (i == 6) { check(after.objects[i] <= before.objects[i] + cpus, "dead thread slots bounded"); continue; }
        check(after.objects[i] <= before.objects[i] && after.charged[i] <= before.charged[i] + 65536, "resource charges returned");
    }
    check(after.accounts <= before.accounts + cpus, "retired accounts bounded");
}
static void overlay_quotas(void) {
    const char *dirs[] = {"/tmp/budget-overlay", "/tmp/budget-overlay/lower", "/tmp/budget-overlay/upper", "/tmp/budget-overlay/work", "/tmp/budget-overlay/merged"};
    for (int i = 0; i < 5; ++i) check(mkdir(dirs[i], 0700) == 0, "overlay directories");
    const char *files[] = {"/tmp/budget-overlay/lower/a", "/tmp/budget-overlay/lower/b", "/tmp/budget-overlay/lower/c"};
    for (int i = 0; i < 3; ++i) write_script(files[i], "lower", 5);
    check(mount("overlay", dirs[4], "overlay", 0, "lowerdir=/tmp/budget-overlay/lower,upperdir=/tmp/budget-overlay/upper,workdir=/tmp/budget-overlay/work") == 0, "overlay mount");
    check(unlink("/tmp/budget-overlay/merged/a") == 0, "initial whiteout");
    struct { uint32_t version; struct { uint16_t tag, perm; uint32_t id; } entries[5]; } acl =
        {2, {{1,7,UINT32_MAX},{2,6,1000},{4,7,UINT32_MAX},{16,7,UINT32_MAX},{32,7,UINT32_MAX}}};
    check(setxattr(dirs[4], "system.posix_acl_default", &acl, sizeof acl, 0) == 0, "overlay default ACL");
    int n = 0;
    for (; n < MAX; ++n) {
        maps[n] = mmap(NULL, page, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (maps[n] == MAP_FAILED) { check(errno == ENOMEM, "overlay quota reached"); break; }
    }
    check(n > 4 && n < MAX, "overlay mapping bound");
    check(unlink("/tmp/budget-overlay/merged/b") != 0 && errno == ENOMEM, "denied unlink before whiteout");
    check(rename("/tmp/budget-overlay/merged/c", "/tmp/budget-overlay/merged/new") != 0 && errno == ENOMEM, "denied rename before namespace change");
    struct stat st;
    check(lstat("/tmp/budget-overlay/merged/b", &st) == 0 && S_ISREG(st.st_mode), "denied unlink preserves lower");
    check(lstat("/tmp/budget-overlay/merged/c", &st) == 0 && S_ISREG(st.st_mode), "denied rename preserves source");
    for (int i = 0; i < 4; ++i) check(munmap(maps[--n], page) == 0, "release creation allowance");
    int fd = open("/tmp/budget-overlay/merged/a", O_CREAT | O_EXCL | O_WRONLY, 0600);
    check(fd < 0 && errno == ENOMEM, "late ACL admission denial");
    check(lstat("/tmp/budget-overlay/upper/a", &st) == 0 && S_ISCHR(st.st_mode) && st.st_rdev == 0, "denied creation retains old whiteout");
    check(lstat("/tmp/budget-overlay/merged/a", &st) != 0 && errno == ENOENT, "denied creation stays hidden");
    for (int i = 0; i < n; ++i) check(munmap(maps[i], page) == 0, "release overlay quota");
    sleep(12);
    fd = open("/tmp/budget-overlay/merged/a", O_CREAT | O_EXCL | O_WRONLY, 0600); check(fd >= 0, "overlay creation recovery"); close(fd);
    check(lstat("/tmp/budget-overlay/upper/a", &st) == 0 && S_ISREG(st.st_mode), "committed replacement published");
    check(unlink("/tmp/budget-overlay/merged/a") == 0 && rename("/tmp/budget-overlay/merged/c", "/tmp/budget-overlay/merged/new") == 0, "overlay mutation recovery");
    check(lstat("/tmp/budget-overlay/merged/c", &st) != 0 && errno == ENOENT, "rename whiteout hides source");
    fd = open("/tmp/budget-overlay/merged/new", O_RDONLY); char data[5]; check(fd >= 0 && read(fd, data, 5) == 5 && memcmp(data, "lower", 5) == 0, "rename retains content"); close(fd);
    printf("KRES overlay-quotas PASS\n"); fflush(stdout);
}
int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "--shebang-ok") == 0) _exit(0);
    page = (size_t)sysconf(_SC_PAGESIZE);
    printf("KRES START page=%zu\n", page); fflush(stdout);
    int view = open("/proc/kernel-resources", O_RDONLY); check(view >= 0, "accounting view");
    char text[2048]; int length = read(view, text, sizeof text - 1); check(length > 0, "read accounting view");
    text[length] = 0; close(view); check(strstr(text, "OwnerLimit:") && strstr(text, "Kind Objects Bytes"), "accounting fields");
    creator_lifetimes();
    run("descriptors", descriptors); run("mappings", mappings); run("files", files);
    run("sockets", sockets); run("empty-records", records); run("semaphores", semaphores);
    run("shared-memory", shared_memory); run("messages", messages); run("attributes", attributes);
    run("exec-failures", exec_failures); run("scripts", scripts); run("FIFO-lifetimes", fifo_lifetimes); run("PTY-lifetimes", pty_lifetimes); run("watches", watches); run("threads", threads); run("processes", processes);
    overlay_quotas();
    printf("KRES PASS\n"); fflush(stdout); for (;;) pause();
}
