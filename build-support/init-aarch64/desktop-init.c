// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* Freestanding ARM64 init for the desktop image.
 *
 * Native applications are separate processes, and the compositor is a
 * supervised process too: losing either one must not strand the machine at
 * the framebuffer console. PID 1 restarts the compositor after an unexpected
 * exit and only opens a recovery shell when the executable cannot start.
 *
 * stdin, stdout and stderr are already /dev/console when the kernel starts
 * init. The compositor inherits them, which is how it reads the keyboard. */
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

static inline i64 syscall2(u64 nr, u64 a0, u64 a1) {
	register u64 x8 __asm__("x8") = nr;
	register u64 x0 __asm__("x0") = a0;
	register u64 x1 __asm__("x1") = a1;
	__asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1) : "memory");
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

static void print_number(u64 value) {
	char digits[24];
	u64 index = sizeof(digits);
	do {
		digits[--index] = (char)('0' + value % 10);
		value /= 10;
	} while (value);
	syscall3(64 /* write */, 1, (u64)&digits[index], sizeof(digits) - index);
}

static const char *signal_name(int signal) {
	switch (signal) {
	case 1: return "SIGHUP";
	case 2: return "SIGINT";
	case 3: return "SIGQUIT";
	case 4: return "SIGILL";
	case 5: return "SIGTRAP";
	case 6: return "SIGABRT";
	case 7: return "SIGBUS";
	case 8: return "SIGFPE";
	case 9: return "SIGKILL";
	case 10: return "SIGUSR1";
	case 11: return "SIGSEGV";
	case 12: return "SIGUSR2";
	case 13: return "SIGPIPE";
	case 14: return "SIGALRM";
	case 15: return "SIGTERM";
	case 24: return "SIGXCPU";
	case 25: return "SIGXFSZ";
	case 31: return "SIGSYS";
	default: return "unknown signal";
	}
}

static void report_desktop_exit(i64 child, int status) {
	int signal = status & 0x7f;
	print("init: vinix-desktop (pid ");
	print_number((u64)child);
	if (signal && signal != 0x7f) {
		print(") crashed with ");
		print(signal_name(signal));
		print(" (signal ");
		print_number((u64)signal);
		print(")");
	} else {
		int code = (status >> 8) & 0xff;
		if (code == 0) {
			print(") exited cleanly");
		} else {
			print(") exited with status ");
			print_number((u64)code);
		}
	}
	print("; restarting in one second\n");
}

/* BusyBox's reboot tools signal PID 1. Catch those requests and forward them
 * to the compositor, which owns the orderly application/framebuffer teardown.
 * SIGHUP is the separate development-session reload request: it tears the
 * compositor down through the same orderly path, but never reaches reboot(2).
 * The raw ARM64 signal ABI needs an rt_sigreturn restorer because this init has
 * no libc trampoline. */
static volatile int requested_power_signal;
static volatile int requested_desktop_reload;

static void power_signal_handler(int signal) {
	if (signal == 1 /* SIGHUP */)
		requested_desktop_reload = 1;
	else
		requested_power_signal = signal;
}

__attribute__((naked)) static void signal_restorer(void) {
	__asm__ volatile(
		"mov x8, #139\n"
		"svc #0\n"
		"brk #0\n");
}

struct kernel_sigaction {
	void (*handler)(int);
	u64 flags;
	void (*restorer)(void);
	u64 mask;
};

static void install_power_signal(int signal) {
	struct kernel_sigaction action = {
		power_signal_handler, 0, signal_restorer, 0,
	};
	syscall4(134 /* rt_sigaction */, (u64)signal, (u64)&action, 0, 8);
}

static void install_power_signals(void) {
	install_power_signal(1 /* SIGHUP: reload desktop */);
	install_power_signal(15 /* SIGTERM: reboot */);
	install_power_signal(10 /* SIGUSR1: halt */);
	install_power_signal(12 /* SIGUSR2: power off */);
}

static void apply_power_request(void) {
	int signal = requested_power_signal;
	u64 command;
	if (!signal)
		return;
	command = signal == 15 ? 0x01234567UL
	        : signal == 10 ? 0xcdef0123UL : 0x4321fedcUL;
	syscall1(81 /* sync */, 0);
	syscall4(142 /* reboot */, 0xfee1deadUL, 0x28121969UL, command, 0);
	print("init: the kernel refused the power request\n");
	requested_power_signal = 0;
}

struct kernel_timespec {
	i64 seconds;
	i64 nanoseconds;
};

static void restart_pause(void) {
	struct kernel_timespec delay = { 1, 0 };
	syscall4(115 /* clock_nanosleep */, 1 /* CLOCK_MONOTONIC */, 0,
	         (u64)&delay, 0);
}

static void teardown_pause(void) {
	struct kernel_timespec delay = { 0, 10000000 /* 10 ms */ };
	syscall4(115 /* clock_nanosleep */, 1 /* CLOCK_MONOTONIC */, 0,
	         (u64)&delay, 0);
}

/* Wait for one supervised child. A power signal interrupts wait4; forward it
 * once, then let the compositor perform its normal clean shutdown. */
