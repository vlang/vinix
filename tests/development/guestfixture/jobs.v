// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

#include <signal.h>
#include <time.h>

struct C.timespec {
	tv_sec i64
	tv_nsec i64
}

fn C.clock_gettime(i32, &C.timespec) i32
fn C.usleep(u32) i32
fn C.getpid() i32
fn C.getppid() i32
fn C.getpgid(i32) i32
fn C.kill(i32, i32) i32
fn C.WIFSIGNALED(i32) i32
fn C.WTERMSIG(i32) i32
fn C.sscanf(&char, &char, ...) i32

fn job_clock() u64 {
	mut value := C.timespec{}
	check(C.clock_gettime(C.CLOCK_MONOTONIC, unsafe { &value }) == 0, 320)
	return u64(value.tv_sec) * 1000000000 + u64(value.tv_nsec)
}

fn job_identity() {
	unsafe {
		check(C.getuid() == 1000 && C.geteuid() == 1000
			&& C.getgid() == 1000 && C.getegid() == 1000, 321)
		check(C.getenv(c'UNSELECTED_PARENT_SECRET') == nil, 322)
		token := C.getenv(c'TEST_TOKEN')
		check(token != nil && C.strcmp(token, c'vinix-native-fixture-secret') == 0, 323)
		C.puts(c'vinix-native-fixture-secret')
		C.write(2, c'vinix-native-fixture-secret\n', 28)
	}
}

fn lifecycle_payload(mode &char) i32 {
	unsafe {
		job_identity()
		prefix := C.getenv(c'VINIX_JOB_PROOF_PREFIX')
		check(prefix != nil && C.getpgid(0) == C.getpid(), 324)
		mut path := [256]char{}
		mut text := [32]char{}
		if C.strcmp(mode, c'tick') == 0 {
			C.snprintf(&path[0], path.len, c'%s.ticks', prefix)
			count := C.snprintf(&text[0], text.len, c'%d\n', C.getppid())
			fd := C.open(&path[0], C.O_WRONLY | C.O_CREAT | C.O_APPEND, u32(0o600))
			check(count > 0 && fd >= 0 && C.write(fd, &text[0], usize(count)) == count
				&& C.close(fd) == 0, 325)
			return 0
		}
		C.snprintf(&path[0], path.len, c'%s.parent.pid', prefix)
		if C.strcmp(mode, c'recover') == 0 {
			fd := C.open(&path[0], C.O_RDONLY)
			if fd >= 0 {
				check(C.close(fd) == 0, 326)
				C.snprintf(&path[0], path.len, c'%s.recovered', prefix)
				write_text(&path[0], c'completed', 9)
				return 0
			}
		}
		count := C.snprintf(&text[0], text.len, c'%d\n', C.getpid())
		check(count > 0, 327)
		write_text(&path[0], &text[0], usize(count))
		pid := C.fork()
		check(pid >= 0, 328)
		if pid == 0 {
			check(C.getpgid(0) == C.getppid(), 329)
			C.snprintf(&path[0], path.len, c'%s.child.pid', prefix)
			count_child := C.snprintf(&text[0], text.len, c'%d\n', C.getpid())
			check(count_child > 0, 330)
			write_text(&path[0], &text[0], usize(count_child))
		}
		for { C.pause() }
		return 1
	}
}

fn start_jobs(action &char, state &char) i32 {
	unsafe {
		pid := C.fork()
		check(pid > -1, 331)
		if pid == 0 {
			argv := [&char(c'/usr/bin/vinix-jobs'), action, state, &char(nil)]!
			C.execv(argv[0], &argv[0])
			C._exit(127)
		}
		return pid
	}
}

fn wait_jobs(pid i32, signal i32) {
	deadline := job_clock() + 10000000000
	mut status := i32(0)
	for {
		result := C.waitpid(pid, unsafe { &status }, C.WNOHANG)
		check(result >= 0, 332)
		if result == pid { break }
		check(job_clock() < deadline, 333)
		C.usleep(10000)
	}
	check(if signal == 0 { C.WIFEXITED(status) != 0 && C.WEXITSTATUS(status) == 0 }
		else { C.WIFSIGNALED(status) != 0 && C.WTERMSIG(status) == signal }, 334)
}

