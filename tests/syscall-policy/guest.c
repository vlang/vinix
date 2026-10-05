#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#define PR_VINIX_SYSCALL_POLICY 0x56490002
#if defined(__aarch64__)
#define SYS_mimmutable 247
#define SYS_pledge 248
#define INSTRUCTION_OFFSET 4
#else
#define SYS_mimmutable 500
#define SYS_pledge 501
#define INSTRUCTION_OFFSET 8
#endif
#define STRIDE 32
struct pin { uint32_t number, flags; uint64_t offset; };
struct request { uint64_t version, base, length, entries, count, reserved; };
typedef long (*stub_fn)(long, long, long, long, long, long);
static unsigned char *text;
static struct pin pins[32];
static int pin_count, failures;
static size_t page;
static volatile int worker_stop;
extern long syscall_at(void *, long);
static const int numbers[] = { SYS_getpid, SYS_getppid, SYS_write, SYS_exit_group,
    SYS_prctl, SYS_clone, SYS_execve, SYS_mprotect, SYS_munmap, SYS_mmap,
    SYS_madvise, SYS_mremap, SYS_rt_sigreturn, SYS_pledge, SYS_read };

static void check(int ok, const char *name) {
    printf("SYSCALL POLICY %s: %s (errno=%d)\n", ok ? "PASS" : "FAIL", name, errno);
    failures += !ok;
}
static long policy(int action, const struct request *input) {
    return prctl(PR_VINIX_SYSCALL_POLICY, action, (unsigned long)input, 0L, 0L);
}
static long invoke(int number, long a, long b, long c, long d, long e, long f) {
    for (int i = 0; i < pin_count; ++i)
        if (pins[i].number == (unsigned)number)
            return ((stub_fn)(text + pins[i].offset - INSTRUCTION_OFFSET))(a, b, c, d, e, f);
    return -ENOSYS;
}
static long pinned_policy(int action, const struct request *input) {
    return invoke(SYS_prctl, PR_VINIX_SYSCALL_POLICY, action, (long)input, 0, 0, 0);
}
static void child_exit(int code) {
    invoke(SYS_exit_group, code, 0, 0, 0, 0, 0);
    __builtin_trap();
}
static int wait_status(pid_t child) {
    int status; pid_t got;
    do got = waitpid(child, &status, 0); while (got < 0 && errno == EINTR);
    return got == child ? status : -1;
}
static int exited_ok(pid_t child) {
    int status = wait_status(child);
    return status >= 0 && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}
