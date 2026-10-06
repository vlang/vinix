// SPDX-License-Identifier: GPL-2.0-or-later
// Independent raw-stat ABI and exact heap-retention fixture.
@[has_globals]
module guestfixture

#include <stat-native-abi.h>

@[typedef]
struct C.FILE {}
struct C.timespec {
	tv_sec i64
	tv_nsec i64
}
struct C.stat {
	st_mode u32
	st_ino u64
	st_dev u64
}
struct C.stat_guest_snapshot {
	count u32
	size [32]u64
	live [32]u64
	pages [32]u64
	large u64
	uaf u64
	free i64
	slab i64
	cached i64
}
struct C.stat_guest_scan {
	label u64
	size u64
	live u64
	pages u64
}
struct C.stat_guest_long {
	value i64
}
struct C.stat_guest_delta {
	objects i64
	pages i64
	large i64
}
@[c_extern]
__global C.stdout &C.FILE
__global stat_guest_target i32
__global stat_guest_text [131072]char

fn C.__errno_location() &i32
fn C.clock_gettime(i32, &C.timespec) i32
fn C.nanosleep(&C.timespec, &C.timespec) i32
fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.strcmp(&char, &char) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.strtok(&char, &char) &char
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.fdopen(i32, &char) &C.FILE
fn C.fgets(&char, i32, &C.FILE) &char
fn C.ferror(&C.FILE) i32
fn C.fclose(&C.FILE) i32
fn C.syscall(isize, ...) isize
fn C.S_ISCHR(u32) bool
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.puts(&char) i32
fn C.sync()
fn C.reboot(i32) i32

fn check(condition bool, original_line i32) bool {
	if !condition {
		unsafe { C.printf(c'XNU STAT FAIL line=%d errno=%d\n', original_line, *C.__errno_location()) }
	}
	return condition
}

fn pause_ns(interval u64) i32 {
	unsafe {
		mut t := C.timespec{}
		if !check(C.clock_gettime(C.CLOCK_MONOTONIC, &t) == 0, 24) { return -1 }
		end := u64(t.tv_sec) * 1000000000 + u64(t.tv_nsec) + interval
		for {
			if !check(C.clock_gettime(C.CLOCK_MONOTONIC, &t) == 0, 27) { return -1 }
			now := u64(t.tv_sec) * 1000000000 + u64(t.tv_nsec)
			if now >= end { return 0 }
			left := end - now
			req := C.timespec{tv_sec: i64(left / 1000000000), tv_nsec: i64(left % 1000000000)}
			if !check(C.nanosleep(&req, nil) == 0 || *C.__errno_location() == C.EINTR, 30) { return -1 }
		}
	}
	return 0
}

fn read_proc(path &char) i32 {
	unsafe {
		fd := C.open(path, C.O_RDONLY)
		if fd < 0 && *C.__errno_location() == C.ENOENT && C.strcmp(path, c'/proc/allocstart') == 0 { return 0 }
		if !check(fd >= 0, 33) { return -1 }
		n := C.read(fd, &stat_guest_text[0], sizeof(stat_guest_text) - 1)
		result := C.close(fd)
		if !check(n > 0 && result == 0, 33) { return -1 }
		stat_guest_text[n] = 0
	}
	return 0
}

fn snapshot(out &C.stat_guest_snapshot) i32 {
	unsafe {
		C.memset(out, 0, sizeof(C.stat_guest_snapshot))
		out.free = -1
		out.slab = -1
		out.cached = -1
		if !check(read_proc(c'/proc/meminfo') == 0, 36) { return -1 }
		mut s := C.strtok(&stat_guest_text[0], c'\n')
		for s != nil {
			mut value := C.stat_guest_long{}
			if C.sscanf(s, c'MemFree: %ld', &value.value) == 1 { out.free = value.value }
			else if C.sscanf(s, c'Slab: %ld', &value.value) == 1 { out.slab = value.value }
			else if C.sscanf(s, c'Cached: %ld', &value.value) == 1 { out.cached = value.value }
			s = C.strtok(nil, c'\n')
		}
		if !check(out.free >= 0 && out.slab >= 0 && out.cached >= 0 && read_proc(c'/proc/slabinfo') == 0, 38) { return -1 }
		mut large := false
		mut uaf := false
		s = C.strtok(&stat_guest_text[0], c'\n')
		for s != nil {
			mut scan := C.stat_guest_scan{}
			if C.sscanf(s, c'size-%llu %llu %llu %llu', &scan.label, &scan.size, &scan.live, &scan.pages) == 4 {
				if !check(scan.label == scan.size && out.count < 32, 40) { return -1 }
				i := out.count
				out.count++
				out.size[i] = scan.size
				out.live[i] = scan.live
				out.pages[i] = scan.pages
			} else if C.sscanf(s, c'large - - %llu', &out.large) == 1 { large = true }
			else if C.sscanf(s, c'# written after free %llu', &out.uaf) == 1 { uaf = true }
			s = C.strtok(nil, c'\n')
		}
		$if arm64 {
			if !check(out.count == 18 && large && uaf, 44) { return -1 }
		} $else {
			if !check(out.count == 14 && large && uaf, 46) { return -1 }
		}
	}
	return 0
}

