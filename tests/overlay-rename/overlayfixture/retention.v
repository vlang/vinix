// SPDX-License-Identifier: GPL-2.0-or-later
module overlayfixture

#include <fcntl.h>
#include <alloca.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

struct C.sockaddr_un {
	sun_family u16
	sun_path [108]char
}

fn C.socket(int, int, int) int
fn C.bind(int, voidptr, u32) int
fn C.alloca(usize) voidptr

fn C.link(&char, &char) int
fn C.symlink(&char, &char) int
fn C.fchdir(int) int
fn C.chdir(&char) int
fn C.openat(int, &char, int, ...) int

fn prepare_retained_layers() {
	unsafe {
		write_file(c'/tmp/overlay-state/lower/layer-file', c'AAAAAAAA', 321)
		check(C.chown(c'/tmp/overlay-state/lower/layer-file', 1000, 1000) == 0, 322)
		// Populate the underlying merged directory before it becomes a layer.
		fd := C.open(c'/tmp/overlay-state/merged/layer-file', C.O_RDONLY)
		check(fd >= 0 && C.close(fd) == 0, 323)
		owned_directory(c'/tmp/overlay-state/stack-upper', 324)
		owned_directory(c'/tmp/overlay-state/stack-work', 325)
		owned_directory(c'/tmp/overlay-state/stacked', 326)
		check(C.mount(c'overlay', c'/tmp/overlay-state/stacked', c'overlay', 0,
			c'lowerdir=/tmp/overlay-state/merged,upperdir=/tmp/overlay-state/stack-upper,workdir=/tmp/overlay-state/stack-work') == 0, 327)
	}
}

fn retained_layers() {
	unsafe {
		held := C.open(c'/tmp/overlay-state/stacked/layer-file', C.O_RDONLY)
		check(held >= 0, 328)
		// The backing alias's Resource changes, while the outer entry still
		// owns the original Resource and its descriptor reads that original.
		write_file(c'/tmp/overlay-state/merged/layer-file', c'BBBBBBBB', 329)
		write_file(c'/tmp/overlay-state/stacked/layer-file', c'CCCCCCCC', 331)
		// Moving a copied-up lower entry retires both nonempty layer arrays;
		// V's managed data pointers must go through the array destructor.
		check(C.rename(c'/tmp/overlay-state/stacked/layer-file',
			c'/tmp/overlay-state/stacked/layer-moved') == 0, 335)
		check(C.unlink(c'/tmp/overlay-state/merged/layer-file') == 0
			&& C.usleep(6500000) == 0, 330)
		check(C.unlink(c'/tmp/overlay-state/stacked/layer-moved') == 0
			&& C.usleep(6500000) == 0, 332)
		mut old := [8]char{}
		check(C.read(held, &old[0], 8) == 8 && C.memcmp(&old[0], c'AAAAAAAA', 8) == 0
			&& C.close(held) == 0, 333)
		mut st := C.stat{}
		check(C.lstat(c'/tmp/overlay-state/merged/layer-file', &st) == -1
			&& *C.__errno_location() == C.ENOENT
			&& C.lstat(c'/tmp/overlay-state/stacked/layer-file', &st) == -1
			&& *C.__errno_location() == C.ENOENT
			&& C.lstat(c'/tmp/overlay-state/stacked/layer-moved', &st) == -1
			&& *C.__errno_location() == C.ENOENT, 334)
		C.puts(c'OVERLAY STACKED LIFETIME: PASS')
		C.fflush(nil)
	}
}

