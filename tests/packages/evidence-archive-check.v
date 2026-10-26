// SPDX-License-Identifier: GPL-2.0-or-later
// Independently verify sealed tar payloads without extracting evidence trees.
module main

import crypto.sha256
import dl
import json2
import os

type ArchiveNew = fn () voidptr
type ArchiveCall = fn (voidptr) i32
type ArchiveOpen = fn (voidptr, &char, usize) i32
type ArchiveOption = fn (voidptr, &char) i32
type ArchiveNext = fn (voidptr, &voidptr) i32
type ArchiveData = fn (voidptr, voidptr, usize) isize
type EntryString = fn (voidptr) &char
type EntrySize = fn (voidptr) i64
type EntryType = fn (voidptr) u32
type ZlibVersion = fn () &char
type InflateInit = fn (voidptr, i32, &char, i32) i32
type Inflate = fn (voidptr, i32) i32
type InflateReset = fn (voidptr, i32) i32

// Public zlib z_stream ABI: uInt is unsigned int, uLong is unsigned long.
// Only input/output pointers and lengths are written by this V caller.
struct GzipStream {
mut:
	next_in   voidptr
	avail_in  u32
	total_in  usize
	next_out  voidptr
	avail_out u32
	total_out usize
	message   voidptr
	state     voidptr
	allocate  voidptr
	release   voidptr
	opaque    voidptr
	data_type i32
	adler     usize
	reserved  usize
}

struct GzipReceipt {
	members       int
	decoded_bytes u64
	zlib_version  string
}

// libarchive's gzip reader does not reliably reject a corrupt CRC trailer.
// Independently drain every gzip member with zlib, whose inflate checks both
// trailer CRC32 and uncompressed length. No decompressed bytes reach disk.
fn check_gzip(path string) !GzipReceipt {
	mut name := 'libz.so.1'
	$if macos {
		name = '/usr/lib/libz.1.dylib'
	}
	handle := dl.open(name, dl.rtld_now | dl.rtld_local)
	if handle == unsafe { nil } { return error('cannot load zlib') }
	defer { dl.close(handle) }
	for symbol in ['zlibVersion', 'inflateInit2_', 'inflate', 'inflateReset2', 'inflateEnd'] {
		if dl.sym(handle, symbol) == unsafe { nil } {
			return error('missing zlib symbol: ' + symbol)
		}
	}
	version := unsafe { ZlibVersion(dl.sym(handle, 'zlibVersion')) }
	initialize := unsafe { InflateInit(dl.sym(handle, 'inflateInit2_')) }
	inflate := unsafe { Inflate(dl.sym(handle, 'inflate')) }
	reset := unsafe { InflateReset(dl.sym(handle, 'inflateReset2')) }
	finish := unsafe { ArchiveCall(dl.sym(handle, 'inflateEnd')) }
	mut stream := GzipStream{}
	if initialize(&stream, 31, version(), i32(sizeof(GzipStream))) != 0 {
		return error('gzip validator initialization failed')
	}
	defer { finish(&stream) }
	mut input := os.open(path)!
	defer { input.close() }
	mut compressed := []u8{len: 1024 * 1024}
	defer { unsafe { compressed.free() } }
	mut output := []u8{len: 1024 * 1024}
	defer { unsafe { output.free() } }
	mut complete := false
	mut members := 0
	mut decoded := u64(0)
	for {
		count := input.read(mut compressed) or { if err is os.Eof { break } else { return err } }
		if count == 0 { break }
		if complete {
			if reset(&stream, 31) != 0 { return error('gzip validator reset failed') }
			complete = false
		}
		stream.next_in = compressed.data
		stream.avail_in = u32(count)
		for {
			before := stream.avail_in
			stream.next_out = output.data
			stream.avail_out = u32(output.len)
			status := inflate(&stream, 0)
			produced := u32(output.len) - stream.avail_out
			decoded += produced
			if status == 1 {
				members++
				complete = true
				if stream.avail_in == 0 { break }
				if reset(&stream, 31) != 0 { return error('gzip validator reset failed') }
				complete = false
			} else if status == -5 && stream.avail_in == 0 && produced == 0 {
				break // Z_BUF_ERROR: need the next compressed input chunk.
			} else if status != 0 {
				return error('gzip integrity validation failed')
			} else if before == stream.avail_in && produced == 0 {
				return error('gzip decoder made no progress')
			}
			if stream.avail_in == 0 && stream.avail_out != 0 { break }
		}
	}
	if !complete || members == 0 { return error('truncated gzip stream') }
	return GzipReceipt{ members: members, decoded_bytes: decoded, zlib_version: c_text(version()) }
}

