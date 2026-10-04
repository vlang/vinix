#define _GNU_SOURCE
#include <stdio.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define CHECK(condition) do { \
    if (!(condition)) { \
        puts("FAIL: kernel guest runner smoke"); \
        for (;;) pause(); \
    } \
} while (0)

int main(void)
{
    setbuf(stdout, NULL);
    CHECK(getpid() == 1);
    struct timespec now;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    unsigned char *memory = mmap(NULL, page, PROT_READ | PROT_WRITE,
                                MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(memory != MAP_FAILED);
    memory[0] = 42;
    pid_t child = fork();
    CHECK(child >= 0);
    if (child == 0) {
        memory[0] = 7;
        _exit(memory[0] == 7 ? 0 : 1);
    }
    int status;
    CHECK(waitpid(child, &status, 0) == child);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0 && memory[0] == 42);
    CHECK(munmap(memory, page) == 0);
    puts("KERNEL GUEST RUNNER: PASS");
    for (;;) pause();
}
