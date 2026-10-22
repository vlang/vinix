// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import crypto.sha256
import tools.packages.pkgprotocol

#include <dirent.h>
fn C.fdopendir(int) voidptr
fn C.readdir(voidptr) &C.dirent
fn C.closedir(voidptr) int

fn local_source_digest(text string) string {
	bytes := text.bytes()
	mut hash := sha256.new()
	mut sum := []u8{len: sha256.size}
	defer { unsafe { bytes.free(); sum.free(); hash.free(); free(hash) } }
	hash.write(bytes) or { panic(err) }
	hash.checksum_into(mut sum)
	return sum.hex()
}

fn local_source_inventory(root int, artifacts []pkgprotocol.LocalSourceArtifact) ! {
	fd := C.openat(root, c'.', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('cannot read captured local source evidence inventory') }
	stream := C.fdopendir(fd)
	if stream == unsafe { nil } { C.close(fd); return error('cannot enumerate local source evidence') }
	defer { C.closedir(stream) }
	mut count := 0
	for {
		C.errno = 0
		entry := C.readdir(stream)
		if entry == unsafe { nil } {
			if C.errno != 0 { return error('cannot finish local source evidence inventory') }
			break
		}
		// This name borrows readdir storage only until the next readdir call.
		name := unsafe { tos(&u8(&entry.d_name[0]), int(C.strlen(&char(&entry.d_name[0])))) }
		if name == '.' || name == '..' { continue }
		count++
		if count > artifacts.len + 1 { return error('local source evidence inventory differs') }
		if name == 'source-offer.json' { continue }
		mut found := false
		for artifact in artifacts { if artifact.path == name { found = true; break } }
		if !found { return error('unlisted local source evidence file') }
	}
	if count != artifacts.len + 1 { return error('local source evidence inventory differs') }
}

// Read one bounded ordinary file through a captured, alias-free directory.
// The returned bytes are owned; no caller path is opened by the JSON decoder.
fn source_offer_bytes(directory int, name string, limit int) !string {
	fd := C.openat(directory, name.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC)
	if fd < 0 { return error('local source evidence file is missing or linked') }
	defer { C.close(fd) }
	mut before := C.stat{}
	if C.fstat(fd, unsafe { &before }) != 0 || u32(before.st_mode) & 0o170000 != 0o100000
		|| before.st_nlink != 1 || before.st_size <= 0 || before.st_size > limit {
		return error('local source evidence needs bounded ordinary single-link files')
	}
	mut bytes := []u8{len: int(before.st_size)}
	defer { unsafe { bytes.free() } }
	mut count := 0
	for count < bytes.len {
		n := C.read(fd, unsafe { &bytes[count] }, usize(bytes.len - count))
		if n <= 0 { return error('incomplete local source evidence file') }
		count += int(n)
	}
	mut sentinel := u8(0)
	mut after := C.stat{}
	if C.read(fd, unsafe { &sentinel }, 1) != 0 || C.fstat(fd, unsafe { &after }) != 0
		|| before.st_dev != after.st_dev || before.st_ino != after.st_ino || before.st_size != after.st_size
		|| before.st_mtime != after.st_mtime || before.st_ctime != after.st_ctime {
		return error('local source evidence changed while reading')
	}
	return bytes.bytestr()
}

// This API admits only a deliberately incomplete local experiment. It cannot
// authorize redistribution. Publisher production admission must establish the
// complete corresponding-source/notice closure through a separate contract.
// The caller must still capture and recheck these inputs during publication.
pub fn admit_local_source_offer(path string, runtime string, version string, architecture string) !pkgprotocol.LocalSourceOffer {
	fd := absolute_directory(path)!
	defer { C.close(fd) }
	mut root := C.stat{}
	if C.fstat(fd, unsafe { &root }) != 0 { return error('cannot capture local source evidence directory') }
	text := source_offer_bytes(fd, 'source-offer.json', 256 * 1024)!
	defer { unsafe { text.free() } }
	mut offer := pkgprotocol.decode_local_source_offer(text)!
	mut accepted := false
	defer { if !accepted { offer.close() } }
	if offer.runtime != runtime || offer.version != version || offer.architecture != architecture {
		return error('local source offer differs from the selected runtime or host')
	}
	mut total := u64(0)
	mut runtime_notice := false
	mut application_notice := false
	for artifact in offer.artifacts {
		bytes := source_offer_bytes(fd, artifact.path, 16 * 1024 * 1024)!
		defer { unsafe { bytes.free() } }
		total += u64(bytes.len)
		if total > 64 * 1024 * 1024 { return error('local source evidence exceeds its total byte bound') }
		digest := local_source_digest(bytes)
		defer { unsafe { digest.free() } }
		if digest != artifact.sha256 { return error('local source evidence digest differs') }
		if artifact.kind in ['notice', 'license']! {
			if artifact.path == 'runtime-LICENSE.txt' { runtime_notice = true }
			if artifact.path == 'application-LICENSE.txt' { application_notice = true }
		}
	}
	if !runtime_notice || !application_notice { return error('local source offer requires both publisher notices') }
	local_source_inventory(fd, offer.artifacts)!
	check := absolute_directory(path)!
	defer { C.close(check) }
	mut current := C.stat{}
	if C.fstat(check, unsafe { &current }) != 0 || root.st_dev != current.st_dev || root.st_ino != current.st_ino {
		return error('local source evidence directory was replaced')
	}
	repeated := source_offer_bytes(fd, 'source-offer.json', 256 * 1024)!
	defer { unsafe { repeated.free() } }
	if repeated != text { return error('local source offer changed during admission') }
	accepted = true
	return offer
}
