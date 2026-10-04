#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/statfs.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { printf("ACCOUNTING FAIL line=%d errno=%d: %s FAIL END\n", __LINE__, errno, #x); for (;;) pause(); } } while (0)
enum { MIB = 1024 * 1024, FILE_BYTES = 2 * MIB, THREADS = 4 };
static size_t page_size;
static unsigned char buffer[16384];
static volatile unsigned long checksum;

static struct rusage usage(int who)
{
    struct rusage result;
    memset(&result, 0, sizeof result);
    CHECK(getrusage(who, &result) == 0);
    return result;
}

static long metric(const char *name)
{
    FILE *file = fopen("/proc/meminfo", "r"); CHECK(file != NULL);
    char line[256], key[64]; long value, found = -1;
    while (fgets(line, sizeof line, file))
        if (sscanf(line, "%63s %ld", key, &value) == 2 && !strcmp(key, name)) found = value;
    CHECK(fclose(file) == 0 && found >= 0);
    return found;
}

/* Field numbers follow proc_pid_stat(5); a command can contain spaces. */
static unsigned long stat_field(unsigned number)
{
    int fd = open("/proc/self/stat", O_RDONLY); CHECK(fd >= 0);
    char text[1024]; ssize_t length = read(fd, text, sizeof text - 1);
    CHECK(length > 0 && close(fd) == 0); text[length] = 0;
    char *at = strrchr(text, ')'); CHECK(at != NULL); ++at;
    for (unsigned field = 3; field <= number; ++field) {
        while (*at == ' ') ++at;
        CHECK(*at != 0);
        if (field == number) return strtoul(at, NULL, 10);
        while (*at && *at != ' ') ++at;
    }
    CHECK(0); return 0;
}

static void transfer(int fd, void *data, size_t amount, int writing)
{
    unsigned char *at = data;
    while (amount) {
        ssize_t count = writing ? write(fd, at, amount) : read(fd, at, amount);
        if (count < 0 && errno == EINTR) continue;
        CHECK(count > 0); at += count; amount -= (size_t)count;
    }
}

