// SPDX-License-Identifier: GPL-2.0-or-later
module companionstage

import crypto.sha256
import nativeapk
import os

#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.fchmod(i32, u32) i32
fn C.fchown(i32, u32, u32) i32
fn C.lseek(i32, i64, i32) i64
fn C.rename(&char, &char) i32

const gms_package = 'com.google.android.gms'
const vending_package = 'com.android.vending'
const file_limit = u64(512) * 1024 * 1024

enum SelectedPackage {
	gms
	vending
}

fn selected_name(selected SelectedPackage) string {
	return match selected {
		.gms { gms_package }
		.vending { vending_package }
	}
}

pub struct Config {
pub:
	source string
	sha256 string
	data string
	scratch string
	source_owner u32
	source_group u32
	target_uid u32
	target_gid u32
}

pub struct Record {
pub:
	package_name string = gms_package
	source_sha256 string
	apk_sha256 string
	target_uid u32
	target_gid u32
	dir_mode u32 = 0o700
	apk_mode u32 = 0o400
	lib_mode u32 = 0o500
	native_libraries map[string]string
}

struct Object {
	dev u64
	inode u64
	uid u32
	gid u32
	mode u32
	nlink u64
	size u64
	directory bool
}

struct Owned {
mut:
	path string
	object Object
	active bool = true
}

struct Work {
mut:
	objects []Owned
}

struct Admission {
	source Object
	data Object
	fd int
}

fn canonical(path string) bool {
	return path.starts_with('/') && path.len > 1 && path.len <= 4096 &&
		!path.contains_any('\x00\n\r\\') &&
		!path[1..].split('/').any(it in ['', '.', '..'])
}

fn object(path string) !Object {
	st := os.lstat(path)!
	if st.get_filetype() !in [.regular, .directory] {
		return error('companion path is not a regular file or directory')
	}
	return Object{st.dev, st.inode, st.uid, st.gid, st.mode & 0o7777,
		st.nlink, st.size, st.get_filetype() == .directory}
}

fn fd_object(fd int) !Object {
	mut st := C.stat{}
	if C.fstat(i32(fd), &st) != 0 { return error('cannot inspect companion descriptor') }
	kind := u32(st.st_mode) & 0o170000
	if kind !in [u32(0o100000), u32(0o040000)] {
		return error('companion descriptor type differs')
	}
	return Object{u64(st.st_dev), u64(st.st_ino), u32(st.st_uid), u32(st.st_gid),
		u32(st.st_mode) & 0o7777, u64(st.st_nlink), u64(st.st_size), kind == 0o040000}
}

fn parents(path string, owner u32) ! {
	if !canonical(path) { return error('noncanonical companion path') }
	root := object('/')!
	if !root.directory || root.uid != 0 || root.mode & 0o7022 != 0 {
		return error('companion filesystem root protection differs')
	}
	mut current := ''
	parts := path[1..].split('/')
	for part in parts[..parts.len - 1] {
		current += '/' + part
		st := object(current)!
		if !st.directory || st.uid !in [u32(0), owner] || st.mode & 0o7022 != 0 {
			return error('companion parent protection differs')
		}
	}
}

fn absent(path string) ! {
	if os.exists(path) || os.is_link(path) { return error('companion target already exists') }
}

fn same_inode(a Object, b Object) bool {
	return a.dev == b.dev && a.inode == b.inode && a.directory == b.directory
}

fn data_unchanged(path string, expected Object) ! {
	actual := object(path)!
	if !same_inode(actual, expected) || actual.uid != expected.uid ||
		actual.gid != expected.gid || actual.mode != expected.mode {
		return error('companion data root identity changed')
	}
}

fn remember(mut work Work, path string) ! {
	if work.objects.len >= 1024 { return error('companion rollback ledger limit') }
	selected := object(path)!
	work.objects << Owned{path: path.clone(), object: selected}
}

fn make_directory(mut work Work, path string, uid u32, gid u32) ! {
	absent(path)!
	os.mkdir(path, mode: 0o700)!
	remember(mut work, path)!
	os.chown(path, int(uid), int(gid))!
	os.chmod(path, 0o700)!
	st := object(path)!
	if !st.directory || st.uid != uid || st.gid != gid || st.mode != 0o700 {
		return error('companion directory owner or mode differs')
	}
}

