// SPDX-License-Identifier: GPL-2.0-only
module archivehost

import hosttest
import json2
import os
import tarcore
import tarstream

#include <sys/file.h>
#include <unistd.h>
#include <fcntl.h>

fn C.flock(i32, i32) i32
fn C.mkstemp(&u8) i32
fn C.mkdtemp(&char) &char
fn C.close(i32) i32
fn C.rename(&char, &char) i32

pub const default_max_bytes = u64(3) * 1024 * 1024 * 1024

struct Lock {
mut:
	fd int = -1
}

fn lock_file(path string) !Lock {
	fd := unsafe { C.open(path.str, C.O_RDWR | C.O_CREAT | C.O_APPEND | C.O_CLOEXEC, 0o666) }
	if fd < 0 { return os.error_posix() }
	if C.flock(fd, C.LOCK_EX) != 0 {
		failure := os.error_posix()
		C.close(fd)
		return failure
	}
	return Lock{ fd: fd }
}

fn (mut held_lock Lock) close() {
	if held_lock.fd < 0 { return }
	fd := held_lock.fd
	held_lock.fd = -1
	C.close(fd)
}

fn regular(path string) bool {
	state := os.stat(path) or { return false }
	return state.get_filetype() == .regular
}

fn mkdir_all(path string) ! {
	// Preserve literal Unix backslashes instead of treating them as separators.
	if path == '' || path == '.' || os.is_dir(path) { return }
	if os.exists(path) { return error('Not a directory: ' + path) }
	mkdir_all(os.dir(path))!
	os.mkdir(path)!
}

fn absolute(path string) string {
	return path_text(if os.is_abs_path(path) { path } else { os.getwd() + '/' + path })
}

fn temporary(destination string, directory bool) !string {
	parent := os.dir(destination)
	mkdir_all(parent)!
	mut pattern := (parent + '/.' + os.file_name(destination) + '.XXXXXX\x00').bytes()
	unsafe {
		if directory {
			path := C.mkdtemp(&char(pattern.data))
			if path == nil { return os.error_posix() }
			return path.vstring().clone()
		}
		fd := C.mkstemp(pattern.data)
		if fd < 0 { return os.error_posix() }
		C.close(fd)
		return pattern[..pattern.len - 1].bytestr()
	}
}

fn replace(source string, destination string) ! {
	if C.rename(source.str, destination.str) != 0 { return os.error_posix() }
}

pub fn source_identity(source string) !map[string]json2.Any {
	path := hosttest.resolve_path(source)!
	state := hosttest.bounds_file_state(path)!
	return {
		'format':   json2.Any(u64(1))
		'source':   path
		'device':   state['st_dev'] or { return error('missing device') }
		'inode':    state['st_ino'] or { return error('missing inode') }
		'size':     state['st_size'] or { return error('missing size') }
		'mtime_ns': state['st_mtime_ns'] or { return error('missing mtime') }
	}
}

fn read_json(path string) !json2.Any {
	return hosttest.decode_json(os.read_file(path)!)
}

fn write_json(path string, value json2.Any, pretty bool) ! {
	mut output := tarcore.create_stream(path)!
	defer { output.close() }
	output.write((json2.encode(value, prettify: pretty, indent_string: '  ') + '\n').bytes())!
	output.close_checked()!
}

pub fn cache_matches(manifest string, identity map[string]json2.Any, outputs []string) bool {
	for path in outputs {
		if !regular(path) || os.file_size(path) <= 0 { return false }
	}
	saved := read_json(manifest) or { return false }
	return saved is map[string]json2.Any && saved == identity
}

pub fn normalized_parts(name string) ![]string {
	if name.starts_with('/') || name.split('/').contains('..') {
		return error('unsafe archive member: ' + name)
	}
	return name.split('/').filter(it != '' && it != '.')
}

fn copy_member(mut source tarstream.Reader, mut destination tarcore.Writer, member tarcore.Member) ! {
	destination.write(tarcore.header(member)!)!
	if member.regular() {
		source.copy_to(mut destination)!
		destination.padding(member.size)!
	}
}

