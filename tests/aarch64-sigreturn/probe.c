#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <ucontext.h>
#include <unistd.h>

static volatile sig_atomic_t ticks;
static volatile sig_atomic_t unaligned_context;
static volatile sig_atomic_t handler_error;
static volatile sig_atomic_t unaligned_phase;

/* Use only async-signal-safe write and local formatting in the handler. The
 * public ucontext is inspected, never changed. The handler's own stack is
 * aligned by the kernel even when the interrupted register-only code is not. */
static void context_line(uint64_t sp, uint64_t pc)
{
    static const char hex[] = "0123456789abcdef";
    char text[] = "SIGNAL-RETURN-CONTEXT sp=0x0000000000000000 pc=0x0000000000000000\n";
    for (unsigned int i = 0; i < 16; ++i) {
        text[27 + i] = hex[(sp >> (60 - i * 4)) & 15];
        text[49 + i] = hex[(pc >> (60 - i * 4)) & 15];
    }
    (void)write(STDOUT_FILENO, text, sizeof(text) - 1);
}

static void alarm_handler(int signum, siginfo_t *info, void *context)
{
    int saved_errno = errno;
    ucontext_t *uc = context;
    if (signum != SIGALRM || info == NULL || uc == NULL) {
        handler_error = 1;
    } else {
        ++ticks;
        if (unaligned_phase && (uc->uc_mcontext.sp & 15) == 8 && !unaligned_context) {
            context_line(uc->uc_mcontext.sp, uc->uc_mcontext.pc);
            unaligned_context = 1;
        }
    }
    errno = saved_errno;
}

static void timer(int enabled)
{
    struct itimerval it = {{0, 0}, {0, 0}};
    if (enabled) {
        it.it_interval.tv_usec = 1000;
        it.it_value.tv_usec = 1000;
    }
    if (setitimer(ITIMER_REAL, &it, NULL) != 0) {
        perror("FAIL: setitimer");
        exit(2);
    }
}

static void require(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: SIGNAL-RETURN %s errno=%d ticks=%d\n", message, errno, ticks);
        exit(2);
    }
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = alarm_handler;
    sa.sa_flags = SA_SIGINFO | SA_RESTART;
    sigemptyset(&sa.sa_mask);
    require(sigaction(SIGALRM, &sa, NULL) == 0, "sigaction");
    printf("SIGNAL-RETURN-START dynamic-musl SA_SIGINFO SA_RESTART\n");

    timer(1);
    volatile uint64_t canary = UINT64_C(0x312fedcba0987654);
    sig_atomic_t start = ticks;
    while (ticks - start < 64) {
        for (unsigned int i = 0; i < 10000; ++i)
            canary = (canary << 7) ^ (canary >> 3) ^ i;
    }
    require(!handler_error, "busy handler");
    printf("SIGNAL-RETURN-BUSY-PASS signals=%d canary=%llx\n", ticks - start,
           (unsigned long long)canary);

    void *self = dlopen(NULL, RTLD_NOW);
    require(self != NULL && dlsym(self, "memcpy") != NULL, "dynamic libc symbol");
    start = ticks;
    unsigned int calls = 0;
    while (ticks - start < 64) {
        jmp_buf env;
        require(setjmp(env) == 0, "setjmp control");
        char *allocation = malloc(512);
        require(allocation != NULL, "malloc");
        int length = snprintf(allocation, 512, "libc iteration %u", ++calls);
        require(length > 0 && strlen(allocation) == (size_t)length, "snprintf strlen");
        free(allocation);
    }
    require(dlclose(self) == 0 && !handler_error, "libc handler");
    printf("SIGNAL-RETURN-LIBC-PASS signals=%d calls=%u\n", ticks - start, calls);
    timer(0);

    int pipefd[2];
    require(pipe(pipefd) == 0, "pipe");
    pid_t writer = fork();
    require(writer >= 0, "fork writer");
    if (writer == 0) {
        close(pipefd[0]);
        for (unsigned int i = 0; i < 8; ++i) {
            usleep(20000);
            if (write(pipefd[1], "x", 1) != 1) _exit(3);
        }
        close(pipefd[1]);
        _exit(0);
    }
    close(pipefd[1]);
    timer(1);
    start = ticks;
    unsigned int bytes = 0, interrupted = 0;
    for (;;) {
        char byte;
        ssize_t n = read(pipefd[0], &byte, 1);
        if (n == 1) { require(byte == 'x', "pipe data"); ++bytes; }
        else if (n == 0) break;
        else if (errno == EINTR) ++interrupted;
        else require(0, "pipe read");
    }
    close(pipefd[0]);
    int writer_status = 0;
    pid_t reaped;
    do { reaped = waitpid(writer, &writer_status, 0); } while (reaped < 0 && errno == EINTR);
    require(reaped == writer && WIFEXITED(writer_status) && WEXITSTATUS(writer_status) == 0,
            "writer status");
    require(bytes == 8 && ticks > start && !handler_error, "I/O handler");
    printf("SIGNAL-RETURN-IO-PASS signals=%d bytes=%u EINTR=%u\n", ticks - start, bytes, interrupted);
    timer(0);

    /* All compiler-generated accesses and C calls use an aligned stack.
     * This single assembly block temporarily changes SP by eight bytes, waits
     * for a genuine asynchronous SIGALRM through a global-address register,
     * and restores SP before returning to compiler-generated code. No memory
     * access through SP, C call, fake frame, or ucontext edit occurs here. */
    unaligned_phase = 1;
    unaligned_context = 0;
    printf("SIGNAL-RETURN-UNALIGNED-BEGIN\n");
    timer(1);
    __asm__ volatile(
        "sub sp, sp, #8\n"
        "1: ldr w9, [%0]\n"
        "cbz w9, 1b\n"
        "add sp, sp, #8\n"
        : : "r"(&unaligned_context) : "x9", "memory", "cc");
    timer(0);
    require(unaligned_context && !handler_error, "unaligned context returned");
    printf("SIGNAL-RETURN-PASS signals=%d unaligned-context=1\n", ticks);
    return 0;
}