static void wait_for_child(i64 child, int *status) {
	int forwarded_signal = 0;
	for (;;) {
		int signal = requested_power_signal;
		if (!signal && requested_desktop_reload)
			signal = 1 /* SIGHUP */;
		if (signal && signal != forwarded_signal) {
			syscall2(129 /* kill */, (u64)child, (u64)signal);
			forwarded_signal = signal;
		}
		if (syscall4(260 /* wait4 */, (u64)child, (u64)status, 0, 0) == child)
			return;
	}
}

static i64 spawn_program(char **arguments, char **fallback, int own_group,
					 int *status, char **environment, int trace_launch) {
	i64 child = syscall5(220 /* clone */, 17 /* SIGCHLD */, 0, 0, 0, 0);
	/* Keep the post-clone trace on the child only. Concurrent parent/child
	 * writes to the framebuffer console make the diagnostic itself capable of
	 * stalling before exec, which hides the boundary it is meant to expose. */
	if (child == 0) {
		if (own_group)
			syscall2(154 /* setpgid */, 0, 0);
		if (trace_launch)
			print("init: GPU desktop child process group ready; entering execve\n");
		syscall3(221 /* execve */, (u64)arguments[0], (u64)arguments,
		         (u64)environment);
		if (trace_launch)
			print("init: GPU desktop execve returned; trying software fallback\n");
		if (fallback)
			syscall3(221 /* execve */, (u64)fallback[0], (u64)fallback,
			         (u64)environment);
		if (trace_launch)
			print("init: GPU and software desktop execve both failed\n");
		syscall1(93 /* exit */, 127);
	}
	if (child > 0) {
		if (own_group)
			syscall2(154 /* setpgid */, (u64)child, (u64)child);
		wait_for_child(child, status);
	}
	return child;
}

static void reap_exited_children(void) {
	int status;
	while (syscall4(260 /* wait4 */, (u64)(i64)-1, (u64)&status,
	                1 /* WNOHANG */, 0) > 0) {
	}
}

static int wait_for_desktop_group(i64 child, int attempts) {
	while (attempts-- > 0) {
		/* The compositor's application children are adopted by PID 1 when it
		 * exits. Reap first: kill(group, 0) deliberately still sees zombies. */
		reap_exited_children();
		if (syscall2(129 /* kill */, (u64)-child, 0) < 0)
			return 1;
		teardown_pause();
	}
	return 0;
}

static void stop_desktop_group(i64 child) {
	if (child <= 0) {
		reap_exited_children();
		return;
	}

	/* Application children inherit the compositor's process group. If the
	 * compositor died before closing them, do not carry them into its next
	 * session. More importantly, do not launch a replacement while those old
	 * processes are still exiting: doing that used to race their address-space
	 * and scheduler teardown against the new compositor, intermittently
	 * wedging the whole guest after an in-Terminal desktop rebuild. */
	syscall2(129 /* kill */, (u64)-child, 15 /* SIGTERM */);
	if (wait_for_desktop_group(child, 100 /* one second */))
		return;

	syscall2(129 /* kill */, (u64)-child, 9 /* SIGKILL */);
	if (!wait_for_desktop_group(child, 500 /* five seconds */))
		print("init: old desktop process group did not stop within five seconds\n");
	reap_exited_children();
}

static int gpu_available(void) {
	i64 fd = syscall4(56 /* openat */, (u64)(i64)-100 /* AT_FDCWD */,
	                  (u64)"/dev/dri/renderD128", 2 /* O_RDWR */, 0);
	if (fd < 0)
		return 0;
	syscall1(57 /* close */, (u64)fd);
	return 1;
}

static int executable_available(const char *path) {
	i64 fd = syscall4(56 /* openat */, (u64)(i64)-100 /* AT_FDCWD */,
	                  (u64)path, 0 /* O_RDONLY */, 0);
	if (fd < 0)
		return 0;
	syscall1(57 /* close */, (u64)fd);
	return 1;
}

/* A development reload replaces /usr/bin/vinix-desktop so all of its
 * multicall application links use the same freshly built program. A disk-root
 * QEMU machine persists that mutation, including across a host-side image
 * rebuild whose contents happen to be unchanged. Restore the packaged inode
 * atomically at boot and clear /run state before deciding which session this
 * boot should start. The immutable copy is deliberately outside /usr/bin so a
 * reload can never overwrite it through one of the multicall links. */
