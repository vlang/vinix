// Independent terminal-job-control oracle; original C guards and sequencing retained.
@[has_globals]
module guestfixture

#include <native-abi.h>

struct C.tj_signal_word {
mut:
	value i32
}

struct C.tj_transition_word {
mut:
	value i32
}

@[typedef]
struct C.sigset_t {}

@[typedef]
struct C.pthread_t {}

struct C.sigaction {
mut:
	sa_handler fn (i32)
	sa_mask    C.sigset_t
	sa_flags   i32
}

struct C.timespec {
mut:
	tv_sec  i64
	tv_nsec i64
}

struct C.termios {
mut:
	c_lflag u32
	c_cc    [32]u8
}

struct C.stat {
mut:
	st_mode u32
	st_rdev u64
}

struct C.rlimit {
mut:
	rlim_cur u64
	rlim_max u64
}

struct C.pollfd {
mut:
	fd      i32
	events  i16
	revents i16
}

@[c_extern]
__global C.errno i32

@[c_extern]
__global C.stdout voidptr

__global failures i32
__global caught_signal C.tj_signal_word
__global transition_state &C.tj_transition_word
__global restart_terminal i32
__global restart_gate i32
__global open_epoch i32
__global open_started [3]i32
__global open_done [3]i32
__global open_errors i32

fn C.__builtin_alloca(usize) voidptr
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaddset(&C.sigset_t, i32) i32
fn C.sigprocmask(i32, &C.sigset_t, &C.sigset_t) i32
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.signal(i32, fn (i32)) fn (i32)
fn C.vinix_terminal_acquire_foreground(i32)
fn C.vinix_terminal_caught(i32)
fn C.vinix_terminal_transition_signal(i32)
fn C.vinix_terminal_race_open(voidptr) voidptr
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.WIFSTOPPED(i32) bool
fn C.WSTOPSIG(i32) i32
fn C.WIFSIGNALED(i32) bool
fn C.WTERMSIG(i32) i32
fn C.getpgrp() i32
fn C.getppid() i32
fn C.setpgid(i32, i32) i32
fn C.setsid() i32
fn C.tcsetpgrp(i32, i32) i32
fn C.tcgetpgrp(i32) i32
fn C.tcgetattr(i32, &C.termios) i32
fn C.tcsetattr(i32, i32, &C.termios) i32
fn C.strstr(&char, &char) &char
fn C.strtol(&char, voidptr, i32) i64
fn C.memset(voidptr, i32, usize) voidptr
fn C.clock_gettime(i32, &C.timespec) i32
fn C.nanosleep(&C.timespec, &C.timespec) i32
fn C.usleep(u32) i32
fn C.pipe(&i32) i32
fn C.pause() i32
fn C.kill(i32, i32) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.execl(&char, &char, ...) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.posix_openpt(i32) i32
fn C.ioctl(i32, u64, ...) i32
fn C.fstat(i32, &C.stat) i32
fn C.S_ISCHR(u32) bool
fn C.mknod(&char, u32, u64) i32
fn C.getrlimit(i32, &C.rlimit) i32
fn C.setrlimit(i32, &C.rlimit) i32
fn C.dup(i32) i32
fn C.poll(&C.pollfd, u64, i32) i32
fn C.unlink(&char) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__atomic_load_n(&i32, i32) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_fetch_add(&i32, i32, i32) i32
fn C.strcmp(&char, &char) i32
fn C.atoi(&char) i32
fn C.dup2(i32, i32) i32
fn C.setvbuf(voidptr, voidptr, i32, usize) i32

@[export:'vinix_terminal_acquire_foreground']
pub fn acquire_foreground(number i32) {
	unsafe {
		caught_signal.value = number
		mask := &C.sigset_t(C.__builtin_alloca(sizeof(C.sigset_t)))
		C.sigemptyset(mask)
		C.sigaddset(mask, C.SIGTTOU)
		C.sigprocmask(C.SIG_BLOCK, mask, nil)
		if C.tcsetpgrp(restart_terminal, C.getpgrp()) != 0 || C.write(restart_gate, c'r', 1) != 1 {
			C._exit(80)
		}
	}
}

@[export:'vinix_terminal_caught']
pub fn caught(number i32) {
	unsafe { caught_signal.value = number }
}

@[export:'vinix_terminal_transition_signal']
pub fn transition_signal(number i32) {
	unsafe {
		if number == C.SIGHUP { transition_state[0].value++ }
		if number == C.SIGCONT { transition_state[1].value++ }
	}
}

fn check(ok bool, name &char) {
	unsafe {
		C.printf(c'TERMINAL JOBS %s: %s (errno=%d)\n', if ok {
			&char(c'PASS')
		} else {
			&char(c'FAIL')
		}, name, C.errno)
		failures += if ok { i32(0) } else { i32(1) }
	}
}

fn wait_status(child i32, flags i32) i32 {
	unsafe {
		status := &i32(C.__builtin_alloca(sizeof(i32)))
		mut value := i32(0)
		for {
			value = C.waitpid(child, status, flags)
			if !(value == -1 && C.errno == C.EINTR) { break }
		}
		return if value == child { *status } else { i32(-1) }
	}
}

fn exited_ok(child i32) bool {
	unsafe {
		status := wait_status(child, 0)
		return status >= 0 && C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0
	}
}

fn block(number i32, how i32) {
	unsafe {
		set := &C.sigset_t(C.__builtin_alloca(sizeof(C.sigset_t)))
		C.sigemptyset(set)
		C.sigaddset(set, number)
		C.sigprocmask(how, set, nil)
	}
}

