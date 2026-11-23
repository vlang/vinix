// SPDX-License-Identifier: GPL-2.0-or-later
module textbusyfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.stat {
	st_ino u64
	st_nlink u64
	st_size i64
	st_mode u32
}

fn C.alloca(usize) voidptr
fn C.access(&char, i32) i32
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
fn C.execve(&char, &&char, &&char) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.fchmod(i32, u32) i32
fn C.fstat(i32, &C.stat) i32
fn C.ftruncate(i32, i64) i32
fn C.link(&char, &char) i32
fn C.mkdir(&char, u32) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mount(&char, &char, &char, usize, voidptr) i32
fn C.munmap(voidptr, usize) i32
fn C.open(&char, i32, ...) i32
fn C.pause() i32
fn C.pipe(&i32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.read(i32, voidptr, usize) isize
fn C.rename(&char, &char) i32
fn C.sleep(u32) u32
fn C.strcmp(&char, &char) i32
fn C.sync()
fn C.syscall(isize, ...) isize
fn C.sysconf(i32) i64
fn C.truncate(&char, i64) i32
fn C.umount(&char) i32
fn C.unlink(&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.write(i32, voidptr, usize) isize
fn C._exit(i32)
fn C.__errno_location() &i32

const reply_fd = 40
const request_fd = 41

struct Group {
	pid i32
	reader i32
	writer i32
}

fn require(ok bool, label &char) {
	if ok { return }
	unsafe {
		C.printf(c'LINUX TEXTBUSY FAIL: %s errno=%d\n', label, *C.__errno_location())
		C.fflush(nil)
	}
	C._exit(1)
}

fn copy_program(dest &char) {
	unsafe {
		input := C.open(c'/proc/self/exe', C.O_RDONLY)
		output := C.open(dest, C.O_CREAT | C.O_EXCL | C.O_WRONLY, 0o755)
		require(input >= 0 && output >= 0, c'open image copy')
		buffer := C.alloca(8192)
		for {
			size := C.read(input, buffer, 8192)
			if size == 0 { break }
			require(size > 0 && C.write(output, buffer, usize(size)) == size, c'copy image bytes')
		}
		require(C.close(input) == 0 && C.close(output) == 0, c'close image copy')
	}
}

fn data_file(path &char, bytes &char, size usize) {
	fd := C.open(path, C.O_CREAT | C.O_EXCL | C.O_WRONLY, 0o755)
	require(fd >= 0 && C.write(fd, bytes, size) == isize(size) && C.close(fd) == 0,
		c'create control file')
}

fn exec_command(path &char, option &char, fd i32) i32 {
	unsafe {
		mut args := &&char(C.alloca(4 * sizeof(voidptr)))
		args[0] = path
		args[1] = option
		args[2] = nil
		args[3] = nil
		if fd >= 0 { return i32(C.syscall(isize(C.SYS_execveat), fd, c'', args, &args[3], C.AT_EMPTY_PATH)) }
		return C.execve(path, args, &args[3])
	}
}

fn expect_exec_error(path &char, fd i32, error_number i32, label &char) {
	unsafe {
		require(exec_command(path, c'--unexpected', fd) == -1 && *C.__errno_location() == error_number, label)
	}
}

fn expect_open_error(path &char, flags i32, error_number i32, label &char) {
	unsafe { require(C.open(path, flags) == -1 && *C.__errno_location() == error_number, label) }
}

fn expect_open(path &char, flags i32, label &char) {
	fd := C.open(path, flags)
	require(fd >= 0 && C.close(fd) == 0, label)
}

fn next_byte(fd i32, expected u8, label &char) {
	mut value := u8(0)
	require(C.read(fd, unsafe { &value }, 1) == 1 && value == expected, label)
}

fn wait_success(pid i32, label &char) {
	mut status := i32(0)
	require(C.waitpid(pid, &status, 0) > 0 && status == 0, label)
}

fn child_ready() {
	require(C.write(reply_fd, c'R', 1) == 1, c'worker ready')
}

fn worker() i32 {
	child_ready()
	for {
		mut command := u8(0)
		require(C.read(request_fd, unsafe { &command }, 1) == 1, c'worker command')
		match command {
			`q` { return 0 }
			`f` {
				pid := C.fork()
				require(pid >= 0, c'worker fork')
				if pid != 0 { return 0 }
				child_ready()
			}
			`e` { require(exec_command(c'/tmp/textbusy-next', c'--worker', -1) == 0, c'worker replacement') }
			else { require(false, c'unexpected worker command') }
		}
	}
	return 1
}

fn launch(path &char) Group {
	unsafe {
		up := &i32(C.alloca(2 * sizeof(i32)))
		down := &i32(C.alloca(2 * sizeof(i32)))
		require(C.pipe(up) == 0 && C.pipe(down) == 0, c'worker pipes')
		pid := C.fork()
		require(pid >= 0, c'launch fork')
		if pid == 0 {
			require(C.dup2(up[1], reply_fd) == reply_fd && C.dup2(down[0], request_fd) == request_fd,
				c'worker endpoints')
			C.close(up[0]); C.close(up[1]); C.close(down[0]); C.close(down[1])
			require(exec_command(path, c'--worker', -1) == 0, c'launch exec')
			C._exit(1)
		}
		C.close(up[1]); C.close(down[0])
		next_byte(up[0], `R`, c'launched worker ready')
		return Group{pid, up[0], down[1]}
	}
}

fn finish(child Group, descendant bool) {
	require(C.write(child.writer, c'q', 1) == 1, c'worker shutdown')
	wait_success(if descendant { -1 } else { child.pid }, c'worker exited')
	C.close(child.reader)
	C.close(child.writer)
}

fn controls() {
	image := &char(c'/tmp/textbusy-image')
	alias := &char(c'/tmp/textbusy-alias')
	next_image := &char(c'/tmp/textbusy-next')
	script := &char(c'/tmp/textbusy-script')
	invalid := &char(c'/tmp/textbusy-invalid')
	C.mkdir(c'/tmp', 0o755)
	copy_program(image)
	copy_program(next_image)
	require(C.link(image, alias) == 0, c'create hard link')
	fd := C.open(image, C.O_RDWR | C.O_CLOEXEC)
	require(fd >= 0, c'initial writer')
	expect_exec_error(image, fd, C.ETXTBSY, c'writer blocks descriptor exec before cloexec')
	copy := C.dup(fd)
	require(copy >= 0 && C.close(fd) == 0, c'transfer writer to dup')
	expect_exec_error(alias, -1, C.ETXTBSY, c'writer blocks hard link exec')
	page := usize(C.sysconf(C._SC_PAGESIZE))
	mapping := C.mmap(unsafe { nil }, page, C.PROT_READ, C.MAP_SHARED, copy, 0)
	require(mapping != voidptr(-1) && C.close(copy) == 0, c'retain writer through mapping')
	expect_exec_error(image, -1, C.ETXTBSY, c'mapping retains writer')
	require(C.munmap(mapping, page) == 0, c'release mapping writer')

	data_file(invalid, c'invalid', 7)
	for _ in 0 .. 100 {
		expect_exec_error(invalid, -1, C.ENOEXEC, c'invalid image rejected')
		expect_open(invalid, C.O_RDWR, c'failed loader releases claim')
	}
	data_file(script, c'#!/tmp/textbusy-image --worker\n', 31)
	writer := C.open(script, C.O_WRONLY)
	require(writer >= 0, c'open script writer')
	expect_exec_error(script, -1, C.ETXTBSY, c'writer blocks script exec')
	require(C.close(writer) == 0, c'close script writer')

	child := launch(script)
	expect_open(script, C.O_RDWR, c'script writable while interpreter runs')
	expect_open(alias, C.O_RDONLY, c'reading an executing file succeeds')
	expect_open(alias, C.O_PATH | C.O_TRUNC, c'O_PATH ignores truncation')
	expect_open_error(image, C.O_WRONLY, C.ETXTBSY, c'running image blocks writer')
	expect_open_error(alias, C.O_RDWR | C.O_TRUNC, C.ETXTBSY, c'hard link blocks writable truncation')
	expect_open_error(alias, C.O_RDONLY | C.O_TRUNC, C.ETXTBSY, c'hard link blocks read-only truncation')
	unsafe { require(C.truncate(alias, 0) == -1 && *C.__errno_location() == C.ETXTBSY, c'pathname truncate blocked') }
	require(C.write(child.writer, c'f', 1) == 1, c'fork worker')
	next_byte(child.reader, `R`, c'forked image ready')
	wait_success(child.pid, c'original image owner exited')
	expect_open_error(alias, C.O_WRONLY, C.ETXTBSY, c'fork retains executing image')
	require(C.rename(invalid, image) == 0, c'replace path to busy image')
	expect_open(image, C.O_WRONLY, c'replacement inode writable')
	expect_open_error(alias, C.O_WRONLY, C.ETXTBSY, c'alias still denotes executing inode')
	require(C.write(child.writer, c'e', 1) == 1, c'exec new image')
	next_byte(child.reader, `R`, c'replacement image ready')
	expect_open(alias, C.O_RDWR, c'exec releases old denial')
	expect_open_error(next_image, C.O_RDWR, C.ETXTBSY, c'exec installs new denial')
	finish(child, true)
	expect_open(next_image, C.O_RDWR, c'exit releases last denial')
}

fn check_data_aliases(path &char, alias &char) {
	reader := C.open(path, C.O_RDONLY)
	writer := C.open(alias, C.O_RDWR)
	require(reader >= 0 && writer >= 0, c'open persisted data aliases')
	page := usize(C.sysconf(C._SC_PAGESIZE))
	mapping := C.mmap(unsafe { nil }, page, C.PROT_READ, C.MAP_SHARED, reader, 0)
	require(mapping != voidptr(-1) && unsafe { *&u8(mapping) } == `o`, c'fault mapping through first link')
	require(C.pwrite(writer, c'new', 3, 0) == 3 && unsafe { *&u8(mapping) } == `n`,
		c'write through another link updates the mapped page')
	require(C.fchmod(writer, 0o640) == 0 && C.ftruncate(writer, 1) == 0,
		c'change mode and size through the second link')
	metadata := unsafe { &C.stat(C.alloca(sizeof(C.stat))) }
	require(C.fstat(reader, metadata) == 0 && metadata.st_mode & 0o777 == 0o640
		&& metadata.st_size == 1 && metadata.st_nlink == 2, c'other link observes mode and size')
	require(C.unlink(alias) == 0 && C.fstat(reader, metadata) == 0 && metadata.st_nlink == 1,
		c'other link observes unlink')
	require(C.munmap(mapping, page) == 0 && C.close(reader) == 0 && C.close(writer) == 0,
		c'release data alias descriptors')
}

fn unlinked_executable(image &char, alias &char, child Group) {
	metadata := unsafe { &C.stat(C.alloca(sizeof(C.stat))) }
	fd := C.open(image, C.O_RDONLY)
	require(fd >= 0 && C.fstat(fd, metadata) == 0 && metadata.st_nlink == 2,
		c'read executable inode before unlink')
	inode := metadata.st_ino
	require(C.unlink(image) == 0 && C.fstat(fd, metadata) == 0 && metadata.st_nlink == 1,
		c'executable sees the first unlink')
	require(C.unlink(alias) == 0 && C.fstat(fd, metadata) == 0 && metadata.st_nlink == 0
		&& C.close(fd) == 0, c'executable sees the last unlink')
	// Allow Vinix's five-second pathname grace period and one-second reap
	// interval to finish. The running image is now the only inode owner.
	C.sleep(7)
	C.sync()
	new_file := C.open(c'/tmp/textbusy-while-running', C.O_CREAT | C.O_EXCL | C.O_RDWR, 0o600)
	require(new_file >= 0 && C.fstat(new_file, metadata) == 0 && metadata.st_ino != inode
		&& C.close(new_file) == 0, c'allocator cannot reuse the running inode')
	finish(child, false)
	C.sync()
	reused := C.open(c'/tmp/textbusy-after-exit', C.O_CREAT | C.O_EXCL | C.O_RDWR, 0o600)
	require(reused >= 0 && C.fstat(reused, metadata) == 0 && metadata.st_ino == inode
		&& C.close(reused) == 0, c'inode can be reused after executable exit')
}

fn persisted_hardlinks(device &char) {
	image := &char(c'/tmp/textbusy-image')
	alias := &char(c'/tmp/textbusy-links/image')
	data := &char(c'/tmp/textbusy-data')
	data_alias := &char(c'/tmp/textbusy-links/data')
	require(C.mount(device, c'/tmp', c'ext2', 0, unsafe { nil }) == 0, c'mount private ext2 for persistent hardlinks')
	copy_program(image)
	require(C.mkdir(c'/tmp/textbusy-links', 0o755) == 0 && C.link(image, alias) == 0,
		c'disk hardlink creation across directories')
	data_file(data, c'old', 3)
	require(C.link(data, data_alias) == 0, c'disk hardlink creation for data')
	require(C.umount(c'/tmp') == 0 && C.mount(device, c'/tmp', c'ext2', 0, unsafe { nil }) == 0,
		c'remount private ext2 before opening aliases')
	fd := C.open(alias, C.O_WRONLY)
	require(fd >= 0, c'remounted alias writer')
	expect_exec_error(image, -1, C.ETXTBSY, c'persisted hardlink writer blocks exec')
	require(C.close(fd) == 0, c'close persisted alias writer')
	child := launch(image)
	expect_open_error(alias, C.O_WRONLY, C.ETXTBSY, c'persisted hardlink executable blocks writer')
	finish(child, false)
	expect_open(alias, C.O_WRONLY, c'persisted hardlink writer released on exit')
	check_data_aliases(data, data_alias)
	unlinked_executable(image, alias, launch(image))
	C.sync()
	require(C.umount(c'/tmp') == 0, c'unmount disk after final inode release')
	C.puts(c'LINUX TEXTBUSY DISK: persisted hardlink checks passed')
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc >= 2 && C.strcmp(argv[1], c'--worker') == 0 { return worker() }
		if argc == 2 && C.strcmp(argv[1], c'--unexpected') == 0 { require(false, c'busy exec unexpectedly succeeded') }
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		controls()
		if !reference {
			device := $if arm64 { &char(c'/dev/vda') } $else { &char(c'/dev/sd0') }
			if C.access(device, C.F_OK) == 0 { persisted_hardlinks(device) }
		}
		C.puts(c'LINUX TEXTBUSY SUMMARY: writer and image lifetime controls passed')
		C.puts(if reference { c'LINUX TEXTBUSY REFERENCE: PASS' } else { c'LINUX TEXTBUSY: PASS' })
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