pub fn split_archive(source_path string, base_path string, seed_path string) !(int, i64) {
	base_temp := temporary(base_path, false)!
	defer { os.rm(base_temp) or {} }
	seed_temp := temporary(seed_path, false)!
	defer { os.rm(seed_temp) or {} }
	mut source := tarstream.open_plain(source_path)!
	defer { source.close() }
	mut base := tarcore.create_stream(base_temp)!
	defer { base.close() }
	mut seed := tarcore.create_gzip(seed_temp)!
	defer { seed.close() }
	mut root_seen := false
	mut members := 0
	mut bytes := i64(0)
	for {
		mut member := source.next() or {
			if err is tarstream.End { break }
			return err
		}
		parts := normalized_parts(member.name)!
		if parts.len == 0 || parts[0] != 'root' {
			copy_member(mut source, mut base, member)!
		} else if parts.len == 1 {
			root_seen = true
			base.write(tarcore.header(member)!)!
		} else {
			member.name = parts[1..].join('/')
			if member.kind == `1` {
				links := normalized_parts(member.linkname)!
				if links.len > 0 && links[0] == 'root' { member.linkname = links[1..].join('/') }
			}
			copy_member(mut source, mut seed, member)!
			members++
			bytes += member.size
		}
	}
	if !root_seen { base.add(tarcore.Member{ name: './root/', kind: `5`, mode: 0o755 }, []u8{})! }
	base.finish()!
	seed.finish()!
	base.close_checked()!
	seed.close_checked()!
	replace(base_temp, base_path)!
	replace(seed_temp, seed_path)!
	return members, bytes
}

pub fn desktop_split(source string, base string, seed string, manifest string) !bool {
	if !regular(source) { return error('desktop initramfs is missing: ' + source) }
	mkdir_all(os.dir(manifest))!
	mut held_lock := lock_file(os.dir(manifest) + '/.' + os.file_name(manifest) + '.lock')!
	defer { held_lock.close() }
	identity := source_identity(source)!
	if cache_matches(manifest, identity, [base, seed]) {
		println('QEMU storage images are current: ' + base)
		return false
	}
	members, bytes := split_archive(source, base, seed)!
	staged := temporary(manifest, false)!
	defer { os.rm(staged) or {} }
	mut sorted := map[string]json2.Any{}
	mut keys := identity.keys()
	keys.sort()
	for key in keys { sorted[key] = identity[key] or { panic('missing identity') } }
	write_json(staged, sorted, true)!
	replace(staged, manifest)!
	println('Split desktop initramfs: ${base} plus ${seed} (${members} root entries, ${bytes} bytes)')
	return true
}

pub fn split_parts(source_path string, staging string, max_bytes u64) ![]string {
	mut source := tarstream.open_plain(source_path)!
	defer { source.close() }
	mut parts := []string{}
	mut output := tarcore.Writer{}
	mut opened := false
	defer { if opened { output.close() } }
	mut estimated := u64(0)
	for {
		member := source.next() or {
			if err is tarstream.End { break }
			return err
		}
		payload := if member.regular() { (u64(member.size) + 511) / 512 * 512 } else { u64(0) }
		needed := u64(512) + payload
		if needed + 10240 > max_bytes {
			return error('tar member exceeds module limit: ' + member.name)
		}
		if !opened || estimated + needed + 10240 > max_bytes {
			if opened {
				output.finish()!
				output.close_checked()!
				opened = false
			}
			number := (parts.len + 1).str()
			part := staging + '/part-' + '0'.repeat(int_max(0, 3 - number.len)) + number + '.tar'
			output = tarcore.create_stream(part)!
			opened = true
			parts << part
			estimated = 0
		}
		copy_member(mut source, mut output, member)!
		estimated += needed
	}
	if !opened { return error('initramfs is empty') }
	output.finish()!
	output.close_checked()!
	opened = false
	for part in parts {
		if u64(os.file_size(part)) > max_bytes {
			return error('module exceeds size limit: ' + part)
		}
	}
	return parts
}

fn current_parts(manifest string, expected map[string]json2.Any, directory string, max_bytes u64) []string {
	saved := read_json(manifest) or { return []string{} }
	if saved !is map[string]json2.Any { return []string{} }
	identity := saved['identity'] or { return []string{} }
	names := saved['parts'] or { return []string{} }
	if identity !is map[string]json2.Any || identity != expected { return []string{} }
	if names !is []json2.Any { return []string{} }
	if names.len == 0 { return []string{} }
	mut paths := []string{}
	for name in names {
		if name !is string { return []string{} }
		path := if os.is_abs_path(name) { name } else { directory + '/' + name }
		if !regular(path) || os.file_size(path) <= 0 || u64(os.file_size(path)) > max_bytes {
			return []string{}
		}
		paths << path
	}
	return paths
}

