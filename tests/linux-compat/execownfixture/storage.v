// SPDX-License-Identifier: GPL-2.0-or-later
module execownfixture

struct Slabs {
mut:
	sizes   [32]u64
	live    [32]u64
	rows    int
	large   u64
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
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate,
				&live, &pages) == 4 {
				if counts.rows >= 32 || size != duplicate || size == 0 { return false }
				if counts.rows > 0 && size <= counts.sizes[counts.rows - 1] { return false }
				counts.sizes[counts.rows] = size
				counts.live[counts.rows] = live
				counts.rows++
			} else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 {
				if large { return false }
				large = true
			} else if C.sscanf(&data[position], c'# written after free %lu', &counts.tainted) == 1 {
				if guarded { return false }
				guarded = true
			}
			for position < int(length) && data[position] != char(10) { position++ }
			position++
		}
		return counts.rows > 0 && large && guarded
	}
}

// Each cycle exercises the same imported vectors through several exec error
// paths. Measure after caches and deferred VFS reclamation have settled.
fn storage() bool {
	unsafe {
		C.alarm(90)
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if fd < 0 { return false }
		defer { C.close(fd) }
		for _ in 0 .. 64 {
			if !failure_cycle() { return false }
		}
		C.usleep(13_000_000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs))))
		after := &Slabs(C.alloca(usize(sizeof(Slabs))))
		if !snapshot(fd, before) { return false }
		mut completed := 0
		for _ in 0 .. 200 {
			if !failure_cycle() { return false }
			completed++
		}
		C.usleep(13_000_000)
		if !snapshot(fd, after) { return false }
		mut good := before.rows == after.rows && before.large == after.large
			&& before.tainted == 0 && after.tainted == 0
		for row in 0 .. before.rows {
			if before.sizes[row] != after.sizes[row] || before.live[row] != after.live[row] {
				good = false
			}
			C.printf(c'LINUX EXECOWN SLAB: uid=%u size=%lu live=%lu/%lu cycles=200\n',
				C.getuid(), before.sizes[row], before.live[row], after.live[row])
		}
		C.printf(c'LINUX EXECOWN STORAGE: uid=%u cycles=%d big_pages=%lu/%lu tainted=%lu/%lu %s\n',
			C.getuid(), completed, before.large, after.large, before.tainted, after.tainted,
			if good { &char(c'PASS') } else { &char(c'FAIL') })
		C.alarm(0)
		return good
	}
}
