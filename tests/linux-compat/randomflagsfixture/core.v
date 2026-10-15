// SPDX-License-Identifier: GPL-2.0-or-later
module randomflagsfixture

#include <alloca.h>
#include <errno.h>
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/random.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct Counts {
mut:
	calls    [4]u64
	failures [4]u64
}

struct Slabs {
mut:
	sizes [32]u64
	live  [32]u64
	rows  i32
	large u64
}

struct Region {
	base &u8
	page usize
}

struct Result {
	ret  isize
	code i32
}

fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.getrandom(voidptr, usize, u32) isize
fn C.getpagesize() i32
fn C.getuid() u32
fn C.geteuid() u32
fn C.getgid() u32
fn C.getegid() u32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.pipe2(&i32, i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.alarm(u32) u32
fn C.usleep(u32) i32
fn C.pause() i32
fn C.strcmp(&char, &char) i32
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32

fn fatal(stage i32) {
	C.printf(c'LINUX RANDOMFLAGS FAIL: setup stage=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(1)
}

fn address(region &Region, shape i32) voidptr {
	unsafe {
		return match shape {
			0 { voidptr(region.base + region.page + 128) }
			1 { voidptr(region.base + region.page + 141) }
			2 { nil }
			3 { voidptr(1) }
			4 { voidptr(region.base + 8) }
			else { voidptr(region.base + 3 * region.page + 16) }
		}
	}
}

fn invoke(region &Region, shape i32, length u64, flags u32, form i32) Result {
	unsafe {
		err := C.__errno_location()
		*err = 0
		pointer := address(region, shape)
		ret := if form == 3 {
			C.getrandom(pointer, usize(length), flags)
		} else {
			word := if form == 0 {
				u64(flags)
			} else if form == 1 {
				0x1234567800000000 | u64(flags)
			} else {
				0xffffffff00000000 | u64(flags)
			}
			C.syscall(C.SYS_getrandom, pointer, length, word)
		}
		return Result{ret, *err}
	}
}

fn reset(region &Region) {
	unsafe { C.memset(region.base + region.page, 0xa5, 2 * region.page) }
}

fn guarded(region &Region, shape i32, length u64, written bool) bool {
	unsafe {
		start := if shape == 0 { usize(128) } else { usize(141) }
		for index in usize(0) .. 2 * region.page {
			if written && index >= start && u64(index - start) < length { continue }
			if region.base[region.page + index] != 0xa5 { return false }
		}
		// The read-only page is a fault destination, never a valid output.
		for index in usize(0) .. region.page {
			if region.base[3 * region.page + index] != 0xa5 { return false }
		}
		return true
	}
}

fn record(counts &Counts, kind i32, ordinary bool, region &Region, shape i32, length u64, flags u32, form i32, code i32) {
	unsafe {
		reset(region)
		result := invoke(region, shape, length, flags, form)
		valid := result.ret == if code == 0 { isize(length) } else { isize(-1) }
			&& result.code == code && guarded(region, shape, length, code == 0 && length > 0)
		mut c := &Counts(counts)
		c.calls[kind]++
		if !valid {
			c.failures[kind]++
			if c.failures[kind] <= 4 {
				C.printf(c'LINUX RANDOMFLAGS DETAIL: ordinary=%d kind=%d flags=%x form=%d shape=%d count=%lu result=%ld/%d expected_errno=%d\n', i32(ordinary), kind, flags, form, shape, length, result.ret, result.code, code)
			}
		}
	}
}

fn matrix(counts &Counts, ordinary bool, region &Region) {
	unsafe {
		for flags in [u32(6), 7]! {
			for form in 0 .. 4 {
				for shape in 0 .. 6 {
					for length in [u64(0), 1, 255, 256, 257, u64(region.page), u64(region.page + 1),
						0x80000000, u64(-1)]! {
						record(counts, 0, ordinary, region, i32(shape), length, flags, i32(form), C.EINVAL)
					}
				}
			}
		}
		for flags in [u32(8), 9, 10, 11, 12, 13, 14, 15, 0x80000000, 0xfffffffe, 0xffffffff]! {
			for form in 0 .. 4 {
				for shape in 0 .. 6 {
					for length in [u64(0), 1, 255, 256, 257, u64(region.page), u64(region.page + 1),
						0x80000000, u64(-1)]! {
						record(counts, 1, ordinary, region, i32(shape), length, flags, i32(form), C.EINVAL)
					}
				}
			}
		}
		for flags in [u32(0), 1, 2, 3, 4, 5]! {
			for form in 0 .. 4 {
				for shape in 0 .. 6 {
					record(counts, 2, ordinary, region, i32(shape), 0, flags, i32(form), 0)
				}
			}
			for form in 0 .. 4 {
				for shape in 0 .. 6 {
					for length in [u64(1), 255, 256, 257]! {
						record(counts, 3, ordinary, region, i32(shape), length, flags, i32(form), if shape < 2 {
							i32(0)
						} else {
							i32(C.EFAULT)
						})
					}
				}
			}
		}
	}
}

fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination)
		*counts = Slabs{}
		mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0)
		if length <= 0 || length >= 4096 { return false }
		data[int(length)] = 0
		mut position := 0
		mut large := false
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
			}
			for position < int(length) && data[position] != char(10) { position++ }
			position++
		}
		return counts.rows > 0 && large
	}
}

