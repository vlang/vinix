// SPDX-License-Identifier: GPL-2.0-or-later
module msealfixture

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}

@[typedef]
struct C.pthread_barrier_t {}

fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_barrier_init(&C.pthread_barrier_t, voidptr, u32) i32
fn C.pthread_barrier_wait(&C.pthread_barrier_t) i32
fn C.pthread_barrier_destroy(&C.pthread_barrier_t) i32

fn C.syscall(i64, ...) i64
fn C.__errno_location() &i32
fn C.__builtin_alloca(u64) voidptr
fn C.mmap(voidptr, u64, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, u64) i32
fn C.mprotect(voidptr, u64, i32) i32
fn C.madvise(voidptr, u64, i32) i32
fn C.mlock(voidptr, u64) i32
fn C.munlock(voidptr, u64) i32
fn C.msync(voidptr, u64, i32) i32
fn C.ftruncate(i32, i64) i32
fn C.close(i32) i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, u64) i64
fn C.write(i32, voidptr, u64) i64
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.open(&char, i32, ...) i32
fn C.pread(i32, voidptr, u64, i64) i64
fn C.sscanf(&char, &char, ...) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.setuid(u32) i32
fn C.execl(&char, &char, ...) i32
fn C._exit(i32)
fn C.sysconf(i32) i64
fn C.usleep(u32) i32
fn C.strcmp(&char, &char) i32
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

const mseal_nr = i64(462)
const map_fixed_noreplace = i32(0x100000)
const madv_dontneed_locked = i32(24)

struct Checks {
mut:
	count i32
	failures i32
}

fn (mut checks Checks) expect(label &char, actual i64, expected i64, code i32) {
	checks.count++
	error := if actual == -1 { unsafe { *C.__errno_location() } } else { 0 }
	if actual != expected || error != code {
		checks.failures++
		C.printf(c'LINUX MSEAL FAIL: %s got %ld/%d expected %ld/%d\n', label, actual, error,
			expected, code)
	}
}

fn (mut checks Checks) require(label &char, condition bool) {
	checks.expect(label, if condition { 0 } else { 1 }, 0, 0)
}

fn seal(address voidptr, length u64, flags u64) i64 {
	return C.syscall(mseal_nr, address, length, flags)
}

fn anon(length u64, shared_map bool) voidptr {
	flags := C.MAP_ANONYMOUS | if shared_map { C.MAP_SHARED } else { C.MAP_PRIVATE }
	return unsafe { C.mmap(nil, length, C.PROT_READ | C.PROT_WRITE, flags, -1, 0) }
}

fn at(base voidptr, offset u64) voidptr { return voidptr(u64(base) + offset) }

fn put(address voidptr, value u8) { unsafe { *&u8(address) = value } }

fn get(address voidptr) u8 { return unsafe { *&u8(address) } }

fn fixed(address voidptr, length u64, flag i32) i64 {
	return i64(C.mmap(address, length, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS | flag, -1, 0))
}

fn remap(source voidptr, old_len u64, new_len u64, flags u64, target voidptr) i64 {
	return C.syscall(i64(C.SYS_mremap), source, old_len, new_len, flags, target)
}

fn arguments(mut checks Checks, page u64) {
	unsafe {
		mapping := anon(4 * page, false)
		checks.require(c'map for validation', mapping != voidptr(-1))
		if mapping == voidptr(-1) { return }
		second := at(mapping, page)
		last := at(mapping, 3 * page)
		checks.expect(c'unmap middle two pages', C.munmap(second, 2 * page), 0, 0)
		checks.expect(c'aligned zero length at a hole', seal(second, 0, 0), 0, 0)
		checks.expect(c'address alignment precedes zero length', seal(at(mapping, 1), 0, 0), -1, C.EINVAL)
		checks.expect(c'full-width flags', seal(mapping, 0, u64(1) << 32), -1, C.EINVAL)
		checks.expect(c'length rounding overflow', seal(mapping, ~u64(0), 0), -1, C.EINVAL)
		checks.expect(c'end overflow', seal(mapping, u64(0) - u64(mapping), 0), -1, C.EINVAL)
		checks.expect(c'unmapped start', seal(second, page, 0), -1, C.ENOMEM)
		checks.expect(c'mapped endpoints with a gap', seal(mapping, 4 * page, 0), -1, C.ENOMEM)
		checks.expect(c'unmapped rounded end', seal(mapping, page + 1, 0), -1, C.ENOMEM)
		checks.expect(c'rejected seal leaves prefix mutable', C.mprotect(mapping, page, C.PROT_READ), 0, 0)
		checks.expect(c'rejected seal leaves suffix mutable', C.munmap(last, page), 0, 0)
		checks.expect(c'unmap original prefix', C.munmap(mapping, page), 0, 0)
	}
}