fn handler(number i32) {
	unsafe {
		action := &C.sigaction(C.__builtin_alloca(sizeof(C.sigaction)))
		C.memset(action, 0, sizeof(C.sigaction))
		action.sa_handler = C.vinix_terminal_caught
		C.sigemptyset(&action.sa_mask)
		C.sigaction(number, action, nil)
	}
}

fn background() i32 {
	unsafe {
		child := C.fork()
		if child == 0 && C.setpgid(0, 0) != 0 { C._exit(90) }
		return child
	}
}

fn foreground(slave i32, group i32) {
	block(C.SIGTTOU, C.SIG_BLOCK)
	check(C.tcsetpgrp(slave, group) == 0, c'set foreground process group')
	block(C.SIGTTOU, C.SIG_UNBLOCK)
}

fn slab_kb() i64 {
	unsafe {
		data := &char(C.__builtin_alloca(8192))
		fd := C.open(c'/proc/meminfo', C.O_RDONLY)
		if fd < 0 { return -1 }
		length := C.read(fd, data, 8191)
		C.close(fd)
		if length <= 0 { return -1 }
		data[length] = 0
		line := C.strstr(data, c'Slab:')
		return if line != nil { C.strtol(line + 5, nil, 10) } else { i64(-1) }
	}
}

fn allocation_tracking() {
	unsafe {
		fd := C.open(c'/proc/allocstart', C.O_RDONLY)
		byte := &char(C.__builtin_alloca(1))
		if fd >= 0 {
			C.read(fd, byte, 1)
			C.close(fd)
		}
	}
}

fn allocation_sites() {
	unsafe {
		data := &char(C.__builtin_alloca(65536))
		fd := C.open(c'/proc/allocsites', C.O_RDONLY)
		if fd < 0 { return }
		amount := C.read(fd, data, 65535)
		C.close(fd)
		if amount > 0 {
			data[amount] = 0
			C.printf(c'TERMINAL ALLOCATION SITES\n%s\n', data)
		}
	}
}

fn settle_grace() {
	unsafe {
		start := &C.timespec(C.__builtin_alloca(sizeof(C.timespec)))
		now := &C.timespec(C.__builtin_alloca(sizeof(C.timespec)))
		mut interval := C.timespec{ tv_nsec: 100000000 }
		C.clock_gettime(C.CLOCK_MONOTONIC, start)
		for {
			C.nanosleep(&interval, nil)
			C.clock_gettime(C.CLOCK_MONOTONIC, now)
			if !(now.tv_sec - start.tv_sec < 6 || (now.tv_sec - start.tv_sec == 6 && now.tv_nsec < start.tv_nsec)) {
				break
			}
		}
	}
}

fn permission_cases(master i32, slave i32) {
	unsafe {
		mut child := background()
		if child == 0 {
			byte := &char(C.__builtin_alloca(1))
			block(C.SIGTTIN, C.SIG_BLOCK)
			C.errno = 0
			C._exit(if C.read(slave, byte, 1) == -1 && C.errno == C.EIO { 0 } else { 1 })
		}
		check(child > 0 && exited_ok(child), c'blocked background read fails EIO')
		child = background()
		if child == 0 {
			byte := &char(C.__builtin_alloca(1))
			C.signal(C.SIGTTIN, C.SIG_IGN)
			C.errno = 0
			C._exit(if C.read(slave, byte, 1) == -1 && C.errno == C.EIO { 0 } else { 1 })
		}
		check(child > 0 && exited_ok(child), c'ignored background read fails EIO')
		child = background()
		if child == 0 {
			byte := &char(C.__builtin_alloca(1))
			handler(C.SIGTTIN)
			C.errno = 0
			C._exit(if C.read(slave, byte, 1) == -1 && C.errno == C.EINTR && caught_signal.value == C.SIGTTIN {
				0
			} else {
				1
			})
		}
		check(child > 0 && exited_ok(child), c'caught background read receives SIGTTIN and EINTR')
		child = background()
		if child == 0 { C._exit(if C.write(slave, c'n', 1) == 1 { 0 } else { 1 }) }
		check(child > 0 && exited_ok(child), c'background output allowed without TOSTOP')
		settings := &C.termios(C.__builtin_alloca(sizeof(C.termios)))
		check(C.tcgetattr(slave, settings) == 0, c'read terminal settings')
		settings.c_lflag |= u32(C.TOSTOP)
		check(C.tcsetattr(slave, C.TCSANOW, settings) == 0, c'enable TOSTOP')
		child = background()
		if child == 0 {
			handler(C.SIGTTOU)
			C.errno = 0
			C._exit(if C.write(slave, c'x', 1) == -1 && C.errno == C.EINTR && caught_signal.value == C.SIGTTOU {
				0
			} else {
				1
			})
		}
		check(child > 0 && exited_ok(child), c'TOSTOP catches background output before writing')
		child = background()
		if child == 0 {
			block(C.SIGTTOU, C.SIG_BLOCK)
			C._exit(if C.write(slave, c'b', 1) == 1 { 0 } else { 1 })
		}
		check(child > 0 && exited_ok(child), c'blocked SIGTTOU permits background output')
		child = background()
		if child == 0 {
			C.signal(C.SIGTTOU, C.SIG_IGN)
			C._exit(if C.write(slave, c'i', 1) == 1 { 0 } else { 1 })
		}
		check(child > 0 && exited_ok(child), c'ignored SIGTTOU permits background output')
		settings.c_lflag &= ~u32(C.TOSTOP)
		check(C.tcsetattr(slave, C.TCSANOW, settings) == 0, c'disable TOSTOP')
		child = background()
		if child == 0 {
			handler(C.SIGTTOU)
			mut changed := *settings
			changed.c_lflag ^= u32(C.ECHO)
			C.errno = 0
			C._exit(if C.tcsetattr(slave, C.TCSANOW, &changed) == -1 && C.errno == C.EINTR && caught_signal.value == C.SIGTTOU {
				0
			} else {
				1
			})
		}
		check(child > 0 && exited_ok(child), c'background attribute change signals regardless TOSTOP')
		observed := &C.termios(C.__builtin_alloca(sizeof(C.termios)))
		check(C.tcgetattr(slave, observed) == 0 && observed.c_lflag == settings.c_lflag, c'rejected attribute change leaves settings intact')
		child = background()
		if child == 0 {
			handler(C.SIGTTOU)
			C.errno = 0
			C._exit(if C.tcsetpgrp(slave, C.getpgrp()) == -1 && C.errno == C.EINTR && caught_signal.value == C.SIGTTOU {
				0
			} else {
				1
			})
		}
		check(child > 0 && exited_ok(child), c'background foreground-group mutation receives SIGTTOU')
		child = background()
		if child == 0 {
			block(C.SIGTTOU, C.SIG_BLOCK)
			if C.tcsetpgrp(slave, C.getpgrp()) != 0 || C.tcgetpgrp(slave) != C.getpgrp() {
				C._exit(1)
			}
			C._exit(if C.tcsetpgrp(slave, C.getppid()) != 0 { 2 } else { 0 })
		}
		check(child > 0 && exited_ok(child), c'blocked SIGTTOU permits group mutation')
		child = background()
		if child == 0 {
			byte := &char(C.__builtin_alloca(1))
			block(C.SIGTTIN, C.SIG_BLOCK)
			for i := i32(0); i < 10; i++ { C.read(slave, byte, 1) }
			before := slab_kb()
			allocation_tracking()
			for i := i32(0); i < 1000; i++ {
				if C.read(slave, byte, 1) != -1 || C.errno != C.EIO { C._exit(1) }
			}
			after := slab_kb()
			C.printf(c'TERMINAL JOBS SLAB before=%ld after=%ld KiB\n', before, after)
			if after - before > 64 { allocation_sites() }
			C._exit(if before >= 0 && after >= 0 && after - before <= 64 { 0 } else { 2 })
		}
		check(child > 0 && exited_ok(child), c'1000 rejected reads retain no growing slab memory')
		data := &char(C.__builtin_alloca(2))
		check(C.write(master, c'R\n', 2) == 2 && C.read(slave, data, 2) == 2 && data[0] == char(`R`), c'foreground read still consumes data')
	}
}

