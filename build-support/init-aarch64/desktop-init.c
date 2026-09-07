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

static inline i64 syscall4(u64 nr, u64 a0, u64 a1, u64 a2, u64 a3) {
	register u64 x8 __asm__("x8") = nr;
	register u64 x0 __asm__("x0") = a0;
	register u64 x1 __asm__("x1") = a1;
	register u64 x2 __asm__("x2") = a2;
	register u64 x3 __asm__("x3") = a3;
	__asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory");
	return (i64)x0;
}

static inline i64 syscall5(u64 nr, u64 a0, u64 a1, u64 a2, u64 a3, u64 a4) {
	register u64 x8 __asm__("x8") = nr;
	register u64 x0 __asm__("x0") = a0;
	register u64 x1 __asm__("x1") = a1;
	register u64 x2 __asm__("x2") = a2;
	register u64 x3 __asm__("x3") = a3;
	register u64 x4 __asm__("x4") = a4;
	__asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4) : "memory");
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

static int gpu_available(void) {
	i64 fd = syscall4(56 /* openat */, (u64)(i64)-100 /* AT_FDCWD */,
	                  (u64)"/dev/dri/renderD128", 2 /* O_RDWR */, 0);
	if (fd < 0)
		return 0;
	syscall1(57 /* close */, (u64)fd);
	return 1;
}

static char *environment[] = {
	"PATH=/aarch64-linux-musl-native/bin:/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin",
	"HOME=/root",
	"TERM=linux",
	"PS1=vinix# ",
	"USER=root",
	"LOGNAME=root",
	"SHELL=/bin/busybox",
	"LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules",
	"LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri",
	"SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt",
	(char *)0,
};

void _start(void) {
	char *desktop[] = { "/usr/bin/vinix-desktop", (char *)0 };
	char *gpu_desktop[] = { "/usr/bin/vinix-desktop-gpu", (char *)0 };
	char *shell[] = { "/bin/busybox", "sh", (char *)0 };

#ifdef VINIX_WIFI_BUNDLE
	char *wifi[] = {
		"/usr/bin/wifi-ctl", "load", "/usr/share/vinix/wifi", (char *)0,
	};
	int status = 0;
	i64 child;

	print("\nVinix: loading the selected Wi-Fi firmware\n");
	child = syscall5(220 /* clone */, 17 /* SIGCHLD */, 0, 0, 0, 0);
	if (child == 0) {
		syscall3(221 /* execve */, (u64)wifi[0], (u64)wifi, (u64)environment);
		print("init: could not start /usr/bin/wifi-ctl\n");
		syscall1(93 /* exit */, 127);
	}
	if (child < 0 || syscall4(260 /* wait4 */, (u64)child, (u64)&status, 0, 0) < 0 || status != 0)
		print("init: Wi-Fi firmware load failed; continuing without wireless\n");
#endif

	if (gpu_available()) {
		print("\nVinix: starting the GPU-enabled desktop\n");
		syscall3(221 /* execve */, (u64)gpu_desktop[0], (u64)gpu_desktop,
		         (u64)environment);
		print("init: GPU desktop unavailable; using the static software desktop\n");
	}

	print("\nVinix: starting the desktop\n");
	syscall3(221 /* execve */, (u64)desktop[0], (u64)desktop, (u64)environment);

	print("init: could not start /usr/bin/vinix-desktop; falling back to a shell\n");
	syscall3(221 /* execve */, (u64)shell[0], (u64)shell, (u64)environment);

	print("init: no shell either\n");
	syscall1(93 /* exit */, 1);
	for (;;) {
	}
}