fn read_check(mut checks Checks, inaccessible voidptr, accessible voidptr) {
	unsafe {
		mut fds := [2]i32{}
		status := C.pipe(&fds[0])
		checks.expect(c'pipe for user access', status, 0, 0)
		if status != 0 { return }
		checks.expect(c'prefix protection committed before EPERM', C.write(fds[1], inaccessible, 1), -1, C.EFAULT)
		actual := C.write(fds[1], accessible, 1)
		checks.expect(c'sealed page still readable', actual, 1, 0)
		if actual == 1 {
			mut byte := u8(0)
			checks.expect(c'read sealed byte from pipe', C.read(fds[0], &byte, 1), 1, 0)
			checks.require(c'sealed pipe byte retained', byte == 77)
		}
		C.close(fds[0])
		C.close(fds[1])
	}
}

fn protected_ranges(mut checks Checks, page u64) {
	unsafe {
		base := anon(4 * page, false)
		checks.require(c'map for boundary checks', base != voidptr(-1))
		if base == voidptr(-1) { return }
		first := at(base, page)
		second := at(base, 2 * page)
		suffix := at(base, 3 * page)
		put(base, 29)
		put(first, 77)
		put(second, 89)
		checks.expect(c'make two pages read-only', C.mprotect(first, 2 * page, C.PROT_READ), 0, 0)
		checks.expect(c'round seal length up', seal(first, page + 1, 0), 0, 0)
		checks.expect(c'idempotent seal of subrange', seal(second, 1, 0), 0, 0)
		$if arm64 {
			checks.expect(c'AArch64 address tags are ignored', seal(voidptr(u64(second)
				| (u64(0x5a) << 56)), 1, 0), 0, 0)
		}
		checks.expect(c'same protection still refused', C.mprotect(first, page, C.PROT_READ), -1, C.EPERM)
		checks.expect(c'opposite protection refused on rounded page', C.mprotect(second, page,
			C.PROT_READ | C.PROT_WRITE), -1, C.EPERM)
		checks.expect(c'partial protection refusal', C.mprotect(base, 2 * page, C.PROT_NONE), -1, C.EPERM)
		read_check(mut checks, base, first)
		checks.expect(c'restore unsealed prefix', C.mprotect(base, page, C.PROT_READ | C.PROT_WRITE), 0, 0)
		checks.expect(c'overlapping unmap refused atomically', C.munmap(base, 3 * page), -1, C.EPERM)
		checks.require(c'prefix retained by atomic refusal', get(base) == 29)
		checks.expect(c'fixed replacement refused', fixed(base, 2 * page, C.MAP_FIXED), -1, C.EPERM)
		checks.expect(c'noreplace conflict', fixed(first, page, map_fixed_noreplace), -1, C.EEXIST)
		checks.require(c'prefix retained by fixed mmap refusal', get(base) == 29)
		checks.expect(c'sealed source cannot shrink', remap(first, 2 * page, page, 0, nil), -1, C.EPERM)
		checks.expect(c'sealed source cannot grow', remap(first, page, 2 * page, 1, nil), -1, C.EPERM)
		checks.expect(c'sealed source rejects same length', remap(first, page, page, 0, nil), -1, C.EPERM)
		checks.expect(c'sealed destination rejects move', remap(base, page, page, 3, second), -1, C.EPERM)
		shared_source := anon(page, true)
		checks.require(c'shared anonymous source', shared_source != voidptr(-1))
		if shared_source != voidptr(-1) {
			put(shared_source, 103)
			checks.expect(c'sealed destination rejects shared move', remap(shared_source, page,
				page, 3, second), -1, C.EPERM)
			checks.require(c'shared source retained', get(shared_source) == 103)
			checks.expect(c'unmap shared source', C.munmap(shared_source, page), 0, 0)
		}
		for advice in [C.MADV_DONTNEED, C.MADV_FREE, C.MADV_REMOVE, C.MADV_DONTFORK,
			C.MADV_WIPEONFORK, madv_dontneed_locked]! {
			checks.expect(c'private read-only discard refused', C.madvise(first, page, advice), -1, C.EPERM)
		}
		checks.expect(c'normal advice permitted', C.madvise(first, page, C.MADV_NORMAL), 0, 0)
		checks.expect(c'dofork permitted', C.madvise(first, page, C.MADV_DOFORK), 0, 0)
		checks.expect(c'keeponfork permitted', C.madvise(first, page, C.MADV_KEEPONFORK), 0, 0)
		checks.expect(c'msync permitted', C.msync(first, page, C.MS_SYNC), 0, 0)
		checks.expect(c'lock subrange', C.mlock(second, page), 0, 0)
		checks.expect(c'locked page still sealed', C.madvise(second, page, madv_dontneed_locked), -1, C.EPERM)
		checks.expect(c'unlock subrange', C.munlock(second, page), 0, 0)
		checks.expect(c'unlocked page still sealed', C.munmap(second, page), -1, C.EPERM)
		checks.require(c'protected bytes retained', get(first) == 77 && get(second) == 89)
		checks.expect(c'left neighbor can unmap', C.munmap(base, page), 0, 0)
		checks.expect(c'right neighbor can unmap', C.munmap(suffix, page), 0, 0)
	}
}