fn session_cases(master i32, slave i32, image &char) {
	unsafe {
		gate := &i32(C.__builtin_alloca(2 * sizeof(i32)))
		check(C.pipe(gate) == 0, c'create session gate')
		mut child := C.fork()
		if child == 0 {
			C.close(gate[0])
			if C.setsid() < 0 { C._exit(1) }
			mut ready := char(`r`)
			if C.write(gate[1], &ready, 1) != 1 { C._exit(2) }
			for { C.pause() }
		}
		C.close(gate[1])
		byte := &char(C.__builtin_alloca(1))
		check(C.read(gate[0], byte, 1) == 1, c'foreign session ready')
		C.close(gate[0])
		C.errno = 0
		check(C.tcsetpgrp(slave, child) == -1 && C.errno == C.EPERM, c'foreign-session foreground group rejected')
		C.errno = 0
		check(C.setpgid(child, child) == -1 && C.errno == C.EPERM, c'foreign-session child group mutation rejected')
		C.kill(child, C.SIGKILL)
		wait_status(child, 0)
		child = background()
		if child == 0 {
			C.errno = 0
			C._exit(if C.setpgid(C.getppid(), C.getpgrp()) == -1 && C.errno == C.ESRCH {
				0
			} else {
				1
			})
		}
		check(child > 0 && exited_ok(child), c'child cannot alter parent process group')
		C.errno = 0
		check(C.tcsetpgrp(slave, -1) == -1 && C.errno == C.EINVAL, c'negative foreground group rejected')
		C.errno = 0
		check(C.tcsetpgrp(slave, 0) == -1 && C.errno == C.ESRCH, c'nonexistent zero foreground group rejected')
		child = C.fork()
		if child == 0 {
			if C.setsid() < 0 { C._exit(1) }
			C.errno = 0
			C._exit(if C.tcgetpgrp(slave) == -1 && C.errno == C.ENOTTY && C.tcgetpgrp(master) >= 0 {
				0
			} else {
				2
			})
		}
		check(child > 0 && exited_ok(child), c'non-controlling slave query rejected but master query usable')
		check(C.pipe(gate) == 0, c'create exec gate')
		child = C.fork()
		if child == 0 {
			C.close(gate[0])
			fd := &char(C.__builtin_alloca(24))
			C.snprintf(fd, 24, c'%d', gate[1])
			C.execl(image, image, c'--after-exec', fd, voidptr(nil))
			C._exit(1)
		}
		C.close(gate[1])
		check(C.read(gate[0], byte, 1) == 1, c'child completed exec')
		C.close(gate[0])
		C.errno = 0
		check(C.setpgid(child, child) == -1 && C.errno == C.EACCES, c'parent cannot change child group after exec')
		C.kill(child, C.SIGKILL)
		wait_status(child, 0)
	}
}

