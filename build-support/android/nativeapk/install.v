// SPDX-License-Identifier: GPL-2.0-or-later
module nativeapk

import compress.szip
import crypto.sha256
import os
import rand

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
	identity := sha256.sum(os.read_bytes(apk)!).hex()
	parent := data + '/native-libraries'
	os.mkdir_all(parent, mode: 0o700)!
	if os.is_link(parent) { return error('native library directory is a symlink') }
	destination := parent + '/' + identity
	// Build a complete new directory before publishing it. In particular a
	// duplicate/traversal/corrupt ZIP must never leave a partially installed APK.
	staging := os.join_path(parent, '.install-' + rand.uuid_v4())
	os.mkdir(staging, mode: 0o700)!
	defer { os.rmdir_all(staging) or {} }
	mut archive := szip.open(apk, .no_compression, .read_only)!
	defer { archive.close() }
	mut names := map[string]string{}
	for index in 0 .. archive.total()! {
		archive.open_entry_by_index(index)!
		defer { archive.close_entry() }
		if archive.is_dir()! { continue }
		name := library_name(archive.name(), abi)!
		if name == '' { continue }
		if name in names { return error('duplicate APK native library: ' + name) }
		names[name] = ''
		if archive.size() > 512 * 1024 * 1024 { return error('APK native library is too large') }
		file := staging + '/' + name
		archive.extract_entry(file)!
		mut input := os.open(file)!
		mut header := []u8{len: 20}
		count := input.read(mut header)!
		input.close()
		if count != 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
			|| header[18] != 183 || header[19] != 0 {
			return error('APK native library is not little-endian AArch64 ELF64: ' + name)
		}
		os.chmod(file, 0o500)!
		names[name] = sha256.sum(os.read_bytes(file)!).hex()
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
			|| sha256.sum(os.read_bytes(old)!).hex() != expected {
			return error('installed native library content changed: ' + name)
		}
	}
	return destination
}
