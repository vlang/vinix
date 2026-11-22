// SPDX-License-Identifier: GPL-2.0-or-later
module futex2fixture

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}

struct C.sigaction {
mut:
	sa_handler voidptr
	sa_flags i32
}

struct C.timespec {
mut:
	tv_sec i64
	tv_nsec i64
}

fn C.syscall(i64, ...) i64
fn C.__errno_location() &i32
fn C.__builtin_alloca(u64) voidptr
fn C.clock_gettime(i32, &C.timespec) i32
fn C.mmap(voidptr, u64, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, u64) i32
fn C.mprotect(voidptr, u64, i32) i32
fn C.sysconf(i32) i64
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.pread(i32, voidptr, u64, i64) i64
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_self() C.pthread_t
fn C.pthread_kill(C.pthread_t, i32) i32
fn C.sigaction(i32, &C.sigaction, voidptr) i32
fn C.usleep(u32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.strcmp(&char, &char) i32
fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

const waitv_nr = i64(449)
const wake_nr = i64(454)
const wait_nr = i64(455)
const requeue_nr = i64(456)
const private = u64(130)
const shared_word_flags = u64(2)
const all_bits = u64(0xffffffff)
const monotonic = i32(1)
const realtime = i32(0)
const wide = u64(1) << 32

struct Request {
mut:
	value u64
	address u64
	flags u32
	reserved u32
}

struct Checks {
mut:
	count int
	failures int
}

fn (mut checks Checks) expect(label &char, actual i64, expected i64, error i32) {
	checks.count++
	actual_error := if actual == -1 { unsafe { *C.__errno_location() } } else { 0 }
	if actual != expected || actual_error != error {
		checks.failures++
		C.printf(c'LINUX FUTEX2 FAIL: %s got %ld/%d expected %ld/%d\n', label, actual,
			actual_error, expected, error)
	}
}

fn request(address u64, flags u64) Request {
	return Request{address: address, flags: u32(flags)}
}

fn waitv(entries &Request, count u64, flags u64, deadline voidptr, clock_id i32) i64 {
	return C.syscall(waitv_nr, entries, count, flags, deadline, i64(clock_id))
}

fn wait(address u64, value u64, mask u64, flags u64, deadline voidptr, clock_id i32) i64 {
	return C.syscall(wait_nr, address, value, mask, flags, deadline, i64(clock_id))
}

fn wake(address u64, mask u64, count i64, flags u64) i64 {
	return C.syscall(wake_nr, address, mask, count, flags)
}

fn legacy_wake(address u64, count i64, flags u64) i64 {
	op := if flags == private { i64(129) } else { i64(1) }
	return C.syscall(i64(C.SYS_futex), address, op, count, i64(0), i64(0), i64(0))
}

fn deadline(clock_id i32, delay_nsec i64) C.timespec {
	mut result := C.timespec{}
	C.clock_gettime(clock_id, &result)
	result.tv_nsec += delay_nsec
	result.tv_sec += result.tv_nsec / 1000000000
	result.tv_nsec %= 1000000000
	return result
}

fn arguments(mut checks Checks, guard u64) {
	unsafe {
		mut words := [2]u32{}
		first := u64(&words[0])
		second := u64(&words[1])
		mut entries := [request(first, private), request(second, private)]!
		expired := C.timespec{}
		invalid := C.timespec{tv_nsec: 1000000000}
		checks.expect(c'zero count', waitv(&entries[0], 0, 0, nil, monotonic), -1, C.EINVAL)
		checks.expect(c'over maximum', waitv(&entries[0], 129, 0, nil, monotonic), -1, C.EINVAL)
		checks.expect(c'null vector', waitv(nil, 1, 0, nil, monotonic), -1, C.EINVAL)
		checks.expect(c'vector flags first', waitv(&Request(guard), 1, 1, voidptr(guard), 8), -1, C.EINVAL)
		checks.expect(c'bad clock before deadline copy', waitv(&entries[0], 1, 0, voidptr(guard), 8), -1, C.EINVAL)
		checks.expect(c'bad deadline before vector copy', waitv(&Request(guard), 1, 0, &invalid, monotonic), -1, C.EINVAL)
		checks.expect(c'unreadable deadline', waitv(&entries[0], 1, 0, voidptr(guard), monotonic), -1, C.EFAULT)
		checks.expect(c'unreadable vector', waitv(&Request(guard), 1, 0, nil, monotonic), -1, C.EFAULT)
		last := &Request(guard - sizeof(Request))
		*last = entries[0]
		checks.expect(c'guarded vector tail', waitv(last, 2, 0, nil, monotonic), -1, C.EFAULT)

		entries[0].value = 1
		entries[1].flags = 3
		checks.expect(c'import before word comparison', waitv(&entries[0], 2, 0, nil, monotonic), -1, C.EINVAL)
		entries[1].flags = u32(private)
		entries[1].reserved = 1
		checks.expect(c'reserved word', waitv(&entries[0], 2, 0, nil, monotonic), -1, C.EINVAL)
		entries[1].reserved = 0
		entries[1].value = wide
		checks.expect(c'vector value width', waitv(&entries[0], 2, 0, nil, monotonic), -1, C.EINVAL)
		entries[1].value = 0
		entries[1].address = guard + 1
		checks.expect(c'key validation before comparison', waitv(&entries[0], 2, 0, nil, monotonic), -1, C.EINVAL)
		entries[1].address = guard
		checks.expect(c'low count and flags, ignored clock', waitv(&entries[0], wide + 2, wide, nil, 8), -1, C.EAGAIN)
		entries[1].flags = u32(shared_word_flags)
		checks.expect(c'shared key fault before comparison', waitv(&entries[0], 2, 0, nil, monotonic), -1, C.EFAULT)
		entries[0].value = 0
		entries[1].flags = u32(private)
		checks.expect(c'private comparison fault', waitv(&entries[0], 2, 0, nil, monotonic), -1, C.EFAULT)
		checks.expect(c'fault removes earlier waiter', legacy_wake(first, 1, private), 0, 0)
		entries[1].address = second
		entries[1].value = 1
		checks.expect(c'mismatch before expiry', waitv(&entries[0], 2, 0, &expired, monotonic), -1, C.EAGAIN)
		checks.expect(c'mismatch removes earlier waiter', legacy_wake(first, 1, private), 0, 0)
		entries[1].value = 0
		checks.expect(c'past monotonic deadline', waitv(&entries[0], 2, 0, &expired, monotonic), -1, C.ETIMEDOUT)
		checks.expect(c'past realtime deadline', waitv(&entries[0], 2, 0, &expired, realtime), -1, C.ETIMEDOUT)
		checks.expect(c'zero wake mask', wake(first, 0, 1, private), -1, C.EINVAL)
		checks.expect(c'wide wake mask', wake(first, wide | 1, 1, private), -1, C.EINVAL)
		checks.expect(c'zero wake still checks address', wake(guard + 1, 1, 0, private), -1, C.EINVAL)
		checks.expect(c'private wake needs no mapped word', wake(guard, 1, 1, private), 0, 0)
		checks.expect(c'shared wake needs readable word', wake(guard, 1, 1, shared_word_flags), -1, C.EFAULT)
		checks.expect(c'wide single value', wait(first, wide, 1, private, nil, monotonic), -1, C.EINVAL)
		checks.expect(c'wide single mask', wait(first, 0, wide, private, nil, monotonic), -1, C.EINVAL)
		checks.expect(c'single invalid flags before timeout', wait(first, 0, 1, 6, voidptr(guard), monotonic), -1, C.EINVAL)
		checks.expect(c'single timeout before zero mask', wait(first, 0, 0, private, voidptr(guard), monotonic), -1, C.EFAULT)
		checks.expect(c'zero single mask', wait(first, 0, 0, private, nil, monotonic), -1, C.EINVAL)
		checks.expect(c'low single flags', wait(first, 1, 1, private | wide, nil, 8), -1, C.EAGAIN)
		checks.expect(c'single realtime timeout', wait(first, 0, 1, private, &expired, realtime), -1, C.ETIMEDOUT)
		checks.expect(c'requeue outer flags', C.syscall(requeue_nr, &entries[0], u64(1), i64(0), i64(1)), -1, C.EINVAL)
		checks.expect(c'requeue guarded tail', C.syscall(requeue_nr, last, u64(0), i64(-1), i64(1)), -1, C.EFAULT)
		checks.expect(c'requeue negative count', C.syscall(requeue_nr, &entries[0], u64(0), i64(-1), i64(1)), -1, C.EINVAL)
		entries[0].value = 1
		checks.expect(c'requeue requires comparison', C.syscall(requeue_nr, &entries[0], wide, i64(0), i64(1)), -1, C.EAGAIN)
	}
}

enum Mode {
	legacy
	masked
	requeue
	interrupt
	restart
}

struct Waker {
	address u64
	target u64
	thread C.pthread_t
	mode Mode
mut:
	status int
}

fn signal_handler(_ i32) {}

fn drive_wait(argument voidptr) voidptr {
	unsafe {
		mut waker := &Waker(argument)
		if waker.mode in [.interrupt, .restart] {
			C.usleep(100000)
			waker.status = C.pthread_kill(waker.thread, C.SIGUSR1)
			if waker.mode == .interrupt || waker.status != 0 { return nil }
			C.usleep(100000)
		}
		if waker.mode == .masked {
			C.usleep(100000)
			if wake(waker.address, 4, 1, private) != 0 || wake(waker.address, 2, 0, private) != 0 {
				waker.status = 1
				return nil
			}
		}
		for _ in 0 .. 2000 {
			result := match waker.mode {
				.legacy, .restart { legacy_wake(waker.address, 1, private) }
				.masked { wake(waker.address, 2, -1, private) }
				.requeue {
					mut pair := [request(waker.address, private), request(waker.target, shared_word_flags)]!
					pair[1].value = 123 // Only the source value is compared.
					C.syscall(requeue_nr, &pair[0], u64(0), i64(0), i64(1))
				}
				.interrupt { i64(0) }
			}
			if result == 1 {
				if waker.mode == .requeue && (legacy_wake(waker.address, 1, private) != 0
					|| wake(waker.target, all_bits, 1, private) != 0
				|| wake(waker.target, all_bits, 1, shared_word_flags) != 1) {
					waker.status = 2
				}
				return nil
			}
			if result != 0 { break }
			C.usleep(1000)
		}
		waker.status = 3
		return nil
	}
}

fn threaded(mut checks Checks, shared_word u64) {
	unsafe {
		mut words := [128]u32{}
		mut entries := [128]Request{}
		for i in 0 .. entries.len { entries[i] = request(u64(&words[i]), private) }
		for mode in [Mode.legacy, .masked, .requeue, .interrupt, .restart]! {
			if mode in [.interrupt, .restart] {
				mut action := C.sigaction{}
				action.sa_handler = voidptr(signal_handler)
				action.sa_flags = if mode == .restart { 0x10000000 } else { 0 }
				checks.expect(c'install signal handler', C.sigaction(C.SIGUSR1, &action, nil), 0, 0)
			}
			last := if mode == .legacy { 127 } else { 2 }
			address := entries[last].address
			mut worker := Waker{address: address, target: shared_word, mode: mode, thread: C.pthread_self()}
			mut worker_id := C.pthread_t{}
			status := C.pthread_create(&worker_id, nil, drive_wait, &worker)
			checks.expect(c'create waker', status, 0, 0)
			if status != 0 { return }
			clock_id := if mode == .masked { realtime } else { monotonic }
			limit := deadline(clock_id, 4000000000)
			match mode {
				.legacy { checks.expect(c'untimed legacy wake at last index', waitv(&entries[0], 128, 0, nil, 8), last, 0) }
				.masked { checks.expect(c'wait and masked wake', wait(address, 0, 2, private, &limit, clock_id), 0, 0) }
				.interrupt { checks.expect(c'interrupted waitv', waitv(&entries[0], 3, 0, &limit, clock_id), -1, C.EINTR) }
				else { checks.expect(c'woken index', waitv(&entries[0], u64(last + 1), 0, &limit, clock_id), last, 0) }
			}
			checks.expect(c'join waker', C.pthread_join(worker_id, nil), 0, 0)
			checks.expect(c'waker status', worker.status, 0, 0)
			checks.expect(c'first waiter removed', legacy_wake(entries[0].address, 1, private), 0, 0)
			checks.expect(c'last waiter removed', legacy_wake(address, 1, private), 0, 0)
			checks.expect(c'target waiter removed', wake(shared_word, all_bits, 1, shared_word_flags), 0, 0)
		}
	}
}

fn cross_process(mut checks Checks, shared_word u64) {
	unsafe {
		local := u32(0)
		entries := [request(u64(&local), private), request(shared_word, shared_word_flags)]!
		child := C.fork()
		if child == 0 {
			for _ in 0 .. 2000 {
				result := wake(shared_word, all_bits, 1, shared_word_flags)
				if result == 1 { C._exit(0) }
				if result != 0 { C._exit(2) }
				C.usleep(1000)
			}
			C._exit(1)
		}
		checks.expect(c'fork shared waker', if child > 0 { 0 } else { -1 }, 0, 0)
		if child < 0 { return }
		limit := deadline(monotonic, 4000000000)
		checks.expect(c'shared wake from another process', waitv(&entries[0], 2, 0, &limit, monotonic), 1, 0)
		mut status := i32(-1)
		checks.expect(c'reap shared waker', C.waitpid(child, &status, 0), child, 0)
		checks.expect(c'shared waker status', status, 0, 0)
	}
}

struct SlabCounts {
mut:
	objects [32]u64
	rows int
	large_pages u64
}

fn snapshot(fd i32, mut counts SlabCounts) bool {
	unsafe {
		mut buffer := [4096]char{}
		length := C.pread(fd, &buffer[0], sizeof(buffer) - 1, 0)
		if length <= 0 { return false }
		mut large_found := false
		mut offset := 0
		for offset < length {
			mut size := u64(0)
			mut duplicate := u64(0)
			mut live := u64(0)
			if C.sscanf(&buffer[offset], c'size-%lu %lu %lu', &size, &duplicate, &live) == 3 {
				if counts.rows >= counts.objects.len || size != duplicate { return false }
				counts.objects[counts.rows] = live
				counts.rows++
			} else if C.sscanf(&buffer[offset], c'large - - %lu', &counts.large_pages) == 1 {
				large_found = true
			}
			for offset < length && buffer[offset] != char(10) { offset++ }
			offset++
		}
		return counts.rows > 0 && large_found
	}
}

fn retention(mut checks Checks, guard u64) {
	unsafe {
		C.mount(c'proc', c'/proc', c'proc', 0, nil)
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		checks.expect(c'open slab accounting', if fd < 0 { -1 } else { 0 }, 0, 0)
		if fd < 0 { return }
		defer { C.close(fd) }
		mut words := [128]u32{}
		mut entries := [128]Request{}
		for i in 0 .. entries.len { entries[i] = request(u64(&words[i]), private) }
		mut samples := &SlabCounts(C.__builtin_alloca(2 * sizeof(SlabCounts)))
		mut wrong := 0
		expired := C.timespec{}
		for cohort in 0 .. 2 {
			for _ in 0 .. if cohort == 0 { 32 } else { 512 } {
				entries[127].address = u64(&words[127])
				entries[127].value = 1
				if waitv(&entries[0], 128, 0, &expired, monotonic) != -1 || *C.__errno_location() != C.EAGAIN { wrong++ }
				entries[127].address = guard
				entries[127].value = 0
				if waitv(&entries[0], 128, 0, nil, monotonic) != -1 || *C.__errno_location() != C.EFAULT { wrong++ }
			}
			mut sample := &samples[cohort]
			*sample = SlabCounts{}
			checks.expect(c'read warmed slab accounting', if snapshot(fd, mut sample) { 0 } else { 1 }, 0, 0)
		}
		mut growth := 0
		for i in 0 .. samples[0].rows {
			if samples[1].objects[i] > samples[0].objects[i] { growth++ }
		}
		C.printf(c'LINUX FUTEX2 RETENTION: cycles=512 classes=%d growing=%d large_pages=%lu/%lu\n',
			samples[0].rows, growth, samples[0].large_pages, samples[1].large_pages)
		checks.expect(c'unchanged results during storage cohorts', wrong, 0, 0)
		checks.expect(c'stable live slab classes', growth, 0, 0)
		checks.expect(c'stable large pages', if samples[1].large_pages <= samples[0].large_pages { 0 } else { 1 }, 0, 0)
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		page := u64(C.sysconf(C._SC_PAGESIZE))
		shared_word := C.mmap(nil, page, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED | C.MAP_ANONYMOUS, -1, 0)
		arena := C.mmap(nil, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if shared_word == voidptr(-1) || arena == voidptr(-1) { return 2 }
		*&u32(shared_word) = 0
		guard := u64(arena) + page
		if C.mprotect(voidptr(guard), page, C.PROT_NONE) != 0 { return 2 }
		mut checks := Checks{}
		arguments(mut checks, guard)
		threaded(mut checks, u64(shared_word))
		cross_process(mut checks, u64(shared_word))
		if !reference { retention(mut checks, guard) }
		checks.expect(c'unmap guard', C.munmap(arena, page * 2), 0, 0)
		checks.expect(c'unmap shared word', C.munmap(shared_word, page), 0, 0)
		C.printf(c'LINUX FUTEX2 SUMMARY: checks=%d failures=%d\n', checks.count, checks.failures)
		if checks.failures == 0 {
			C.puts(if reference { c'LINUX FUTEX2 REFERENCE: PASS' } else { c'LINUX FUTEX2: PASS' })
		}
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