fn check_child(mut checks Checks, child i32, label &char) {
	checks.require(c'fork child', child > 0)
	if child > 0 {
		mut status := i32(-1)
		checks.expect(c'reap child', C.waitpid(child, &status, 0), child, 0)
		checks.expect(label, status, 0, 0)
	}
}

fn writable_and_fork(mut checks Checks, page u64) {
	unsafe {
		base := anon(3 * page, false)
		checks.require(c'map one writable VMA', base != voidptr(-1))
		if base == voidptr(-1) { return }
		middle := at(base, page)
		checks.expect(c'seal only the writable middle page', seal(middle, page, 0), 0, 0)
		checks.expect(c'left piece remains mutable', C.mprotect(base, page, C.PROT_READ), 0, 0)
		checks.expect(c'right piece remains mutable', C.munmap(at(base, 2 * page), page), 0, 0)
		put(middle, 43)
		checks.require(c'userspace can write a sealed writable mapping', get(middle) == 43)
		checks.expect(c'writable discard allowed', C.madvise(middle, page, C.MADV_DONTNEED), 0, 0)
		checks.require(c'writable discard cleared bytes', get(middle) == 0)
		put(middle, 61)
		checks.expect(c'lock writable sealed page', C.mlock(middle, page), 0, 0)
		checks.expect(c'discard writable locked page explicitly', C.madvise(middle, page,
			madv_dontneed_locked), 0, 0)
		checks.require(c'locked writable discard cleared bytes', get(middle) == 0)
		checks.expect(c'unlock writable sealed page', C.munlock(middle, page), 0, 0)
		put(middle, 54)
		checks.expect(c'writable wipe on fork allowed', C.madvise(middle, page, C.MADV_WIPEONFORK), 0, 0)
		child := C.fork()
		if child == 0 {
			if get(middle) != 0 { C._exit(1) }
			if C.munmap(middle, page) != -1 || *C.__errno_location() != C.EPERM { C._exit(2) }
			if C.mprotect(middle, page, C.PROT_READ) != -1 || *C.__errno_location() != C.EPERM { C._exit(3) }
			C._exit(0)
		}
		check_child(mut checks, child, c'child keeps seal and receives wiped bytes')
		checks.require(c'parent retains own byte', get(middle) == 54)
		checks.expect(c'parent retains seal', C.munmap(middle, page), -1, C.EPERM)
		checks.expect(c'unmap left surviving piece', C.munmap(base, page), 0, 0)
	}
}

fn file_alias(mut checks Checks, page u64) {
	unsafe {
		fd := i32(C.syscall(i64(C.SYS_memfd_create), c'mseal-alias', u64(0)))
		checks.require(c'create file backing', fd >= 0)
		if fd < 0 { return }
		defer { C.close(fd) }
		checks.expect(c'extend file backing', C.ftruncate(fd, i64(page)), 0, 0)
		writer := C.mmap(nil, page, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, fd, 0)
		reader := C.mmap(nil, page, C.PROT_READ, C.MAP_SHARED, fd, 0)
		checks.require(c'file aliases mapped', writer != voidptr(-1) && reader != voidptr(-1))
		if writer == voidptr(-1) || reader == voidptr(-1) { return }
		checks.expect(c'seal read-only shared file', seal(reader, page, 0), 0, 0)
		checks.expect(c'file-backed advice allowed', C.madvise(reader, page, C.MADV_DONTNEED), 0, 0)
		put(writer, 88)
		checks.expect(c'sync sealed shared file mapping', C.msync(reader, page, C.MS_SYNC), 0, 0)
		checks.require(c'alias still updates backing file', get(reader) == 88)
		checks.expect(c'sealed file unmap blocked', C.munmap(reader, page), -1, C.EPERM)
		checks.expect(c'other alias can unmap', C.munmap(writer, page), 0, 0)
	}
}

