// SPDX-License-Identifier: GPL-2.0-or-later
module mqueuefixture

#include <sys/inotify.h>

fn C.inotify_init1(i32) i32
fn C.inotify_add_watch(i32, &char, u32) i32
fn C.strtoll(&char, voidptr, i32) i64
fn C.strstr(&char, &char) &char

fn admission_memory_current() i64 {
	unsafe {
		fd := C.open(c'/tmp/mq-budget/test/memory.current', C.O_RDONLY)
		if fd < 0 { return -1 }
		mut buf := [64]char{}
		count := C.read(fd, &buf[0], buf.len - 1)
		C.close(fd)
		return if count > 0 { C.strtoll(&buf[0], nil, 10) } else { i64(-1) }
	}
}

fn admission_worker(mut s State, ready i32, proceed i32) i32 {
	unsafe {
		if C.write(ready, c'r', 1) != 1 || C.read(proceed, s.buf, 1) != 1 { return 1 }
		q := quota_queue(mut s, c'admission-calibration')
		// No mqueuefs view exists yet, so no retired vnode holds the
		// unlinked queue after close.
		if q < 0 || mq_unlink(c'admission-calibration') != 0 { return 2 }
		if C.write(ready, c'q', 1) != 1 || C.read(proceed, s.buf, 1) != 1 { return 3 }
		if C.close(i32(q)) != 0 { return 4 }
		if C.write(ready, c'c', 1) != 1 || C.read(proceed, s.buf, 1) != 1 { return 5 }
		failed := quota_queue(mut s, c'admission-limited')
		if failed != -C.ENOMEM {
			C.printf(c'LINUX MQUEUE admission open result=%ld\n', failed)
			if failed >= 0 {
				mq_unlink(c'admission-limited')
				C.close(i32(failed))
			}
			return 6
		}
		return 0
	}
}

fn admission_limit(mut s State, child i32, ready i32, proceed i32) bool {
	unsafe {
		mut buf := [64]char{}
		if C.read(ready, &buf[0], 1) != 1 { return false }
		C.snprintf(&buf[0], buf.len, c'%d', child)
		if !write_text_file(c'/tmp/mq-budget/test/cgroup.procs', &buf[0]) { return false }
		if C.write(proceed, c'p', 1) != 1 || C.read(ready, &buf[0], 1) != 1 { return false }
		opened := admission_memory_current()
		if C.write(proceed, c'p', 1) != 1 || C.read(ready, &buf[0], 1) != 1 { return false }
		closed := admission_memory_current()
		delta := opened - closed
		// The FD and Handle total 1152 bytes. Leave space for the queue and
		// less than 1024 extra bytes, allowing for the short pipe I/O charge.
		limit := opened - 512
		C.printf(c'LINUX MQUEUE admission: open=%ld closed=%ld limit=%ld\n', opened, closed, limit)
		calibrated := closed >= 0 && delta > 1152
		check(mut s, c'queue and descriptor charges calibrated', calibrated, delta)
		if !calibrated { return false }
		C.snprintf(&buf[0], buf.len, c'%ld', limit)
		return write_text_file(c'/tmp/mq-budget/test/memory.max', &buf[0])
	}
}

fn admission_denied_file() bool {
	unsafe {
		fd := C.open(c'/proc/kernel-resources', C.O_RDONLY)
		if fd < 0 { return false }
		mut buf := [2048]char{}
		count := C.read(fd, &buf[0], buf.len - 1)
		C.close(fd)
		return count > 0 && C.strstr(&buf[0], c'LastDenied: cgroup\n') != nil
			&& C.strstr(&buf[0], c'LastDeniedKind: file\nLastDeniedRequested: 1024\n') != nil
	}
}

fn open_admission(mut s State) {
	unsafe {
		s.label = c'open admission'
		configured := C.syscall(isize(C.SYS_unshare), clone_newipc) == 0
			&& C.mkdir(c'/tmp/mq-budget', 0o700) == 0
			&& C.mount(c'none', c'/tmp/mq-budget', c'cgroup2', 0, nil) == 0
			&& C.mkdir(c'/tmp/mq-budget/test', 0o700) == 0
			&& C.mkdir(c'/tmp/mq-admission-view', 0o700) == 0
		mut ready := [2]i32{}
		mut proceed := [2]i32{}
		if !configured || C.pipe(&ready[0]) != 0 || C.pipe(&proceed[0]) != 0 {
			check(mut s, c'setup', false, result(-1))
			return
		}
		child := C.fork()
		if child == 0 {
			C.close(ready[0])
			C.close(proceed[1])
			C._exit(admission_worker(mut s, ready[1], proceed[0]))
		}
		C.close(ready[1])
		C.close(proceed[0])
		limited := child > 0 && admission_limit(mut s, child, ready[0], proceed[1])
		mounted := limited && C.mount(c'none', c'/tmp/mq-admission-view', c'mqueue', 0, nil) == 0
		watch := if mounted { C.inotify_init1(C.IN_NONBLOCK | C.IN_CLOEXEC) } else { i32(-1) }
		watched := watch >= 0 && C.inotify_add_watch(watch, c'/tmp/mq-admission-view', C.IN_CREATE | C.IN_DELETE) >= 0
		started := watched && C.write(proceed[1], c'p', 1) == 1
		C.close(proceed[1])
		C.close(ready[0])
		status := wait_quota_child(child)
		check(mut s, c'open fails with ENOMEM under cgroup limit', started && status == 0, status)
		if watched {
			check(mut s, c'cgroup refused the open file charge', admission_denied_file(), 0)
			events := result(C.read(watch, s.buf, 4096))
			check(mut s, c'failed open emits no inotify events', events == -C.EAGAIN, events)
			missing := mq_open(c'admission-limited', o_rdonly, 0, nil)
			check(mut s, c'failed open leaves the name absent', missing == -C.ENOENT, missing)
			if missing >= 0 { C.close(i32(missing)) }
			q := quota_queue(mut s, c'admission-limited')
			event := if q >= 0 { result(C.read(watch, s.buf, 4096)) } else { i64(-1) }
			check(mut s, c'successful open publishes the name and emits IN_CREATE',
				q >= 0 && event >= 16 && (&u32(s.buf))[1] == C.IN_CREATE, q)
			if q >= 0 {
				mq_unlink(c'admission-limited')
				C.close(i32(q))
			}
		}
		if watch >= 0 { C.close(watch) }
		if mounted { C.umount(c'/tmp/mq-admission-view') }
		C.umount(c'/tmp/mq-budget')
	}
}
