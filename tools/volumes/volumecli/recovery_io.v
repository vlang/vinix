// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

#include <unistd.h>
#include <sys/stat.h>

fn C.fchmod(i32, u32) i32
fn C.linkat(i32, &char, i32, &char, i32) i32

// Exact, private, pinned binary inputs. Recheck the descriptor after EOF so
// ownership/permissions and length changes cannot silently become trusted.
fn read_recovery_file(path &char, output &u8, size int) bool {
	return size > 0 && read_private_key_file(path, output, size, size) == size
}

fn read_private_key_file(path &char, output &u8, minimum int, maximum int) int {
	if minimum <= 0 || maximum < minimum || maximum > 1024 { return 0 }
	fd := C.open(path, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK)
	if fd < 0 { C.perror(c'vinix-volume: open key input'); return 0 }
	defer { C.close(fd) }
	return read_private_key_fd(fd, output, minimum, maximum)
}

// The caller owns fd. Relative boot inputs use the same pinned-file policy.
fn read_private_key_fd(fd i32, output &u8, minimum int, maximum int) int {
	if minimum <= 0 || maximum < minimum || maximum > 1024 { return 0 }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || C.S_ISREG(info.st_mode) == 0 || info.st_size < minimum || info.st_size > maximum
		|| info.st_mode & 0o077 != 0 || info.st_uid != C.geteuid() { plan_error(c'key input must be a private owned regular file within the required size'); return 0 }
	size := int(info.st_size)
	mut done := 0
	for done < size {
		count := C.read(fd, unsafe { output + done }, usize(size - done))
		if count < 0 && unsafe { C.errno == C.EINTR } { continue }
		if count <= 0 || count > size - done { plan_error(c'incomplete key input'); return 0 }; done += int(count)
	}
	mut extra := u8(0); defer { erase_key(unsafe { &extra }, 1) }
	for {
		count := C.read(fd, unsafe { &extra }, 1)
		if count < 0 && unsafe { C.errno == C.EINTR } { continue }
		if count != 0 { plan_error(c'key input changed while reading'); return 0 }; break
	}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_size != size || info.st_mode & 0o077 != 0
		|| info.st_uid != C.geteuid() { plan_error(c'key input changed while reading'); return 0 }
	return size
}

fn recovery_nonce(output &u8) bool {
	return key_random_bytes(output, 12)
}

fn key_random_bytes(output &u8, size int) bool {
	if size <= 0 || size > 64 { return false }
	fd := C.open(c'/dev/urandom', C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK)
	if fd < 0 { C.perror(c'vinix-volume: open nonce source'); return false }
	defer { C.close(fd) }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_mode & C.S_IFMT != C.S_IFCHR { plan_error(c'nonce source must be a character device'); return false }
	mut done := 0
	for done < size {
		count := C.read(fd, unsafe { output + done }, usize(size - done))
		if count < 0 && unsafe { C.errno == C.EINTR } { continue }
		if count <= 0 || count > size - done { plan_error(c'nonce source failed'); return false }; done += int(count)
	}
	return true
}

// Hard-link publication is atomic and never replaces a destination, including
// dangling symlinks or aliases of an input. Keep the directory lock throughout
// publication and reporting. An owned directory prevents temporary-file swaps.
@[direct_array_access]
fn publish_recovery(edit &PlanEdit, bytes &u8, size int) bool {
	if edit.directory < 0 || !edit.locked || (size != 64 && size != recovery_bytes && size != sealed_bytes && size != volume_seal_bytes && size != volume_ciphertext_bytes && size != volume_ciphertext_scrub_bytes) { return false }
	mut info := C.stat{}
	if C.fstat(edit.directory, unsafe { &info }) != 0 || info.st_mode & C.S_IFMT != C.S_IFDIR
		|| info.st_uid != C.geteuid() || info.st_mode & 0o022 != 0 { plan_error(c'key destination directory must be owned and not writable by group or others'); return false }
	mut temporary := [64]char{}; mut fd := i32(-1); mut owned := false
	defer {
		if fd >= 0 { C.close(fd) }
		if owned && C.unlinkat(edit.directory, &temporary[0], 0) != 0 { C.perror(c'vinix-volume: temporary key cleanup failed') }
	}
	for attempt in 0 .. 64 {
		length := C.snprintf(&temporary[0], sizeof(temporary), c'.vinix-key-%d-%d', C.getpid(), attempt)
		if length <= 0 || length >= 64 { return false }
		if C.strcmp(&temporary[0], &edit.name[0]) == 0 { continue }
		fd = C.openat(edit.directory, &temporary[0], C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, u32(0o600))
		if fd >= 0 { owned = true; break }
		if unsafe { C.errno != C.EEXIST } { C.perror(c'vinix-volume: create temporary key'); return false }
	}
	if fd < 0 { plan_error(c'no unused temporary key filename'); return false }
	if C.fchmod(fd, 0o600) != 0 { C.perror(c'vinix-volume: private output permissions'); return false }
	mut done := 0
	for done < size {
		count := C.write(fd, unsafe { bytes + done }, usize(size - done))
		if count < 0 && unsafe { C.errno == C.EINTR } { continue }
		if count <= 0 || count > size - done { plan_error(c'incomplete recovery output'); return false }; done += int(count)
	}
	if C.fsync(fd) != 0 { C.perror(c'vinix-volume: flush key output'); return false }
	closed := C.close(fd); fd = -1
	if closed != 0 { C.perror(c'vinix-volume: close key output'); return false }
	if C.linkat(edit.directory, &temporary[0], edit.directory, &edit.name[0], 0) != 0 { C.perror(c'vinix-volume: publish key without replacement'); return false }
	if C.unlinkat(edit.directory, &temporary[0], 0) != 0 {
		plan_error(c'key output published, but temporary cleanup and durability are unconfirmed'); return false
	}
	owned = false
	if C.fsync(edit.directory) != 0 { plan_error(c'key output published, but directory durability is unconfirmed'); return false }
	return true
}

struct RecoveryFiles {
mut:
	edit PlanEdit
	key [64]u8
	recovery [64]u8
	envelope [160]u8
	nonce [12]u8
}

@[direct_array_access]
fn recovery_key_file(input &char, recovery &char, destination &char, backup bool) i32 {
	mut work := unsafe { &RecoveryFiles(C.alloca(sizeof(RecoveryFiles))) }
	unsafe { *work = RecoveryFiles{} }
	defer { close_plan_edit(mut work.edit); erase_key(work, sizeof(RecoveryFiles)) }
	if !read_recovery_file(recovery, &work.recovery[0], 64) { return 1 }
	if backup {
		if !read_recovery_file(input, &work.key[0], 64) || !recovery_nonce(&work.nonce[0]) { return 1 }
		if !encode_recovery(&work.key[0], &work.recovery[0], &work.nonce[0], &work.envelope[0]) {
			return plan_error(c'volume and recovery keys must differ and have distinct halves')
		}
	} else {
		if !read_recovery_file(input, &work.envelope[0], recovery_bytes) { return 1 }
		if !decode_recovery(&work.envelope[0], recovery_bytes, &work.recovery[0], &work.key[0]) { return plan_error(c'invalid recovery envelope or recovery key') }
	}
	if !open_plan_destination(destination, mut work.edit, true) { return 1 }
	if !publish_recovery(&work.edit, if backup { &work.envelope[0] } else { &work.key[0] }, if backup { recovery_bytes } else { 64 }) { return 1 }
	return finish_bundle_report(C.printf(if backup { c'key backup published\n' } else { c'key recovery published\n' }) >= 0)
}