fn ensure_owned_catalog(mut work Work, path string, uid u32, gid u32) ! {
	if !os.exists(path) && !os.is_link(path) {
		make_directory(mut work, path, uid, gid)!
		return
	}
	current := object(path)!
	if !current.directory || current.uid != uid || current.gid != gid || current.mode != 0o700 {
		return error('companion shared catalog protection differs')
	}
	mut owned := false
	for item in work.objects {
		if item.active && item.path == path && same_inode(current, item.object) { owned = true }
	}
	if !owned { return error('companion shared catalog is not owned by this batch') }
	for name in os.ls(path)! {
		child := path + '/' + name
		entry := object(child)!
		mut admitted := false
		for item in work.objects {
			if item.active && item.path == child && same_inode(entry, item.object) { admitted = true }
		}
		if !admitted || entry.directory || entry.nlink != 1 || entry.uid != uid ||
			entry.gid != gid || entry.mode != 0o400 ||
			name !in [gms_package + '.apk', vending_package + '.apk'] {
			return error('companion shared catalog entry differs')
		}
	}
}

// Removing the first private cache releases ledger capacity before the second
// package. Retaining creation order keeps parents before their later children.
fn prune_removed(mut work Work) {
	mut retained := []Owned{cap: 1024}
	retained.flags |= .noslices
	for item in work.objects {
		// Struct copies share string storage. Each surviving entry must own
		// its path before the previous ledger's strings are released.
		if item.active { retained << Owned{path: item.path.clone(), object: item.object, active: true} }
		unsafe { item.path.free() }
	}
	unsafe { work.objects.free() }
	work.objects = retained
}

// Only remove exact inodes created by this attempt, children before parents.
// Unexpected replacements and nonempty directories remain available for audit.
fn rollback(mut work Work, prefix string) bool {
	mut complete := true
	for index := work.objects.len - 1; index >= 0; index-- {
		item := work.objects[index]
		if !item.active || (prefix != '' && item.path != prefix &&
			!item.path.starts_with(prefix + '/')) { continue }
		if !os.exists(item.path) && !os.is_link(item.path) {
			work.objects[index].active = false
			continue
		}
		current := object(item.path) or { complete = false; continue }
		if !same_inode(current, item.object) || (!current.directory && current.nlink != 1) {
			complete = false
			continue
		}
		if current.directory {
			os.rmdir(item.path) or { complete = false; continue }
		} else {
			os.rm(item.path) or { complete = false; continue }
		}
		work.objects[index].active = false
	}
	return complete
}

fn publish(mut work Work, temporary string, destination string) ! {
	absent(destination)!
	mut found := false
	for item in work.objects {
		if item.path == temporary || item.path.starts_with(temporary + '/') {
			if !same_inode(object(item.path)!, item.object) {
				return error('companion staging inode changed before publication')
			}
			found = true
		}
	}
	if !found { return error('companion publication is not owned') }
	if unsafe { C.rename(&char(temporary.str), &char(destination.str)) } != 0 {
		return error('cannot atomically publish companion object')
	}
	for index, item in work.objects {
		if item.path == temporary || item.path.starts_with(temporary + '/') {
			replacement := destination + item.path[temporary.len..]
			unsafe { work.objects[index].path.free() }
			work.objects[index].path = replacement
		}
	}
}

fn digest_fd(fd int) !string {
	if C.lseek(i32(fd), 0, C.SEEK_SET) != 0 { return error('cannot rewind companion input') }
	mut state := sha256.new()
	mut bytes := []u8{len: 65536}
	mut checksum := []u8{len: 32}
	defer { unsafe { state.free(); free(state); bytes.free(); checksum.free() } }
	mut total := u64(0)
	for {
		n := C.read(i32(fd), bytes.data, uint(bytes.len))
		if n < 0 && C.errno == C.EINTR { continue }
		if n < 0 { return error('cannot hash companion input') }
		if n == 0 { break }
		total += u64(n)
		if total > file_limit { return error('companion file exceeds byte limit') }
		state.write(bytes[..int(n)])!
	}
	state.checksum_into(mut checksum)
	return checksum.hex()
}

fn verify_digest(fd int, expected string) ! {
	actual := digest_fd(fd)!
	defer { unsafe { actual.free() } }
	if actual != expected { return error('companion file digest differs') }
}

fn open_regular(path string, expected Object) !int {
	fd := unsafe { C.open(&char(path.str), C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK) }
	if fd < 0 { return error('cannot open companion source') }
	actual := fd_object(fd) or { C.close(fd); return err }
	if actual != expected || actual.directory || actual.nlink != 1 {
		C.close(fd)
		return error('companion source changed before descriptor open')
	}
	return fd
}

