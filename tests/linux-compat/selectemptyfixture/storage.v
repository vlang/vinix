// SPDX-License-Identifier: GPL-2.0-or-later
module selectemptyfixture

struct Slabs {
mut:
	sizes [32]u64
	live [32]u64
	rows int
	large u64
	tainted u64
}
fn snapshot(fd int, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination)
		*counts = Slabs{}
		mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0)
		if length <= 0 || length >= 4096 { return false }
		data[int(length)] = 0
		mut position := 0
		mut large := false
		mut guarded := false
		for position < int(length) {
			mut size := u64(0)
			mut duplicate := u64(0)
			mut live := u64(0)
			mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 {
				if counts.rows >= 32 || size != duplicate { return false }
				counts.sizes[counts.rows] = size
				counts.live[counts.rows] = live
				counts.rows++
			} else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 {
				large = true
			} else if C.sscanf(&data[position], c'# written after free %lu', &counts.tainted) == 1 {
				guarded = true
			}
			for position < int(length) && data[position] != char(10) { position++ }
			position++
		}
		return counts.rows > 0 && large && guarded
	}
}
fn cycle() int {
	unsafe {
		original := u64(1) << u64(C.SIGUSR1 - 1)
		setmask(original)
		if send_to(active, C.SIGUSR1) != 0 { fatal(21) }
		zero := [i64(0), i64(0)]!
		temporary := u64(0)
		pair := [u64(&temporary), u64(8)]!
		ret := C.syscall(isize(C.SYS_pselect6), 0, nil, nil, nil, nil, &pair[0])
		code := *C.__errno_location()
		if ret == -1 && code == C.EINTR { return 1 }
		// Preserve the original refusal as a storage baseline. It remains a
		// semantic failure in the main cases; explicitly drain its queued signal.
		if ret == -1 && code == C.EINVAL && C.syscall(isize(C.SYS_rt_sigtimedwait), &original, nil, &zero[0], usize(8)) == C.SIGUSR1 { return 0 }
		fatal(22); return -1
	}
}
fn storage() bool {
	unsafe {
		C.alarm(50)
		mut s := State{tid: int(C.syscall(isize(C.SYS_gettid))), pid: int(C.syscall(isize(C.SYS_getpid)))}
		active = &s
		mut action := C.sigaction{sa_handler: handler}
		if C.sigemptyset(&action.sa_mask) != 0 || C.sigaction(C.SIGUSR1, &action, nil) != 0 { fatal(23) }
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if fd < 0 { fatal(24) }
		for _ in 0 .. 64 { cycle() }
		C.usleep(13_000_000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs))))
		after := &Slabs(C.alloca(usize(sizeof(Slabs))))
		if !snapshot(fd, before) { fatal(25) }
		mut interrupted := 0
		for _ in 0 .. 200 { interrupted += cycle() }
		C.usleep(13_000_000)
		if !snapshot(fd, after) { fatal(26) }
		mut good := before.rows == after.rows && before.large == after.large && before.tainted == 0 && after.tainted == 0
		for row in 0 .. before.rows {
			if before.sizes[row] != after.sizes[row] || before.live[row] != after.live[row] { good = false }
			C.printf(c'LINUX SELECTEMPTY SLAB: uid=%u size=%lu live=%lu/%lu cycles=200\n', C.getuid(), before.sizes[row], before.live[row], after.live[row])
		}
		C.printf(c'LINUX SELECTEMPTY STORAGE: uid=%u cycles=200 interrupted=%d big_pages=%lu/%lu tainted=%lu/%lu %s\n', C.getuid(), interrupted, before.large, after.large, before.tainted, after.tainted, if good { &char(c'PASS') } else { &char(c'FAIL') })
		C.close(fd)
		return good
	}
}