fn brk_check(mut checks Checks, page u64) {
	unsafe {
		child := C.fork()
		if child == 0 {
			initial := u64(C.syscall(i64(C.SYS_brk), u64(0)))
			heap := (initial + page - 1) & ~(page - 1)
			end := heap + 2 * page
			if u64(C.syscall(i64(C.SYS_brk), end)) != end { C._exit(1) }
			if seal(voidptr(end), page, 0) != -1 || *C.__errno_location() != C.ENOMEM { C._exit(2) }
			put(voidptr(heap), 71)
			if seal(voidptr(heap + page), page, 0) != 0 { C._exit(3) }
			if u64(C.syscall(i64(C.SYS_brk), initial)) != end { C._exit(4) }
			if get(voidptr(heap)) != 71 { C._exit(5) }
			if u64(C.syscall(i64(C.SYS_brk), end + page)) != end + page { C._exit(6) }
			C._exit(0)
		}
		check_child(mut checks, child, c'brk protects seal and leaves its reserve unsealed')
	}
}

fn credentials_and_exec(mut checks Checks, page u64, program &char) {
	unsafe {
		child := C.fork()
		if child == 0 {
			if C.setuid(1000) != 0 { C._exit(1) }
			base := anon(3 * page, false)
			if base == voidptr(-1) || seal(at(base, page), page, 0) != 0 { C._exit(2) }
			C.execl(program, program, c'--exec-child', voidptr(nil))
			C._exit(3)
		}
		check_child(mut checks, child, c'unprivileged seal and exec teardown')
	}
}

fn openbsd_policy(mut checks Checks, page u64) {
	unsafe {
		base := anon(3 * page, false)
		checks.require(c'map OpenBSD policy control', base != voidptr(-1))
		if base == voidptr(-1) { return }
		mimmutable := $if arm64 { i64(247) } $else { i64(500) }
		second := at(base, page)
		checks.expect(c'create hole for mimmutable', C.munmap(second, page), 0, 0)
		checks.expect(c'mimmutable accepts gaps', C.syscall(mimmutable, base, 3 * page), 0, 0)
		checks.expect(c'mimmutable blocks writable discard', C.madvise(base, page, C.MADV_DONTNEED), -1, C.EPERM)
		checks.expect(c'mimmutable blocks protection across a hole', C.mprotect(base, 3 * page,
			C.PROT_READ), -1, C.EPERM)
		checks.expect(c'mimmutable did not reserve the hole', fixed(second, page, map_fixed_noreplace), i64(second), 0)
		checks.expect(c'unmap ordinary mapping in hole', C.munmap(second, page), 0, 0)
	}
}

struct Move {
	src voidptr
	dst voidptr
	length u64
mut:
	start C.pthread_barrier_t
	result i64
	code i32
}

fn move_thread(argument voidptr) voidptr {
	unsafe {
		mut work := &Move(argument)
		C.pthread_barrier_wait(&work.start)
		work.result = remap(work.src, work.length, work.length, 3, work.dst)
		if work.result == -1 { work.code = *C.__errno_location() }
		return nil
	}
}

fn move_races(mut checks Checks, page u64) {
	unsafe {
		length := 128 * page
		for _ in 0 .. 8 {
			src := anon(length, false)
			dst := anon(length, false)
			checks.require(c'race spans mapped', src != voidptr(-1) && dst != voidptr(-1))
			if src == voidptr(-1) || dst == voidptr(-1) { return }
			put(src, 21)
			put(at(src, length - 1), 22)
			put(dst, 31)
			put(at(dst, length - 1), 32)
			mut work := Move{src: src, dst: dst, length: length}
			barrier := C.pthread_barrier_init(&work.start, nil, 2)
			checks.expect(c'create move barrier', barrier, 0, 0)
			if barrier != 0 { return }
			mut worker_id := C.pthread_t{}
			created := C.pthread_create(&worker_id, nil, move_thread, &work)
			checks.expect(c'create move worker', created, 0, 0)
			if created != 0 { return }
			C.pthread_barrier_wait(&work.start)
			checks.expect(c'concurrent seal succeeds', seal(dst, length, 0), 0, 0)
			checks.expect(c'join move worker', C.pthread_join(worker_id, nil), 0, 0)
			checks.expect(c'destroy move barrier', C.pthread_barrier_destroy(&work.start), 0, 0)
			if work.result == i64(dst) {
				checks.require(c'seal sees a complete moved mapping', get(dst) == 21 && get(at(dst, length - 1)) == 22)
				// Keep the number of checks independent of the race outcome.
				checks.expect(c'destination remains sealed', C.munmap(dst, length), -1, C.EPERM)
			} else {
				checks.require(c'seal precedes move and keeps prior bytes', work.result == -1
					&& work.code == C.EPERM && get(dst) == 31 && get(at(dst, length - 1)) == 32
					&& get(src) == 21 && get(at(src, length - 1)) == 22)
				checks.expect(c'remove unmoved source', C.munmap(src, length), 0, 0)
			}
		}
	}
}

