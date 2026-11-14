// SPDX-License-Identifier: GPL-2.0-or-later
module selectorderfixture

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

fn cycle(t &Targets, apis int) {
 for api in 0 .. apis { for amount in 0 .. 3 { for pack in 0 .. if api == 0 { 6 } else { 1 } {
 for timeout in 0 .. 5 { for descriptor in 0 .. 6 {
 install(t,descriptor)
 result := probe(t,api,amount,pack,timeout,descriptor)
 if result.checks != 9 { fatal(34) }
 if descriptor != 4 && C.close(32) != 0 { fatal(35) }
 } } } } }
}

fn storage(t &Targets, apis int) bool {
 unsafe {
 fd := C.open(c'/proc/slabinfo',C.O_RDONLY)
 if fd < 0 { fatal(31) }
 defer { C.close(fd) }
 for _ in 0 .. 64 { cycle(t,apis) }
 C.usleep(13_000_000)
 before := &Slabs(C.alloca(usize(sizeof(Slabs))))
 after := &Slabs(C.alloca(usize(sizeof(Slabs))))
 if !snapshot(fd,before) { fatal(32) }
 for _ in 0 .. 200 { cycle(t,apis) }
 C.usleep(13_000_000)
 if !snapshot(fd,after) { fatal(33) }
 mut good := before.rows == after.rows && before.large == after.large && before.tainted == 0 && after.tainted == 0
 for row in 0 .. before.rows {
 if before.sizes[row] != after.sizes[row] || before.live[row] != after.live[row] { good = false }
 C.printf(c'LINUX SELECTORDER SLAB: uid=%u size=%lu live=%lu/%lu cycles=200\n',C.getuid(),before.sizes[row],before.live[row],after.live[row])
 }
 C.printf(c'LINUX SELECTORDER STORAGE: uid=%u cycles=200 big_pages=%lu/%lu tainted=%lu/%lu %s\n',C.getuid(),before.large,after.large,before.tainted,after.tainted,if good { &char(c'PASS') } else { &char(c'FAIL') })
 return good
 }
}