fn part_name(name string) bool {
	if !name.starts_with('part-') || !name.ends_with('.tar') { return false }
	value := name[5..name.len - 4]
	return value.len >= 3 && value.bytes().all(it.is_digit())
}

pub fn qemu_split(source_path string, directory_path string, max_bytes u64) ![]string {
	if max_bytes < 20480 || max_bytes > 4294967295 {
		return error("--max-bytes must be between 20480 and FAT32's 4 GiB limit")
	}
	source := hosttest.resolve_path(source_path)!
	if !regular(source) { return error('not a regular file: ' + source) }
	directory := absolute(directory_path)
	mkdir_all(directory)!
	mut held_lock := lock_file(directory + '/.lock')!
	defer { held_lock.close() }
	mut identity := source_identity(source)!
	identity['max_bytes'] = max_bytes
	manifest := directory + '/manifest.json'
	mut parts := current_parts(manifest, identity, directory, max_bytes)
	if parts.len == 0 {
		eprintln('==> Splitting ' + os.file_name(source) + ' into uncompressed FAT32 modules...')
		staging := temporary(directory + '/parts', true)!
		defer { hosttest.remove_work_dir(staging) or { eprintln(err) } }
		staged := split_parts(source, staging, max_bytes)!
		new_manifest := staging + '/manifest.json'
		write_json(new_manifest, {
			'identity': json2.Any(identity)
			'parts':    json2.Any(staged.map(json2.Any(os.file_name(it))))
		}, false)!
		for part in staged { replace(part, directory + '/' + os.file_name(part))! }
		replace(new_manifest, manifest)!
		parts = staged.map(directory + '/' + os.file_name(it))
		current := parts.map(os.file_name(it))
		for name in os.ls(directory)! {
			path := directory + '/' + name
			if name !in current && part_name(name) && (regular(path) || os.is_link(path)) {
				os.rm(path)!
			}
		}
	}
	return parts
}

pub fn module_iso(source_path string, output_path string) !bool {
	source := hosttest.resolve_path(source_path)!
	if !regular(source) { return error('not a regular file: ' + source) }
	output := absolute(output_path)
	if source == output { return error('source and ISO output must differ') }
	xorriso := os.find_abs_path_of_executable('xorriso') or { return error('xorriso is required to build the QEMU module ISO') }
	mkdir_all(os.dir(output))!
	manifest := output + '.json'
	mut held_lock := lock_file(os.dir(output) + '/.' + os.file_name(output) + '.lock')!
	defer { held_lock.close() }
	identity := source_identity(source)!
	if regular(output) && os.file_size(output) > os.file_size(source) && cache_matches(manifest, identity, [output]) {
		println(output)
		return false
	}
	eprintln('==> Building ISO9660 QEMU module disk from ' + os.file_name(source) + '...')
	staging := temporary(output, true)!
	defer { hosttest.remove_work_dir(staging) or { eprintln(err) } }
	iso := staging + '/module.iso'
	result := hosttest.capture([xorriso, '-as', 'mkisofs', '-iso-level', '3', '-R', '-r', '-J',
		'-graft-points', '-o', iso, 'boot/initramfs.tar=' + source], '', -1, os.environ())!
	if result.code != 0 { return error('xorriso failed:\n' + result.stderr) }
	if source_identity(source)! != identity {
		return error('QEMU initramfs changed while building the ISO')
	}
	if os.file_size(iso) <= os.file_size(source) {
		return error('QEMU module ISO is smaller than its initramfs')
	}
	new_manifest := staging + '/manifest.json'
	mut sorted := map[string]json2.Any{}
	mut keys := identity.keys()
	keys.sort()
	for key in keys { sorted[key] = identity[key] or { panic('missing identity') } }
	write_json(new_manifest, sorted, false)!
	replace(iso, output)!
	replace(new_manifest, manifest)!
	println(output)
	return true
}
