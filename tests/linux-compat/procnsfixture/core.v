// SPDX-License-Identifier: GPL-2.0-or-later
module procnsfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct Slabs {
mut:
	sizes   [32]u64
	live    [32]u64
	rows    i32
	large   u64
	tainted u64
}

struct Shared {
mut:
	target   i32
	stop     i32
	failures i32
	epoch    i32
	ack      [4]i32
	calls    [4]i32
}

struct Worker {
	shared &Shared
	index  i32
}

struct C.stat {
	st_mode u32
	st_ino  u64
}

@[typedef]
struct C.pthread_t {}

fn C.alloca(usize) voidptr
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.readlink(&char, &char, usize) isize
fn C.fchdir(i32) i32
fn C.fstat(i32, &C.stat) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.pipe2(&i32, i32) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__errno_location() &i32
fn C._exit(i32)
fn C.printf(&char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.usleep(u32) i32
fn C.pause() i32
fn C.sscanf(&char, &char, ...) i32
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.strcmp(&char, &char) i32
fn C.syscall(isize, ...) isize

@[c:'__atomic_load_n']
fn C.load(&i32, i32) i32

@[c:'__atomic_store_n']
fn C.store(&i32, i32, i32)

@[c:'__atomic_fetch_add']
fn C.increment(&i32, i32, i32) i32

fn fatal(stage i32) {
	C.printf(c'LINUX PROCNS FAIL: stage=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}

fn identity() {
	unsafe {
		mut buffer := [64]char{}
		n := C.readlink(c'/proc/self/ns/ipc', &buffer[0], 63)
		if n <= 0 || n >= 63 { fatal(1) }
	}
}

fn reap(child i32) {
	mut status := i32(-1)
	if child < 0 || C.waitpid(child, &status, 0) != child || status != 0 { fatal(2) }
}

fn operation(kind i32, shared &Shared) {
	if kind == 0 {
		identity()
		return
	}
	child := C.fork()
	if child < 0 { fatal(3) }
	if child == 0 {
		if kind >= 2 { identity() }
		C._exit(0)
	}
	if shared != unsafe { nil } {
		C.store(unsafe { &shared.target }, child, 3)
		wake(shared)
	}
	reap(child)
}

fn walker(pointer voidptr) voidptr {
	unsafe {
		worker := &Worker(pointer)
		shared := worker.shared
		mut path := [80]char{}
		mut data := [64]char{}
		for C.load(&shared.stop, 2) == 0 {
			epoch := C.load(&shared.epoch, 2)
			target := C.load(&shared.target, 2)
			if target > 0 {
				C.snprintf(&path[0], 80, c'/proc/%d/ns/ipc', target)
				n := C.readlink(&path[0], &data[0], 63)
				code := *C.__errno_location()
				C.increment(&shared.calls[worker.index], 1, 0)
				// Linux can lose the task after lookup but before its access check.
				if !(n > 0 && n < 63) && !(n == -1 && (code == C.ENOENT || code == C.ESRCH
					|| code == C.EACCES)) {
					C.increment(&shared.failures, 1, 0)
				}
			}
			C.store(&shared.ack[worker.index], epoch, 3)
			if target == 0 {
				result := C.syscall(C.SYS_futex, &shared.target, i32(128), i32(0), nil, nil, i32(0))
				code := *C.__errno_location()
				if result != 0 && !(result == -1 && (code == C.EAGAIN || code == C.EINTR)) {
					fatal(24)
				}
			} else {
				C.usleep(1000)
			}
		}
		return nil
	}
}

fn wake(shared &Shared) {
	if C.syscall(C.SYS_futex, unsafe { &shared.target }, i32(129), i32(4), unsafe { nil }, unsafe { nil }, i32(0)) < 0 {
		fatal(25)
	}
}

fn quiesce(shared &Shared) {
	unsafe {
		C.store(&shared.target, -1, 3)
		epoch := C.load(&shared.epoch, 2) + 1
		C.store(&shared.epoch, epoch, 3)
		wake(shared)
		for _ in 0 .. 20000 {
			mut ready := true
			for i in 0 .. 4 { if C.load(&shared.ack[i], 2) != epoch { ready = false } }
			if ready {
				C.store(&shared.target, 0, 3)
				return
			}
			C.usleep(1000)
		}
		fatal(26)
	}
}

fn prune() {
	if C.open(c'/proc/2147483647/ns/ipc', C.O_RDONLY) != -1 || unsafe { *C.__errno_location() } != C.ENOENT {
		fatal(27)
	}
}

fn held() {
	unsafe {
		mut pipe := [i32(-1), i32(-1)]!
		if C.pipe2(&pipe[0], 0) != 0 { fatal(4) }
		child := C.fork()
		if child < 0 { fatal(5) }
		if child == 0 {
			C.close(pipe[1])
			identity()
			mut byte := u8(0)
			if C.read(pipe[0], &byte, 1) != 1 { C._exit(1) }
			C._exit(0)
		}
		C.close(pipe[0])
		mut path := [80]char{}
		C.snprintf(&path[0], 80, c'/proc/%d/ns', child)
		directory := C.open(&path[0], C.O_RDONLY | C.O_DIRECTORY)
		root := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY)
		if directory < 0 || root < 0 { fatal(6) }
		mut linkpath := [96]char{}
		C.snprintf(&linkpath[0], 96, c'%s/ipc', &path[0])
		link := C.open(&linkpath[0], C.O_PATH | C.O_NOFOLLOW)
		if link < 0 { fatal(7) }
		original := &C.stat(C.alloca(512))
		current := &C.stat(C.alloca(512))
		if C.fstat(link, original) != 0 || C.fchdir(directory) != 0 || C.close(directory) != 0 {
			fatal(8)
		}
		mut byte := u8(1)
		if C.write(pipe[1], &byte, 1) != 1 || C.close(pipe[1]) != 0 { fatal(9) }
		reap(child)
		// Force registration validation and pruning of this cached process root.
		if C.open(&path[0], C.O_RDONLY | C.O_DIRECTORY) != -1 || *C.__errno_location() != C.ENOENT {
			fatal(10)
		}
		C.usleep(13000000)
		if C.fstat(link, current) != 0 || current.st_ino != original.st_ino || current.st_mode != original.st_mode {
			fatal(11)
		}
		if C.close(link) != 0 { fatal(12) }
		// Only cwd now retains ns; its parent pins must retain the process root.
		C.usleep(13000000)
		mut cwd := [256]char{}
		length := C.readlink(c'/proc/self/cwd', &cwd[0], 255)
		if length < isize(C.strlen(&path[0])) || C.memcmp(&cwd[0], &path[0], C.strlen(&path[0])) != 0 {
			fatal(13)
		}
		inherited := C.fork()
		if inherited < 0 { fatal(14) }
		if inherited == 0 {
			C.usleep(13000000)
			mut copy := [256]char{}
			n := C.readlink(c'/proc/self/cwd', &copy[0], 255)
			C._exit(if n == length && C.memcmp(&copy[0], &cwd[0], usize(n)) == 0 && C.fchdir(root) == 0 {
				0
			} else {
				1
			})
		}
		if C.fchdir(root) != 0 || C.close(root) != 0 { fatal(15) }
		reap(inherited)
		C.puts(c'LINUX PROCNS HELD: O_PATH symlink=1 cwd=1 parent=1 inherited=1 grace_seconds=13')
		C.fflush(nil)
	}
}

fn C.strlen(&char) usize

fn storage(kind i32, observer i32, tracked bool) bool {
	unsafe {
		shared := &Shared(C.alloca(sizeof(Shared)))
		*shared = Shared{}
		mut threads := [4]C.pthread_t{}
		workers := &Worker(C.alloca(4 * sizeof(Worker)))
		if kind == 3 {
			for i in 0 .. 4 {
				workers[i] = Worker{ shared: shared, index: i32(i) }
				if C.pthread_create(&threads[i], nil, walker, &workers[i]) != 0 { fatal(16) }
			}
		}
		for _ in 0 .. 200 { operation(kind, if kind == 3 { shared } else { nil }) }
		if kind == 3 {
			quiesce(shared)
			for i in 0 .. 4 {
				if C.load(&shared.calls[i], 2) == 0 { fatal(28) }
				C.store(&shared.calls[i], 0, 3)
			}
		}
		// Remove the last cached dead child in both cohorts. Park the readers
		// before this refresh so they cannot change the snapshot's cache state.
		prune()
		C.usleep(26000000)
		before := &Slabs(C.alloca(sizeof(Slabs)))
		after := &Slabs(C.alloca(sizeof(Slabs)))
		if !snapshot(observer, before) { fatal(17) }
		if tracked {
			reset := C.open(c'/proc/allocstart', 0)
			mut data := [8]char{}
			if reset < 0 || C.pread(reset, &data[0], 7, 0) <= 0 || C.close(reset) != 0 { fatal(18) }
		}
		for _ in 0 .. 200 { operation(kind, if kind == 3 { shared } else { nil }) }
		if kind == 3 { quiesce(shared) }
		prune()
		C.usleep(26000000)
		if !snapshot(observer, after) { fatal(19) }
		mut good := before.rows == after.rows && before.large == after.large && C.load(&shared.failures, 2) == 0
		good = good && before.tainted == 0 && after.tainted == 0
		if kind == 3 {
			for i in 0 .. 4 { if C.load(&shared.calls[i], 2) == 0 { good = false } }
		}
		for i in 0 .. int(before.rows) {
			if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }
			C.printf(c'LINUX PROCNS SLAB: kind=%d size=%lu live=%lu/%lu cycles=200\n', kind, before.sizes[i], before.live[i], after.live[i])
		}
		C.printf(c'LINUX PROCNS STORAGE: kind=%d cycles=200 big_pages=%lu/%lu written_after_free=%lu/%lu errors=%d %s\n', kind, before.large, after.large, before.tainted, after.tainted, C.load(&shared.failures, 2), if good {
			&char(c'PASS')
		} else {
			&char(c'FAIL')
		})
		C.fflush(nil)
		if kind == 3 {
			for i in 0 .. 4 {
				calls := C.load(&shared.calls[i], 2)
				C.printf(c'LINUX PROCNS READER: index=%d calls=%d\n', i, calls)
				if calls == 0 { good = false }
			}
			C.store(&shared.stop, 1, 3)
			C.store(&shared.target, -1, 3)
			wake(shared)
			for i in 0 .. 4 { if C.pthread_join(threads[i], nil) != 0 { fatal(20) } }
		}
		return good
	}
}

fn reference_race() bool {
	unsafe {
		shared := &Shared(C.alloca(sizeof(Shared)))
		*shared = Shared{}
		mut threads := [4]C.pthread_t{}
		workers := &Worker(C.alloca(4 * sizeof(Worker)))
		for i in 0 .. 4 {
			workers[i] = Worker{ shared: shared, index: i32(i) }
			if C.pthread_create(&threads[i], nil, walker, &workers[i]) != 0 { fatal(29) }
		}
		for _ in 0 .. 200 { operation(3, shared) }
		quiesce(shared)
		mut good := C.load(&shared.failures, 2) == 0
		for i in 0 .. 4 {
			calls := C.load(&shared.calls[i], 2)
			C.printf(c'LINUX PROCNS REFERENCE READER: index=%d calls=%d\n', i, calls)
			if calls == 0 { good = false }
		}
		C.store(&shared.stop, 1, 3)
		C.store(&shared.target, -1, 3)
		wake(shared)
		for i in 0 .. 4 { if C.pthread_join(threads[i], nil) != 0 { fatal(30) } }
		C.printf(c'LINUX PROCNS REFERENCE RACE: errors=%d workers=4\n', shared.failures)
		return good
	}
}

@[export:'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		held()
		if reference && !reference_race() { fatal(31) }
		if !reference {
			observer := C.open(c'/proc/slabinfo', 0)
			if observer < 0 { fatal(21) }
			tracker := C.open(c'/proc/allocstart', 0)
			tracked := tracker >= 0
			if tracked { C.close(tracker) }
			mut good := true
			for kind in 0 .. 4 { if !storage(i32(kind), observer, tracked) { good = false } }
			if C.close(observer) != 0 { fatal(22) }
			if !good {
				C.puts(c'LINUX PROCNS FAIL: retained proc namespace tree or concurrent lookup')
				C.fflush(nil)
				return 1
			}
		}
		C.puts(if reference { c'LINUX PROCNS REFERENCE: PASS' } else { c'LINUX PROCNS: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
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