static unsigned char *allocate(size_t amount)
{
    /* Vinix eagerly fills small mappings. Reserve a demand-paged span, then
     * keep only the touched prefix so every test owns exactly `amount`. */
    size_t reserved = amount < 64 * MIB ? 64 * MIB : amount;
    unsigned char *memory = mmap(NULL, reserved, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(memory != MAP_FAILED);
    for (size_t offset = 0; offset < amount; offset += page_size) memory[offset] = (unsigned char)(offset / page_size);
    if (reserved > amount) CHECK(munmap(memory + amount, reserved - amount) == 0);
    return memory;
}

static void anonymous_rss(void)
{
    /* The guest itself is a lazily mapped EXT2 executable. Warm the parser
     * and allocation helpers before attributing disk faults to this span. */
    unsigned char *warmup = allocate(page_size);
    CHECK(munmap(warmup, page_size) == 0);
    unsigned long old_rss = stat_field(24);
    struct rusage before = usage(RUSAGE_SELF);
    unsigned char *memory = allocate(32 * MIB);
    struct rusage touched = usage(RUSAGE_SELF);
    unsigned long resident = stat_field(24);
    unsigned long stat_minor = stat_field(10), stat_major = stat_field(12);
    printf("ACCOUNTING ANON: page_bytes=%zu minflt=%ld -> %ld majflt=%ld -> %ld rss_pages=%lu -> %lu peak_kb=%ld\n",
        page_size, before.ru_minflt, touched.ru_minflt, before.ru_majflt, touched.ru_majflt,
        old_rss, resident, touched.ru_maxrss);
    CHECK(touched.ru_maxrss >= 32 * 1024);
    CHECK(resident >= old_rss + 32 * MIB / page_size);
    CHECK(touched.ru_minflt - before.ru_minflt >= (long)(32 * MIB / page_size));
    CHECK(touched.ru_majflt == before.ru_majflt);
    CHECK(stat_minor >= (unsigned long)touched.ru_minflt);
    CHECK(stat_major == (unsigned long)touched.ru_majflt);
    CHECK(mprotect(memory, 32 * MIB, PROT_NONE) == 0);
    CHECK(stat_field(24) >= resident);
    CHECK(mprotect(memory, 32 * MIB, PROT_READ | PROT_WRITE) == 0);
    CHECK(memory[0] == 0 && memory[page_size] == 1);

    /* libc can take a few COW faults while returning from fork, but it must
     * not copy the thousands of faults accumulated by its parent. */
    int pipefd[2]; CHECK(pipe(pipefd) == 0);
    pid_t child = fork(); CHECK(child >= 0);
    if (!child) {
        close(pipefd[0]); struct rusage fresh = usage(RUSAGE_SELF);
        transfer(pipefd[1], &fresh, sizeof fresh, 1); close(pipefd[1]); _exit(0);
    }
    close(pipefd[1]); struct rusage fresh;
    transfer(pipefd[0], &fresh, sizeof fresh, 0); close(pipefd[0]);
    int status; struct rusage exited;
    CHECK(wait4(child, &status, 0, &exited) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK(fresh.ru_minflt < touched.ru_minflt / 2 && fresh.ru_majflt == 0);
    CHECK(fresh.ru_inblock == 0 && fresh.ru_oublock == 0);
    CHECK(fresh.ru_maxrss >= 32 * 1024); /* Inherited resident pages count as RSS. */
    CHECK(munmap(memory, 32 * MIB) == 0);
    struct rusage unmapped = usage(RUSAGE_SELF);
    CHECK(unmapped.ru_maxrss >= touched.ru_maxrss);
    CHECK(stat_field(24) + 31 * MIB / page_size < resident);
    printf("ACCOUNTING RSS: peak_kb=%ld minflt_delta=%ld resident_pages=%lu\n",
        touched.ru_maxrss, touched.ru_minflt - before.ru_minflt, resident);
    puts("ACCOUNTING PASS: anonymous faults, RSS peak and fresh fork counters");
}

static void shared_fork_rss(void)
{
    size_t amount = 8 * MIB;
    unsigned char *memory = mmap(NULL, amount, PROT_READ | PROT_WRITE,
        MAP_SHARED | MAP_ANONYMOUS, -1, 0); CHECK(memory != MAP_FAILED);
    for (size_t offset = 0; offset < amount; offset += page_size) memory[offset] = 0x31;
    unsigned long inherited = stat_field(24) * page_size / 1024;
    int pipefd[2]; CHECK(pipe(pipefd) == 0);
    pid_t child = fork(); CHECK(child >= 0);
    if (!child) {
        close(pipefd[0]); struct rusage fresh = usage(RUSAGE_SELF);
        CHECK(fresh.ru_maxrss >= (long)inherited);
        CHECK(fresh.ru_maxrss < 24 * 1024); /* Parent's old 32 MiB peak is not inherited. */
        memory[0] = 0x73; transfer(pipefd[1], &fresh, sizeof fresh, 1); close(pipefd[1]); _exit(0);
    }
    close(pipefd[1]); struct rusage fresh;
    transfer(pipefd[0], &fresh, sizeof fresh, 0); close(pipefd[0]);
    int status; struct rusage exited;
    CHECK(wait4(child, &status, 0, &exited) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK(memory[0] == 0x73 && exited.ru_maxrss >= fresh.ru_maxrss);
    CHECK(munmap(memory, amount) == 0);
    puts("ACCOUNTING PASS: shared fork residency without inherited peak history");
}

static void physical_io(void)
{
    struct statfs filesystem;
    CHECK(statfs("/root", &filesystem) == 0 && filesystem.f_type == 0xef53);
    int fd = open("/root/accounting-data", O_CREAT | O_TRUNC | O_RDWR, 0600); CHECK(fd >= 0);
    memset(buffer, 0x6b, sizeof buffer);
    struct rusage before = usage(RUSAGE_SELF);
    for (off_t offset = 0; offset < FILE_BYTES; offset += sizeof buffer)
        CHECK(pwrite(fd, buffer, sizeof buffer, offset) == sizeof buffer);
    CHECK(fsync(fd) == 0);
    struct rusage written = usage(RUSAGE_SELF);
    CHECK(written.ru_oublock - before.ru_oublock >= FILE_BYTES / 512);
    CHECK(pread(fd, buffer, sizeof buffer, 0) == sizeof buffer && buffer[0] == 0x6b);
    checksum += buffer[0]; /* Warm libc pread and this data page before snapshots. */
    CHECK(posix_fadvise(fd, 0, 0, POSIX_FADV_RANDOM) == 0);
    CHECK(posix_fadvise(fd, 0, 0, POSIX_FADV_DONTNEED) == 0);
    before = usage(RUSAGE_SELF);
    CHECK(pread(fd, buffer, sizeof buffer, 0) == sizeof buffer && buffer[0] == 0x6b);
    struct rusage fetched = usage(RUSAGE_SELF);
    CHECK(fetched.ru_inblock - before.ru_inblock >= (long)(sizeof buffer / 512));
    for (int i = 0; i < 100; ++i)
        CHECK(pread(fd, buffer, sizeof buffer, 0) == sizeof buffer && buffer[0] == 0x6b);
    struct rusage cached = usage(RUSAGE_SELF);
    CHECK(cached.ru_inblock == fetched.ru_inblock);

    /* Private read-only mmap faults observe cold backing-device reads on
     * the first pass, then fault the same bytes from the warm vnode cache. */
    CHECK(posix_fadvise(fd, 0, 0, POSIX_FADV_DONTNEED) == 0);
    before = usage(RUSAGE_SELF);
    unsigned char *memory = mmap(NULL, FILE_BYTES, PROT_READ, MAP_PRIVATE, fd, 0);
    CHECK(memory != MAP_FAILED);
    for (size_t offset = 0; offset < FILE_BYTES; offset += page_size) checksum += memory[offset];
    struct rusage cold = usage(RUSAGE_SELF);
    CHECK(cold.ru_majflt > before.ru_majflt && cold.ru_inblock > before.ru_inblock);
    CHECK(munmap(memory, FILE_BYTES) == 0);
    before = usage(RUSAGE_SELF);
    memory = mmap(NULL, FILE_BYTES, PROT_READ, MAP_PRIVATE, fd, 0); CHECK(memory != MAP_FAILED);
    for (size_t offset = 0; offset < FILE_BYTES; offset += page_size) checksum += memory[offset];
    struct rusage warm = usage(RUSAGE_SELF);
    CHECK(warm.ru_minflt > before.ru_minflt && warm.ru_majflt == before.ru_majflt);
    CHECK(warm.ru_inblock == before.ru_inblock);
    CHECK(munmap(memory, FILE_BYTES) == 0 && close(fd) == 0);
    printf("ACCOUNTING IO: written_blocks=%ld fetched_blocks=%ld major_faults=%ld warm_minors=%ld\n",
        written.ru_oublock, fetched.ru_inblock, cold.ru_majflt - cached.ru_majflt, warm.ru_minflt - before.ru_minflt);
    puts("ACCOUNTING PASS: physical I/O, cache hits and cold/warm file faults");
}

struct worker_result { long faults, switches; };
static void *worker(void *opaque)
{
    struct worker_result *result = opaque;
    struct rusage before = usage(RUSAGE_THREAD);
    unsigned char *memory = allocate(8 * MIB);
    for (int i = 0; i < 12; ++i) CHECK(usleep(20000) == 0);
    CHECK(munmap(memory, 8 * MIB) == 0);
    struct rusage after = usage(RUSAGE_THREAD);
    result->faults = after.ru_minflt - before.ru_minflt;
    result->switches = after.ru_nvcsw - before.ru_nvcsw;
    printf("ACCOUNTING WORKER: minor_faults=%ld voluntary_switches=%ld\n", result->faults, result->switches);
    CHECK(result->faults >= (long)(8 * MIB / page_size) && result->switches > 0);
    return NULL;
}

static uint64_t now_ns(void)
{
    struct timespec now; CHECK(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}

static atomic_int busy_ready, busy_stop;
static void *busy_worker(void *unused)
{
    (void)unused; atomic_store(&busy_ready, 1);
    volatile unsigned long value = 1;
    while (!atomic_load(&busy_stop)) for (int i = 0; i < 10000; ++i) value = value * 33 + 1;
    return NULL;
}

static void threads_and_switches(void)
{
    struct rusage before = usage(RUSAGE_SELF);
    pthread_t threads[THREADS]; struct worker_result results[THREADS];
    memset(results, 0, sizeof results);
    for (int i = 0; i < THREADS; ++i) CHECK(pthread_create(&threads[i], NULL, worker, &results[i]) == 0);
    long faults = 0, switches = 0;
    for (int i = 0; i < THREADS; ++i) {
        CHECK(pthread_join(threads[i], NULL) == 0); faults += results[i].faults; switches += results[i].switches;
    }
    struct rusage joined = usage(RUSAGE_SELF);
    CHECK(joined.ru_minflt - before.ru_minflt >= faults);
    CHECK(joined.ru_nvcsw - before.ru_nvcsw >= switches);
    struct rusage main_thread = usage(RUSAGE_THREAD);
    CHECK(joined.ru_minflt > main_thread.ru_minflt);
    CHECK(joined.ru_maxrss == main_thread.ru_maxrss);

    cpu_set_t original, single; CPU_ZERO(&single); CPU_SET(0, &single);
    CHECK(sched_getaffinity(0, sizeof original, &original) == 0);
    CHECK(sched_setaffinity(0, sizeof single, &single) == 0);
    atomic_store(&busy_ready, 0); atomic_store(&busy_stop, 0);
    pthread_t busy; CHECK(pthread_create(&busy, NULL, busy_worker, NULL) == 0);
    while (!atomic_load(&busy_ready)) CHECK(usleep(1000) == 0);
    before = usage(RUSAGE_THREAD);
    volatile unsigned long value = 1; uint64_t end = now_ns() + UINT64_C(500000000);
    while (now_ns() < end) for (int i = 0; i < 10000; ++i) value = value * 17 + 1;
    struct rusage preempted = usage(RUSAGE_THREAD);
    atomic_store(&busy_stop, 1); CHECK(pthread_join(busy, NULL) == 0);
    CHECK(sched_setaffinity(0, sizeof original, &original) == 0);
    CHECK(preempted.ru_nivcsw > before.ru_nivcsw);
    printf("ACCOUNTING THREADS: worker_faults=%ld voluntary_switches=%ld busy_preemptions=%ld\n",
        faults, switches, preempted.ru_nivcsw - before.ru_nivcsw);
    puts("ACCOUNTING PASS: per-thread totals, exited threads and voluntary/involuntary switches");
}

static void child_work(size_t amount)
{
    unsigned char *memory = allocate(amount);
    for (int i = 0; i < 8; ++i) CHECK(usleep(20000) == 0);
    CHECK(munmap(memory, amount) == 0);
    /* Previously mapped pages can remain pinned through a grace period.
     * Use a fresh file that no task has mapped to make its read truly cold. */
    char path[64]; snprintf(path, sizeof path, "/root/accounting-child-%ld", (long)getpid());
    int fd = open(path, O_CREAT | O_EXCL | O_RDWR, 0600); CHECK(fd >= 0);
    CHECK(pwrite(fd, buffer, sizeof buffer, 0) == sizeof buffer && fsync(fd) == 0);
    CHECK(posix_fadvise(fd, 0, 0, POSIX_FADV_RANDOM) == 0);
    CHECK(posix_fadvise(fd, 0, 0, POSIX_FADV_DONTNEED) == 0);
    struct rusage before = usage(RUSAGE_SELF);
    CHECK(pread(fd, buffer, sizeof buffer, 0) == sizeof buffer && buffer[0] == 0x6b);
    CHECK(pwrite(fd, buffer, sizeof buffer, 0) == sizeof buffer && fsync(fd) == 0);
    struct rusage after = usage(RUSAGE_SELF);
    printf("ACCOUNTING CHILD IO: resident_kb=%zu read_blocks=%ld write_blocks=%ld\n",
        amount / 1024, after.ru_inblock - before.ru_inblock, after.ru_oublock - before.ru_oublock);
    CHECK(after.ru_inblock > before.ru_inblock && after.ru_oublock > before.ru_oublock);
    CHECK(close(fd) == 0 && unlink(path) == 0);
}

static struct rusage reap(pid_t child)
{
    int status; struct rusage result;
    CHECK(wait4(child, &status, 0, &result) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    return result;
}

static void children(void)
{
    struct rusage before = usage(RUSAGE_CHILDREN);
    pid_t child = fork(); CHECK(child >= 0);
    if (!child) { child_work(12 * MIB); _exit(0); }
    struct rusage first = reap(child);
    CHECK(first.ru_maxrss >= 12 * 1024 && first.ru_minflt >= (long)(12 * MIB / page_size) && first.ru_nvcsw > 0);
    CHECK(first.ru_maxrss < usage(RUSAGE_SELF).ru_maxrss);
    CHECK(first.ru_inblock > 0 && first.ru_oublock > 0);
    struct rusage once = usage(RUSAGE_CHILDREN);
    CHECK(once.ru_minflt - before.ru_minflt == first.ru_minflt);
    CHECK(once.ru_nvcsw - before.ru_nvcsw == first.ru_nvcsw);

    int pipefd[2]; CHECK(pipe(pipefd) == 0);
    child = fork(); CHECK(child >= 0);
    if (!child) {
        close(pipefd[0]);
        pid_t grandchild = fork(); CHECK(grandchild >= 0);
        if (!grandchild) { close(pipefd[1]); child_work(20 * MIB); _exit(0); }
        struct rusage grand = reap(grandchild);
        transfer(pipefd[1], &grand, sizeof grand, 1); close(pipefd[1]);
        child_work(8 * MIB); _exit(0);
    }
    close(pipefd[1]); struct rusage grand;
    transfer(pipefd[0], &grand, sizeof grand, 0); close(pipefd[0]);
    struct rusage second = reap(child), after = usage(RUSAGE_CHILDREN);
    CHECK(grand.ru_maxrss >= 20 * 1024 && second.ru_maxrss == grand.ru_maxrss);
    CHECK(second.ru_minflt >= grand.ru_minflt + (long)(8 * MIB / page_size));
    CHECK(after.ru_minflt - once.ru_minflt == second.ru_minflt);
    CHECK(after.ru_majflt - once.ru_majflt == second.ru_majflt);
    CHECK(after.ru_inblock - once.ru_inblock == second.ru_inblock);
    CHECK(after.ru_oublock - once.ru_oublock == second.ru_oublock);
    CHECK(after.ru_nvcsw - once.ru_nvcsw == second.ru_nvcsw);
    CHECK(after.ru_nivcsw - once.ru_nivcsw == second.ru_nivcsw);
    long expected = before.ru_maxrss > first.ru_maxrss ? before.ru_maxrss : first.ru_maxrss;
    if (second.ru_maxrss > expected) expected = second.ru_maxrss;
    CHECK(after.ru_maxrss == expected);
    CHECK(stat_field(11) == (unsigned long)after.ru_minflt && stat_field(13) == (unsigned long)after.ru_majflt);
    printf("ACCOUNTING CHILDREN: first_peak=%ld grandchild_peak=%ld combined_peak=%ld minflt=%ld\n",
        first.ru_maxrss, grand.ru_maxrss, after.ru_maxrss, after.ru_minflt);
    puts("ACCOUNTING PASS: wait4, descendant sums and maximum child RSS");
}

struct exec_report { struct rusage process, thread; };

static long cpu_microseconds(struct rusage value)
{
    return (value.ru_utime.tv_sec + value.ru_stime.tv_sec) * 1000000
        + value.ru_utime.tv_usec + value.ru_stime.tv_usec;
}

static void exec_peak(void)
{
    int pipefd[2]; CHECK(pipe(pipefd) == 0);
    pid_t child = fork(); CHECK(child >= 0);
    if (!child) {
        close(pipefd[0]);
        (void)allocate(16 * MIB); /* exec itself must tear down this mapping. */
        struct rusage before = usage(RUSAGE_SELF);
        CHECK(usleep(20000) == 0);
        struct rusage task = usage(RUSAGE_THREAD);
        char descriptor[24], peak[32], faults[32], task_faults[32], switches[32], cpu[32];
        snprintf(descriptor, sizeof descriptor, "%d", pipefd[1]);
        snprintf(peak, sizeof peak, "%ld", before.ru_maxrss);
        snprintf(faults, sizeof faults, "%ld", before.ru_minflt);
        snprintf(task_faults, sizeof task_faults, "%ld", task.ru_minflt);
        snprintf(switches, sizeof switches, "%ld", task.ru_nvcsw);
        snprintf(cpu, sizeof cpu, "%ld", cpu_microseconds(task));
        execl("/sbin/init", "init", "--after-exec", descriptor, peak, faults,
            task_faults, switches, cpu, NULL);
        CHECK(0);
    }
    close(pipefd[1]); struct exec_report after;
    transfer(pipefd[0], &after, sizeof after, 0); close(pipefd[0]);
    struct rusage exited = reap(child);
    CHECK(after.process.ru_maxrss >= 16 * 1024 && exited.ru_maxrss >= after.process.ru_maxrss);
    CHECK(after.thread.ru_maxrss == after.process.ru_maxrss);
    puts("ACCOUNTING PASS: exec preserves counters and RSS history");
}

static void retention(void)
{
    for (int i = 0; i < 50; ++i) {
        (void)usage(RUSAGE_SELF); (void)usage(RUSAGE_THREAD); (void)usage(RUSAGE_CHILDREN); (void)stat_field(24);
    }
    long before = metric("Slab:");
    for (int i = 0; i < 1000; ++i) {
        (void)usage(RUSAGE_SELF); (void)usage(RUSAGE_THREAD); (void)usage(RUSAGE_CHILDREN); (void)stat_field(24);
    }
    long after = metric("Slab:");
    printf("ACCOUNTING RETAINED: 3000 getrusage + 1000 proc reads slab_kb=%ld -> %ld\n", before, after);
    CHECK(after <= before + 16);
}

static void errors_and_retention(void)
{
    struct rusage result;
    errno = 0; CHECK(getrusage(12345, &result) == -1 && errno == EINVAL);
    errno = 0; CHECK(syscall(SYS_getrusage, 12345, NULL) == -1 && errno == EINVAL);
    errno = 0; CHECK(syscall(SYS_getrusage, RUSAGE_SELF, (void *)128) == -1 && errno == EFAULT);
    errno = 0; CHECK(syscall(SYS_getrusage, RUSAGE_THREAD, NULL) == -1 && errno == EFAULT);
    pid_t child = fork(); CHECK(child >= 0);
    if (!child) _exit(0);
    int status;
    errno = 0; CHECK(syscall(SYS_wait4, child, &status, 0, (void *)128) == -1 && errno == EFAULT);
    (void)reap(child); /* EFAULT must preserve the child's wait event. */
    retention();
    puts("ACCOUNTING PASS: pointer errors, wait-event retry and bounded syscall scratch");
}

int main(int argc, char **argv)
{
#ifdef __x86_64__
    int serial = open("/dev/com1", O_WRONLY | O_NOCTTY);
    if (serial >= 0) { dup2(serial, 1); dup2(serial, 2); close(serial); }
#endif
    setbuf(stdout, NULL); page_size = (size_t)sysconf(_SC_PAGESIZE); CHECK(page_size >= 4096);
    if (argc == 8 && !strcmp(argv[1], "--after-exec")) {
        struct exec_report after = { .process = usage(RUSAGE_SELF), .thread = usage(RUSAGE_THREAD) };
        CHECK(after.process.ru_maxrss >= strtol(argv[3], NULL, 10));
        CHECK(after.process.ru_minflt >= strtol(argv[4], NULL, 10));
        CHECK(after.thread.ru_minflt >= strtol(argv[5], NULL, 10));
        CHECK(after.thread.ru_nvcsw >= strtol(argv[6], NULL, 10));
        CHECK(cpu_microseconds(after.thread) >= strtol(argv[7], NULL, 10));
        int fd = (int)strtol(argv[2], NULL, 10);
        transfer(fd, &after, sizeof after, 1); close(fd); _exit(0);
    }
    puts("ACCOUNTING START");
#ifdef ACCOUNTING_RETENTION_ONLY
    /* Keep the same translation unit warning-clean in the baseline mode. */
    (void)anonymous_rss; (void)shared_fork_rss; (void)physical_io;
    (void)threads_and_switches; (void)children; (void)exec_peak;
    (void)errors_and_retention;
    retention();
#else
    anonymous_rss(); shared_fork_rss(); physical_io(); threads_and_switches(); children(); exec_peak(); errors_and_retention();
    CHECK(unlink("/root/accounting-data") == 0); sync();
#endif
    puts("ACCOUNTING DONE pass ino=0");
    for (;;) pause();
}
