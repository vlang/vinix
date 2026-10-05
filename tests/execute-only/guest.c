#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#if defined(__aarch64__)
static const unsigned char code[] = {0x40, 0x05, 0x80, 0x52, 0xc0, 0x03, 0x5f, 0xd6};
#ifdef EXECUTE_ONLY_EXPECT_READABLE
#define NATIVE_XONLY 0
#else
#define NATIVE_XONLY 1
#endif
#else
static const unsigned char code[] = {0xb8, 0x2a, 0, 0, 0, 0xc3};
#define NATIVE_XONLY 0
#endif
static int failures;
static void check(int ok, const char *name) {
    printf("EXECUTE ONLY %s: %s errno=%d\n", ok ? "PASS" : "FAIL", name, errno);
    failures += !ok;
}
static int status_of(pid_t pid) {
    int status = -1;
    if (pid <= 0) return -1;
    while (waitpid(pid, &status, 0) < 0) if (errno != EINTR) return -1;
    return status;
}
static int exits_ok(int status) {
    return status >= 0 && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}
static int segv(int status) {
    return status >= 0 && WIFSIGNALED(status) && WTERMSIG(status) == SIGSEGV;
}
static int run_code(void *p) { return ((int (*)(void))p)(); }
static void sync_code(unsigned char *p, size_t length) {
#if defined(__aarch64__)
    uintptr_t ctr;
    __asm__ volatile("mrs %0, ctr_el0" : "=r"(ctr));
    size_t dline = 4u << ((ctr >> 16) & 15), iline = 4u << (ctr & 15);
    uintptr_t end = (uintptr_t)p + length;
    for (uintptr_t address = (uintptr_t)p & ~(dline - 1); address < end; address += dline)
        __asm__ volatile("dc cvau, %0" : : "r"(address) : "memory");
    __asm__ volatile("dsb ish" : : : "memory");
    for (uintptr_t address = (uintptr_t)p & ~(iline - 1); address < end; address += iline)
        __asm__ volatile("ic ivau, %0" : : "r"(address) : "memory");
    __asm__ volatile("dsb ish; isb" : : : "memory");
#else
    (void)p; (void)length;
#endif
}
static void fill_code(unsigned char *p, size_t page, int count) {
    for (int i = 0; i < count; i++) memcpy(p + (size_t)i * page, code, sizeof(code));
    sync_code(p, page * (size_t)count);
}
static int copy_denied(int fd, const void *p) {
    errno = 0;
    ssize_t n = write(fd, p, sizeof(code));
    return NATIVE_XONLY ? n == -1 && errno == EFAULT : n == (ssize_t)sizeof(code);
}
static void drain_compat(int fd) {
    if (!NATIVE_XONLY) { unsigned char bytes[sizeof(code)]; (void)read(fd, bytes, sizeof(bytes)); }
}
static long slab_kb(void) {
    char bytes[4096];
    int fd = open("/proc/meminfo", O_RDONLY);
    if (fd < 0) return -1;
    ssize_t n = read(fd, bytes, sizeof(bytes) - 1);
    close(fd);
    if (n < 0) return -1;
    bytes[n] = 0;
    char *p = strstr(bytes, "Slab:");
    return p ? strtol(p + 5, NULL, 10) : -1;
}
int main(void) {
    int console = open("/dev/com1", O_WRONLY | O_NOCTTY);
    if (console >= 0) { dup2(console, 1); dup2(console, 2); close(console); }
    setvbuf(stdout, NULL, _IONBF, 0);
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char *p = mmap(NULL, 3 * page, PROT_READ | PROT_WRITE,
                           MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    int ends[2] = {-1, -1};
    check(p != MAP_FAILED && pipe(ends) == 0, "prepare native code and checked-copy pipe");
    if (p == MAP_FAILED || ends[0] < 0) goto finish;
    fill_code(p, page, 3);
    check(mprotect(p, 3 * page, PROT_EXEC) == 0 && run_code(p) == 42,
          "explicit execute-only native instruction fetch");
    pid_t child = fork();
    if (!child) { volatile unsigned char value = *p; _exit(value == code[0] ? 0 : 1); }
    int status = status_of(child);
    check(NATIVE_XONLY ? segv(status) : exits_ok(status), "native data-read protection (x86 readable fallback)");
    check(copy_denied(ends[1], p), "checked read honors native execute-only support");
    drain_compat(ends[0]);
    unsigned char input[sizeof(code)] = {0};
    check(write(ends[1], input, sizeof(input)) == sizeof(input), "prepare checked output");
    errno = 0;
    check(read(ends[0], p, sizeof(input)) == -1 && errno == EFAULT,
          "checked output cannot modify executable text");
    check(read(ends[0], input, sizeof(input)) == sizeof(input), "failed checked output preserves pipe bytes");
    check(mprotect(p, page, PROT_READ | PROT_EXEC) == 0 && !memcmp(p, code, sizeof(code)) && run_code(p) == 42,
          "read-execute transition permits data reads");
    check(mprotect(p, page, PROT_READ | PROT_WRITE) == 0, "writable transition removes execute permission");
    child = fork();
    if (!child) _exit(run_code(p) == 42 ? 0 : 1);
    check(segv(status_of(child)), "data-only mapping rejects instruction fetch");
    check(mprotect(p, page, PROT_EXEC) == 0 && run_code(p) == 42, "restore execute-only permission");
    puts("EXECUTE ONLY PASS: permissions and checked copies");

    check(mprotect(p + page, page, PROT_READ | PROT_EXEC) == 0, "split range retains independent protections");
    check(!memcmp(p + page, code, sizeof(code)) && run_code(p + 2 * page) == 42,
          "split center readable while outer code still executes");
    check(copy_denied(ends[1], p + 2 * page), "split preserves outer execute-only checked-copy rule");
    drain_compat(ends[0]);
    child = fork();
    if (!child) {
        if (run_code(p) != 42 || run_code(p + page) != 42) _exit(1);
        if (!copy_denied(ends[1], p)) _exit(2);
        _exit(0);
    }
    check(exits_ok(status_of(child)), "fork retains execute-only and readable split permissions");
    drain_compat(ends[0]);
    child = fork();
    if (!child) {
        if (mprotect(p, page, PROT_READ | PROT_WRITE)) _exit(1);
#if defined(__aarch64__)
        p[0] = 0x60; /* mov w0, #43 */
#else
        p[1] = 43;
#endif
        sync_code(p, page);
        if (mprotect(p, page, PROT_EXEC) || run_code(p) != 43) _exit(2);
        _exit(0);
    }
    check(exits_ok(status_of(child)) && run_code(p) == 42,
          "fork COW writable transition preserves parent's execute-only bytes");
    unsigned char *moved = mremap(p + 2 * page, page, 2 * page, MREMAP_MAYMOVE);
    check(moved != MAP_FAILED && run_code(moved) == 42, "remap retains execute-only instruction bytes");
    if (moved != MAP_FAILED) {
        check(copy_denied(ends[1], moved), "remap preserves checked-copy protection");
        drain_compat(ends[0]);
        check(mprotect(moved, page, PROT_READ | PROT_EXEC) == 0 && !memcmp(moved, code, sizeof(code)),
              "remapped bytes survive protection change");
        munmap(moved, 2 * page);
    }

    int fd = open("/tmp/execute-only-code", O_CREAT | O_TRUNC | O_RDWR, 0600);
    unsigned char *file_code = MAP_FAILED;
    if (fd >= 0 && ftruncate(fd, (off_t)page) == 0 && pwrite(fd, code, sizeof(code), 0) == sizeof(code))
        file_code = mmap(NULL, page, PROT_EXEC, MAP_PRIVATE, fd, 0);
    check(file_code != MAP_FAILED && run_code(file_code) == 42, "demand-paged file executes without a readable data mapping");
    if (file_code != MAP_FAILED) {
        check(copy_denied(ends[1], file_code), "file-backed checked-read rule");
        drain_compat(ends[0]);
        check(mprotect(file_code, page, PROT_READ | PROT_EXEC) == 0 && !memcmp(file_code, code, sizeof(code)),
              "file-backed protection transition preserves code");
        munmap(file_code, page);
    }
    if (fd >= 0) close(fd);
    unlink("/tmp/execute-only-code");
    check(mprotect(p, page, PROT_EXEC) == 0, "prepare repeated checked denials");
    for (int i = 0; i < 100; i++) { (void)copy_denied(ends[1], p); drain_compat(ends[0]); }
    long before = slab_kb();
    int bad = 0;
    for (int i = 0; i < 3000; i++) {
        bad += !copy_denied(ends[1], p);
        drain_compat(ends[0]);
    }
    long after = slab_kb();
    printf("EXECUTE ONLY slab: before=%ld after=%ld KiB\n", before, after);
    check(!bad && before >= 0 && after >= 0 && after <= before + 16,
          "repeated native checked reads have bounded retained scratch");
    munmap(p, 3 * page);
    close(ends[0]); close(ends[1]);
    puts("EXECUTE ONLY PASS: fork split remap and demand paging");
finish:
    puts(failures ? "EXECUTE ONLY GUEST: FAIL" : "EXECUTE ONLY GUEST: PASS");
    for (;;) pause();
}
