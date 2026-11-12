// SPDX-License-Identifier: GPL-2.0-or-later
module nativeapk

import compress.szip
import crypto.sha256
import os
import rand

fn file_hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 65536}
	defer { unsafe { buffer.free(); digest.free(); free(digest) } }
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	mut result := []u8{len: 32}
	defer { unsafe { result.free() } }
	digest.checksum_into(mut result)
	return result.hex()
}

// Current V's read-only close does not release ZIP storage. Every entry name,
// cached payload and backing byte array belongs to this reader; path is borrowed.
fn release_archive(archive &szip.Zip) {
	for entry in archive.entries {
		unsafe { entry.name.free(); entry.data.free() }
	}
	unsafe { archive.entries.free(); archive.filedata.free(); free(archive) }
}

// Only the process ABI is installed. ZIP paths never become filesystem paths.
pub fn library_name(entry string, abi string) !string {
	prefix := 'lib/' + abi + '/'
	if !entry.starts_with(prefix) { return '' }
	name := entry[prefix.len..]
	if name == '' || name.contains('/') || name.contains('\\') || name.contains('..')
		|| !name.starts_with('lib') || !name.ends_with('.so')
		|| !name.bytes().all(it.is_alnum() || it in [`_`, `-`, `.`, `+`]) {
		return error('invalid APK native library entry: ' + entry)
	}
	return name
}

pub fn install(apk string, data string, abi string) !string {
	if abi != 'arm64-v8a' { return error('unsupported native APK ABI: ' + abi) }
	identity := file_hash(apk)!
	parent := data + '/native-libraries'
	os.mkdir_all(parent, mode: 0o700)!
	if os.is_link(parent) { return error('native library directory is a symlink') }
	destination := parent + '/' + identity
	// Build a complete new directory before publishing it. In particular a
	// duplicate/traversal/corrupt ZIP must never leave a partially installed APK.
	staging := os.join_path(parent, '.install-' + rand.uuid_v4())
	os.mkdir(staging, mode: 0o700)!
	defer { os.rmdir_all(staging) or {} }
	mut archive := szip.open_lazy(apk)!
	defer { release_archive(archive) }
	mut names := map[string]string{}
	for index in 0 .. archive.total()! {
		archive.open_entry_by_index(index)!
		defer { archive.close_entry() }
		name := if archive.is_dir()! { '' } else { library_name(archive.name(), abi)! }
		// Preserve whole-archive payload validation without retaining every
		// decoded DEX/resource. Only one bounded entry is owned at a time.
		if archive.size() > 512 * 1024 * 1024 { return error('APK entry is too large') }
		payload := archive.read_entry_bytes()!
		if name == '' { unsafe { payload.free() }; continue }
		if name in names { unsafe { payload.free() }; return error('duplicate APK native library: ' + name) }
		names[name] = ''
		file := staging + '/' + name
		os.write_file_array(file, payload) or { unsafe { payload.free() }; return err }
		unsafe { payload.free() }
		mut input := os.open(file)!
		mut header := []u8{len: 20}
		defer { unsafe { header.free() } }
		count := input.read(mut header)!
		input.close()
		if count != 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
			|| header[18] != 183 || header[19] != 0 {
			return error('APK native library is not little-endian AArch64 ELF64: ' + name)
		}
		os.chmod(file, 0o500)!
		names[name] = file_hash(file)!
	}
	if !os.exists(destination) {
		// rename never falls back to a partial recursive copy. If another
		// launcher published this hash concurrently, verify that copy below.
		os.rename(staging, destination) or {
			if !os.is_dir(destination) { return err }
		}
	}
	// A previously installed content hash remains valid while another instance
	// uses it. Reuse it only after checking every file against the fresh ZIP.
	if os.is_link(destination) { return error('native library destination is a symlink') }
	if os.ls(destination)!.len != names.len { return error('installed native library entries changed') }
	for name, expected in names {
		old := destination + '/' + name
		if os.is_link(old) || !os.is_file(old)
			|| file_hash(old)! != expected {
			return error('installed native library content changed: ' + name)
		}
	}
	return destination
}
