/* Freestanding ARM64 init for the desktop image.
 *
 * It exists only to hand control to the compositor. The desktop image carries
 * nothing but the desktop, BusyBox and this, so there is no service manager to
 * go through and no reason for one: if the compositor exits, init falls back
 * to a shell so the machine stays usable.
 *
 * stdin, stdout and stderr are already /dev/console when the kernel starts
 * init, and exec keeps them, which is how the desktop reads the keyboard. */
typedef unsigned long u64;
typedef long i64;

static inline i64 syscall3(u64 nr, u64 a0, u64 a1, u64 a2) {
	register u64 x8 __asm__("x8") = nr;
	register u64 x0 __asm__("x0") = a0;
	register u64 x1 __asm__("x1") = a1;
	register u64 x2 __asm__("x2") = a2;
	__asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory");
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
	syscall3(64 /* write */, 1, (u64)text, string_length(text));
}

static char *environment[] = {
	"PATH=/bin:/sbin:/usr/bin:/usr/sbin",
	"HOME=/root",
	"TERM=linux",
	"PS1=vinix# ",
	(char *)0,
};

void _start(void) {
	char *desktop[] = { "/usr/bin/vinix-desktop", (char *)0 };
	char *shell[] = { "/bin/busybox", "sh", (char *)0 };

	print("\nVinix: starting the desktop\n");
	syscall3(221 /* execve */, (u64)desktop[0], (u64)desktop, (u64)environment);

	print("init: could not start /usr/bin/vinix-desktop; falling back to a shell\n");
	syscall3(221 /* execve */, (u64)shell[0], (u64)shell, (u64)environment);

	print("init: no shell either\n");
	syscall1(93 /* exit */, 1);
	for (;;) {
	}
}
