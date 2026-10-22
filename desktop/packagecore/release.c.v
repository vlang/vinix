// SPDX-License-Identifier: GPL-2.0-or-later
module packagecore

import tools.packages.pkgprotocol

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>

fn C.openat(int, &char, int, ...int) int
fn C.fstat(int, &C.stat) int
fn C.read(int, voidptr, usize) isize
fn C.close(int) int

fn release_trusted(fd int, owner u32, directory bool) !C.stat {
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || u32(info.st_uid) != owner || u32(info.st_mode) & 0o022 != 0
		|| (u32(info.st_mode) & u32(C.S_IFMT)) != if directory { u32(C.S_IFDIR) } else { u32(C.S_IFREG) } {
		return error('untrusted release declaration')
	}
	return info
}

// This is routing metadata, not publisher authority. The service still verifies
// the exact signed closure, repository configuration and policy during review.
// root is a caller-selected trust boundary; production always supplies '/'.
// The shared decoder bounds this read to 8 MiB and 4096 roots/pins. This
// deliberately checks routing structure only; malformed signed semantics are
// refused by the existing service review, never retried as a legacy install.
pub fn release_requirement_at(root string, owner u32, architecture string, id string) !bool {
	if architecture !in ['aarch64', 'x86_64'] || !identifier(id) { return error('invalid release route') }
	mut directory := C.open(&char(root.str), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	if directory < 0 { return error('release root unavailable') }
	defer { C.close(directory) }
	release_trusted(directory, owner, true)!
	for part in ['usr', 'share', 'vinix-packages']! {
		next := C.openat(directory, &char(part.str), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
		if next < 0 {
			if C.errno == C.ENOENT { return false }
			return error('release declaration parent unavailable or aliased')
		}
		C.close(directory)
		directory = next
		release_trusted(directory, owner, true)!
	}
	fd := C.openat(directory, c'applications.json', C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC, 0)
	if fd < 0 {
		if C.errno == C.ENOENT { return false }
		return error('release declaration unavailable or aliased')
	}
	defer { C.close(fd) }
	before := release_trusted(fd, owner, false)!
	if before.st_size <= 0 || before.st_size > 8 * 1024 * 1024 { return error('invalid release declaration size') }
	mut bytes := []u8{len: int(before.st_size)}
	defer { unsafe { bytes.free() } }
	mut count := 0
	for count < bytes.len {
		n := C.read(fd, unsafe { &bytes[count] }, usize(bytes.len - count))
		if n <= 0 { return error('incomplete release declaration') }
		count += int(n)
	}
	mut sentinel := u8(0)
	if C.read(fd, &sentinel, 1) != 0 { return error('release declaration changed while reading') }
	after := release_trusted(fd, owner, false)!
	if before.st_dev != after.st_dev || before.st_ino != after.st_ino || before.st_size != after.st_size
		|| C.vinix_workflow_mtime_ns(unsafe { &before }) != C.vinix_workflow_mtime_ns(unsafe { &after })
		|| C.vinix_workflow_ctime_ns(unsafe { &before }) != C.vinix_workflow_ctime_ns(unsafe { &after })
		|| before.st_mtime != after.st_mtime || before.st_ctime != after.st_ctime {
		return error('release declaration changed while reading')
	}
	return release_requirement(unsafe { tos(bytes.data, bytes.len) }, architecture, id)
}

fn release_requirement(text string, architecture string, id string) !bool {
	mut document := pkgprotocol.decode_deployment_document(text)!
	defer { document.close() }
	if document.format != 2 || document.architecture != architecture {
		return error('release declaration must lock this architecture')
	}
	// Only explicit roots replace a legacy acquisition. A dependency with the
	// same ID, or an installed executable, cannot select an application.
	for i, root in document.packages {
		if !identifier(root) { return error('invalid release roots') }
		for j in 0 .. i { if document.packages[j] == root { return error('duplicate release root') } }
	}
	if id !in document.packages { return false }
	for pin in document.locked {
		if pin.id == id { return true }
	}
	return error('release root has no exact locked package')
}
