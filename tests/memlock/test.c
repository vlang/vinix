#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/reboot.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#if defined(__aarch64__)
#define SYS_vinix_mimmutable 247
#else
#define SYS_vinix_mimmutable 500
#endif

#define FORGED_BRK_RESERVATION 0x20000000

#define CHECK(x) do { if (!(x)) { printf("VINIX MEMLOCK: FAIL line=%d errno=%d: %s\n", __LINE__, errno, #x); return 1; } } while (0)
static size_t page;

static unsigned long field(const char *path, const char *name)
{
    char buffer[8192];
    int fd = open(path, O_RDONLY);
    if (fd < 0) return ~0ul;
    ssize_t count = read(fd, buffer, sizeof buffer - 1);
    close(fd);
    if (count < 0) return ~0ul;
    buffer[count] = 0;
    char *value = strstr(buffer, name);
    return value ? strtoul(value + strlen(name), NULL, 10) : ~0ul;
}

static unsigned long locked(void) { return field("/proc/self/status", "VmLck:"); }
static unsigned long slab(void) { return field("/proc/meminfo", "Slab:"); }

static int limit(size_t bytes)
{
    struct rlimit value = { .rlim_cur = bytes, .rlim_max = RLIM_INFINITY };
    return setrlimit(RLIMIT_MEMLOCK, &value);
}

static int drop_lock_capability(void)
{
    struct { uint32_t version; int pid; } header = { .version = 0x20080522 };
    struct { uint32_t effective, permitted, inheritable; } data[2];
    if (syscall(SYS_capget, &header, data)) return -1;
    data[0].effective &= ~(1u << 14); /* Linux CAP_IPC_LOCK */
    data[0].permitted &= ~(1u << 14);
    return (int)syscall(SYS_capset, &header, data);
}

static int status(pid_t child)
{
    int value;
    pid_t result;
    do result = waitpid(child, &value, 0); while (result < 0 && errno == EINTR);
    return result == child && WIFEXITED(value) ? WEXITSTATUS(value) : 255;
}

static int resident(void *address)
{
    unsigned char value = 0;
    return mincore(address, page, &value) == 0 ? !!(value & 1) : -1;
}

