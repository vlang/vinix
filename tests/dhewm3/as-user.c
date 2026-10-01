/* Run the benchmark as the guest's ordinary game user on both kernels. */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

static uint64_t counter(void)
{
    uint64_t value;
    __asm__ volatile("isb; mrs %0, cntvct_el0" : "=r"(value) : : "memory");
    return value;
}

int main(int argc, char **argv)
{
    if (argc < 2)
        return 2;
    if (setgid(1000) != 0 || setuid(1000) != 0) {
        perror("setuid/setgid");
        return 1;
    }
    uint64_t frequency;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(frequency));
    uint64_t started = counter();
    pid_t child = fork();
    if (child == -1) {
        perror("fork");
        return 1;
    }
    if (child == 0) {
        execvp(argv[1], argv + 1);
        perror("execvp");
        _exit(1);
    }
    int status;
    if (waitpid(child, &status, 0) != child) {
        perror("waitpid");
        return 1;
    }
    uint64_t elapsed = counter() - started;
    uint64_t elapsed_ns = elapsed / frequency * 1000000000 +
                          elapsed % frequency * 1000000000 / frequency;
    printf("DHEWM3-ELAPSED ns=%llu status=%d\n", (unsigned long long)elapsed_ns, status);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