fn copy_regular(mut work Work, source string, expected Object, pin string,
	destination string, uid u32, gid u32, mode u32) ! {
	input := open_regular(source, expected)!
	defer { C.close(input) }
	verify_digest(input, pin)!
	if C.lseek(i32(input), 0, C.SEEK_SET) != 0 { return error('cannot rewind companion copy') }
	output := unsafe { C.open(&char(destination.str), C.O_RDWR | C.O_CREAT | C.O_EXCL |
		C.O_NOFOLLOW | C.O_CLOEXEC, 0o600) }
	if output < 0 { return error('cannot exclusively create companion copy') }
	defer { C.close(output) }
	remember(mut work, destination)!
	mut buffer := []u8{len: 65536}
	defer { unsafe { buffer.free() } }
	mut total := u64(0)
	for {
		n := C.read(i32(input), buffer.data, uint(buffer.len))
		if n < 0 && C.errno == C.EINTR { continue }
		if n < 0 { return error('cannot read companion copy') }
		if n == 0 { break }
		total += u64(n)
		if total > file_limit || total > expected.size { return error('companion copy exceeds expected size') }
		mut written := 0
		for written < n {
			count := C.write(i32(output), unsafe { &buffer[written] }, uint(n - written))
			if count < 0 && C.errno == C.EINTR { continue }
			if count <= 0 { return error('incomplete companion copy') }
			written += int(count)
		}
	}
	if total != expected.size || fd_object(input)! != expected || object(source)! != expected {
		return error('companion source changed during copy')
	}
	if C.fchown(output, uid, gid) != 0 || C.fchmod(output, mode) != 0 {
		return error('cannot set companion file owner or mode')
	}
	actual := fd_object(output)!
	if actual.directory || actual.uid != uid || actual.gid != gid || actual.mode != mode ||
		actual.nlink != 1 || actual.size != expected.size || same_inode(actual, expected) {
		return error('companion copied file metadata differs')
	}
	verify_digest(output, pin)!
	if object(destination)! != actual { return error('companion copy path changed') }
}

fn admit(config Config, selected SelectedPackage) !Admission {
	for path in [config.source, config.data, config.scratch] { parents(path, config.source_owner)! }
	if config.sha256.len != 64 || !config.sha256.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) ||
		config.scratch == config.data || config.scratch.starts_with(config.data + '/') ||
		config.data.starts_with(config.scratch + '/') || config.source.starts_with(config.scratch + '/') {
		return error('invalid companion selector or scratch placement')
	}
	source := object(config.source)!
	if source.directory || source.uid != config.source_owner || source.gid != config.source_group ||
		source.nlink != 1 || source.mode & 0o7222 != 0 || source.mode & 0o400 == 0 ||
		source.size == 0 || source.size > file_limit {
		return error('companion source protection differs')
	}
	data := object(config.data)!
	if !data.directory || data.uid != config.target_uid || data.gid != config.target_gid || data.mode != 0o700 {
		return error('companion data root owner or mode differs')
	}
	catalog := config.data + '/_installed_apks_'
	name := selected_name(selected)
	package := config.data + '/' + name + '_'
	pending := config.data + '/.' + name + '_.pending'
	for path in [catalog, package, pending, config.scratch] { absent(path)! }
	fd := open_regular(config.source, source)!
	mut accepted := false
	defer { if !accepted { C.close(fd) } }
	verify_digest(fd, config.sha256)!
	if fd_object(fd)! != source || object(config.source)! != source {
		return error('companion source changed during admission')
	}
	accepted = true
	return Admission{source, data, fd}
}

fn stage_inner(config Config, selected SelectedPackage, admission Admission, mut work Work) !Record {
	source := admission.source
	data := admission.data
	fd := admission.fd
	name := selected_name(selected)
	catalog := config.data + '/_installed_apks_'
	package := config.data + '/' + name + '_'
	pending := config.data + '/.' + name + '_.pending'
	for path in [package, pending, config.scratch] { absent(path)! }
	if fd_object(fd)! != source || object(config.source)! != source {
		return error('companion admitted source changed before staging')
	}
	data_unchanged(config.data, data)!
	verify_digest(fd, config.sha256)!
	make_directory(mut work, config.scratch, config.source_owner, config.source_group)!
	make_directory(mut work, config.scratch + '/native-libraries', config.source_owner, config.source_group)!
	libraries := nativeapk.install(config.source, config.scratch, 'arm64-v8a')!
	defer { unsafe { libraries.free() } }
	if libraries != config.scratch + '/native-libraries/' + config.sha256 {
		return error('companion extraction path differs')
	}
	remember(mut work, libraries)!
	names := os.ls(libraries)!
	defer { unsafe { names.free() } }
	for cached_name in names { remember(mut work, libraries + '/' + cached_name)! }
	if names.len == 0 || names.len > 256 { return error('companion native library count differs') }
	if fd_object(fd)! != source || object(config.source)! != source { return error('companion source changed during extraction') }
	verify_digest(fd, config.sha256)!
	data_unchanged(config.data, data)!
	ensure_owned_catalog(mut work, catalog, config.target_uid, config.target_gid)!
	make_directory(mut work, pending, config.target_uid, config.target_gid)!
	make_directory(mut work, pending + '/lib', config.target_uid, config.target_gid)!
	mut hashes := map[string]string{}
	for library_name in names {
		if nativeapk.library_name('lib/arm64-v8a/' + library_name, 'arm64-v8a')! != library_name {
			return error('companion extracted library name differs')
		}
		path := libraries + '/' + library_name
		original := object(path)!
		if original.directory || original.uid != config.source_owner || original.gid != config.source_group ||
			original.mode != 0o500 || original.nlink != 1 {
			return error('companion extracted library metadata differs')
		}
		library_fd := open_regular(path, original)!
		pin := digest_fd(library_fd) or { C.close(library_fd); return err }
		C.close(library_fd)
		copy_regular(mut work, path, original, pin, pending + '/lib/' + library_name,
			config.target_uid, config.target_gid, 0o500) or { unsafe { pin.free() }; return err }
		hashes[library_name.clone()] = pin
	}
	apk_pending := catalog + '/.' + name + '.apk.pending'
	copy_regular(mut work, config.source, source, config.sha256, apk_pending,
		config.target_uid, config.target_gid, 0o400)!
	if fd_object(fd)! != source || object(config.source)! != source { return error('companion source changed before publication') }
	verify_digest(fd, config.sha256)!
	data_unchanged(config.data, data)!
	publish(mut work, pending, package)!
	publish(mut work, apk_pending, catalog + '/' + name + '.apk')!
	data_unchanged(config.data, data)!
	if object(config.source)! != source { return error('companion source identity changed after publication') }
	return Record{package_name: name, source_sha256: config.sha256.clone(), apk_sha256: config.sha256.clone(),
		target_uid: config.target_uid, target_gid: config.target_gid, native_libraries: hashes}
}