static int ranges(void)
{
    CHECK(drop_lock_capability() == 0 && limit(2 * page + page - 1) == 0);
    unsigned char *memory = mmap(NULL, 64 * 1024 * 1024, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(memory != MAP_FAILED && resident(memory) == 0 && locked() == 0);
    CHECK(mlock(memory + 1, page - 1) == 0);
    CHECK(resident(memory) == 1 && locked() == page / 1024);
    CHECK(mlock(memory, page) == 0 && locked() == page / 1024);
    CHECK(mlock(memory + page, page) == 0 && locked() == 2 * page / 1024);
    CHECK(mlock(memory + 2 * page, 1) == -1 && errno == ENOMEM);
    CHECK(locked() == 2 * page / 1024 && resident(memory + 2 * page) == 0);
    CHECK(mprotect(memory, page, PROT_READ) == 0 && locked() == 2 * page / 1024);
    CHECK(madvise(memory, page, MADV_DONTNEED) == -1 && errno == EINVAL);
    CHECK(madvise(memory, page, MADV_FREE) == -1 && errno == EINVAL);
    CHECK(munlock(memory + 1, 1) == 0 && locked() == page / 1024);
    CHECK(madvise(memory, page, MADV_DONTNEED) == 0 && resident(memory) == 0);
    CHECK(mlock(memory + 2 * page, page) == 0 && locked() == 2 * page / 1024);
    CHECK(munlock(memory + 3 * page, page) == 0 && locked() == 2 * page / 1024);
    CHECK(munmap(memory + page, page) == 0 && locked() == page / 1024);
    CHECK(mlock(memory, 3 * page) == -1 && errno == ENOMEM); /* hole: no partial locks */
    CHECK(locked() == page / 1024 && resident(memory) == 0);
    CHECK(munlock(memory, 3 * page) == -1 && errno == ENOMEM && locked() == page / 1024);
    CHECK(munlockall() == 0 && locked() == 0);
    CHECK(mlock((void *)(uintptr_t)-1, 2) == -1 && errno == EINVAL);
    CHECK(syscall(SYS_mmap, NULL, SIZE_MAX, (long)(PROT_READ | PROT_WRITE),
        (long)(MAP_PRIVATE | MAP_ANONYMOUS | MAP_LOCKED), -1L, 0L) == -1 && errno == EINVAL);
    CHECK(munmap(memory, 64 * 1024 * 1024) == 0);
    return 0;
}

static int files_and_guards(void)
{
    CHECK(drop_lock_capability() == 0 && limit(4 * page) == 0);
    int fd = open("/tmp/memlock-file", O_CREAT | O_TRUNC | O_RDWR, 0644);
    CHECK(fd >= 0 && ftruncate(fd, (off_t)page) == 0);
    CHECK(pwrite(fd, "file data", 10, 0) == 10);
    char *mapping = mmap(NULL, 2 * page, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    CHECK(mapping != MAP_FAILED && close(fd) == 0 && resident(mapping) == 0);
    CHECK(mlock(mapping, 2 * page) == -1 && errno == ENOMEM && locked() == 0);
    CHECK(resident(mapping) == 0);
    CHECK(mlock(mapping, page) == 0 && resident(mapping) == 1 && !memcmp(mapping, "file data", 10));
    CHECK(locked() == page / 1024 && munlock(mapping, page) == 0);
    CHECK(munmap(mapping, 2 * page) == 0);
    fd = open("/tmp/memlock-file", O_RDWR);
    CHECK(fd >= 0 && ftruncate(fd, (off_t)(2 * page)) == 0);
    mapping = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    CHECK(mapping != MAP_FAILED && close(fd) == 0);
    mapping[0] = 'P';
    CHECK(mlock(mapping, page) == 0);
    char *moved = mremap(mapping, page, 2 * page, MREMAP_MAYMOVE);
    CHECK(moved != MAP_FAILED && moved[0] == 'P' && locked() == 2 * page / 1024);
    CHECK(mremap(moved, 2 * page, 3 * page, MREMAP_MAYMOVE) == MAP_FAILED && errno == ENOMEM);
    CHECK(moved[0] == 'P' && locked() == 2 * page / 1024);
    CHECK(mprotect(moved, 2 * page, PROT_READ) == 0);
    void *target = mmap(NULL, 2 * page, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(target != MAP_FAILED);
    char *readonly = mremap(moved, 2 * page, 2 * page, MREMAP_MAYMOVE | MREMAP_FIXED,
        target);
    CHECK(readonly == target && readonly[0] == 'P' && locked() == 2 * page / 1024);
    CHECK(munmap(readonly, 2 * page) == 0 && locked() == 0);
    fd = open("/tmp/memlock-file", O_RDONLY);
    char byte;
    CHECK(fd >= 0 && read(fd, &byte, 1) == 1 && byte == 'f' && close(fd) == 0);
    void *guard = mmap(NULL, page, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_STACK, -1, 0);
    CHECK(guard != MAP_FAILED && resident(guard) == 0);
    CHECK(mlock(guard, page) == 0 && resident(guard) == 1 && locked() == page / 1024);
    pid_t child = fork();
    CHECK(child >= 0);
    if (!child) { (void)*(volatile char *)guard; _exit(1); }
    int value;
    CHECK(waitpid(child, &value, 0) == child && WIFSIGNALED(value) && WTERMSIG(value) == SIGSEGV);
    CHECK(mprotect(guard, page, PROT_READ) == 0 && locked() == page / 1024);
    CHECK(mprotect(guard, page, PROT_NONE) == 0 && locked() == page / 1024);
    CHECK(munlockall() == 0 && munmap(guard, page) == 0);
    return 0;
}

static int inheritance(void)
{
    CHECK(drop_lock_capability() == 0 && limit(2 * page) == 0);
    unsigned char *memory = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(memory != MAP_FAILED && mlock(memory, page) == 0);
    memory[0] = 42;
    pid_t child = fork();
    CHECK(child >= 0);
    if (!child) {
        if (locked() != 0 || limit(0) || mlock(memory, page) != -1 || errno != EPERM) _exit(1);
        if (madvise(memory, page, MADV_DONTNEED) || memory[0] != 0) _exit(2);
        _exit(0);
    }
    CHECK(status(child) == 0 && memory[0] == 42 && locked() == page / 1024);
    void *grown = mremap(memory, page, 2 * page, MREMAP_MAYMOVE);
    CHECK(grown != MAP_FAILED && *(unsigned char *)grown == 42 && locked() == 2 * page / 1024);
    CHECK(mremap(grown, 2 * page, 3 * page, MREMAP_MAYMOVE) == MAP_FAILED && errno == EAGAIN);
    CHECK(locked() == 2 * page / 1024 && *(unsigned char *)grown == 42);
    CHECK(mmap(grown, 3 * page, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED | MAP_LOCKED, -1, 0) == MAP_FAILED && errno == EAGAIN);
    CHECK(locked() == 2 * page / 1024 && *(unsigned char *)grown == 42);
    CHECK(mmap(grown, page, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0) == grown);
    CHECK(locked() == page / 1024 && *(unsigned char *)grown == 0);
    CHECK(munmap(grown, 2 * page) == 0 && locked() == 0);
    unsigned char *code = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(code != MAP_FAILED);
#if defined(__aarch64__)
    const uint32_t instructions[] = { 0x52800540, 0xd65f03c0 }; /* mov w0,42; ret */
#else
    const unsigned char instructions[] = { 0xb8, 42, 0, 0, 0, 0xc3 }; /* mov eax,42; ret */
#endif
    memcpy(code, instructions, sizeof instructions);
    CHECK(mlock(code, page) == 0 && mprotect(code, page, PROT_READ | PROT_EXEC) == 0);
    int (*function)(void) = (int (*)(void))code;
    CHECK(function() == 42);
    code = mremap(code, page, 2 * page, MREMAP_MAYMOVE);
    CHECK(code != MAP_FAILED && locked() == 2 * page / 1024);
    function = (int (*)(void))code;
    CHECK(function() == 42 && munmap(code, 2 * page) == 0 && locked() == 0);
    CHECK(limit(8 * page) == 0);
    char *split = mmap(NULL, 4 * page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(split != MAP_FAILED);
    split[0] = 31; split[3 * page] = 32;
    CHECK(mlock(split + page, page) == 0 && munlock(split + page, page) == 0);
    char *joined = mremap(split, 4 * page, 5 * page, MREMAP_MAYMOVE);
    CHECK(joined != MAP_FAILED && joined[0] == 31 && joined[3 * page] == 32 && locked() == 0);
    CHECK(munmap(joined, 5 * page) == 0);
    CHECK(mlockall(MCL_FUTURE) == 0);
    child = fork();
    CHECK(child >= 0);
    if (!child) {
        if (mlockall(MCL_FUTURE) || limit(0) || setgid(65534) || setuid(65534)) _exit(1);
        char *arguments[] = { "init", "--exec-clean", NULL };
        char *environment[] = { NULL };
        execve("/sbin/init", arguments, environment);
        _exit(3);
    }
    CHECK(status(child) == 0 && munlockall() == 0);
    return 0;
}

static int current_and_future(void)
{
    CHECK(drop_lock_capability() == 0 && limit(2 * page) == 0);
    void *span = mmap(NULL, 4 * page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(span != MAP_FAILED);
    CHECK(mlockall(MCL_CURRENT) == -1 && errno == ENOMEM && locked() == 0);
    CHECK(mlockall(MCL_FUTURE) == 0 && locked() == 0);
    CHECK(mmap(span, 2 * page, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0) == span);
    CHECK(locked() == 2 * page / 1024);
    CHECK(mmap(NULL, page, PROT_READ, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0) == MAP_FAILED && errno == EAGAIN);
    CHECK(munmap(span, 2 * page) == 0 && locked() == 0);
    uintptr_t old_break = (uintptr_t)syscall(SYS_brk, 0);
    CHECK(old_break != 0);
    uintptr_t start = (old_break + page - 1) & ~(uintptr_t)(page - 1);
    CHECK((uintptr_t)syscall(SYS_brk, start + 2 * page) == start + 2 * page);
    CHECK(locked() == 2 * page / 1024);
    CHECK(mremap((void *)start, page, 2 * page, MREMAP_MAYMOVE) == MAP_FAILED && errno == EINVAL);
    CHECK((uintptr_t)syscall(SYS_brk, 0) == start + 2 * page && locked() == 2 * page / 1024);
    CHECK(mprotect((void *)start, 2 * page, PROT_NONE) == 0 && locked() == 2 * page / 1024);
    CHECK(munlock((void *)start, 2 * page) == 0 && locked() == 0);
    CHECK(mlock((void *)start, 2 * page) == 0 && locked() == 2 * page / 1024);
    CHECK(mprotect((void *)start, 2 * page, PROT_READ | PROT_WRITE) == 0);
    CHECK((uintptr_t)syscall(SYS_brk, start + 3 * page) == start + 2 * page);
    CHECK(locked() == 2 * page / 1024);
    CHECK((uintptr_t)syscall(SYS_brk, old_break) == old_break && locked() == 0);
    /* A sealed heap tail must fail before prefaulting or charging it. */
    CHECK(limit(4 * page) == 0);
    CHECK(resident((void *)start) == 1); /* prior successful growth populated it */
    uintptr_t sealed = start + 2 * page;
    CHECK(resident((void *)sealed) == 0);
    CHECK(syscall(SYS_vinix_mimmutable, (void *)sealed, page) == 0);
    CHECK((uintptr_t)syscall(SYS_brk, sealed + page) == old_break);
    CHECK(locked() == 0 && resident((void *)sealed) == 0);
    void *forged = mmap(NULL, page, PROT_NONE,
        MAP_PRIVATE | MAP_ANONYMOUS | FORGED_BRK_RESERVATION, -1, 0);
    CHECK(forged == MAP_FAILED && errno == EINVAL && locked() == 0);
    CHECK(limit(page) == 0);
    CHECK(mremap((void *)(start + 8 * page), page, 2 * page, MREMAP_MAYMOVE)
        == MAP_FAILED && errno == EINVAL && locked() == 0);
    void *future_guard = mmap(NULL, page, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(future_guard != MAP_FAILED && resident(future_guard) == 1 && locked() == page / 1024);
    CHECK(mremap(future_guard, page, 2 * page, MREMAP_MAYMOVE) == MAP_FAILED && errno == EAGAIN);
    CHECK(resident(future_guard) == 1 && locked() == page / 1024);
    CHECK(limit(2 * page) == 0);
    future_guard = mremap(future_guard, page, 2 * page, MREMAP_MAYMOVE);
    CHECK(future_guard != MAP_FAILED && locked() == 2 * page / 1024);
    CHECK(resident(future_guard) == 1 && resident((char *)future_guard + page) == 1);
    CHECK(munmap(future_guard, 2 * page) == 0 && locked() == 0);
    CHECK(munlockall() == 0);
    void *ordinary = mmap(NULL, page, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(ordinary != MAP_FAILED && resident(ordinary) == 0 && locked() == 0);
    CHECK(munmap(ordinary, page) == 0 && munmap((char *)span + 2 * page, 2 * page) == 0);
    struct rlimit as = { .rlim_cur = 0, .rlim_max = RLIM_INFINITY };
    CHECK(setrlimit(RLIMIT_AS, &as) == 0);
    CHECK(mremap((void *)(start + 8 * page), page, 2 * page, MREMAP_MAYMOVE)
        == MAP_FAILED && errno == EINVAL);
    CHECK(mmap(NULL, page, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | FORGED_BRK_RESERVATION,
        -1, 0) == MAP_FAILED && errno == EINVAL);
    CHECK(mmap(NULL, page, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0) == MAP_FAILED && errno == ENOMEM);
    return 0;
}

static int capability_and_flags(void)
{
    void *mapping = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(mapping != MAP_FAILED && limit(0) == 0);
    CHECK(mlock(mapping, page) == 0 && locked() == page / 1024); /* CAP_IPC_LOCK bypass */
    CHECK(munlockall() == 0);
    uintptr_t old_break = (uintptr_t)syscall(SYS_brk, 0);
    uintptr_t heap = (old_break + page - 1) & ~(uintptr_t)(page - 1);
    CHECK((uintptr_t)syscall(SYS_brk, heap + 2 * page) == heap + 2 * page);
    CHECK(mprotect((void *)heap, 2 * page, PROT_NONE) == 0);
    CHECK(mlockall(MCL_CURRENT | MCL_FUTURE) == 0 && locked() > 0);
    unsigned long all = locked();
    CHECK(munlock((void *)heap, page) == 0 && locked() == all - page / 1024);
    CHECK(mlockall(MCL_CURRENT) == 0); /* clears future mode */
    unsigned long before = locked();
    void *new_mapping = mmap(NULL, page, PROT_READ, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(new_mapping != MAP_FAILED && locked() == before);
    CHECK(munlockall() == 0 && locked() == 0 && drop_lock_capability() == 0);
    CHECK(mlock(mapping, page) == -1 && errno == EPERM);
    CHECK(mlock(mapping, 0) == -1 && errno == EPERM);
    CHECK(munlock(mapping, 0) == 0);
    CHECK(limit(page) == 0 && syscall(SYS_mlock2, mapping, page, 0) == 0 && locked() == page / 1024);
    CHECK(munlockall() == 0);
    CHECK(syscall(SYS_mlock2, mapping, page, 1) == -1 && errno == EOPNOTSUPP);
    CHECK(syscall(SYS_mlock2, mapping, page, 2) == -1 && errno == EINVAL);
    CHECK(mlockall(0) == -1 && errno == EINVAL);
    CHECK(mlockall(4) == -1 && errno == EINVAL);
    CHECK(mlockall(8) == -1 && errno == EINVAL);
    CHECK(mlockall(MCL_CURRENT | 4) == -1 && errno == EOPNOTSUPP);
    CHECK(mlockall(MCL_FUTURE | 4) == -1 && errno == EOPNOTSUPP);
    CHECK((uintptr_t)syscall(SYS_brk, old_break) == old_break);
    CHECK(locked() == 0 && munmap(mapping, page) == 0 && munmap(new_mapping, page) == 0);
    return 0;
}

static char *race_source, *race_target;
static size_t race_length;
static int race_fd;
static atomic_int race_failed, race_moves;

static void *replace_worker(void *unused)
{
    (void)unused;
    for (int i = 0; i < 300; ++i) {
        if (mmap(race_source, race_length, PROT_READ | PROT_WRITE,
            MAP_PRIVATE | MAP_FIXED, race_fd, 0) != race_source) {
            atomic_store(&race_failed, 1); break;
        }
        sched_yield();
    }
    return NULL;
}

static void *move_worker(void *unused)
{
    (void)unused;
    for (int i = 0; i < 300; ++i) {
        if (mlock(race_source, race_length) && errno != ENOMEM && errno != EAGAIN) {
            atomic_store(&race_failed, 2); break;
        }
        char *moved = mremap(race_source, race_length, 2 * race_length,
            MREMAP_MAYMOVE | MREMAP_FIXED, race_target);
        if (moved == MAP_FAILED) {
            if (errno != EFAULT && errno != ENOMEM && errno != EAGAIN && errno != EINVAL) {
                atomic_store(&race_failed, 3); break;
            }
        } else {
            if (moved != race_target || moved[0] != 'r') { atomic_store(&race_failed, 4); break; }
            atomic_fetch_add(&race_moves, 1);
        }
        if (munmap(race_target, 2 * race_length)) { atomic_store(&race_failed, 5); break; }
        sched_yield();
    }
    return NULL;
}

static int replacement_race(void)
{
    CHECK(drop_lock_capability() == 0 && limit(8 * page) == 0);
    race_length = 4 * page;
    race_fd = open("/tmp/memlock-race", O_CREAT | O_TRUNC | O_RDWR, 0644);
    CHECK(race_fd >= 0 && ftruncate(race_fd, (off_t)(2 * race_length)) == 0);
    CHECK(pwrite(race_fd, "r", 1, 0) == 1);
    race_source = mmap(NULL, race_length, PROT_READ | PROT_WRITE, MAP_PRIVATE, race_fd, 0);
    race_target = mmap(NULL, 2 * race_length, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(race_source != MAP_FAILED && race_target != MAP_FAILED);
    pthread_t replace, move;
    CHECK(pthread_create(&replace, NULL, replace_worker, NULL) == 0);
    CHECK(pthread_create(&move, NULL, move_worker, NULL) == 0);
    CHECK(pthread_join(replace, NULL) == 0 && pthread_join(move, NULL) == 0);
    printf("MEMLOCK RACE: error=%d successful_moves=%d\n", atomic_load(&race_failed), atomic_load(&race_moves));
    CHECK(atomic_load(&race_failed) == 0 && munlockall() == 0 && locked() == 0);
    CHECK(mmap(race_source, race_length, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_FIXED, race_fd, 0) == race_source);
    CHECK(race_source[0] == 'r' && mlock(race_source, race_length) == 0);
    char *moved = mremap(race_source, race_length, 2 * race_length,
        MREMAP_MAYMOVE | MREMAP_FIXED, race_target);
    CHECK(moved == race_target && moved[0] == 'r' && locked() == 8 * page / 1024);
    CHECK(munmap(moved, 2 * race_length) == 0 && locked() == 0 && close(race_fd) == 0);
    return 0;
}

static void allocation_sites(int start)
{
    char buffer[8192];
    int fd = open(start ? "/proc/allocstart" : "/proc/allocsites", O_RDONLY);
    if (fd < 0) return;
    ssize_t count;
    while ((count = read(fd, buffer, sizeof buffer - 1)) > 0) {
        buffer[count] = 0;
        if (!start) printf("MEMLOCK ALLOCS: %s", buffer);
    }
    close(fd);
}

static int repeated(void)
{
    CHECK(drop_lock_capability() == 0 && limit(4 * page) == 0);
    char *mapping = mmap(NULL, 64 * page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(mapping != MAP_FAILED);
    for (int i = 0; i < 64; ++i) {
        CHECK(mlock(mapping + i * page, page) == 0);
        CHECK(munlock(mapping + i * page, page) == 0);
    }
    unsigned long before = slab();
    allocation_sites(1);
    for (int i = 0; i < 300; ++i) {
        CHECK(mlock(mapping + (i % 62 + 1) * page + 1, page) == 0);
        CHECK(munlock(mapping + (i % 62 + 1) * page + 1, page) == 0);
        CHECK(mlock(mapping, 5 * page) == -1 && errno == ENOMEM);
        CHECK(mmap(NULL, 5 * page, PROT_READ | PROT_WRITE,
            MAP_PRIVATE | MAP_ANONYMOUS | MAP_LOCKED, -1, 0) == MAP_FAILED && errno == EAGAIN);
    }
    unsigned long after = slab();
    allocation_sites(0);
    printf("MEMLOCK SLAB: before=%lu after=%lu KiB\n", before, after);
    CHECK(before != ~0ul && after <= before + 32 && locked() == 0);
    CHECK(munmap(mapping, 64 * page) == 0);
    return 0;
}

int main(int argc, char **argv)
{
    page = (size_t)sysconf(_SC_PAGESIZE);
    if (argc == 2 && !strcmp(argv[1], "--exec-clean")) {
        CHECK(locked() == 0);
        void *mapping = mmap(NULL, page, PROT_READ, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        CHECK(mapping != MAP_FAILED && locked() == 0);
        CHECK(mlock(mapping, page) == -1 && errno == EPERM);
        return 0;
    }
    int console = open("/dev/com1", O_WRONLY);
    if (console < 0) console = open("/dev/console", O_WRONLY);
    if (console >= 0) { dup2(console, 1); dup2(console, 2); close(console); }
    setvbuf(stdout, NULL, _IONBF, 0);
    int (*tests[])(void) = { ranges, files_and_guards, inheritance, current_and_future, capability_and_flags, replacement_race, repeated };
    const char *markers[] = { "range population and limits", "file and guard mappings", "fork, remap, replacement and exec",
        "current, future and heap locking", "capability and unsupported flags", "concurrent file replacement and remap",
        "repeated lock and unlock stay flat" };
    int failed = 0;
    for (unsigned i = 0; i < sizeof tests / sizeof tests[0]; ++i) {
        pid_t child = fork();
        if (!child) _exit(tests[i]());
        int result = child < 0 ? 255 : status(child);
        if (result != 0) {
            printf("VINIX MEMLOCK: FAIL test=%u child_status=%d\n", i, result);
            failed = 1;
            continue;
        }
        printf("MEMLOCK PASS: %s\n", markers[i]);
    }
    puts(failed ? "VINIX MEMLOCK: FAIL" : "VINIX MEMLOCK: PASS");
    sync();
    reboot(RB_POWER_OFF);
    for (;;) pause();
}