fn job_pid(prefix &char, suffix &char) i32 {
	unsafe {
		mut path := [256]char{}
		C.snprintf(&path[0], path.len, c'%s.%s.pid', prefix, suffix)
		deadline := job_clock() + 10000000000
		for {
			mut text := [32]char{}
			fd := C.open(&path[0], C.O_RDONLY)
			if fd >= 0 {
				count := C.read(fd, &text[0], text.len - 1)
				check(C.close(fd) == 0 && count >= 0, 335)
				mut pid := i32(0)
				if count > 0 && C.sscanf(&text[0], c'%d', &pid) == 1 {
					check(pid > 1, 336)
					return pid
				}
			}
			check(job_clock() < deadline, 337)
			C.usleep(10000)
		}
		return -1
	}
}

fn retired_job(pid i32) {
	deadline := job_clock() + 10000000000
	for {
		result := C.kill(pid, 0)
		code := unsafe { *C.__errno_location() }
		if result == -1 && code == C.ESRCH { return }
		// A probe may be refused while the exiting task releases its
		// namespaces. Refusal does not prove retirement: wait for ESRCH.
		check(result == 0 || (result == -1 && code == C.EPERM), 339)
		check(job_clock() < deadline, 338)
		C.usleep(10000)
	}
}

fn job_state(path &char, in_flight bool, detail &char, runs &char) {
	unsafe {
		private_receipt(path, detail)
		mut text := [4096]char{}
		fd := C.open(path, C.O_RDONLY)
		count := C.read(fd, &text[0], text.len - 1)
		check(fd >= 0 && count > 0 && count < text.len - 1 && C.close(fd) == 0, 340)
		check(C.strstr(&text[0], if in_flight { c'"in_flight":true' } else { c'"in_flight":false' }) != nil
			&& C.strstr(&text[0], runs) != nil, 341)
	}
}

fn snapshot_job(source &char, target &char) {
	unsafe {
		mut text := [4096]char{}
		fd := C.open(source, C.O_RDONLY)
		count := C.read(fd, &text[0], text.len - 1)
		check(fd >= 0 && count > 0 && count < text.len - 1 && C.close(fd) == 0, 342)
		write_text(target, &text[0], usize(count))
	}
}

