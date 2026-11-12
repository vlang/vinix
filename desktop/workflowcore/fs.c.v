// SPDX-License-Identifier: GPL-2.0-or-later
// Shared descriptor-based boundary for document and file services.
module workflowcore

import os

#include <fcntl.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>

$if macos {
	#define vinix_workflow_rename(a,b,c,d) renameatx_np(a,b,c,d,RENAME_EXCL)
	#define vinix_workflow_exchange(a,b,c,d) renameatx_np(a,b,c,d,RENAME_SWAP)
	#define vinix_workflow_mtime_ns(s) ((s)->st_mtimespec.tv_nsec)
	#define vinix_workflow_ctime_ns(s) ((s)->st_ctimespec.tv_nsec)
} $else {
	#include <sys/syscall.h>
	#define vinix_workflow_rename(a,b,c,d) syscall(SYS_renameat2,a,b,c,d,1)
	#define vinix_workflow_exchange(a,b,c,d) syscall(SYS_renameat2,a,b,c,d,2)
	#define vinix_workflow_mtime_ns(s) ((s)->st_mtim.tv_nsec)
	#define vinix_workflow_ctime_ns(s) ((s)->st_ctim.tv_nsec)
}
fn C.vinix_workflow_mtime_ns(&C.stat) i64
fn C.vinix_workflow_ctime_ns(&C.stat) i64
fn C.vinix_workflow_rename(int, &char, int, &char) int
fn C.vinix_workflow_exchange(int, &char, int, &char) int
fn C.fstat(int, &C.stat) int
fn C.fstatat(int, &char, &C.stat, int) int
fn C.fchmod(int, u32) int
fn C.fchown(int, u32, u32) int
fn C.renameat(int, &char, int, &char) int
fn C.openat(int, &char, int, ...int) int
fn C.mkdirat(int, &char, u32) int
fn C.unlinkat(int, &char, int) int
fn C.fsync(int) int
fn C.flock(int, int) int
fn C.lseek(int, i64, int) i64
fn C.read(int, voidptr, uint) int
fn C.write(int, voidptr, uint) int
fn C.close(int) int
fn C.access(&char, int) int
fn C.readlinkat(int, &char, &char, uint) int
fn C.symlinkat(&char, int, &char) int
fn C.futimens(int, &C.timespec) int

pub struct Identity {
pub:
	device u64
	inode u64
	size u64
	modified i64
	accessed i64
	changed i64
	modified_ns i64
	changed_ns i64
	mode u32
	uid u32
	gid u32
}

pub fn (a Identity) same_node(b Identity) bool { return a.device == b.device && a.inode == b.inode }
pub fn (a Identity) unchanged(b Identity) bool {
	return a.same_node(b) && a.size == b.size && a.modified == b.modified && a.changed == b.changed && a.modified_ns == b.modified_ns && a.changed_ns == b.changed_ns && a.mode == b.mode
}
pub fn (a Identity) directory() bool { return a.mode & u32(C.S_IFMT) == u32(C.S_IFDIR) }
pub fn (a Identity) regular() bool { return a.mode & u32(C.S_IFMT) == u32(C.S_IFREG) }
pub fn (a Identity) link() bool { return a.mode & u32(C.S_IFMT) == u32(C.S_IFLNK) }

fn from_stat(s C.stat) Identity {
	return Identity{device: u64(s.st_dev), inode: u64(s.st_ino), size: u64(s.st_size), modified: i64(s.st_mtime), accessed: i64(s.st_atime), changed: i64(s.st_ctime), modified_ns: C.vinix_workflow_mtime_ns(unsafe { &s }), changed_ns: C.vinix_workflow_ctime_ns(unsafe { &s }), mode: u32(s.st_mode), uid: u32(s.st_uid), gid: u32(s.st_gid)}
}

pub fn valid_path(path string) bool {
	if path.len < 2 || path.len > 4096 || !path.starts_with('/') || path.ends_with('/') || path.contains('\x00') { return false }
	mut start := 1
	for i in 1 .. path.len + 1 {
		if i < path.len && path[i] != `/` { continue }
		length := i - start
		if length == 0 || (length == 1 && path[start] == `.`) || (length == 2 && path[start] == `.` && path[start + 1] == `.`) { return false }
		start = i + 1
	}
	return true
}

// Resolve parent aliases once; keep the final component (including a link).
pub fn canonical(path string) !string {
	if !valid_path(path) { return error('invalid path') }
	directory := os.dir(path)
	name := os.file_name(path)
	parent := os.real_path(directory)
	defer { unsafe { directory.free(); name.free(); parent.free() } }
	if parent == '' || !os.is_dir(parent) { return error('parent unavailable') }
	return os.join_path(parent, name)
}