fn retention_cycle() {
	unsafe {
		fd := C.open(c'/tmp/overlay-state/merged/transient', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(fd >= 0 && C.write(fd, c'BBBBBBBB', 8) == 8 && C.close(fd) == 0, 300)
		check(C.rename(c'/tmp/overlay-state/merged/transient', c'/tmp/overlay-state/merged/transient-renamed') == 0
			&& C.unlink(c'/tmp/overlay-state/merged/transient-renamed') == 0, 301)
		check(C.link(c'/tmp/overlay-state/merged/anchor', c'/tmp/overlay-state/merged/hard') == 0
			&& C.rename(c'/tmp/overlay-state/merged/hard', c'/tmp/overlay-state/merged/hard-renamed') == 0
			&& C.unlink(c'/tmp/overlay-state/merged/hard-renamed') == 0, 302)
		check(C.symlink(c'anchor', c'/tmp/overlay-state/merged/symbolic') == 0
			&& C.rename(c'/tmp/overlay-state/merged/symbolic', c'/tmp/overlay-state/merged/symbolic-renamed') == 0
			&& C.unlink(c'/tmp/overlay-state/merged/symbolic-renamed') == 0, 303)
		check(C.mkdir(c'/tmp/overlay-state/merged/transient-dir', 0o700) == 0, 304)
		dir := C.open(c'/tmp/overlay-state/merged/transient-dir', C.O_RDONLY | C.O_DIRECTORY)
		check(dir >= 0 && C.rmdir(c'/tmp/overlay-state/merged/transient-dir') == 0
			&& C.close(dir) == 0, 305)
		socket := bind_socket()
		check(C.unlink(c'/tmp/overlay-state/merged/transient-socket') == 0
			&& C.close(socket) == 0, 316)
	}
}

fn bind_socket() int {
	unsafe {
		fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
		mut address := &C.sockaddr_un(C.alloca(sizeof(C.sockaddr_un)))
		*address = C.sockaddr_un{}
		address.sun_family = u16(C.AF_UNIX)
		check(fd >= 0 && C.snprintf(&address.sun_path[0], 108,
			c'/tmp/overlay-state/merged/transient-socket') > 0, 317)
		check(C.bind(fd, voidptr(address), u32(sizeof(C.sockaddr_un))) == 0, 318)
		return fd
	}
}

fn retained_socket() {
	unsafe {
		socket := bind_socket()
		path := C.open(c'/tmp/overlay-state/merged/transient-socket', C.O_PATH)
		check(path >= 0 && C.unlink(c'/tmp/overlay-state/merged/transient-socket') == 0
			&& C.close(socket) == 0 && C.usleep(6500000) == 0, 319)
		mut st := C.stat{}
		check(C.fstat(path, &st) == 0 && st.st_mode & C.S_IFMT == C.S_IFSOCK
			&& st.st_uid == 1000 && C.close(path) == 0, 320)
		C.puts(c'OVERLAY SOCKET LIFETIME: PASS')
		C.fflush(nil)
	}
}

fn retained_directory() {
	unsafe {
		check(C.mkdir(c'/tmp/overlay-state/merged/held-dir', 0o700) == 0, 306)
		dir := C.open(c'/tmp/overlay-state/merged/held-dir', C.O_RDONLY | C.O_DIRECTORY)
		check(dir >= 0 && C.fchdir(dir) == 0
			&& C.rmdir(c'/tmp/overlay-state/merged/held-dir') == 0
			&& C.usleep(6500000) == 0, 307)
		mut st := C.stat{}
		check(C.fstat(dir, &st) == 0 && st.st_nlink == 0
			&& st.st_mode & C.S_IFMT == C.S_IFDIR && st.st_uid == 1000, 308)
		check(C.openat(dir, c'forbidden', C.O_CREAT | C.O_WRONLY, u32(0o600)) == -1
			&& *C.__errno_location() == C.ENOENT, 309)
		parent := C.openat(dir, c'..', C.O_RDONLY | C.O_DIRECTORY)
		check(parent >= 0 && C.close(parent) == 0 && C.close(dir) == 0
			&& C.usleep(6500000) == 0, 310)
		// The cwd owns the alias after its descriptor has closed too.
		parent_cwd := C.open(c'..', C.O_RDONLY | C.O_DIRECTORY)
		check(parent_cwd >= 0 && C.close(parent_cwd) == 0
			&& C.chdir(c'/') == 0, 311)
		C.puts(c'OVERLAY DIRECTORY LIFETIME: PASS')
		C.fflush(nil)
	}
}

fn retention_batch() {
	for iteration in 0 .. 1000 {
		publish(if iteration % 2 == 0 { c'BBBBBBBB' } else { c'AAAAAAAA' })
	}
	for _ in 0 .. 100 { retention_cycle() }
	// Alias, backing-node and socket backend queues each need their grace;
	// allow the TCG writeback worker time to finish every due batch too.
	check(C.usleep(25000000) == 0, 312)
}

fn overlay_retention() {
	unsafe {
		write_file(c'/tmp/overlay-state/merged/anchor', c'AAAAAAAA', 313)
		retained_directory()
		retained_socket()
		retained_layers()
		retention_batch()
		sample(30)
		retention_batch()
		sample(31)
		mut st := C.stat{}
		check(C.lstat(c'/tmp/overlay-state/merged/anchor', &st) == 0
			&& st.st_nlink == 1 && st.st_uid == 1000, 315)
		C.puts(c'OVERLAY RETENTION: PASS')
		C.fflush(nil)
	}
}