fn cycle(region &Region) bool {
	unsafe {
		for flags in [u32(6), 7, 8, 0x80000000, 0xffffffff]! {
			for form in 0 .. 4 {
				for shape in [i32(0), 2, 4, 5]! {
					for length in [u64(0), 257, u64(-1)]! {
						reset(region)
						r := invoke(region, shape, length, flags, i32(form))
						if r.ret != -1 || r.code != C.EINVAL || !guarded(region, shape, length, false) {
							return false
						}
					}
				}
			}
		}
		for flags in [u32(0), 1, 2, 3, 4, 5]! {
			for form in 0 .. 4 {
				r := invoke(region, 2, 0, flags, i32(form))
				if r.ret != 0 || r.code != 0 { return false }
			}
		}
		return true
	}
}

fn storage(region &Region, ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo', 0)
		if observer < 0 { return false }
		defer { C.close(observer) }
		for _ in 0 .. 32 { if !cycle(region) { return false } }
		C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs))))
		after := &Slabs(C.alloca(usize(sizeof(Slabs))))
		if !snapshot(observer, before) { return false }
		for _ in 0 .. 200 { if !cycle(region) { return false } }
		C.usleep(13000000)
		if !snapshot(observer, after) { return false }
		mut good := before.rows == after.rows && before.large == after.large
		for index in 0 .. int(before.rows) {
			if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {
				good = false
			}
			C.printf(c'LINUX RANDOMFLAGS SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index])
		}
		C.printf(c'LINUX RANDOMFLAGS STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good {
			&char(c'PASS')
		} else {
			&char(c'FAIL')
		})
		C.fflush(nil)
		return good
	}
}

fn qualify(counts &Counts, ordinary bool, reference bool) bool {
	unsafe {
		C.alarm(600)
		uid := if ordinary { u32(1000) } else { u32(0) }
		if ordinary && (C.setgroups(0, nil) != 0 || C.setgid(uid) != 0 || C.setuid(uid) != 0) {
			fatal(1)
		}
		if C.getuid() != uid || C.geteuid() != uid || C.getgid() != uid || C.getegid() != uid {
			fatal(2)
		}
		page := usize(C.getpagesize())
		if page != 4096 && page != 16384 { fatal(3) }
		base := C.mmap(nil, 5 * page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if base == voidptr(-1) { fatal(4) }
		C.memset(base, 0xa5, 5 * page)
		if C.mprotect(base, page, C.PROT_NONE) != 0 || C.mprotect(voidptr(usize(base) + 3 * page), page, C.PROT_READ) != 0 || C.mprotect(voidptr(usize(base) + 4 * page), page, C.PROT_NONE) != 0 {
			fatal(5)
		}
		mut region := Region{&u8(base), page}
		// Establish seeded nonblocking readiness with a real successful call.
		mut ready := false
		for _ in 0 .. 100 {
			result := invoke(&region, 0, 32, 1, 0)
			if result.ret == 32 && result.code == 0 {
				ready = true
				break
			}
			if result.ret != -1 || result.code != C.EAGAIN { fatal(6) }
			C.usleep(10000)
		}
		if !ready { fatal(7) }
		C.printf(c'LINUX RANDOMFLAGS TOPOLOGY: ordinary=%d uid=%u page=%lu readiness=seeded\n', i32(ordinary), uid, page)
		matrix(counts, ordinary, &region)
		mut good := counts.failures[0] == 0 && counts.failures[1] == 0 && counts.failures[2] == 0 && counts.failures[3] == 0
		if good && !reference && !storage(&region, ordinary) { good = false }
		if C.munmap(base, 5 * page) != 0 { fatal(8) }
		for kind in 0 .. 4 {
			C.printf(c'LINUX RANDOMFLAGS CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind])
			if counts.failures[kind] != 0 { good = false }
		}
		C.alarm(0)
		C.fflush(nil)
		return good
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if sizeof(Counts) != 64 { fatal(9) }
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		mut good := true
		for ordinary in [false, true]! {
			mut pipe := [i32(-1), i32(-1)]!
			if C.pipe2(&pipe[0], 0) != 0 { fatal(10) }
			child := C.fork()
			if child < 0 { fatal(11) }
			if child == 0 {
				C.close(pipe[0])
				counts := &Counts(C.alloca(usize(sizeof(Counts))))
				*counts = Counts{}
				passed := qualify(counts, ordinary, reference)
				sent := C.write(pipe[1], counts, sizeof(Counts)) == isize(sizeof(Counts))
				C.close(pipe[1])
				C._exit(if passed && sent { 0 } else { 1 })
			}
			C.close(pipe[1])
			counts := &Counts(C.alloca(usize(sizeof(Counts))))
			*counts = Counts{}
			received := C.read(pipe[0], counts, sizeof(Counts)) == isize(sizeof(Counts))
			C.close(pipe[0])
			mut status := i32(-1)
			completed := C.waitpid(child, &status, 0) == child && status == 0
			if !received || !completed { good = false }
			if received {
				for kind in 0 .. 4 {
					C.printf(c'LINUX RANDOMFLAGS FINAL: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind])
					if counts.failures[kind] != 0 { good = false }
				}
			}
			C.fflush(nil)
		}
		if !good {
			C.puts(c'LINUX RANDOMFLAGS FAIL: flag errors or buffer guards')
			C.fflush(nil)
			return 1
		}
		C.puts(if reference {
			c'LINUX RANDOMFLAGS REFERENCE: PASS'
		} else {
			c'LINUX RANDOMFLAGS: PASS'
		})
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