pub fn open_parent(path string) !(int, string) {
	if !valid_path(path) { return error('invalid path') }
	parts := unsafe { tos(path.str + 1, path.len - 1) }.split('/')
	defer { unsafe { parts.free() } }
	mut fd := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC, 0)
	if fd < 0 { return error('root unavailable') }
	for i in 0 .. parts.len - 1 {
		next := C.openat(fd, &char(parts[i].str), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
		C.close(fd)
		if next < 0 { return error('parent unavailable or is a link') }
		fd = next
	}
	return fd, parts.last().clone()
}

fn identify_at(fd int, name string) !Identity {
	mut s := C.stat{}
	if C.fstatat(fd, &char(name.str), unsafe { &s }, C.AT_SYMLINK_NOFOLLOW) != 0 { return error('item unavailable') }
	return from_stat(s)
}

fn identify_fd(fd int) !Identity {
	mut s := C.stat{}
	if C.fstat(fd, unsafe { &s }) != 0 { return error('descriptor unavailable') }
	return from_stat(s)
}

pub fn identify(path string) !Identity {
	if path == '/' {
		fd := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC, 0)
		if fd < 0 { return error('root unavailable') }
		defer { C.close(fd) }
		return identify_fd(fd)!
	}
	fd, leaf := open_parent(path)!
	defer { C.close(fd); unsafe { leaf.free() } }
	return identify_at(fd, leaf)!
}

pub fn item_exists(path string) bool {
	if _ := identify(path) { return true }
	return false
}

fn copy_metadata(fd int, id Identity) ! {
	mut times := [C.timespec{tv_sec: id.accessed}, C.timespec{tv_sec: id.modified, tv_nsec: id.modified_ns}]!
	if C.fchmod(fd, id.mode & 0o777) != 0 || C.futimens(fd, &times[0]) != 0 || C.fsync(fd) != 0 { return error('cannot preserve copied metadata') }
}

fn write_all(fd int, bytes []u8) ! {
	mut at := 0
	for at < bytes.len {
		count := C.write(fd, unsafe { &u8(bytes.data) + at }, uint(bytes.len - at))
		if count < 0 && C.errno == C.EINTR { continue }
		if count <= 0 { return error('write failed (${C.errno})') }
		at += int(count)
	}
}

pub fn read_regular(path string, limit int) ![]u8 {
	parent, name := open_parent(path)!
	defer { C.close(parent); unsafe { name.free() } }
	fd := C.openat(parent, &char(name.str), C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC, 0)
	if fd < 0 { return error('cannot read item') }
	defer { C.close(fd) }
	before := identify_fd(fd)!
	if !before.regular() || before.size > u64(limit) { return error('not a regular file or exceeds limit') }
	mut bytes := []u8{len: int(before.size)}
	mut at := 0
	for at < bytes.len {
		count := C.read(fd, unsafe { &u8(bytes.data) + at }, uint(bytes.len - at))
		if count < 0 && C.errno == C.EINTR { continue }
		if count <= 0 { unsafe { bytes.free() }; return error('read interrupted') }
		at += int(count)
	}
	after := identify_fd(fd)!
	if !before.unchanged(after) { unsafe { bytes.free() }; return error('file changed while reading') }
	return bytes
}

pub struct SaveOptions {
pub:
	expected ?Identity
	create_only bool
}

// Write on the destination filesystem, sync, then publish a whole new inode.
// A failed pre-publication step leaves the original bytes untouched.
pub fn atomic_save(path string, data []u8, options SaveOptions) !Identity {
	prepared := begin_atomic_save(path, options)!
	mut output := &AtomicWriter{...prepared}
	defer { output.close(); unsafe { free(output) } }
	write_all(output.descriptor(), data)!
	return output.publish()!
}

// A streamed save uses the same staging and publication rules as byte saves.
// Call close on every path; only publish exposes the completed file.
pub struct AtomicWriter {
mut:
	fd int = -1
	parent int = -1
	path string
	leaf string
	temporary string
	root Identity
	staged Identity
	original ?Identity
	published bool
}