fn stop_cases(master i32, slave i32) {
	unsafe {
		settings := &C.termios(C.__builtin_alloca(sizeof(C.termios)))
		C.tcgetattr(slave, settings)
		settings.c_lflag &= ~u32(C.ICANON)
		settings.c_cc[C.VMIN] = 1
		check(C.tcsetattr(slave, C.TCSANOW, settings) == 0, c'use noncanonical foreground input')
		owner := C.getpgrp()
		mut child := background()
		if child == 0 {
			byte := &char(C.__builtin_alloca(1))
			C._exit(if C.read(slave, byte, 1) == 1 && *byte == char(`Q`) { 0 } else { 1 })
		}
		mut status := wait_status(child, C.WUNTRACED)
		check(status >= 0 && C.WIFSTOPPED(status) && C.WSTOPSIG(status) == C.SIGTTIN, c'background read stops with SIGTTIN')
		foreground(slave, child)
		check(C.write(master, c'Q', 1) == 1 && C.kill(child, C.SIGCONT) == 0, c'feed and continue foreground reader')
		check(exited_ok(child), c'continued read restarts in foreground')
		foreground(slave, owner)
		settings.c_lflag |= u32(C.TOSTOP)
		check(C.tcsetattr(slave, C.TCSANOW, settings) == 0, c'enable default writer stop')
		child = background()
		if child == 0 { C._exit(if C.write(slave, c'w', 1) == 1 { 0 } else { 1 }) }
		status = wait_status(child, C.WUNTRACED)
		check(status >= 0 && C.WIFSTOPPED(status) && C.WSTOPSIG(status) == C.SIGTTOU, c'default background writer stops with SIGTTOU')
		foreground(slave, child)
		C.kill(child, C.SIGCONT)
		check(exited_ok(child), c'continued writer restarts in foreground')
		foreground(slave, owner)
		settings.c_lflag &= ~u32(C.TOSTOP)
		check(C.tcsetattr(slave, C.TCSANOW, settings) == 0, c'disable default writer stop')
		gate := &i32(C.__builtin_alloca(2 * sizeof(i32)))
		check(C.pipe(gate) == 0, c'restart readiness pipe')
		child = background()
		if child == 0 {
			C.close(gate[0])
			restart_terminal = slave
			restart_gate = gate[1]
			action := &C.sigaction(C.__builtin_alloca(sizeof(C.sigaction)))
			C.memset(action, 0, sizeof(C.sigaction))
			action.sa_handler = C.vinix_terminal_acquire_foreground
			action.sa_flags = i32(C.SA_RESTART)
			C.sigemptyset(&action.sa_mask)
			C.sigaction(C.SIGTTIN, action, nil)
			mut byte := char(0)
			amount := C.read(slave, &byte, 1)
			C.printf(c'TERMINAL RESTART amount=%ld byte=%u signal=%d errno=%d\n', amount, i32(u8(byte)), caught_signal.value, C.errno)
			C._exit(if amount == 1 && byte == char(`A`) && caught_signal.value == C.SIGTTIN {
				0
			} else {
				1
			})
		}
		C.close(gate[1])
		ready := &char(C.__builtin_alloca(1))
		ready_count := C.read(gate[0], ready, 1)
		C.usleep(50000)
		check(ready_count == 1 && C.write(master, c'A', 1) == 1, c'restart handler acquires foreground and receives input')
		C.close(gate[0])
		check(exited_ok(child), c'caught SIGTTIN with SA_RESTART restarts read')
		foreground(slave, owner)
		child = background()
		if child == 0 {
			for { C.pause() }
		}
		check(C.setpgid(child, child) == 0, c"publish foreground child's group")
		foreground(slave, child)
		check(C.write(master, c'\x1a', 1) == 1, c'feed terminal suspend character')
		status = wait_status(child, C.WUNTRACED)
		check(status >= 0 && C.WIFSTOPPED(status) && C.WSTOPSIG(status) == C.SIGTSTP, c'terminal suspend targets foreground group')
		foreground(slave, owner)
		C.kill(child, C.SIGKILL)
		wait_status(child, 0)
		child = background()
		if child == 0 {
			for { C.pause() }
		}
		check(C.setpgid(child, child) == 0, c'publish foreground interrupt group')
		sibling := C.fork()
		if sibling == 0 {
			for { C.pause() }
		}
		check(C.setpgid(sibling, child) == 0, c'join sibling to foreground group')
		foreground(slave, child)
		check(C.write(master, c'\x03', 1) == 1, c'feed terminal interrupt character')
		status = wait_status(child, 0)
		check(status >= 0 && C.WIFSIGNALED(status) && C.WTERMSIG(status) == C.SIGINT, c'foreground leader receives SIGINT')
		status = wait_status(sibling, 0)
		check(status >= 0 && C.WIFSIGNALED(status) && C.WTERMSIG(status) == C.SIGINT, c'foreground sibling receives SIGINT')
		foreground(slave, owner)
	}
}