fn job_lifecycle_checks() {
	unsafe {
		for name in [&char(c'deadline'), &char(c'term'), &char(c'int'), &char(c'watch'), &char(c'interrupted')]! {
			mut plan := [256]char{}
			mut state := [256]char{}
			C.snprintf(&plan[0], plan.len, c'/home/developer/%s-jobs.json', name)
			C.snprintf(&state[0], state.len, c'/home/developer/%s-state', name)
			check(command(c'/usr/bin/vinix-jobs', c'init', &plan[0], &state[0]) == 0, 343)
		}
		check(command(c'/usr/bin/vinix-jobs', c'run-due', c'/home/developer/deadline-state', nil) == 1, 344)
		retired_job(job_pid(c'/home/developer/deadline', c'parent'))
		retired_job(job_pid(c'/home/developer/deadline', c'child'))
		job_state(c'/home/developer/deadline-state/state.json', false, c'job deadline expired', c'"runs":1')

		for name in [&char(c'term'), &char(c'int')]! {
			mut state := [256]char{}
			mut prefix := [256]char{}
			C.snprintf(&state[0], state.len, c'/home/developer/%s-state', name)
			C.snprintf(&prefix[0], prefix.len, c'/home/developer/%s', name)
			owner := start_jobs(c'watch', &state[0])
			parent := job_pid(&prefix[0], c'parent')
			child := job_pid(&prefix[0], c'child')
			check(C.getpgid(parent) == parent && C.getpgid(child) == parent, 345)
			check(command(c'/usr/bin/vinix-jobs', c'run-due', &state[0], nil) == 1, 346)
			check(command(c'/usr/bin/vinix-jobs', c'acknowledge-interrupted', &state[0], c'fixture') == 1, 347)
			check(C.kill(owner, if C.strcmp(name, c'term') == 0 { C.SIGTERM } else { C.SIGINT }) == 0, 348)
			wait_jobs(owner, 0)
			retired_job(parent)
			retired_job(child)
			mut path := [512]char{}
			C.snprintf(&path[0], path.len, c'%s/state.json', &state[0])
			job_state(&path[0], false, c'job interrupted', c'"runs":1')
		}

		watcher := start_jobs(c'watch', c'/home/developer/watch-state')
		deadline := job_clock() + 20000000000
		for {
			mut text := [4096]char{}
			fd := C.open(c'/home/developer/watch-state/state.json', C.O_RDONLY)
			// Preserve open's errno; read(-1) would mask it with EBADF.
			check(fd >= 0, 349)
			count := C.read(fd, &text[0], text.len - 1)
			check(count > 0 && C.close(fd) == 0, 349)
			if C.strstr(&text[0], c'"runs":2') != nil && C.strstr(&text[0], c'"in_flight":false') != nil { break }
			check(job_clock() < deadline && C.kill(watcher, 0) == 0, 350)
			C.usleep(10000)
		}
		check(C.kill(watcher, C.SIGTERM) == 0, 351)
		wait_jobs(watcher, 0)
		job_state(c'/home/developer/watch-state/state.json', false, c'finished', c'"runs":2')
		mut ticks := [128]char{}
		fd_ticks := C.open(c'/home/developer/watch.ticks', C.O_RDONLY)
		count_ticks := C.read(fd_ticks, &ticks[0], ticks.len - 1)
		mut expected := [128]char{}
		bytes := C.snprintf(&expected[0], expected.len, c'%d\n%d\n', watcher, watcher)
		check(fd_ticks >= 0 && C.close(fd_ticks) == 0 && count_ticks == bytes
			&& C.memcmp(&ticks[0], &expected[0], usize(bytes)) == 0, 352)

		owner := start_jobs(c'run-due', c'/home/developer/interrupted-state')
		parent := job_pid(c'/home/developer/interrupted', c'parent')
		child := job_pid(c'/home/developer/interrupted', c'child')
		check(C.getpgid(parent) == parent && C.getpgid(child) == parent, 353)
		check(C.kill(owner, C.SIGKILL) == 0, 354)
		wait_jobs(owner, C.SIGKILL)
		check(C.kill(parent, 0) == 0 && C.kill(child, 0) == 0, 355)
		check(command(c'/usr/bin/vinix-jobs', c'run-due', c'/home/developer/interrupted-state', nil) == 1, 356)
		snapshot_job(c'/home/developer/interrupted-state/state.json', c'/home/developer/interrupted-before.json')
		job_state(c'/home/developer/interrupted-before.json', true, c'running', c'"runs":0')
		// Only the fixture's freshly observed, still-live group is signalled.
		// The scheduler never acts on a PID persisted from a previous run.
		check(C.kill(-parent, C.SIGKILL) == 0, 357)
		retired_job(parent)
		retired_job(child)
		check(command(c'/usr/bin/vinix-jobs', c'acknowledge-interrupted', c'/home/developer/interrupted-state', c'fixture') == 0, 358)
		check(command(c'/usr/bin/vinix-jobs', c'run-due', c'/home/developer/interrupted-state', nil) == 0, 359)
		job_state(c'/home/developer/interrupted-state/state.json', false, c'finished', c'"runs":1')
		mut proof := [10]char{}
		fd := C.open(c'/home/developer/interrupted.recovered', C.O_RDONLY)
		check(fd >= 0 && C.read(fd, &proof[0], 9) == 9 && C.close(fd) == 0
			&& C.strcmp(&proof[0], c'completed') == 0, 360)
		C.puts(c'DEVELOPMENT JOB CONTROL PASS: UID 1000, deadline and INT/TERM group retirement, concurrent-owner refusal, watcher ticks with one PID, killed-owner retry blocked until acknowledgement')
	}
}
