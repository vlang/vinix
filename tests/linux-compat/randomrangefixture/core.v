// SPDX-License-Identifier: GPL-2.0-or-later
module randomrangefixture

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
	base  &u8
	page  usize
	upper &u8
	limit u64
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
	C.printf(c'LINUX RANDOMRANGE FAIL: setup stage=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
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
			5 { voidptr(region.base + 3 * region.page + 16) }
			6 { voidptr(region.upper + region.page + 128) }
			7 { voidptr(region.upper + region.page + 141) }
			8 { voidptr(region.upper + 8) }
			9 { voidptr(region.upper + 3 * region.page + 16) }
			10 { voidptr(u64(1) << 63) }
			11 { voidptr((u64(1) << 63) + 1) }
			12 { voidptr(u64(1) << 60) }
			13 { voidptr(u64(-1)) }
			else { voidptr(region.limit + u64(region.page)) }
		}
	}
}

fn available(region &Region, shape i32) u64 {
	return if shape == 0 || shape == 6 {
		u64(2 * region.page - 128)
	} else if shape == 1 || shape == 7 {
		u64(2 * region.page - 141)
	} else {
		u64(0)
	}
}

fn ceiling(page usize) u64 {
	unsafe {
		for bits in [u32(56), 52, 48, 47]! {
			pointer := voidptr(u64(1) << (bits - 1))
			mapped := C.mmap(pointer, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS | 0x100000, -1, 0)
			if mapped != voidptr(-1) {
				if mapped != pointer || C.munmap(mapped, page) != 0 { fatal(12) }
				return u64(1) << bits
			}
			if *C.__errno_location() != C.ENOMEM && *C.__errno_location() != C.EINVAL && *C.__errno_location() != C.EFAULT {
				fatal(13)
			}
		}
		fatal(14)
		return 0
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
	unsafe {
		C.memset(region.base + region.page, 0xa5, 2 * region.page)
		C.memset(region.upper + region.page, 0xa5, 2 * region.page)
	}
}

fn guarded(region &Region, shape i32, written u64) bool {
	unsafe {
		pointer := u64(address(region, shape))
		for base in [region.base, region.upper]! {
			for index in usize(0) .. 2 * region.page {
				current := u64(base) + u64(region.page + index)
				if current >= pointer && current - pointer < written { continue }
				if base[region.page + index] != 0xa5 { return false }
			}
			for index in usize(0) .. region.page {
				if base[3 * region.page + index] != 0xa5 { return false }
			}
		}
		return true
	}
}

fn record(counts &Counts, kind i32, ordinary bool, region &Region, shape i32, length u64, flags u32, form i32, code i32, partial bool) {
	unsafe {
		reset(region)
		result := invoke(region, shape, length, flags, form)
		written := if code != 0 {
			u64(0)
		} else if partial {
			available(region, shape)
		} else {
			length
		}
		valid_ret := if code != 0 {
			result.ret == -1
		} else if partial {
			result.ret > 0 && u64(result.ret) <= written
		} else {
			result.ret == isize(length)
		}
		mut valid := valid_ret && result.code == code && guarded(region, shape, written)
		if written >= 32 {
			pointer := &u8(address(region, shape))
			mut changed := false
			for index in u64(0) .. written {
				if pointer[index] != 0xa5 {
					changed = true
					break
				}
			}
			if !changed { valid = false }
		}
		mut c := &Counts(counts)
		c.calls[kind]++
		if !valid {
			c.failures[kind]++
			if c.failures[kind] <= 4 {
				C.printf(c'LINUX RANDOMRANGE DETAIL: ordinary=%d kind=%d flags=%x form=%d shape=%d count=%lu result=%ld/%d expected_errno=%d partial=%d\n', i32(ordinary), kind, flags, form, shape, length, result.ret, result.code, code, i32(partial))
			}
		}
	}
}

fn matrix(counts &Counts, ordinary bool, region &Region) {
	unsafe {
		cap := u64(0x7fffffff) & ~(u64(region.page) - 1)
		for flags in [u32(0), 1, 2, 3, 4, 5]! {
			for form in 0 .. 4 {
				for shape in [i32(6), 7, 8, 9]! {
					gap := region.limit - u64(address(region, shape))
					for length in [gap + u64(region.page), gap + u64(region.page) + 1, cap, cap + 1,
						u64(0x80000000), u64(0x100000000), u64(0x8000000000000000), u64(-1)]! {
						record(counts, 0, ordinary, region, shape, length, flags, i32(form), C.EFAULT, false)
					}
				}
				for shape in 10 .. 15 {
					record(counts, 0, ordinary, region, i32(shape), 0, flags, i32(form), C.EFAULT, false)
				}
				for shape in [i32(0), 1, 6, 7]! {
					for length in [u64(0), 1, 31, 32, 33, 255, 256, 257]! {
						record(counts, 2, ordinary, region, shape, length, flags, i32(form), 0, false)
					}
					prefix := available(region, shape)
					if shape < 2 {
						for length in [prefix + 1, prefix + 257, u64(3 * region.page), cap, cap + 1,
							u64(0x80000000), u64(0x100000000), u64(0x8000000000000000), u64(-1)]! {
							record(counts, 2, ordinary, region, shape, length, flags, i32(form), 0, true)
						}
					} else {
						gap := region.limit - u64(address(region, shape))
						for length in [prefix + 1, prefix + 257, u64(3 * region.page), gap / 2,
							gap - u64(region.page)]! {
							record(counts, 2, ordinary, region, shape, length, flags, i32(form), 0, true)
						}
					}
				}
				for shape in [i32(2), 3, 4, 5, 8, 9]! {
					record(counts, 3, ordinary, region, shape, 0, flags, i32(form), 0, false)
				}
				for shape in [i32(2), 3, 4, 5, 8, 9, 10, 11, 12, 13, 14]! {
					for length in [u64(1), 255, 257, cap, u64(-1)]! {
						record(counts, 3, ordinary, region, shape, length, flags, i32(form), C.EFAULT, false)
					}
				}
			}
		}
		for flags in [u32(6), 7, 8, 9, 0x80000000, 0xffffffff]! {
			for form in 0 .. 4 {
				for shape in 0 .. 15 {
					for length in [u64(0), 1, 257, cap, u64(-1)]! {
						record(counts, 1, ordinary, region, i32(shape), length, flags, i32(form), C.EINVAL, false)
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
		cap := u64(0x7fffffff) & ~(u64(region.page) - 1)
		for flags in [u32(0), 1, 2, 3, 4, 5]! {
			for form in [i32(0), 3]! {
				for shape in [i32(6), 7, 10, 13]! {
					reset(region)
					result := invoke(region, shape, if shape < 10 { cap } else { u64(0) }, flags, form)
					if result.ret != -1 || result.code != C.EFAULT || !guarded(region, shape, 0) {
						return false
					}
				}
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
			C.printf(c'LINUX RANDOMRANGE SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n', i32(ordinary), before.sizes[index], before.live[index], after.live[index])
		}
		C.printf(c'LINUX RANDOMRANGE STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n', i32(ordinary), before.large, after.large, if good {
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
		base := C.mmap(voidptr(u64(0x100000000)), 5 * page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS | 0x100000, -1, 0)
		if base != voidptr(u64(0x100000000)) { fatal(4) }
		C.memset(base, 0xa5, 5 * page)
		if C.mprotect(base, page, C.PROT_NONE) != 0 || C.mprotect(voidptr(usize(base) + 3 * page), page, C.PROT_READ) != 0 || C.mprotect(voidptr(usize(base) + 4 * page), page, C.PROT_NONE) != 0 {
			fatal(5)
		}
		limit := ceiling(page)
		upper := C.mmap(voidptr(limit - 0x40000000), 5 * page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS | 0x100000, -1, 0)
		if upper != voidptr(limit - 0x40000000) { fatal(15) }
		C.memset(upper, 0xa5, 5 * page)
		if C.mprotect(upper, page, C.PROT_NONE) != 0 || C.mprotect(voidptr(u64(upper) + 3 * u64(page)), page, C.PROT_READ) != 0 || C.mprotect(voidptr(u64(upper) + 4 * u64(page)), page, C.PROT_NONE) != 0 {
			fatal(16)
		}
		mut region := Region{&u8(base), page, &u8(upper), limit}
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
		C.printf(c'LINUX RANDOMRANGE TOPOLOGY: ordinary=%d uid=%u page=%lu readiness=seeded ceiling=%lx cap=%lx\n', i32(ordinary), uid, page, limit, u64(0x7fffffff) & ~(u64(page) - 1))
		matrix(counts, ordinary, &region)
		mut good := counts.failures[0] == 0 && counts.failures[1] == 0 && counts.failures[2] == 0 && counts.failures[3] == 0
		if good && !reference && !storage(&region, ordinary) { good = false }
		if C.munmap(upper, 5 * page) != 0 || C.munmap(base, 5 * page) != 0 { fatal(8) }
		for kind in 0 .. 4 {
			C.printf(c'LINUX RANDOMRANGE CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind])
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
					C.printf(c'LINUX RANDOMRANGE FINAL: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind])
					if counts.failures[kind] != 0 { good = false }
				}
			}
			C.fflush(nil)
		}
		if !good {
			C.puts(c'LINUX RANDOMRANGE FAIL: range errors, bounded transfers or buffer guards')
			C.fflush(nil)
			return 1
		}
		C.puts(if reference {
			c'LINUX RANDOMRANGE REFERENCE: PASS'
		} else {
			c'LINUX RANDOMRANGE: PASS'
		})
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