struct SlabCounts {
mut:
	rows int
	live [32]u64
	large u64
}

fn snapshot(fd i32, mut counts SlabCounts) bool {
	unsafe {
		mut data := [4096]char{}
		length := C.pread(fd, &data[0], sizeof(data) - 1, 0)
		if length <= 0 { return false }
		mut large_found := false
		mut index := 0
		for index < length {
			mut size := u64(0)
			mut same := u64(0)
			mut live := u64(0)
			if C.sscanf(&data[index], c'size-%lu %lu %lu', &size, &same, &live) == 3 {
				if counts.rows >= counts.live.len || size != same { return false }
				counts.live[counts.rows] = live
				counts.rows++
			} else if C.sscanf(&data[index], c'large - - %lu', &counts.large) == 1 {
				large_found = true
			}
			for index < length && data[index] != char(10) { index++ }
			index++
		}
		return counts.rows > 0 && large_found
	}
}

fn seal_and_exit(page u64) bool {
	unsafe {
		child := C.fork()
		if child == 0 {
			base := anon(3 * page, false)
			if base == voidptr(-1) { C._exit(1) }
			middle := at(base, page)
			put(middle, 49)
			if seal(middle, page, 0) != 0 || seal(middle, 1, 0) != 0 { C._exit(2) }
			if C.munmap(base, page) != 0 || C.munmap(at(base, 2 * page), page) != 0 { C._exit(3) }
			if C.munmap(middle, page) != -1 || *C.__errno_location() != C.EPERM { C._exit(4) }
			C._exit(0)
		}
		mut status := i32(-1)
		return child > 0 && C.waitpid(child, &status, 0) == child && status == 0
	}
}

fn retention(mut checks Checks, page u64) {
	unsafe {
		C.mount(c'proc', c'/proc', c'proc', 0, nil)
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		checks.require(c'open slab accounting', fd >= 0)
		if fd < 0 { return }
		defer { C.close(fd) }
		samples := &SlabCounts(C.__builtin_alloca(2 * sizeof(SlabCounts)))
		mut failed := 0
		for cohort in 0 .. 2 {
			for _ in 0 .. if cohort == 0 { 32 } else { 200 } {
				if !seal_and_exit(page) { failed++ }
			}
			C.usleep(4000000)
			mut sample := &samples[cohort]
			*sample = SlabCounts{}
			checks.require(c'read slab accounting', snapshot(fd, mut sample))
		}
		checks.expect(c'all seal and exit cohorts completed', failed, 0, 0)
		mut growing := 0
		for i in 0 .. samples[0].rows {
			if samples[1].live[i] > samples[0].live[i] { growing++ }
		}
		C.printf(c'LINUX MSEAL RETENTION: cycles=200 classes=%d growing=%d large_pages=%lu/%lu\n',
			i32(samples[0].rows), i32(growing), samples[0].large, samples[1].large)
		checks.require(c'slab rows unchanged', samples[0].rows == samples[1].rows)
		checks.require(c'no live slab class grew', growing == 0)
		checks.require(c'no large-page growth', samples[1].large <= samples[0].large)
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc > 1 && C.strcmp(argv[1], c'--exec-child') == 0 { return 0 }
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		page := u64(C.sysconf(C._SC_PAGESIZE))
		mut checks := Checks{}
		arguments(mut checks, page)
		protected_ranges(mut checks, page)
		writable_and_fork(mut checks, page)
		file_alias(mut checks, page)
		brk_check(mut checks, page)
		credentials_and_exec(mut checks, page, argv[0])
		move_races(mut checks, page)
		if !reference {
			openbsd_policy(mut checks, page)
			retention(mut checks, page)
		}
		C.printf(c'LINUX MSEAL SUMMARY: checks=%d failures=%d\n', checks.count, checks.failures)
		if checks.failures == 0 {
			C.puts(if reference { c'LINUX MSEAL REFERENCE: PASS' } else { c'LINUX MSEAL: PASS' })
		}
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