fn console_cases() i32 {
	unsafe {
		failures = 0
		if C.setsid() < 0 { return 1 }
		console := C.open(c'/dev/console', C.O_RDWR | C.O_NOCTTY)
		C.errno = 0
		check(console >= 0 && C.tcgetpgrp(console) == -1 && C.errno == C.ENOTTY, c'O_NOCTTY console open leaves terminal unclaimed')
		claimed := C.open(c'/dev/console', C.O_RDWR)
		check(claimed >= 0 && C.tcgetpgrp(claimed) == C.getpgrp(), c'console open claims eligible session')
		mut child := background()
		if child == 0 {
			byte := &char(C.__builtin_alloca(1))
			block(C.SIGTTIN, C.SIG_BLOCK)
			C.errno = 0
			C._exit(if C.read(console, byte, 1) == -1 && C.errno == C.EIO { 0 } else { 1 })
		}
		check(child > 0 && exited_ok(child), c'console background read enforces SIGTTIN')
		settings := &C.termios(C.__builtin_alloca(sizeof(C.termios)))
		check(C.tcgetattr(console, settings) == 0, c'console attributes')
		settings.c_lflag |= u32(C.TOSTOP)
		check(C.tcsetattr(console, C.TCSANOW, settings) == 0, c'console enables TOSTOP')
		child = background()
		if child == 0 {
			handler(C.SIGTTOU)
			C.errno = 0
			C._exit(if C.write(console, c'x', 1) == -1 && C.errno == C.EINTR && caught_signal.value == C.SIGTTOU {
				0
			} else {
				1
			})
		}
		check(child > 0 && exited_ok(child), c'console background write enforces TOSTOP')
		C.signal(C.SIGHUP, C.SIG_IGN)
		check(C.ioctl(console, C.TIOCNOTTY, 0) == 0, c'console detach')
		C.close(claimed)
		C.close(console)
		return if failures != 0 { 1 } else { 0 }
	}
}

fn orphan_mutations() {
	unsafe {
		C.signal(C.SIGHUP, C.SIG_IGN)
		transition_state = &C.tj_transition_word(C.mmap(nil, 4096, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED | C.MAP_ANONYMOUS, -1, 0))
		check(voidptr(transition_state) != voidptr(C.MAP_FAILED), c'orphan transition shared state')
		if voidptr(transition_state) == voidptr(C.MAP_FAILED) { return }
		owner := C.getpgrp()
		for change_session := i32(0); change_session < 2; change_session++ {
			C.memset(transition_state, 0, 4096)
			gate := &i32(C.__builtin_alloca(2 * sizeof(i32)))
			check(C.pipe(gate) == 0, c'orphan transition gate')
			parent := C.fork()
			if parent == 0 {
				C.close(gate[1])
				if change_session == 0 && C.setpgid(0, 0) != 0 { C._exit(1) }
				job := C.fork()
				if job == 0 {
					C.close(gate[0])
					if C.setpgid(0, if change_session != 0 { i32(0) } else { owner }) != 0 {
						C._exit(2)
					}
					action := &C.sigaction(C.__builtin_alloca(sizeof(C.sigaction)))
					C.memset(action, 0, sizeof(C.sigaction))
					action.sa_handler = C.vinix_terminal_transition_signal
					C.sigemptyset(&action.sa_mask)
					C.sigaction(C.SIGHUP, action, nil)
					C.sigaction(C.SIGCONT, action, nil)
					transition_state[2].value = 1
					for { C.pause() }
				}
				for transition_state[2].value == 0 { C.usleep(1000) }
				if C.kill(job, C.SIGSTOP) != 0 || !C.WIFSTOPPED(wait_status(job, C.WUNTRACED)) {
					C._exit(3)
				}
				changed := if change_session != 0 {
					C.setsid() > 0
				} else {
					C.setpgid(0, owner) == 0
				}
				transition_state[3].value = if changed { 1 } else { 0 }
				transition_state[4].value = 1
				release := &char(C.__builtin_alloca(1))
				C.read(gate[0], release, 1)
				valid := changed && transition_state[0].value == 1 && transition_state[1].value == 1
				C.kill(job, C.SIGKILL)
				wait_status(job, 0)
				C.close(gate[0])
				C._exit(if valid { 0 } else { 4 })
			}
			C.close(gate[0])
			for i := i32(0); i < 5000 && (transition_state[4].value == 0 || transition_state[0].value == 0 || transition_state[1].value == 0); i++ {
				C.usleep(1000)
			}
			check(transition_state[3].value != 0 && transition_state[0].value == 1 && transition_state[1].value == 1, if change_session != 0 {
				c'setsid resumes newly orphaned stopped group'
			} else {
				c'setpgid resumes newly orphaned stopped group'
			})
			C.write(gate[1], c'r', 1)
			C.close(gate[1])
			check(parent > 0 && exited_ok(parent), c'orphan mutation parent finishes')
		}
		C.munmap(transition_state, 4096)
	}
}

