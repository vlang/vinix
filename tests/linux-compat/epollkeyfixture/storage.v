// SPDX-License-Identifier: GPL-2.0-or-later
module epollkeyfixture

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

fn targets() Targets { unsafe {
 a := &i32(C.alloca(8)); b := &i32(C.alloca(8))
 if C.pipe2(a,C.O_NONBLOCK) != 0 || C.pipe2(b,C.O_NONBLOCK) != 0 { fatal(40) }
 byte := &u8(C.alloca(1)); *byte = 0x59
 if C.write(a[1],byte,1) != 1 || C.write(b[1],byte,1) != 1 { fatal(41) }
 path := &char(C.alloca(64))
 if C.snprintf(path,64,c'/proc/self/fd/%d',a[0]) <= 0 { fatal(42) }
 reopened := C.open(path,C.O_RDONLY|C.O_NONBLOCK)
 epfd := C.epoll_create1(C.EPOLL_CLOEXEC)
 target := C.fcntl(a[0],C.F_DUPFD_CLOEXEC,70)
 if reopened < 0 || epfd < 0 || target < 70 || C.close(target) != 0 { fatal(43) }
 return Targets{reader:a[0],writer:a[1],other_reader:b[0],other_writer:b[1],reopened:reopened,epfd:epfd,target:target}
} }
// Keep the descriptions and procfs reopen stable. Exercise only descriptor
// replacement and watch add/modify/delete ownership during measurement.
fn cycle(t &Targets,_apis int) { unsafe {
 for api in 0 .. 2 { for mode in 0 .. 2 {
 if C.dup2(t.reader,t.target) != t.target || ctl(api,t.epfd,1,t.target,0x1122334455667788) != 0 { fatal(44) }
 source := if mode == 0 { t.other_reader } else { t.reopened }
 if C.dup2(source,t.target) != t.target { fatal(45) }
 // Semantic failures on the original are recorded by qualify(); still
 // complete exactly the same ownership operations and strict storage guard.
 ctl(api,t.epfd,1,t.target,0x8877665544332211)
 ctl(api,t.epfd,3,t.target,0x246813579abcdef0)
 mut sum := Totals{}
 wait_probe(mut sum,t.epfd,5)
 ctl(api,t.epfd,2,t.target,0)
 if C.dup2(t.reader,t.target) != t.target { fatal(46) }
 ctl(api,t.epfd,2,t.target,0)
 if C.close(t.target) != 0 { fatal(47) }
 } }
} }

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
 C.printf(c'LINUX EPOLLKEY SLAB: uid=%u size=%lu live=%lu/%lu cycles=200\n',C.getuid(),before.sizes[row],before.live[row],after.live[row])
 }
 C.printf(c'LINUX EPOLLKEY STORAGE: uid=%u cycles=200 big_pages=%lu/%lu tainted=%lu/%lu %s\n',C.getuid(),before.large,after.large,before.tainted,after.tainted,if good { &char(c'PASS') } else { &char(c'FAIL') })
 return good
 }
}
