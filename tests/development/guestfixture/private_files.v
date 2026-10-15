// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

#include <sys/stat.h>

fn C.mkfifo(&char, u32) i32
fn C.rename(&char, &char) i32

// A bad private-file path must fail before a FIFO writer arrives. Retain the
// live child identity until waitpid so timeout cleanup never uses a saved PID.
fn private_file_command(action &char, state &char) i32 {
	pid := start_jobs(action, state)
	deadline := job_clock() + 3000000000
	mut status := i32(0)
	for {
		result := C.waitpid(pid, unsafe { &status }, C.WNOHANG)
		check(result >= 0, 420)
		if result == pid { break }
		if job_clock() >= deadline {
			check(C.kill(pid, C.SIGKILL) == 0, 421)
			check(C.waitpid(pid, unsafe { &status }, 0) == pid, 422)
			check(false, 423)
		}
		C.usleep(10000)
	}
	check(C.WIFEXITED(status) != 0, 424)
	return C.WEXITSTATUS(status)
}

fn fifo_identity(path &char) u64 {
	mut st := C.stat{}
	check(C.stat(path, unsafe { &st }) == 0 && st.st_uid == 1000
		&& st.st_mode & C.S_IFMT == C.S_IFIFO && st.st_mode & 0o777 == 0o600, 425)
	return st.st_ino
}

fn private_file_checks() {
	unsafe {
		state := &char(c'/home/developer/fifo-token')
		check(command(c'/usr/bin/vinix-jobs', c'init', c'/home/developer/fifo-jobs.json', state) == 0, 426)
		check(C.unlink(c'/home/developer/token') == 0
			&& C.mkfifo(c'/home/developer/token', 0o600) == 0, 427)
		inode := fifo_identity(c'/home/developer/token')
		check(private_file_command(c'run-due', state) == 1, 428)
		check(fifo_identity(c'/home/developer/token') == inode, 429)
		check(C.open(c'/home/developer/payload.done', C.O_RDONLY) == -1, 430)
		snapshot_job(c'/home/developer/fifo-token/state.json', c'/home/developer/fifo-failed.json')
		job_state(c'/home/developer/fifo-failed.json', false, c'private file must be regular', c'"runs":1')

		check(C.unlink(c'/home/developer/token') == 0, 431)
		write_text(c'/home/developer/token', c'vinix-native-fixture-secret', 27)
		// The failed attempt still enforces its normal interval. Retry after it
		// becomes due, without rewriting the pinned plan or scheduler state.
		deadline := job_clock() + 4000000000
		for private_file_command(c'run-due', state) != 0 {
			check(job_clock() < deadline, 432)
			C.usleep(100000)
		}
		mut proof := [10]char{}
		fd := C.open(c'/home/developer/payload.done', C.O_RDONLY)
		check(fd >= 0 && C.read(fd, &proof[0], 9) == 9 && C.close(fd) == 0
			&& C.strcmp(&proof[0], c'completed') == 0, 433)
		check(C.unlink(c'/home/developer/payload.done') == 0, 434)
		job_state(c'/home/developer/fifo-token/state.json', false, c'finished', c'"runs":2')

		for name in [&char(c'plan'), &char(c'state')]! {
			mut path := [256]char{}
			mut saved := [256]char{}
			C.snprintf(&path[0], path.len, c'/home/developer/fifo-token/%s.json', name)
			C.snprintf(&saved[0], saved.len, c'/home/developer/fifo-token/%s.saved', name)
			check(C.rename(&path[0], &saved[0]) == 0 && C.mkfifo(&path[0], 0o600) == 0, 435)
			original := fifo_identity(&path[0])
			for action in [&char(c'status'), &char(c'run-due')]! {
				check(private_file_command(action, state) == 1, 436)
				check(fifo_identity(&path[0]) == original, 437)
				check(C.open(c'/home/developer/payload.done', C.O_RDONLY) == -1, 438)
			}
			check(C.unlink(&path[0]) == 0 && C.rename(&saved[0], &path[0]) == 0, 439)
		}
		C.puts(c'DEVELOPMENT PRIVATE FILE PASS: UID 1000, unwritten credential/plan/state FIFOs refused promptly, inodes preserved, failed attempt settled and rotated credential executed')
	}
}