fn leader_hangup() bool {
	unsafe {
		transition_state = &C.tj_transition_word(C.mmap(nil, 4096, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED | C.MAP_ANONYMOUS, -1, 0))
		if voidptr(transition_state) == voidptr(C.MAP_FAILED) { return false }
		ready := &i32(C.__builtin_alloca(2 * sizeof(i32)))
		release := &i32(C.__builtin_alloca(2 * sizeof(i32)))
		if C.pipe(ready) != 0 || C.pipe(release) != 0 { return false }
		leader := C.fork()
		if leader == 0 {
			C.close(ready[0])
			C.close(release[1])
			if C.setsid() < 0 { C._exit(1) }
			master := C.posix_openpt(C.O_RDWR | C.O_NOCTTY)
			mut unlocked := i32(0)
			id := &u32(C.__builtin_alloca(sizeof(u32)))
			if master < 0 || C.ioctl(master, C.TIOCSPTLCK, &unlocked) != 0 || C.ioctl(master, C.TIOCGPTN, id) != 0 {
				C._exit(2)
			}
			path := &char(C.__builtin_alloca(64))
			C.snprintf(path, 64, c'/dev/pts/%u', *id)
			slave := C.open(path, C.O_RDWR | C.O_NOCTTY)
			if slave < 0 || C.ioctl(slave, C.TIOCSCTTY, 0) != 0 { C._exit(3) }
			mut job := C.fork()
			if job == 0 {
				C.close(ready[1])
				C.close(release[0])
				if C.setpgid(0, 0) != 0 { C._exit(4) }
				action := &C.sigaction(C.__builtin_alloca(sizeof(C.sigaction)))
				C.memset(action, 0, sizeof(C.sigaction))
				action.sa_handler = C.vinix_terminal_transition_signal
				C.sigemptyset(&action.sa_mask)
				C.sigaction(C.SIGHUP, action, nil)
				C.sigaction(C.SIGCONT, action, nil)
				transition_state[2].value = 1
				for transition_state[0].value == 0 || transition_state[1].value == 0 {
					C.usleep(1000)
				}
				C.errno = 0
				no_query := C.tcgetpgrp(slave) == -1 && C.errno == C.ENOTTY
				C.errno = 0
				no_tty := C.open(c'/dev/tty', C.O_RDWR | C.O_NOCTTY) == -1 && C.errno == C.ENXIO
				transition_state[3].value = if no_query && no_tty { 1 } else { 0 }
				successor := C.fork()
				if successor == 0 {
					C.signal(C.SIGHUP, C.SIG_IGN)
					C.signal(C.SIGCONT, C.SIG_IGN)
					C._exit(if C.setsid() > 0 && C.ioctl(slave, C.TIOCSCTTY, 0) == 0 && C.ioctl(slave, C.TIOCNOTTY, 0) == 0 {
						0
					} else {
						5
					})
				}
				transition_state[4].value = if successor > 0 && exited_ok(successor) {
					1
				} else {
					0
				}
				C.close(slave)
				C.close(master)
				C._exit(0)
			}
			for transition_state[2].value == 0 { C.usleep(1000) }
			if C.tcsetpgrp(slave, job) != 0 || C.kill(job, C.SIGSTOP) != 0 || !C.WIFSTOPPED(wait_status(job, C.WUNTRACED)) {
				C._exit(6)
			}
			C.write(ready[1], &job, sizeof(i32))
			C.close(ready[1])
			byte := &char(C.__builtin_alloca(1))
			C.read(release[0], byte, 1)
			C.close(release[0])
			C._exit(0)
		}
		C.close(ready[1])
		C.close(release[0])
		mut job := i32(0)
		amount := C.read(ready[0], &job, sizeof(i32))
		C.close(ready[0])
		C.write(release[1], c'r', 1)
		C.close(release[1])
		leader_status := if leader > 0 { wait_status(leader, 0) } else { i32(-1) }
		mut valid := leader_status >= 0 && C.WIFEXITED(leader_status) && C.WEXITSTATUS(leader_status) == 0 && amount == isize(sizeof(i32)) && job > 0
		job_status := if valid { wait_status(job, 0) } else { i32(-1) }
		valid = valid && job_status >= 0 && C.WIFEXITED(job_status) && C.WEXITSTATUS(job_status) == 0
		C.printf(c'TERMINAL HANGUP leader_status=%d job=%d status=%d ready_bytes=%ld hup=%d cont=%d detached=%d successor=%d\n', leader_status, job, job_status, amount, transition_state[0].value, transition_state[1].value, transition_state[3].value, transition_state[4].value)
		check(valid && transition_state[0].value == 1 && transition_state[1].value == 1, c'session-leader exit sends HUP and resumes stopped foreground job')
		check(valid && transition_state[3].value != 0, c'session-leader exit clears controlling identity for remaining members')
		check(valid && transition_state[4].value != 0, c'a new session can claim the hung-up terminal')
		C.munmap(transition_state, 4096)
		return valid && failures == 0
	}
}

@[export:'vinix_terminal_race_open']
pub fn race_open(argument voidptr) voidptr {
	unsafe {
		worker := i32(isize(argument))
		mut previous := i32(0)
		// One uninitialized native stack slot is reused, like the C loop local.
		information := &C.stat(C.__builtin_alloca(sizeof(C.stat)))
		for {
			epoch := C.__atomic_load_n(&open_epoch, C.__ATOMIC_ACQUIRE)
			if epoch < 0 { return nil }
			if epoch == previous {
				C.usleep(100)
				continue
			}
			previous = epoch
			C.__atomic_store_n(&open_started[worker], epoch, C.__ATOMIC_RELEASE)
			for i := i32(0); i < 32; i++ {
				alias := C.open(c'/dev/tty', C.O_RDWR | C.O_NOCTTY)
				if alias >= 0 {
					if C.fstat(alias, information) != 0 || !C.S_ISCHR(information.st_mode) {
						C.__atomic_fetch_add(&open_errors, 1, C.__ATOMIC_RELAXED)
					}
					C.usleep(100)
					if C.close(alias) != 0 {
						C.__atomic_fetch_add(&open_errors, 1, C.__ATOMIC_RELAXED)
					}
				} else if C.errno != C.ENXIO && C.errno != C.EIO {
					C.__atomic_fetch_add(&open_errors, 1, C.__ATOMIC_RELAXED)
				}
			}
			C.__atomic_store_n(&open_done[worker], epoch, C.__ATOMIC_RELEASE)
		}
		return nil
	}
}