struct ArchiveApi {
	handle          voidptr
	new_reader      ArchiveNew    = unsafe { nil }
	support_gzip    ArchiveCall   = unsafe { nil }
	support_tar     ArchiveCall   = unsafe { nil }
	open_filename   ArchiveOpen   = unsafe { nil }
	set_options     ArchiveOption = unsafe { nil }
	next_header     ArchiveNext   = unsafe { nil }
	read_data       ArchiveData   = unsafe { nil }
	close_reader    ArchiveCall   = unsafe { nil }
	free_reader     ArchiveCall   = unsafe { nil }
	pathname        EntryString   = unsafe { nil }
	symlink_target  EntryString   = unsafe { nil }
	hardlink_target EntryString   = unsafe { nil }
	size            EntrySize     = unsafe { nil }
	filetype        EntryType     = unsafe { nil }
}

fn load_api() !ArchiveApi {
	mut name := 'libarchive.so.13'
	$if macos {
		name = '/usr/lib/libarchive.2.dylib'
	}
	handle := dl.open(name, dl.rtld_now | dl.rtld_local)
	if handle == unsafe { nil } { return error('cannot load libarchive: ' + dl.dlerror()) }
	for symbol in ['archive_read_new', 'archive_read_support_filter_gzip',
		'archive_read_support_format_tar', 'archive_read_open_filename', 'archive_read_set_options',
		'archive_read_next_header', 'archive_read_data', 'archive_read_close', 'archive_read_free',
		'archive_entry_pathname', 'archive_entry_symlink', 'archive_entry_hardlink',
		'archive_entry_size', 'archive_entry_filetype'] {
		if dl.sym(handle, symbol) == unsafe { nil } {
			dl.close(handle)
			return error('missing libarchive symbol: ' + symbol)
		}
	}
	return ArchiveApi{
		handle:          handle
		new_reader:      unsafe { ArchiveNew(dl.sym(handle, 'archive_read_new')) }
		support_gzip:    unsafe { ArchiveCall(dl.sym(handle, 'archive_read_support_filter_gzip')) }
		support_tar:     unsafe { ArchiveCall(dl.sym(handle, 'archive_read_support_format_tar')) }
		open_filename:   unsafe { ArchiveOpen(dl.sym(handle, 'archive_read_open_filename')) }
		set_options:     unsafe { ArchiveOption(dl.sym(handle, 'archive_read_set_options')) }
		next_header:     unsafe { ArchiveNext(dl.sym(handle, 'archive_read_next_header')) }
		read_data:       unsafe { ArchiveData(dl.sym(handle, 'archive_read_data')) }
		close_reader:    unsafe { ArchiveCall(dl.sym(handle, 'archive_read_close')) }
		free_reader:     unsafe { ArchiveCall(dl.sym(handle, 'archive_read_free')) }
		pathname:        unsafe { EntryString(dl.sym(handle, 'archive_entry_pathname')) }
		symlink_target:  unsafe { EntryString(dl.sym(handle, 'archive_entry_symlink')) }
		hardlink_target: unsafe { EntryString(dl.sym(handle, 'archive_entry_hardlink')) }
		size:            unsafe { EntrySize(dl.sym(handle, 'archive_entry_size')) }
		filetype:        unsafe { EntryType(dl.sym(handle, 'archive_entry_filetype')) }
	}
}

fn file_hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut sum := sha256.new()
	defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		count := input.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if count == 0 { break }
		sum.write(buffer[..count])!
	}
	return sum.sum([]u8{}).hex()
}

fn valid_hash(value string) bool {
	if value.len != 64 { return false }
	for c in value.bytes() {
		if (c < `0` || c > `9`) && (c < `a` || c > `f`) { return false }
	}
	return true
}

fn canonical_path(value string) bool {
	if value == '' || value.len > 16384 || value.contains_any('\x00\t\r\n') { return false }
	for part in value.split('/') {
		if part == '' || part == '.' || part == '..' { return false }
	}
	return true
}

struct Expected {
	kind   string
	hash   string
	target string
}

