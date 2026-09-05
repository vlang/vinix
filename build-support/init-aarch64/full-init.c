/* Freestanding ARM64 init for the full BusyBox/GCC/V test image. */
typedef unsigned long u64;
typedef long i64;

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

static inline i64 syscall1(u64 nr, u64 a0) {
    register u64 x8 __asm__("x8") = nr;
    register u64 x0 __asm__("x0") = a0;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8) : "memory");
    return (i64)x0;
}

static u64 string_length(const char *text) {
    u64 length = 0;
    while (text[length])
        ++length;
    return length;
}

static void print(const char *text) {
    syscall3(64, 1, (u64)text, string_length(text));
}

void _start(void) {
#ifdef VINIX_BUSYBOX_ECHO_TEST
	char *arguments[] = {
		"/bin/busybox", "echo", "VINIX BUSYBOX EXEC TEST: PASS", (char *)0,
	};
#else
	char *arguments[] = {
		"/bin/busybox", "sh", "/etc/vinix-boot-test.sh", (char *)0,
	};
#endif
    char *environment[] = {
        "PATH=/aarch64-linux-musl-native/bin:/bin:/sbin:/usr/bin:/usr/sbin",
        "HOME=/root",
        "TERM=linux",
        "PS1=vinix# ",
        "LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules",
        "LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri",
        (char *)0,
    };

	print("\nVinix ARM64 test userland: starting boot tests\n");
	syscall3(221, (u64)arguments[0], (u64)arguments, (u64)environment);
    print("init: execve /bin/sh failed\n");
    syscall1(93, 1);
    for (;;) {}
}