fn owned_open_cases() {
	unsafe {
		mut unlock := i32(0)
		id := &u32(C.__builtin_alloca(sizeof(u32)))
		mut master := C.posix_openpt(C.O_RDWR | C.O_NOCTTY)
		check(master >= 0 && C.ioctl(master, C.TIOCSPTLCK, &unlock) == 0 && C.ioctl(master, C.TIOCGPTN, id) == 0, c'owned-open rollback master')
		if master < 0 { return }
		path := &char(C.__builtin_alloca(64))
		C.snprintf(path, 64, c'/dev/pts/%u', *id)
		mut slave := C.open(path, C.O_RDWR | C.O_NOCTTY)
		check(slave >= 0 && C.ioctl(slave, C.TIOCSCTTY, 0) == 0, c'owned-open rollback claim')
		information := &C.stat(C.__builtin_alloca(sizeof(C.stat)))
		check(C.fstat(slave, information) == 0, c'owned-open device identity')
		check(C.mknod(c'/root/tty-alias', u32(C.S_IFCHR) | u32(0o600), information.st_rdev) == 0, c'mknod forwards owned terminal opens')
		alias := C.open(c'/root/tty-alias', C.O_RDWR | C.O_NOCTTY)
		check(alias >= 0 && C.tcgetpgrp(alias) == C.getpgrp(), c'mknod terminal alias uses controlling session')
		if alias >= 0 { C.close(alias) }
		original := &C.rlimit(C.__builtin_alloca(sizeof(C.rlimit)))
		limited := &C.rlimit(C.__builtin_alloca(sizeof(C.rlimit)))
		check(C.getrlimit(C.RLIMIT_NOFILE, original) == 0, c'read descriptor limit')
		*limited = *original
		limited.rlim_cur = 64
		check(C.setrlimit(C.RLIMIT_NOFILE, limited) == 0, c'limit rollback descriptor table')
		held := &i32(C.__builtin_alloca(64 * sizeof(i32)))
		mut count := i32(0)
		for count < 64 {
			held[count] = C.dup(master)
			if held[count] < 0 { break }
			count++
		}
		mut rolled_back := count < 64 && C.errno == C.EMFILE
		for i := i32(0); i < 100; i++ {
			C.errno = 0
			if C.open(c'/dev/tty', C.O_RDWR | C.O_NOCTTY) != -1 || C.errno != C.EMFILE {
				rolled_back = false
			}
		}
		check(rolled_back, c'full descriptor table rejects owned terminal opens')
		for i := i32(0); i < count; i++ { C.close(held[i]) }
		check(C.setrlimit(C.RLIMIT_NOFILE, original) == 0, c'restore descriptor limit')
		C.close(slave)
		mut polled := C.pollfd{ fd: master, events: i16(C.POLLIN) }
		check(C.poll(&polled, 1, 0) == 1 && (polled.revents & i16(C.POLLHUP)) != 0, c'failed owned opens roll back every slave-open count')
		C.close(master)
		C.unlink(c'/root/tty-alias')
		workers := &C.pthread_t(C.__builtin_alloca(3 * sizeof(C.pthread_t)))
		mut created := i32(0)
		for created < 3 {
			if C.pthread_create(&workers[created], nil, C.vinix_terminal_race_open, voidptr(isize(created))) != 0 {
				break
			}
			created++
		}
		check(created == 3, c'create simultaneous terminal-open workers')
		mut rounds := i32(0)
		race_before := slab_kb()
		allocation_tracking()
		for epoch := i32(1); created == 3 && epoch <= 100; epoch++ {
			master = C.posix_openpt(C.O_RDWR | C.O_NOCTTY)
			if master < 0 || C.ioctl(master, C.TIOCSPTLCK, &unlock) != 0 || C.ioctl(master, C.TIOCGPTN, id) != 0 {
				break
			}
			C.snprintf(path, 64, c'/dev/pts/%u', *id)
			slave = C.open(path, C.O_RDWR | C.O_NOCTTY)
			if slave < 0 || C.ioctl(slave, C.TIOCSCTTY, 0) != 0 { break }
			C.close(slave)
			C.__atomic_store_n(&open_epoch, epoch, C.__ATOMIC_RELEASE)
			for worker := i32(0); worker < 3; worker++ {
				for C.__atomic_load_n(&open_started[worker], C.__ATOMIC_ACQUIRE) != epoch {
					C.usleep(100)
				}
			}
			C.usleep(100)
			C.close(master)
			for worker := i32(0); worker < 3; worker++ {
				for C.__atomic_load_n(&open_done[worker], C.__ATOMIC_ACQUIRE) != epoch {
					C.usleep(100)
				}
			}
			rounds++
		}
		C.__atomic_store_n(&open_epoch, -1, C.__ATOMIC_RELEASE)
		for i := i32(0); i < created; i++ { C.pthread_join(workers[i], nil) }
		settle_grace()
		race_after := slab_kb()
		C.printf(c'TERMINAL OWNED SLAB before=%ld after=%ld KiB\n', race_before, race_after)
		if race_after > race_before + 64 { allocation_sites() }
		C.printf(c'TERMINAL OWNED OPEN rounds=%d errors=%d\n', rounds, open_errors)
		check(rounds == 100 && open_errors == 0, c'concurrent controlling-terminal open and master-close survive')
		check(race_before >= 0 && race_after >= 0 && race_after <= race_before + 64, c'retired terminal pairs and owned-open references remain bounded')
		C.errno = 0
		check(C.open(c'/dev/tty', C.O_RDWR | C.O_NOCTTY) == -1 && C.errno == C.ENXIO, c'master-close clears final controlling-terminal identity')
	}
}