static void prepare_desktop_boot(void) {
	static const char system_desktop[] =
		"/usr/libexec/vinix-desktop-system";
	static const char temporary_desktop[] =
		"/usr/bin/.vinix-desktop.system";
	static const char desktop[] = "/usr/bin/vinix-desktop";
	const u64 at_fdcwd = (u64)(i64)-100;

	syscall3(35 /* unlinkat */, at_fdcwd,
	         (u64)"/run/vinix-desktop-development", 0);
	syscall3(35 /* unlinkat */, at_fdcwd,
	         (u64)"/run/vinix-desktop-ready", 0);

	/* Older images have no immutable copy. Leave their existing desktop alone
	 * rather than removing the only executable they can start. */
	if (!executable_available(system_desktop))
		return;
	syscall3(35 /* unlinkat */, at_fdcwd, (u64)temporary_desktop, 0);
	if (syscall5(37 /* linkat */, at_fdcwd, (u64)system_desktop,
	             at_fdcwd, (u64)temporary_desktop, 0) < 0 ||
	    syscall4(38 /* renameat */, at_fdcwd, (u64)temporary_desktop,
	             at_fdcwd, (u64)desktop) < 0) {
		syscall3(35 /* unlinkat */, at_fdcwd, (u64)temporary_desktop, 0);
		print("init: could not restore the packaged desktop; keeping the existing binary\n");
	}
}

/* A self-hosted desktop build writes this marker before asking PID 1 to
 * reload. On GPU systems that deliberately selects the newly built ordinary
 * framebuffer binary instead of silently going back to the immutable GPU
 * variant from the boot image. The marker lives in /run and vanishes at boot. */
static int development_desktop_requested(void) {
	return executable_available("/run/vinix-desktop-development");
}

/* Hyprland is an optional alternate session. The QEMU runner adds this
 * per-boot marker for run-hyprland-aarch64.sh, so merely staging its runtime
 * never replaces the native desktop with a full-screen terminal. */
static int hyprland_requested(void) {
	i64 fd = syscall4(56 /* openat */, (u64)(i64)-100 /* AT_FDCWD */,
	                  (u64)"/etc/vinix/boot-hyprland", 0 /* O_RDONLY */, 0);
	if (fd < 0)
		return 0;
	syscall1(57 /* close */, (u64)fd);
	return 1;
}

static char *environment[] = {
	"PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
	"HOME=/root",
	"TERM=linux",
	"PS1=vinix# ",
	"USER=root",
	"LOGNAME=root",
	"SHELL=/bin/zsh",
	"LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules",
	"LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri",
	"XDG_RUNTIME_DIR=/run/user/0",
	"XDG_CONFIG_HOME=/root/.config",
	"XDG_CACHE_HOME=/root/.cache",
	"SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt",
	"VINIX_SYSTEM_SESSION=1",
	(char *)0,
};

void _start(void) {
	char *desktop[] = { "/usr/bin/vinix-desktop", (char *)0 };
	char *gpu_desktop[] = { "/usr/bin/vinix-desktop-gpu", (char *)0 };
	char *hyprland[] = { "/usr/bin/start-hyprland-vinix", (char *)0 };
	char *shell[] = { "/bin/zsh", "-l", (char *)0 };
	int status = 0;
	i64 child;
	prepare_desktop_boot();
	install_power_signals();

#ifdef VINIX_WIFI_BUNDLE
	char *wifi[] = {
		"/usr/bin/wifi-ctl", "load", "/usr/share/vinix/wifi", (char *)0,
	};
	print("\nVinix: loading the selected Wi-Fi firmware\n");
	child = spawn_program(wifi, (char **)0, 0, &status, environment, 0);
	if (requested_power_signal)
		apply_power_request();
	if (child < 0 || status != 0)
		print("init: Wi-Fi firmware load failed; continuing without wireless\n");
#endif

	if (hyprland_requested() && executable_available(hyprland[0])) {
		print("\nVinix: starting Hyprland\n");
		child = spawn_program(hyprland, (char **)0, 1, &status, environment, 0);
		if (requested_power_signal)
			apply_power_request();
		print("init: Hyprland exited; starting the native recovery desktop\n");
	}

	for (;;) {
		char **selected = desktop;
		char **fallback = (char **)0;
		if (requested_power_signal)
			apply_power_request();
		if (gpu_available() && !development_desktop_requested()) {
			selected = gpu_desktop;
			fallback = desktop;
			print("\nVinix: starting the GPU-enabled desktop\n");
		} else {
			print("\nVinix: starting the desktop\n");
		}
		status = 0;
		child = spawn_program(selected, fallback, 1, &status, environment,
		                      selected == gpu_desktop);
		if (requested_power_signal)
			apply_power_request();
		if (requested_desktop_reload) {
			requested_desktop_reload = 0;
			print("init: desktop reload requested; starting the new binary\n");
			stop_desktop_group(child);
			/* Closing the old Terminal's PTY can deliver another SIGHUP while
			 * its process group is being dismantled. It belongs to the reload
			 * already completed above; carrying it into the replacement session
			 * creates an endless ready/reload loop. A real later build will send
			 * a new request after the replacement is running. */
			requested_desktop_reload = 0;
			continue;
		}
		if (child < 0 || status == (127 << 8)) {
			print("init: could not start vinix-desktop; opening a recovery shell\n");
			status = 0;
			child = spawn_program(shell, (char **)0, 0, &status, environment, 0);
			if (requested_power_signal)
				apply_power_request();
			if (child < 0)
				print("init: no recovery shell either; retrying the desktop\n");
			continue;
		}
		report_desktop_exit(child, status);
		stop_desktop_group(child);
		restart_pause();
	}
}