fn expected_entries(manifest string) !map[string]Expected {
	if manifest == '' || manifest.len > 64 * 1024 * 1024 || !manifest.ends_with('\n') {
		return error('invalid bounded sealed manifest')
	}
	mut result := map[string]Expected{}
	for line in manifest[..manifest.len - 1].split('\n') {
		parts := line.split('\t')
		if parts.len !in [3, 4] || !valid_hash(parts[1]) || !canonical_path(parts[2])
			|| parts[2] == 'bundle.sha256' || parts[2] in result {
			return error('invalid or duplicate sealed manifest entry')
		}
		if (parts[0] == 'file' && parts.len != 3)
			|| (parts[0] == 'link' && parts.len != 4) || parts[0] !in ['file', 'link'] {
			return error('invalid sealed manifest type')
		}
		target := if parts.len == 4 { parts[3] } else { '' }
		if target.contains_any('\x00\t\r\n')
			|| (parts[0] == 'link' && sha256.hexhash(target) != parts[1]) {
			return error('sealed symlink target hash differs')
		}
		result[parts[2]] = Expected{ kind: parts[0], hash: parts[1], target: target }
	}
	if result.len == 0 { return error('empty sealed manifest') }
	for path, _ in result {
		mut parent := os.dir(path)
		for parent != '.' {
			if parent in result || parent == 'bundle.sha256' {
				return error('sealed member has a non-directory parent')
			}
			parent = os.dir(parent)
		}
	}
	return result
}

fn c_text(value &char) string {
	if value == unsafe { nil } { return '' }
	return unsafe { cstring_to_vstring(value).clone() }
}

// archive_read_data reconstructs sparse holes, including trailing zero bytes.
fn member_hash(api ArchiveApi, reader voidptr, declared i64) !string {
	if declared < 0 { return error('negative member size') }
	mut sum := sha256.new()
	defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	mut total := i64(0)
	for {
		count := api.read_data(reader, buffer.data, usize(buffer.len))
		if count < 0 { return error('archive payload read failed') }
		if count == 0 { break }
		if count > buffer.len || total > declared - count {
			return error('archive member exceeds declared size')
		}
		total += count
		sum.write(buffer[..int(count)])!
	}
	if total != declared { return error('archive member size differs') }
	return sum.sum([]u8{}).hex()
}

struct ArchiveReceipt {
	format           int = 1
	archive          string
	archive_sha256   string
	root             string
	manifest_sha256  string
	sealed_entries   int
	regular_payloads int
	hardlinks        int
	symlinks         int
	directories      int
	gzip             GzipReceipt
	scope            string = 'Exact sealed regular-file bytes and literal symlink targets; canonical directory headers permitted. Directory existence, modes, owners and timestamps are not authenticated by this historical manifest format.'
}