// The caller admits the fixed GMS APK's package, version and certificates and
// ensures selected app UIDs have no processes before this one-use transaction.
pub fn stage(config Config) !Record {
	admission := admit(config, .gms)!
	defer { C.close(admission.fd) }
	mut work := Work{objects: []Owned{cap: 1024}}
	work.objects.flags |= .noslices
	defer {
		for item in work.objects { unsafe { item.path.free() } }
		unsafe { work.objects.free() }
	}
	result := stage_inner(config, .gms, admission, mut work) or {
		if !rollback(mut work, '') { return error(err.msg() + '; companion rollback incomplete') }
		return err
	}
	if !rollback(mut work, config.scratch) {
		rollback(mut work, '')
		return error('companion scratch cleanup incomplete')
	}
	return result
}

fn overlaps(first string, second string) bool {
	return first == second || first.starts_with(second + '/') || second.starts_with(first + '/')
}

fn stage_admitted_pair(gms Config, vending Config, first Admission, second Admission,
	mut work Work) ![]Record {
	first_record := stage_inner(gms, .gms, first, mut work)!
	if !rollback(mut work, gms.scratch) { return error('first companion scratch cleanup incomplete') }
	prune_removed(mut work)
	second_record := stage_inner(vending, .vending, second, mut work)!
	verify_digest(first.fd, gms.sha256)!
	verify_digest(second.fd, vending.sha256)!
	for selected in [first, second]! {
		if fd_object(selected.fd)! != selected.source { return error('companion pair source descriptor changed') }
	}
	if object(gms.source)! != first.source || object(vending.source)! != second.source {
		return error('companion pair source path changed')
	}
	data_unchanged(gms.data, first.data)!
	return [first_record, second_record]
}

// Only these two package identities are selectable. The controller admits both
// APKs first; no partially completed companion survives a later batch failure.
pub fn stage_pair(gms Config, vending Config) ![]Record {
	if gms.data != vending.data || gms.target_uid != vending.target_uid ||
		gms.target_gid != vending.target_gid || gms.source_owner != vending.source_owner ||
		gms.source_group != vending.source_group || overlaps(gms.source, vending.source) ||
		overlaps(gms.scratch, vending.scratch) || overlaps(gms.scratch, vending.source) ||
		overlaps(vending.scratch, gms.source) {
		return error('companion pair identity or placement differs')
	}
	first := admit(gms, .gms)!
	defer { C.close(first.fd) }
	second := admit(vending, .vending)!
	defer { C.close(second.fd) }
	if same_inode(first.source, second.source) { return error('companion pair sources share an inode') }
	mut work := Work{objects: []Owned{cap: 1024}}
	work.objects.flags |= .noslices
	defer {
		for item in work.objects { unsafe { item.path.free() } }
		unsafe { work.objects.free() }
	}
	result := stage_admitted_pair(gms, vending, first, second, mut work) or {
		if !rollback(mut work, '') { return error(err.msg() + '; companion pair rollback incomplete') }
		return err
	}
	if !rollback(mut work, vending.scratch) {
		rollback(mut work, '')
		return error('second companion scratch cleanup incomplete')
	}
	return result
}
