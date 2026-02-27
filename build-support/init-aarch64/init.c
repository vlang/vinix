/* Minimal interactive shell for Vinix aarch64 userland.
 * No libc -- raw SVC syscalls only.
 *
 * Syscall ABI: x8 = number, x0-x5 = args.
 * Numbers: read=3, write=4, exit=15
 */

typedef unsigned long u64;
typedef long i64;
typedef unsigned int u32;

static inline i64 syscall1(u64 nr, u64 a0) {
    register u64 x8 __asm__("x8") = nr;
    register u64 x0 __asm__("x0") = a0;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8) : "memory");
    return (i64)x0;
}

static inline i64 syscall3(u64 nr, u64 a0, u64 a1, u64 a2) {
    register u64 x8 __asm__("x8") = nr;
    register u64 x0 __asm__("x0") = a0;
    register u64 x1 __asm__("x1") = a1;
    register u64 x2 __asm__("x2") = a2;
    __asm__ volatile("svc #0"
        : "+r"(x0)
        : "r"(x8), "r"(x1), "r"(x2)
        : "memory");
    return (i64)x0;
}

#define SYS_read  63
#define SYS_write 64
#define SYS_exit  93

static i64 write(int fd, const void *buf, u64 count) {
    return syscall3(SYS_write, (u64)fd, (u64)buf, count);
}

static i64 read(int fd, void *buf, u64 count) {
    return syscall3(SYS_read, (u64)fd, (u64)buf, count);
}

static void exit(int status) {
    syscall1(SYS_exit, (u64)status);
    for (;;) ;
}

static u64 strlen(const char *s) {
    u64 n = 0;
    while (s[n]) n++;
    return n;
}

static void puts(const char *s) {
    write(1, s, strlen(s));
}

static int strcmp(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return (int)(unsigned char)*a - (int)(unsigned char)*b;
}

/* Skip leading spaces, return 0 if string is empty/whitespace-only */
static int is_empty(const char *s) {
    while (*s == ' ' || *s == '\t') s++;
    return *s == '\0';
}

static void do_help(void) {
    puts("Available commands:\n");
    puts("  help   - show this message\n");
    puts("  hello  - print greeting\n");
    puts("  uname  - show system info\n");
    puts("  echo   - echo arguments\n");
    puts("  exit   - exit shell\n");
}

static void do_uname(void) {
    puts("Vinix 0.1.0 aarch64\n");
}

static void do_hello(void) {
    puts("Hello from userland!\n");
}

/* echo: print everything after "echo " */
static void do_echo(const char *line) {
    const char *p = line + 4; /* skip "echo" */
    while (*p == ' ') p++;
    if (*p) {
        puts(p);
    }
    puts("\n");
}

void _start(void) {
    puts("\n");
    puts("  _   _ _       _\n");
    puts(" | | | (_)_ __ (_)_  __\n");
    puts(" | | | | | '_ \\| \\ \\/ /\n");
    puts(" | |_| | | | | | |>  <\n");
    puts("  \\___/|_|_| |_|_/_/\\_\\\n");
    puts("\n");
    puts("Welcome to Vinix (aarch64)\n");
    puts("Type 'help' for available commands.\n\n");

    char buf[256];

    for (;;) {
        puts("vinix# ");

        /* Read one line (console is in canonical mode, so read blocks
         * until newline and returns the whole line including '\n'). */
        i64 n = read(0, buf, sizeof(buf) - 1);
        if (n <= 0) {
            puts("\nread error or EOF, exiting\n");
            exit(1);
        }

        /* Null-terminate and strip trailing newline */
        buf[n] = '\0';
        if (n > 0 && buf[n - 1] == '\n') buf[n - 1] = '\0';
        if (n > 1 && buf[n - 2] == '\r') buf[n - 2] = '\0';

        if (is_empty(buf)) continue;

        if (strcmp(buf, "help") == 0) {
            do_help();
        } else if (strcmp(buf, "hello") == 0) {
            do_hello();
        } else if (strcmp(buf, "uname") == 0) {
            do_uname();
        } else if (buf[0] == 'e' && buf[1] == 'c' && buf[2] == 'h' &&
                   buf[3] == 'o' && (buf[4] == ' ' || buf[4] == '\0')) {
            do_echo(buf);
        } else if (strcmp(buf, "exit") == 0) {
            puts("Goodbye!\n");
            exit(0);
        } else {
            puts("unknown command: ");
            puts(buf);
            puts("\n");
        }
    }
}