fn sites(name &char, cohort i32) i32 {
	unsafe {
		fd := C.open(c'/proc/allocsites', C.O_RDONLY)
		if fd < 0 && *C.__errno_location() == C.ENOENT { return 0 }
		if !check(fd >= 0, 51) { return -1 }
		f := C.fdopen(fd, c'r')
		if !check(f != nil, 51) { return -1 }
		mut line := [2048]char{}
		for C.fgets(&line[0], i32(sizeof(line)), f) != nil {
			C.printf(c'PERF-SITE program=%s cohort=%d %s', name, cohort, &line[0])
		}
		if !check(C.ferror(f) == 0 && C.fclose(f) == 0, 51) { return -1 }
	}
	return 0
}

fn report(name &char, cohort i32, runs i32, before &C.stat_guest_snapshot, after &C.stat_guest_snapshot) i32 {
	unsafe {
		if !check(before.count == after.count && before.uaf == after.uaf, 54) { return -1 }
		mut nonzero := u32(0)
		for i := u32(0); i < after.count; i++ {
			if !check(before.size[i] == after.size[i], 55) { return -1 }
			delta := C.stat_guest_delta{objects: i64(after.live[i] - before.live[i]), pages: i64(after.pages[i] - before.pages[i])}
			if delta.objects != 0 || delta.pages != 0 {
				nonzero++
				C.printf(c'XNU CHURN CLASS program=%s cohort=%d size=%llu objects=%+lld pages=%+lld\n', name, cohort, after.size[i], delta.objects, delta.pages)
			}
		}
		delta := C.stat_guest_delta{large: i64(after.large - before.large)}
		// Native long fields and unsigned-long-long fields retain their printf ABI.
		C.printf(c'XNU CHURN MEASURE program=%s cohort=%d runs=%d classes=%u nonzero=%u used_kib=%+ld slab_kib=%+ld cached_kib=%+ld large_pages=%+lld written_after_free=%llu\n', name, cohort, runs, after.count, nonzero, before.free - after.free, after.slab - before.slab, after.cached - before.cached, delta.large, after.uaf - before.uaf)
		if !check(sites(name, cohort) == 0, 56) { return -1 }
	}
	return 0
}

fn operation() i32 {
	unsafe {
		mut first := C.stat{}
		mut second := C.stat{}
		if !check(C.syscall(C.SYS_fstat, stat_guest_target, &first) == 0 && C.S_ISCHR(first.st_mode), 60) { return -1 }
		if !check(C.syscall(C.SYS_fstat, i32(-1), &second) == -1 && *C.__errno_location() == C.EBADF, 61) { return -1 }
		if !check(C.syscall(C.SYS_fstat, stat_guest_target, voidptr(usize(1))) == -1 && *C.__errno_location() == C.EFAULT, 62) { return -1 }
		if !check(C.syscall(C.SYS_newfstatat, stat_guest_target, c'', &second, i32(C.AT_EMPTY_PATH)) == 0 && second.st_ino == first.st_ino && second.st_dev == first.st_dev && second.st_mode == first.st_mode, 63) { return -1 }
		if !check(C.syscall(C.SYS_newfstatat, i32(C.AT_FDCWD), c'/dev/null', &second, i32(0)) == 0 && second.st_ino == first.st_ino && second.st_dev == first.st_dev && second.st_mode == first.st_mode, 64) { return -1 }
		if !check(C.syscall(C.SYS_newfstatat, i32(C.AT_FDCWD), c'/absent-stat-probe', &second, i32(0)) == -1 && *C.__errno_location() == C.ENOENT, 65) { return -1 }
		if !check(C.syscall(C.SYS_newfstatat, i32(C.AT_FDCWD), voidptr(usize(1)), &second, i32(0)) == -1 && *C.__errno_location() == C.EFAULT, 66) { return -1 }
		if !check(C.syscall(C.SYS_newfstatat, i32(C.AT_FDCWD), c'/dev/null', voidptr(usize(1)), i32(0)) == -1 && *C.__errno_location() == C.EFAULT, 67) { return -1 }
	}
	return 0
}

fn measurement() i32 {
	unsafe {
		for _ in 0 .. 30 { if !check(operation() == 0, 71) { return -1 } }
		if !check(pause_ns(6100000000) == 0, 72) { return -1 }
		mut a := C.stat_guest_snapshot{}
		mut b := C.stat_guest_snapshot{}
		if !check(snapshot(&a) == 0, 73) { return -1 }
		for cohort := i32(1); cohort <= 3; cohort++ {
			if !check(read_proc(c'/proc/allocstart') == 0 && snapshot(&a) == 0, 75) { return -1 }
			for _ in 0 .. 300 { if !check(operation() == 0, 76) { return -1 } }
			if !check(pause_ns(6100000000) == 0 && snapshot(&b) == 0 && report(c'stat', cohort, 300, &a, &b) == 0, 77) { return -1 }
			for i := u32(0); i < a.count; i++ {
				if !check(a.live[i] == b.live[i] && a.pages[i] == b.pages[i], 79) { return -1 }
			}
			if !check(a.large == b.large && a.uaf == b.uaf, 80) { return -1 }
		}
		C.puts(c'XNU STAT SEMANTICS PASS good=2 empty_path=1 EBADF=1 EFAULT=3 ENOENT=1')
	}
	return 0
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		stat_guest_target = C.open(c'/dev/null', C.O_RDWR)
		result := if stat_guest_target < 0 { i32(-1) } else { measurement() }
		mut verdict := &char(c'PASS')
		if result != 0 { verdict = &char(c'FAIL') }
		C.printf(c'XNU STAT %s\n', verdict)
		C.sync()
		C.reboot(C.RB_POWER_OFF)
		return i32(result != 0)
	}
}
