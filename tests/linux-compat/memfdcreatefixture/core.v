// SPDX-License-Identifier: GPL-2.0-or-later
module memfdcreatefixture

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}

struct C.stat {
	st_mode u32
	st_nlink u64
	st_size i64
	st_uid u32
	st_gid u32
}

fn C.syscall(i64, ...) i64
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.snprintf(&char, u64, &char, ...) i32
fn C.fflush(voidptr) i32
fn C.puts(&char) i32
fn C.pause() i32
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.umask(u32) u32
fn C.geteuid() u32
fn C.getegid() u32
fn C.sysconf(i32) i64
fn C.mmap(voidptr, u64, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, u64, i32) i32
fn C.munmap(voidptr, u64) i32
fn C.memset(voidptr, i32, u64) voidptr
fn C.memcmp(voidptr, voidptr, u64) i32
fn C.strcmp(&char, &char) i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.fstat(i32, &C.stat) i32
fn C.fcntl(i32, i32, ...) i32
fn C.ftruncate(i32, i64) i32
fn C.read(i32, voidptr, u64) i64
fn C.write(i32, voidptr, u64) i64
fn C.readlink(&char, &char, u64) i64
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__atomic_load_n(&i32, i32) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_add_fetch(&i32, i32, i32) i32
fn C.sched_yield() i32

const mfd_exec = u64(0x10)
const mfd_allow_sealing = u64(2)
const mfd_cloexec = u64(1)
const invalid_flags = u64(1 << 30)
const f_get_seals = 1034
const f_add_seals = 1033
const f_seal_seal = 1
const f_seal_grow = 4
const publication_rounds = 256

fn need(ok bool, name &char) {
	if ok { return }
	unsafe {
		C.printf(c'LINUX MEMFDCREATE FAIL: %s errno=%d\n', name, *C.__errno_location())
		C.fflush(nil)
		C._exit(1)
	}
}

fn create(name &char, flags u64) i32 {
	unsafe {
		fd := C.syscall(i64(C.SYS_memfd_create), name, flags)
		return if fd < 0 { -*C.__errno_location() } else { i32(fd) }
	}
}

fn named(fd i32, name &char) bool {
	unsafe {
		mut path := [48]char{}
		mut expected := [300]char{}
		mut actual := [300]char{}
		C.snprintf(&path[0], path.len, c'/proc/self/fd/%d', fd)
		length := C.snprintf(&expected[0], expected.len, c'/memfd:%s (deleted)', name)
		return C.readlink(&path[0], &actual[0], actual.len) == length
			&& C.memcmp(&actual[0], &expected[0], u64(length)) == 0
	}
}