fn manager(image &char) i32 {
	unsafe {
		check(C.setsid() > 0, c'create controlling session')
		master := C.posix_openpt(C.O_RDWR | C.O_NOCTTY)
		mut unlock := i32(0)
		id := &u32(C.__builtin_alloca(sizeof(u32)))
		check(master >= 0 && C.ioctl(master, C.TIOCSPTLCK, &unlock) == 0 && C.ioctl(master, C.TIOCGPTN, id) == 0, c'open PTY master')
		if master < 0 { return 1 }
		path := &char(C.__builtin_alloca(64))
		C.snprintf(path, 64, c'/dev/pts/%u', *id)
		slave := C.open(path, C.O_RDWR | C.O_NOCTTY)
		check(slave >= 0 && C.ioctl(slave, C.TIOCSCTTY, 0) == 0, c'claim controlling PTY')
		if slave < 0 { return 1 }
		check(C.tcgetpgrp(slave) == C.getpgrp(), c'report initial foreground group')
		mut alias := C.open(c'/dev/tty', C.O_RDWR | C.O_NOCTTY)
		check(alias >= 0 && C.tcgetpgrp(alias) == C.getpgrp(), c'/dev/tty opens the claimed device')
		if alias >= 0 { C.close(alias) }
		for i := i32(0); i < 50; i++ {
			alias = C.open(c'/dev/tty', C.O_RDWR | C.O_NOCTTY)
			if alias >= 0 { C.close(alias) }
		}
		open_before := slab_kb()
		mut opens_ok := true
		for i := i32(0); i < 1000; i++ {
			alias = C.open(c'/dev/tty', C.O_RDWR | C.O_NOCTTY)
			if alias < 0 || C.close(alias) != 0 {
				opens_ok = false
				break
			}
		}
		open_after := slab_kb()
		C.printf(c'TERMINAL OPEN SLAB before=%ld after=%ld KiB\n', open_before, open_after)
		check(opens_ok && open_before >= 0 && open_after >= 0 && open_after <= open_before + 8, c'1000 controlling-terminal opens retain bounded slab memory')
		second_master := C.posix_openpt(C.O_RDWR | C.O_NOCTTY)
		mut second_id := u32(0)
		check(second_master >= 0 && C.ioctl(second_master, C.TIOCSPTLCK, &unlock) == 0 && C.ioctl(second_master, C.TIOCGPTN, &second_id) == 0, c'second PTY master')
		C.snprintf(path, 64, c'/dev/pts/%u', second_id)
		second_slave := C.open(path, C.O_RDWR | C.O_NOCTTY)
		C.errno = 0
		check(second_slave >= 0 && C.ioctl(second_slave, C.TIOCSCTTY, 0) == -1 && C.errno == C.EPERM, c'one session cannot claim two controlling terminals')
		permission_cases(master, slave)
		session_cases(master, slave, image)
		orphan_mutations()
		C.puts(c'TERMINAL JOBS PASS: permissions and sessions')
		stop_cases(master, slave)
		C.puts(c'TERMINAL JOBS PASS: stop and foreground signals')
		C.signal(C.SIGHUP, C.SIG_IGN)
		check(C.ioctl(slave, C.TIOCNOTTY, 0) == 0, c'detach controlling terminal')
		C.errno = 0
		check(C.tcgetpgrp(slave) == -1 && C.errno == C.ENOTTY, c'detached terminal loses controlling state')
		C.errno = 0
		check(C.open(c'/dev/tty', C.O_RDWR | C.O_NOCTTY) == -1 && C.errno == C.ENXIO, c'detached session has no /dev/tty')
		check(C.ioctl(second_slave, C.TIOCSCTTY, 0) == 0, c'detached session can claim a new terminal')
		alias = C.open(c'/dev/tty', C.O_RDWR | C.O_NOCTTY)
		claimed := &C.stat(C.__builtin_alloca(sizeof(C.stat)))
		reopened := &C.stat(C.__builtin_alloca(sizeof(C.stat)))
		check(alias >= 0 && C.fstat(alias, reopened) == 0 && C.fstat(second_slave, claimed) == 0 && reopened.st_rdev == claimed.st_rdev, c'/dev/tty follows unique replacement device')
		if alias >= 0 { C.close(alias) }
		check(C.ioctl(second_slave, C.TIOCNOTTY, 0) == 0, c'detach replacement terminal')
		C.close(second_slave)
		C.close(second_master)
		C.close(slave)
		C.close(master)
		owned_open_cases()
		return if failures != 0 { 1 } else { 0 }
	}
}

@[export:'main']
pub fn entry(argc i32, argv &&char) i32 {
	unsafe {
		if argc == 3 && C.strcmp(argv[1], c'--after-exec') == 0 {
			if C.write(C.atoi(argv[2]), c'r', 1) != 1 { return 1 }
			for { C.pause() }
		}
		console := C.open(c'/dev/com1', C.O_WRONLY)
		if console >= 0 {
			C.dup2(console, 1)
			C.dup2(console, 2)
			C.close(console)
		}
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		mut child := C.fork()
		if child == 0 { C._exit(manager(argv[0])) }
		mut passed := child > 0 && exited_ok(child)
		passed = leader_hangup() && passed
		child = C.fork()
		if child == 0 { C._exit(console_cases()) }
		passed = (child > 0 && exited_ok(child)) && passed
		C.puts(if passed { c'TERMINAL JOBS GUEST: PASS' } else { c'TERMINAL JOBS GUEST: FAIL' })
		for { C.pause() }
	}
	return 0
}