pub fn begin_atomic_save(path string, options SaveOptions) !AtomicWriter {
	parent, leaf := open_parent(path)!
	mut ready := false
	defer { if !ready { C.close(parent); unsafe { leaf.free() } } }
	root := identify_fd(parent)!
	mut original := ?Identity(none)
	if old := identify_at(parent, leaf) {
		if !old.regular() { return error('destination is not a regular file') }
		if options.create_only { return error('destination exists') }
		original = old
	} else if C.errno != C.ENOENT { return error('destination unavailable') }
	if expected := options.expected {
		old := original or { return error('document disappeared') }
		if !expected.unchanged(old) { return error('document changed on disk') }
	}
	mut fd := -1
	mut temporary := ''
	for attempt in 0 .. 1000 {
		pid := os.getpid().str()
		number := attempt.str()
		temporary = '.vinix-save-' + pid + '-' + number
		unsafe { pid.free(); number.free() }
		fd = C.openat(parent, &char(temporary.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
		if fd >= 0 { break }
		unsafe { temporary.free() }
		if C.errno != C.EEXIST { return error('cannot stage save') }
	}
	if fd < 0 { return error('no staging name available') }
	staged := identify_fd(fd) or { C.close(fd); C.unlinkat(parent, &char(temporary.str), 0); unsafe { temporary.free() }; return err }
	ready = true
	return AtomicWriter{fd: fd, parent: parent, path: path.clone(), leaf: leaf, temporary: temporary, root: root, staged: staged, original: original}
}

pub fn (writer &AtomicWriter) descriptor() int { return writer.fd }

pub fn (mut writer AtomicWriter) publish() !Identity {
	if writer.fd < 0 || writer.published { return error('save already closed or published') }
	if !writer.staged.same_node(identify_at(writer.parent, writer.temporary)!) { return error('staged document changed') }
	if old := writer.original {
		if C.fchown(writer.fd, old.uid, old.gid) != 0 { return error('cannot preserve document owner') }
		if C.fchmod(writer.fd, old.mode & 0o7777) != 0 { return error('cannot preserve document permissions') }
	}
	if C.fsync(writer.fd) != 0 { return error('cannot sync saved data') }
	// Reopen the named parent to detect device removal/replacement.
	current, current_leaf := open_parent(writer.path)!
	defer { C.close(current); unsafe { current_leaf.free() } }
	if !writer.root.same_node(identify_fd(current)!) { return error('destination volume disappeared') }
	if old := writer.original {
		if !old.unchanged(identify_at(writer.parent, writer.leaf)!) { return error('document changed on disk') }
		if C.renameat(writer.parent, &char(writer.temporary.str), writer.parent, &char(writer.leaf.str)) != 0 { return error('cannot publish saved document') }
	} else {
		if C.vinix_workflow_rename(writer.parent, &char(writer.temporary.str), writer.parent, &char(writer.leaf.str)) != 0 { return error('destination appeared while saving') }
	}
	writer.published = true
	if C.fsync(writer.parent) != 0 { return error('document saved; directory sync failed') }
	return identify_at(writer.parent, writer.leaf)!
}

pub fn (mut writer AtomicWriter) close() {
	if writer.parent >= 0 && !writer.published && writer.temporary.len > 0 {
		if current := identify_at(writer.parent, writer.temporary) {
			if writer.staged.same_node(current) { C.unlinkat(writer.parent, &char(writer.temporary.str), 0) }
		}
	}
	if writer.fd >= 0 { C.close(writer.fd) }
	if writer.parent >= 0 { C.close(writer.parent) }
	unsafe { writer.path.free(); writer.leaf.free(); writer.temporary.free() }
	writer = AtomicWriter{}
}

pub fn rename_exclusive(source string, destination string, expected Identity) ! {
	src, src_name := open_parent(source)!
	defer { C.close(src); unsafe { src_name.free() } }
	dst, dst_name := open_parent(destination)!
	defer { C.close(dst); unsafe { dst_name.free() } }
	if !expected.unchanged(identify_at(src, src_name)!) { return error('source changed') }
	if C.vinix_workflow_rename(src, &char(src_name.str), dst, &char(dst_name.str)) != 0 { return error('move failed (${C.errno})') }
	if C.fsync(src) != 0 || C.fsync(dst) != 0 { return error('move completed; directory sync failed') }
}

// Exchange publishes a replacement without a moment when the old destination
// is missing. The old inode remains at source for undo and crash recovery.
pub fn exchange(source string, destination string, expected Identity, replaced Identity) ! {
	src, src_name := open_parent(source)!
	defer { C.close(src); unsafe { src_name.free() } }
	dst, dst_name := open_parent(destination)!
	defer { C.close(dst); unsafe { dst_name.free() } }
	if !expected.unchanged(identify_at(src, src_name)!) || !replaced.unchanged(identify_at(dst, dst_name)!) { return error('replacement changed') }
	if C.vinix_workflow_exchange(src, &char(src_name.str), dst, &char(dst_name.str)) != 0 { return error('atomic replacement unavailable (${C.errno}); original retained') }
	if C.fsync(src) != 0 || C.fsync(dst) != 0 { return error('replacement published; directory sync failed') }
}

pub fn chmod(path string, expected Identity, mode u32) ! {
	if mode & ~u32(0o777) != 0 { return error('invalid permissions') }
	parent, leaf := open_parent(path)!
	defer { C.close(parent); unsafe { leaf.free() } }
	fd := C.openat(parent, &char(leaf.str), C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC, 0)
	if fd < 0 { return error('cannot open permissions') }
	defer { C.close(fd) }
	if !expected.unchanged(identify_fd(fd)!) { return error('item changed') }
	if C.fchmod(fd, mode) != 0 { return error('cannot change permissions') }
}