fn verify(archive string, root string, manifest_path string, expected_archive_hash string) !ArchiveReceipt {
	if !canonical_path(root) || root.contains('/') || !valid_hash(expected_archive_hash) {
		return error('invalid root basename or archive digest')
	}
	if os.is_link(archive) || os.is_link(manifest_path) {
		return error('requires regular archive and manifest files')
	}
	for path in [archive, manifest_path] {
		if os.lstat(path)!.mode & 0o170000 != 0o100000 {
			return error('requires regular archive and manifest files')
		}
	}
	if os.stat(manifest_path)!.size > 64 * 1024 * 1024 { return error('manifest too large') }
	manifest := os.read_file(manifest_path)!
	expected := expected_entries(manifest)!
	manifest_hash := sha256.hexhash(manifest)
	if file_hash(archive)! != expected_archive_hash {
		return error('archive digest differs before reading')
	}
	gzip := check_gzip(archive)!
	api := load_api()!
	defer { dl.close(api.handle) }
	reader := api.new_reader()
	if reader == unsafe { nil } { return error('cannot allocate archive reader') }
	defer { api.free_reader(reader) }
	// Read beyond the first TAR end marker and expose AppleDouble entries.
	// This also forces compressed stream/trailer consumption through EOF.
	options := 'tar:read_concatenated_archives,tar:!mac-ext'
	if api.support_gzip(reader) != 0 || api.support_tar(reader) != 0
		|| api.set_options(reader, &char(options.str)) != 0
		|| api.open_filename(reader, &char(archive.str), 1024 * 1024) != 0 {
		return error('archive reader initialization failed')
	}
	mut seen := map[string]bool{}
	mut regular := map[string]string{}
	mut hardlinks := map[string]string{}
	mut directories := 0
	mut symlinks := 0
	mut found_manifest := false
	for {
		mut entry := unsafe { nil }
		status := api.next_header(reader, &entry)
		if status == 1 { break } // ARCHIVE_EOF; warnings are refusals.
		if status != 0 || entry == unsafe { nil } { return error('archive header read failed') }
		kind := api.filetype(entry)
		mut name := c_text(api.pathname(entry))
		if kind == 0o040000 && name.ends_with('/') { name = name[..name.len - 1] }
		if !canonical_path(name) || (name != root && !name.starts_with(root + '/')) {
			return error('archive member escapes canonical root')
		}
		if name in seen { return error('duplicate archive member') }
		seen[name] = true
		if seen.len > expected.len * 8 + 65536 { return error('too many archive headers') }
		relative := if name == root { '' } else { name[root.len + 1..] }
		mut parent := os.dir(relative)
		for parent != '.' {
			if parent in expected || parent == 'bundle.sha256' {
				return error('archive member has a non-directory parent')
			}
			parent = os.dir(parent)
		}
		symbolic := c_text(api.symlink_target(entry))
		hard := c_text(api.hardlink_target(entry))
		declared := api.size(entry)
		if kind == 0o040000 {
			if relative in expected || relative == 'bundle.sha256' || symbolic != '' || hard != '' || declared != 0 {
				return error('archive directory type differs')
			}
			if member_hash(api, reader, 0)! != sha256.hexhash('') {
				return error('directory has payload')
			}
			directories++
			continue
		}
		if relative == '' { return error('archive root is not a directory') }
		if relative == 'bundle.sha256' {
			if kind != 0o100000 || symbolic != '' || hard != '' || declared != manifest.len
				|| member_hash(api, reader, declared)! != manifest_hash {
				return error('embedded sealed manifest differs')
			}
			found_manifest = true
			continue
		}
		item := expected[relative] or { return error('unexpected archive payload') }
		if hard != '' {
			if kind !in [u32(0), u32(0o100000)] || symbolic != '' || declared != 0 || item.kind != 'file'
				|| !canonical_path(hard) || !hard.starts_with(root + '/') {
				return error('invalid archive hardlink')
			}
			target := hard[root.len + 1..]
			target_item := expected[target] or { return error('hardlink target absent from seal') }
			if target == relative || target_item.kind != 'file' || target_item.hash != item.hash {
				return error('hardlink target type or hash differs')
			}
			member_hash(api, reader, 0)!
			hardlinks[relative] = target
		} else if kind == 0o120000 {
			if item.kind != 'link' || symbolic != item.target || declared != 0
				|| sha256.hexhash(symbolic) != item.hash {
				return error('archive symlink target differs')
			}
			member_hash(api, reader, 0)!
			symlinks++
		} else if kind == 0o100000 {
			if item.kind != 'file' || symbolic != '' || member_hash(api, reader, declared)! != item.hash {
				return error('archive payload hash or type differs')
			}
			regular[relative] = item.hash
		} else {
			return error('unsupported archive special member')
		}
	}
	if api.close_reader(reader) != 0 { return error('archive reader close failed') }
	if !found_manifest { return error('missing embedded sealed manifest') }
	for path, item in expected {
		if root + '/' + path !in seen { return error('missing sealed archive payload') }
		if path in hardlinks {
			target := hardlinks[path]
			if target !in regular || regular[target] != item.hash {
				return error('hardlink target is not an observed regular payload')
			}
		}
	}
	if file_hash(archive)! != expected_archive_hash || file_hash(manifest_path)! != manifest_hash {
		return error('archive or manifest changed during reading')
	}
	return ArchiveReceipt{
		archive:          os.abs_path(archive)
		archive_sha256:   expected_archive_hash
		root:             root
		manifest_sha256:  manifest_hash
		sealed_entries:   expected.len
		regular_payloads: regular.len
		hardlinks:        hardlinks.len
		symlinks:         symlinks
		directories:      directories
		gzip:             gzip
	}
}

fn main() {
	if os.args.len != 6 || os.args[1] != 'check' {
		eprintln('usage: evidence-archive-check check ARCHIVE ROOT_BASENAME MANIFEST EXPECTED_ARCHIVE_SHA256')
		exit(2)
	}
	receipt := verify(os.args[2], os.args[3], os.args[4], os.args[5]) or {
		eprintln(err)
		exit(1)
	}
	println(json2.encode(receipt))
	println('EVIDENCE ARCHIVE CHECK PASS')
}