static int aborted(pid_t child) {
    int status = wait_status(child);
    return status >= 0 && WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT;
}
static pid_t pinned_fork(void) {
    return (pid_t)invoke(SYS_clone, SIGCHLD, 0, 0, 0, 0, 0);
}
static int compare_pin(const void *left, const void *right) {
    const struct pin *a = left, *b = right;
    return (a->number > b->number) - (a->number < b->number);
}
static void emit(unsigned char *at, unsigned number) {
#if defined(__aarch64__)
    uint32_t instructions[] = { UINT32_C(0xd2800008) | (number << 5),
        UINT32_C(0xd4000001), UINT32_C(0xd65f03c0) };
    memcpy(at, instructions, sizeof(instructions));
#else
    const unsigned char prefix[] = {0x49, 0x89, 0xca, 0xb8}; /* rcx -> r10; mov eax,imm32 */
    memcpy(at, prefix, sizeof(prefix)); memcpy(at + 4, &number, 4);
    at[8] = 0x0f; at[9] = 0x05; at[10] = 0xc3;
#endif
}
static void sync_code(unsigned char *at, size_t length) {
#if defined(__aarch64__)
    unsigned long ctr;
    __asm__ volatile("mrs %0, ctr_el0" : "=r"(ctr));
    size_t data_line = 4UL << ((ctr >> 16) & 15), instruction_line = 4UL << (ctr & 15);
    for (uintptr_t address = (uintptr_t)at & ~(data_line - 1); address < (uintptr_t)at + length; address += data_line)
        __asm__ volatile("dc cvau, %0" : : "r"(address) : "memory");
    __asm__ volatile("dsb ish" : : : "memory");
    for (uintptr_t address = (uintptr_t)at & ~(instruction_line - 1); address < (uintptr_t)at + length; address += instruction_line)
        __asm__ volatile("ic ivau, %0" : : "r"(address) : "memory");
    __asm__ volatile("dsb ish; isb" : : : "memory");
#else
    (void)at; (void)length;
#endif
}
static unsigned char *region(int flags, int seal, int execute, int inherited) {
    unsigned char *result = mmap(NULL, page, PROT_READ | PROT_WRITE,
        flags, -1, 0);
    if (result == MAP_FAILED) return result;
    for (size_t i = 0; i < sizeof(numbers) / sizeof(numbers[0]); ++i)
        emit(result + i * STRIDE, (unsigned)numbers[i]);
    sync_code(result, page);
    if (inherited) (void)madvise(result, page, inherited);
    if (mprotect(result, page, PROT_READ | (execute ? PROT_EXEC : 0))
        || (seal && syscall(SYS_mimmutable, result, page))) return MAP_FAILED;
    return result;
}
static void expect_failure(struct request input, int error, const char *name) {
    errno = 0;
    check(policy(1, &input) == -1 && errno == error && policy(0, NULL) == 0, name);
}
static void *worker(void *unused) {
    (void)unused;
    while (!__atomic_load_n(&worker_stop, __ATOMIC_ACQUIRE)) usleep(1000);
    return NULL;
}
static void caught(int number) { (void)number; _exit(99); }
static long slab_kb(void) {
    char bytes[8192]; int fd = open("/proc/meminfo", O_RDONLY);
    if (fd < 0) return -1;
    ssize_t length = read(fd, bytes, sizeof(bytes) - 1); close(fd);
    if (length <= 0) return -1;
    bytes[length] = 0; char *value = strstr(bytes, "Slab:");
    return value ? strtol(value + 5, NULL, 10) : -1;
}
static void tracking(void) {
    int fd = open("/proc/allocstart", O_RDONLY); char byte;
    if (fd >= 0) { (void)read(fd, &byte, 1); close(fd); }
}
static void sites(void) {
    char bytes[65536]; int fd = open("/proc/allocsites", O_RDONLY);
    if (fd < 0) return;
    ssize_t length = read(fd, bytes, sizeof(bytes) - 1); close(fd);
    if (length > 0) { bytes[length] = 0; printf("SYSCALL POLICY ALLOCATION SITES\n%s\n", bytes); }
}