fn check_names() {
	unsafe {
		need(create(nil, invalid_flags) == -C.EINVAL, c'bad flags precede name faults')
		need(create(nil, 0) == -C.EFAULT, c'bad name pointer')
		page_size := C.sysconf(C._SC_PAGESIZE)
		need(page_size > 0, c'get native page size')
		page := u64(page_size)
		base := &u8(C.mmap(nil, page * 2, C.PROT_READ | C.PROT_WRITE,
			C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		need(i64(base) != -1 && C.mprotect(base + page, page, C.PROT_NONE) == 0, c'map name guard')
		last := base + page - 1
		*last = 0
		mut fd := create(&char(last), 0)
		need(fd >= 0 && named(fd, c'') && C.close(fd) == 0, c'empty name at page boundary')
		*last = `a`
		need(create(&char(last), 0) == -C.EFAULT, c'fault copying a suffix after a readable byte')
		maximum := base + page - 250
		C.memset(maximum, `m`, 249)
		*last = 0
		fd = create(&char(maximum), 0)
		need(fd >= 0 && named(fd, &char(maximum)) && C.close(fd) == 0, c'preserve all 249 bytes')
		*last = `b`
		need(create(&char(maximum), 0) == -C.EINVAL, c'reject a name of 250 nonzero bytes')
		need(C.mprotect(base + page, page, C.PROT_READ | C.PROT_WRITE) == 0, c'open second name page')
		base[page] = `z`
		base[page + 1] = 0
		fd = create(&char(last), 0)
		need(fd >= 0 && named(fd, c'bz') && C.close(fd) == 0, c'import a name across pages')
		need(C.munmap(base, page * 2) == 0, c'unmap name guard')
	}
}

fn check_flags() {
	unsafe {
		fd := create(c'explicit-exec', mfd_exec)
		need(fd >= 0, c'create with MFD_EXEC')
		mut metadata := C.stat{}
		need(C.fstat(fd, &metadata) == 0 && metadata.st_mode & C.S_IFMT == C.S_IFREG
			&& metadata.st_mode & 0o777 == 0o777 && metadata.st_nlink == 0 && metadata.st_size == 0
			&& metadata.st_uid == C.geteuid() && metadata.st_gid == C.getegid(), c'executable anonymous file metadata')
		need(C.fcntl(fd, C.F_GETFL) & 3 == C.O_RDWR && C.fcntl(fd, C.F_GETFD) == 0, c'open access and descriptor flags')
		need(C.fcntl(fd, f_get_seals) == f_seal_seal && C.close(fd) == 0, c'initial seal without MFD_ALLOW_SEALING')
		next := create(c'exec-seals', (u64(0xcafe) << 32) | mfd_exec | mfd_allow_sealing | mfd_cloexec)
		need(next == fd && named(next, c'exec-seals'), c'reuse lowest descriptor with narrowed flags')
		need(C.fcntl(next, C.F_GETFD) == C.FD_CLOEXEC && C.fcntl(next, f_get_seals) == 0
			&& C.fcntl(next, f_add_seals, f_seal_grow) == 0, c'combine MFD_EXEC with CLOEXEC and sealing')
		need(C.ftruncate(next, 1) == -1 && *C.__errno_location() == C.EPERM, c'enforce added growth seal')
		need(C.close(next) == 0, c'close sealed file')
	}
}

fn check_exhaustion() {
	unsafe {
		child := C.fork()
		need(child >= 0, c'fork descriptor limit child')
		if child == 0 {
			limit := [u64(0), u64(0)]!
			need(C.syscall(i64(C.SYS_prlimit64), 0, C.RLIMIT_NOFILE, &limit[0], nil) == 0, c'lower descriptor limit')
			need(create(nil, invalid_flags) == -C.EINVAL && create(nil, 0) == -C.EFAULT,
				c'flags and name faults precede descriptor exhaustion')
			need(create(c'valid', mfd_exec) == -C.EMFILE, c'report exhausted descriptor table')
			C._exit(0)
		}
		mut status := i32(-1)
		need(C.waitpid(child, &status, 0) == child && status == 0, c'descriptor limit child passed')
	}
}

struct Observation {
	fd i32
mut:
	stop i32
	count i32
}

fn observe_descriptors(arg voidptr) voidptr {
	unsafe {
		mut state := &Observation(arg)
		for C.__atomic_load_n(&state.stop, 2) == 0 {
			fd := C.fcntl(state.fd, C.F_DUPFD_CLOEXEC, state.fd + 1)
			if fd < 0 {
				need(*C.__errno_location() == C.EBADF, c'observer sees an empty slot or a descriptor')
				continue
			}
			need(named(fd, c'publication') && C.close(fd) == 0, c'every visible descriptor has its complete name')
			C.__atomic_add_fetch(&state.count, 1, 0)
		}
		return nil
	}
}

fn check_publication() {
	unsafe {
		slot := create(c'publication', 0)
		need(slot >= 0 && C.close(slot) == 0, c'find descriptor slot for concurrent observation')
		mut state := Observation{fd: slot}
		mut observer := C.pthread_t{}
		need(C.pthread_create(&observer, nil, observe_descriptors, voidptr(&state)) == 0, c'start descriptor observer')
		for round in 0 .. publication_rounds {
			fd := create(c'publication', mfd_exec)
			need(fd == slot, c'reserve the same slot under concurrent observation')
			if round == 0 {
				for C.__atomic_load_n(&state.count, 2) == 0 { C.sched_yield() }
			}
			need(C.close(fd) == 0, c'close published descriptor')
		}
		C.__atomic_store_n(&state.stop, 1, 3)
		need(C.pthread_join(observer, nil) == 0, c'join descriptor observer')
	}
}

fn execute_copy() {
	unsafe {
		image := C.open(c'/proc/self/exe', C.O_RDONLY | C.O_CLOEXEC)
		destination := create(c'executable-copy', mfd_exec | mfd_cloexec)
		need(image >= 0 && destination >= 0, c'open the image and executable memfd')
		mut buffer := [4096]u8{}
		for {
			count := C.read(image, &buffer[0], buffer.len)
			if count == 0 { break }
			need(count > 0 && C.write(destination, &buffer[0], u64(count)) == count,
				c'copy complete probe into memfd')
		}
		mut path := [48]char{}
		C.snprintf(&path[0], path.len, c'/proc/self/fd/%d', destination)
		fd := C.open(&path[0], C.O_RDONLY | C.O_CLOEXEC)
		need(fd >= 0 && C.close(image) == 0 && C.close(destination) == 0, c'reopen executable read-only')
		child := C.fork()
		need(child >= 0, c'fork executable memfd child')
		if child == 0 {
			args := [&char(c'memfd-copy'), &char(c'--memfd-image'), &char(nil)]!
			env := [&char(nil)]!
			C.syscall(i64(C.SYS_execveat), fd, c'', &args[0], &env[0], C.AT_EMPTY_PATH)
			need(false, c'execute ELF from memfd with execveat')
		}
		mut status := i32(-1)
		need(C.waitpid(child, &status, 0) == child && status == (43 << 8), c'memfd image executed')
		need(C.close(fd) == 0, c'close executable memfd')
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc > 1 && C.strcmp(argv[1], c'--memfd-image') == 0 { return 43 }
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		C.mount(c'proc', c'/proc', c'proc', 0, nil)
		C.umask(0o077)
		check_names()
		check_flags()
		check_exhaustion()
		check_publication()
		execute_copy()
		C.printf(c'LINUX MEMFDCREATE SUMMARY: publication=%d exec=43\n', publication_rounds)
		C.puts(if reference { c'LINUX MEMFDCREATE REFERENCE: PASS' } else { c'LINUX MEMFDCREATE: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