int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--exec"))
        return policy(0, NULL) == 0 && policy(3, NULL) == 0 ? 0 : 1;
    int console = open("/dev/com1", O_WRONLY | O_NOCTTY);
    if (console >= 0) { dup2(console, 1); dup2(console, 2); close(console); }
    setvbuf(stdout, NULL, _IONBF, 0);
    page = (size_t)sysconf(_SC_PAGESIZE);
    text = region(MAP_PRIVATE | MAP_ANONYMOUS, 0, 1, 0);
    check(text != MAP_FAILED, "create private anonymous syscall veneers");
    if (text == MAP_FAILED) goto finish;
    pin_count = (int)(sizeof(numbers) / sizeof(numbers[0]));
    for (int i = 0; i < pin_count; ++i) {
        pins[i].number = (unsigned)numbers[i]; pins[i].offset = i * STRIDE + INSTRUCTION_OFFSET;
    }
    qsort(pins, pin_count, sizeof(pins[0]), compare_pin);
    struct request input = {1, (uintptr_t)text, page, (uintptr_t)pins, (unsigned)pin_count, 0};
    check(policy(0, NULL) == 0 && policy(3, NULL) == 0 && invoke(SYS_getpid, 0, 0, 0, 0, 0, 0) == getpid(),
          "default Linux mode permits ordinary and copied syscalls");
    expect_failure(input, EPERM, "unsealed executable region rejected");
    check(syscall(SYS_mimmutable, text, page) == 0, "seal executable region");
    struct request bad = input; bad.version = 2; expect_failure(bad, EINVAL, "unknown descriptor version rejected");
    bad = input; bad.reserved = 1; expect_failure(bad, EINVAL, "reserved descriptor field rejected");
    bad = input; bad.count = 0; expect_failure(bad, EINVAL, "empty table rejected");
    bad = input; bad.count = 513; expect_failure(bad, EINVAL, "oversized table rejected");
    bad = input; bad.base++; expect_failure(bad, EINVAL, "unaligned region rejected");
    bad = input; bad.base = UINT64_MAX - page + 1; expect_failure(bad, EINVAL, "wrapped or kernel region rejected");
    bad = input; bad.length = 0; expect_failure(bad, EINVAL, "empty region rejected");
    bad = input; bad.entries = 128; expect_failure(bad, EFAULT, "bad table pointer rejected after allocating scratch");
    errno = 0; check(policy(1, (void *)128) == -1 && errno == EFAULT, "bad descriptor pointer rejected");
    struct pin saved = pins[0]; pins[0].flags = 1; expect_failure(input, EINVAL, "reserved pin flags rejected"); pins[0] = saved;
    pins[0].number = 512; expect_failure(input, EINVAL, "out of range syscall number rejected"); pins[0] = saved;
    pins[1].number = pins[0].number; expect_failure(input, EINVAL, "duplicate syscall number rejected");
    pins[1].number = (unsigned)numbers[1];
    /* Restore sort order from the original complete table. */
    for (int i = 0; i < pin_count; ++i) { pins[i].number = (unsigned)numbers[i]; pins[i].offset = i * STRIDE + INSTRUCTION_OFFSET; }
    qsort(pins, pin_count, sizeof(pins[0]), compare_pin);
    uint64_t old_offset = pins[1].offset; pins[1].offset = pins[0].offset;
    expect_failure(input, EINVAL, "duplicate instruction offset rejected"); pins[1].offset = old_offset;
    old_offset = pins[0].offset; pins[0].offset = page;
    expect_failure(input, EINVAL, "instruction extending past region rejected");
    pins[0].offset = old_offset + 1; expect_failure(input, EINVAL, "wrong instruction bytes or alignment rejected"); pins[0].offset = old_offset;
    unsigned char *other = region(MAP_SHARED | MAP_ANONYMOUS, 1, 1, 0);
    bad = input; bad.base = (uintptr_t)other; expect_failure(bad, EPERM, "shared executable alias rejected");
    other = region(MAP_PRIVATE | MAP_ANONYMOUS, 1, 0, 0);
    bad.base = (uintptr_t)other; expect_failure(bad, EPERM, "nonexecutable immutable text rejected");
    other = region(MAP_PRIVATE | MAP_ANONYMOUS, 1, 1, MADV_DONTFORK);
    bad.base = (uintptr_t)other; expect_failure(bad, EPERM, "text omitted from fork rejected");
    other = region(MAP_PRIVATE | MAP_ANONYMOUS, 1, 1, MADV_WIPEONFORK);
    bad.base = (uintptr_t)other; expect_failure(bad, EPERM, "text wiped at fork rejected");
    int fd = open("/sbin/init", O_RDONLY);
    if (fd >= 0) {
        other = mmap(NULL, page, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, 0);
        if (other != MAP_FAILED) (void)syscall(SYS_mimmutable, other, page);
        bad.base = (uintptr_t)other; expect_failure(bad, EPERM, "file-backed mutable source rejected"); close(fd);
    } else check(0, "open executable source fixture");
    pthread_t thread;
    int made_thread = pthread_create(&thread, NULL, worker, NULL) == 0;
    check(made_thread, "create second thread before registration");
    if (made_thread) {
        expect_failure(input, EPERM, "multithreaded registration rejected under publication lock");
        __atomic_store_n(&worker_stop, 1, __ATOMIC_RELEASE); pthread_join(thread, NULL);
    }
    pid_t child = fork();
    if (!child) {
        if (policy(2, &input) || pinned_policy(0, NULL) != 2
            || invoke(SYS_getpid, 0, 0, 0, 0, 0, 0) <= 0) child_exit(2);
        child_exit(0);
    }
    check(child > 0 && exited_ok(child) && policy(0, NULL) == 0, "direct enforcement install succeeds independently in child");
    unsigned char *copy = region(MAP_PRIVATE | MAP_ANONYMOUS, 0, 1, 0);
    errno = 0;
    check(copy != MAP_FAILED && mremap(copy, page, page, MREMAP_MAYMOVE | 4) == MAP_FAILED
          && errno == EINVAL, "MREMAP_DONTUNMAP cannot create a writable private alias");
    int go[2], ready[2];
    check(pipe(go) == 0 && pipe(ready) == 0, "pre-seal fork COW synchronization pipes");
    child = fork();
    if (!child) {
        text = copy; struct request own = input; own.base = (uintptr_t)copy;
        if (syscall(SYS_mimmutable, copy, page) || policy(2, &own)) child_exit(2);
        char byte = 'r';
        if (invoke(SYS_write, ready[1], (long)&byte, 1, 0, 0, 0) != 1
            || invoke(SYS_read, go[0], (long)&byte, 1, 0, 0, 0) != 1
            || invoke(SYS_getpid, 0, 0, 0, 0, 0, 0) <= 0) child_exit(3);
        child_exit(0);
    }
    close(ready[1]);
    char byte;
    int cow_ready = child > 0 && read(ready[0], &byte, 1) == 1;
    int cow_write = cow_ready && mprotect(copy, page, PROT_READ | PROT_WRITE) == 0;
    if (cow_write) {
        /* Poison the parent's GETPID opcode. The child's sealed copy must
           remain the original instruction even though it predates fork. */
        copy[INSTRUCTION_OFFSET] ^= 1; sync_code(copy, page);
    }
    (void)write(go[1], "g", 1);
    check(cow_write && exited_ok(child), "pre-seal cross-process writer gets COW instead of replacing pinned instruction");
    close(go[0]); close(go[1]); close(ready[0]); munmap(copy, page);
    unsigned char *split = mmap(NULL, 2 * page, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    check(split != MAP_FAILED, "split global isolation fixture");
    if (split != MAP_FAILED) {
        for (int i = 0; i < pin_count; ++i) emit(split + i * STRIDE, (unsigned)numbers[i]);
        sync_code(split, page);
        check(mprotect(split, page, PROT_READ | PROT_EXEC) == 0
              && syscall(SYS_mimmutable, split, page) == 0, "seal only executable half of split anonymous global");
        child = fork();
        if (!child) {
            text = split; struct request own = input; own.base = (uintptr_t)split;
            if (policy(2, &own)) child_exit(2);
            for (int i = 0; i < 1000; ++i) split[page + INSTRUCTION_OFFSET] = (unsigned char)i;
            if (invoke(SYS_getpid, 0, 0, 0, 0, 0, 0) <= 0) child_exit(3);
            child_exit(0);
        }
        check(child > 0 && exited_ok(child), "writable sibling range in split global cannot alias sealed text");
    }
    puts("SYSCALL POLICY PASS: installation validation");

    /* A failed install must free its one transient table every time. */
    bad = input; bad.entries = 128;
    for (int i = 0; i < 32; ++i) (void)policy(1, &bad);
    tracking(); long before = slab_kb(); int bounded = 1;
    for (int i = 0; i < 1000; ++i) { errno = 0; if (policy(1, &bad) != -1 || errno != EFAULT) bounded = 0; }
    long after = slab_kb();
    printf("SYSCALL POLICY REJECTED INSTALL SLAB before=%ld after=%ld KiB loops=1000\n", before, after);
    check(bounded && before >= 0 && after >= 0 && after <= before + 8, "failed registrations return transient table allocations");
    check(policy(1, &input) == 0 && pinned_policy(0, NULL) == 1, "install audit table once");
    check(pinned_policy(1, &input) == -EPERM && pinned_policy(2, &input) == -EPERM, "table cannot be replaced or reinstalled");
    long count = pinned_policy(3, NULL); pid_t self = (pid_t)invoke(SYS_getpid, 0, 0, 0, 0, 0, 0);
    check(self > 0 && pinned_policy(3, NULL) == count, "correct exact instruction passes audit");
    count = pinned_policy(3, NULL);
    long result = syscall(SYS_getpid);
    check(result == self && pinned_policy(3, NULL) == count + 1, "ordinary libc instruction is counted but allowed in audit");
    signal(SIGABRT, caught);
    child = pinned_fork();
    if (!child) {
        if (pinned_policy(0, NULL) != 1 || pinned_policy(3, NULL) != 0 || pinned_policy(4, NULL)) child_exit(2);
        if (invoke(SYS_getpid, 0, 0, 0, 0, 0, 0) <= 0 || pinned_policy(0, NULL) != 2) child_exit(3);
        if (pinned_policy(1, &input) != -EPERM || pinned_policy(2, &input) != -EPERM) child_exit(4);
        child_exit(0);
    }
    check(child > 0 && exited_ok(child), "fork inherits immutable table with independent mode and counter");
    check(pinned_policy(0, NULL) == 1, "child strengthening leaves parent in audit");
    child = pinned_fork();
    if (!child) { if (pinned_policy(4, NULL)) child_exit(2); syscall(SYS_getpid); child_exit(3); }
    check(child > 0 && aborted(child), "enforcement terminates invalid origin despite SIGABRT handler");
    child = pinned_fork();
    if (!child) {
        if (pinned_policy(4, NULL)) child_exit(2);
        for (int i = 0; i < pin_count; ++i)
            if (pins[i].number == SYS_getppid) syscall_at(text + pins[i].offset, SYS_getpid);
        child_exit(3);
    }
    check(child > 0 && aborted(child), "another registered instruction cannot issue a different syscall number");
    child = pinned_fork();
    if (!child) {
        if (pinned_policy(4, NULL)) child_exit(2);
        if (invoke(SYS_pledge, (long)"stdio", 0, 0, 0, 0, 0)
            || pinned_policy(0, NULL) != 2) child_exit(3);
        child_exit(0);
    }
    check(child > 0 && exited_ok(child), "policy controls work under pledge stdio");
    puts("SYSCALL POLICY PASS: audit and enforcement");
    child = pinned_fork();
    if (!child) {
        if (pinned_policy(4, NULL)) child_exit(2);
        char *args[] = {argv[0], "--exec", NULL}; char *environment[] = {NULL};
        invoke(SYS_execve, (long)argv[0], (long)args, (long)environment, 0, 0, 0); child_exit(3);
    }
    check(child > 0 && exited_ok(child), "exec clears policy and inherited table reference");
    child = pinned_fork();
    if (!child) {
        if (pinned_policy(4, NULL)) child_exit(2);
        if (invoke(SYS_mprotect, (long)text, page, PROT_READ | PROT_WRITE, 0, 0, 0) != -EPERM
            || invoke(SYS_munmap, (long)text, page, 0, 0, 0, 0) != -EPERM
            || invoke(SYS_madvise, (long)text, page, MADV_DONTNEED, 0, 0, 0) != -EPERM
            || invoke(SYS_mremap, (long)text, page, page * 2, MREMAP_MAYMOVE, 0, 0) != -EPERM) child_exit(3);
        child_exit(0);
    }
    check(child > 0 && exited_ok(child), "registered text cannot be rewritten unmapped discarded or moved");
    before = slab_kb(); bounded = 1;
    for (int i = 0; i < 10000; ++i) {
        if (invoke(SYS_getpid, 0, 0, 0, 0, 0, 0) != self || pinned_policy(0, NULL) != 1) bounded = 0;
    }
    after = slab_kb(); printf("SYSCALL POLICY ENTRY SLAB before=%ld after=%ld KiB loops=10000\n", before, after);
    check(bounded && before >= 0 && after >= 0 && after <= before + 8, "entry checks and queries allocate nothing per call");
    for (int i = 0; i < 100; ++i) {
        child = pinned_fork();
        if (!child) { if (pinned_policy(0, NULL) != 1) child_exit(2); child_exit(0); }
        if (child <= 0 || !exited_ok(child)) { bounded = 0; break; }
    }
    check(bounded && invoke(SYS_getpid, 0, 0, 0, 0, 0, 0) == self,
          "repeated fork exit and reaping retain valid parent table");
    sites(); puts("SYSCALL POLICY PASS: inheritance and lifetime");
finish:
    puts(failures ? "SYSCALL POLICY GUEST: FAIL" : "SYSCALL POLICY GUEST: PASS");
    for (;;) pause();
}
