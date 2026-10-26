// SPDX-License-Identifier: GPL-2.0-or-later
// Selected, stopped input trees; this is not a hostile-rename/openat sandbox.
module winejitstream

import crypto.sha256
import os

#include <sys/stat.h>
#define wine_static_stat stat
#define wine_static_fstat fstat

struct C.wine_static_stat {
	st_mode u32
	st_size i64
}

fn C.wine_static_fstat(int, &C.wine_static_stat) int

pub const static_input_limit = u64(32 * 1024 * 1024)
pub const static_input_triple = 'x86_64-linux-musl'
pub const static_input_version = '14.2.0'

pub struct StaticEntry {
pub:
	source   string
	relative string
	bytes    u64
	digest   string
}

pub struct StaticPlan {
pub:
	headers     string
	library     string
	gcc         string
	entries     []StaticEntry
	directories []string
	bytes       u64
}

fn static_directory(path string) ! {
	info := os.lstat(path) or { return error('static directory lstat: ' + path + ': ' + err.msg()) }
	if info.get_filetype() != .directory || os.real_path(path) != path {
		return error('static directory must be canonical and ordinary: ' + path)
	}
}

pub fn static_require_absent(path string) ! {
	os.lstat(path) or {
		if err.code() == C.ENOENT { return }
		return error('static destination lstat: ' + path + ': ' + err.msg())
	}
	return error('static destination already exists: ' + path)
}

// O_NOFOLLOW applies to the final component. Ancestors are checked separately;
// all selected inputs must remain stopped while these checks and copies run.
fn static_stream(path string, bytes u64, output string) !string {
	fd := C.open(path.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('static no-follow open failed: ' + path) }
	defer { C.close(fd) }
	mut opened := C.wine_static_stat{}
	if C.wine_static_fstat(fd, &opened) != 0 || (opened.st_mode & u32(C.S_IFMT)) != u32(C.S_IFREG)
		|| opened.st_size < 0 || u64(opened.st_size) != bytes {
		return error('static opened file type/size changed: ' + path)
	}
	mut target := -1
	if output != '' {
		target = C.open(output.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, 0o644)
		if target < 0 { return error('static exclusive output open failed: ' + output) }
	}
	defer { if target >= 0 { C.close(target) } }
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	mut sum := []u8{len: sha256.size}
	defer {
		unsafe { buffer.free(); sum.free(); hash.free(); free(hash) }
	}
	mut consumed := u64(0)
	for {
		count := C.read(fd, buffer.data, usize(buffer.len))
		if count < 0 {
			if C.errno == C.EINTR { continue }
			return error('static read failed: ' + path)
		}
		if count == 0 { break }
		if consumed > bytes || u64(count) > bytes - consumed { return error('static input grew: ' + path) }
		consumed += u64(count)
		hash.write(buffer[..count])!
		mut written := 0
		for target >= 0 && written < count {
			n := C.write(target, unsafe { &buffer[written] }, usize(count - written))
			if n < 0 && C.errno == C.EINTR { continue }
			if n <= 0 { return error('static write failed: ' + output) }
			written += n
		}
	}
	if consumed != bytes || C.wine_static_fstat(fd, &opened) != 0 || opened.st_size < 0
		|| u64(opened.st_size) != bytes {
		return error('static input size changed: ' + path)
	}
	hash.checksum_into(mut sum)
	return sum.hex()
}

fn static_entry(source string, relative string) !StaticEntry {
	info := os.lstat(source) or { return error('static file lstat: ' + source + ': ' + err.msg()) }
	if info.get_filetype() != .regular || os.real_path(source) != source {
		return error('static input must be canonical and ordinary: ' + source)
	}
	if info.size > static_input_limit { return error('static input exceeds 32 MiB: ' + source) }
	return StaticEntry{source: source, relative: relative, bytes: info.size,
		digest: static_stream(source, info.size, '')!}
}

fn static_headers(path string, relative string, top bool, mut files []StaticEntry, mut dirs []string) ! {
	static_directory(path)!
	mut names := os.ls(path)!
	names.sort()
	for name in names {
		if top && name == 'c++' { continue }
		if files.len + dirs.len >= 5000 { return error('static selection exceeds 5000 entries') }
		entry := path + '/' + name
		rel := relative + '/' + name
		info := os.lstat(entry)!
		if info.get_filetype() == .directory {
			dirs << rel
			static_headers(entry, rel, false, mut files, mut dirs)!
		} else {
			files << static_entry(entry, rel)!
		}
	}
}

pub fn static_input_plan(headers string, library string, gcc string) !StaticPlan {
	for path in [headers, library, gcc] { static_directory(path)! }
	mut dirs := [static_input_triple, static_input_triple + '/include', static_input_triple + '/lib',
		'lib', 'lib/gcc', 'lib/gcc/' + static_input_triple,
		'lib/gcc/' + static_input_triple + '/' + static_input_version]
	mut entries := []StaticEntry{}
	static_headers(headers, static_input_triple + '/include', true, mut entries, mut dirs)!
	if entries.len == 0 { return error('empty static C headers') }
	for name in ['crt1.o', 'crti.o', 'crtn.o', 'libc.a', 'libm.a', 'libpthread.a'] {
		entries << static_entry(library + '/' + name, static_input_triple + '/lib/' + name)!
	}
	for name in ['crtbegin.o', 'crtbeginT.o', 'crtend.o', 'libgcc.a', 'libgcc_eh.a'] {
		entries << static_entry(gcc + '/' + name,
			'lib/gcc/' + static_input_triple + '/' + static_input_version + '/' + name)!
	}
	entries.sort(a.relative < b.relative)
	dirs.sort()
	mut total := u64(0)
	for entry in entries {
		if entry.bytes > static_input_limit - total { return error('static selected bytes exceed 32 MiB') }
		total += entry.bytes
	}
	return StaticPlan{headers: headers, library: library, gcc: gcc, entries: entries, directories: dirs, bytes: total}
}

pub fn static_input_recheck(plan StaticPlan) ! {
	if static_input_plan(plan.headers, plan.library, plan.gcc)! != plan {
		return error('static selected source inventory changed')
	}
}

pub fn static_budget(existing u64, selected u64, reserved u64) !u64 {
	if existing > static_input_limit || selected > static_input_limit - existing
		|| reserved > static_input_limit - existing - selected {
		return error('static composition would exceed cumulative 32 MiB')
	}
	return existing + selected + reserved
}

// Account for known fixed receipts separately from the retained dynamic-output
// reserve. Every addition is checked before the next, avoiding u64 wraparound.
pub fn static_receipt_projection(existing u64, selected u64, before u64, after u64, reserved u64) !u64 {
	with_inputs := static_budget(existing, selected, 0)!
	with_before := static_budget(with_inputs, before, 0)!
	return static_budget(with_before, after, reserved)
}

pub fn static_receipt_check(value string, bound u64) ! {
	if u64(value.len) > bound { return error('static receipt exceeds admitted length') }
}

fn static_output_walk(root string, relative string, mut files []StaticEntry, mut dirs []string) ! {
	static_directory(root)!
	mut names := os.ls(root)!
	names.sort()
	for name in names {
		if files.len + dirs.len >= 5000 { return error('static output exceeds 5000 entries') }
		path := root + '/' + name
		rel := if relative == '' { name } else { relative + '/' + name }
		if (os.lstat(path)!).get_filetype() == .directory {
			dirs << rel
			static_output_walk(path, rel, mut files, mut dirs)!
		} else { files << static_entry(path, rel)! }
	}
}

pub fn static_output_verify(plan StaticPlan, destination string) ! {
	mut files := []StaticEntry{}
	mut dirs := []string{}
	static_output_walk(destination, '', mut files, mut dirs)!
	files.sort(a.relative < b.relative)
	dirs.sort()
	if dirs != plan.directories || files.len != plan.entries.len { return error('static output entry set changed') }
	for i, file in files {
		expected := plan.entries[i]
		if file.relative != expected.relative || file.bytes != expected.bytes || file.digest != expected.digest {
			return error('static output bytes changed: ' + file.relative)
		}
	}
}

pub fn static_input_copy(plan StaticPlan, destination string, existing u64, reserved u64, minimum_free_kib u64) ! {
	static_budget(existing, plan.bytes, reserved)!
	static_require_absent(destination)!
	static_directory(os.dir(destination))!
	for source in [plan.headers, plan.library, plan.gcc] {
		if destination == source || destination.starts_with(source + '/') || source.starts_with(destination + '/') {
			return error('static source and destination overlap')
		}
	}
	static_input_recheck(plan)!
	native_require_free(os.dir(destination), minimum_free_kib)!
	os.mkdir(destination)!
	for relative in plan.directories { os.mkdir(destination + '/' + relative)! }
	for entry in plan.entries {
		native_require_free(destination, minimum_free_kib)!
		if static_stream(entry.source, entry.bytes, destination + '/' + entry.relative)! != entry.digest {
			return error('static input changed while copying: ' + entry.source)
		}
	}
	static_output_verify(plan, destination)!
	static_input_recheck(plan)!
}

// Count each path conservatively, including hard-link duplicates and literal
// symlink bytes in compiler scratch. Never traverse a link or remove evidence.
pub fn static_state_bytes(path string) !u64 {
	mut count := StaticCount{}
	return static_state_walk(path, mut count)
}

pub fn static_host_states_bytes(base string) !u64 {
	mut total := u64(0)
	mut count := 0
	for name in os.ls(base)! {
		if !name.starts_with('wine-jit-stream-static-inputs-host-') { continue }
		count++
		if count > 32 { return error('too many selected static host states') }
		path := base + '/' + name
		static_directory(path)!
		bytes := static_state_bytes(path)!
		static_budget(total, bytes, 0)!
		total += bytes
	}
	return total
}

struct StaticCount {
mut:
	entries int
}

fn static_state_walk(path string, mut count StaticCount) !u64 {
	count.entries++
	if count.entries > 30000 { return error('static state exceeds 30000 entries') }
	info := os.lstat(path)!
	if info.get_filetype() in [.regular, .symbolic_link] { return info.size }
	if info.get_filetype() != .directory { return error('unsupported static state entry: ' + path) }
	mut total := u64(0)
	for name in os.ls(path)! {
		bytes := static_state_walk(path + '/' + name, mut count)!
		if bytes > static_input_limit - total { return error('static state exceeds 32 MiB') }
		total += bytes
	}
	return total
}

// Clang -### describes a recipe, not a completed link. Inspect actual existing
// include/library candidates and every explicit startup object in that recipe.
pub fn static_driver_recipe_check(text string, destination string, resource string, original string) ![]string {
	if text.contains(original + '/') { return error('Clang recipe includes original cross installation') }
	words := text.replace('"', '').fields()
	mut candidates := []string{}
	mut startup := []string{}
	for i, word in words {
		mut candidate := ''
		flags := ['-internal-externc-isystem', '-internal-isystem', '-internal-iframework',
			'-cxx-isystem', '-objc-isystem', '-c-isystem', '-isystem', '-iquote', '-idirafter',
			'-iframework', '-I', '-L', '-F']
		if word in flags {
			if i + 1 >= words.len { return error('missing Clang include candidate') }
			candidate = words[i + 1]
		} else {
			for flag in flags {
				if word.starts_with(flag) && word.len > flag.len {
					candidate = word[flag.len..].trim_left('=')
					if candidate == '' { return error('empty Clang search candidate') }
					break
				}
			}
		}
		if candidate != '' {
			if !candidate.starts_with('/') { return error('relative Clang search candidate: ' + candidate) }
			if !os.exists(candidate) {
				if os.is_link(candidate) { return error('dangling Clang search candidate: ' + candidate) }
				continue
			}
			canonical := os.real_path(candidate)
			if !canonical.starts_with(destination + '/') && !canonical.starts_with(os.real_path(resource) + '/') {
				return error('existing Clang search candidate escapes selected roots: ' + candidate)
			}
			candidates << canonical
		}
		base := os.base(word)
		if word.starts_with('/') && base.ends_with('.a') {
			canonical := os.real_path(word)
			if !canonical.starts_with(destination + '/') || (os.lstat(canonical)!).get_filetype() != .regular {
				return error('Clang archive escapes selected root: ' + word)
			}
		}
		if word.starts_with('/') && base.ends_with('.o') && (base.starts_with('crt') || base.starts_with('Scrt')) {
			canonical := os.real_path(word)
			if !canonical.starts_with(destination + '/') || (os.lstat(canonical)!).get_filetype() != .regular {
				return error('Clang startup object escapes selected root: ' + word)
			}
			startup << os.base(word)
		}
	}
	for name in ['crt1.o', 'crti.o', 'crtn.o', 'crtbeginT.o', 'crtend.o'] {
		if name !in startup { return error('missing explicit Clang startup object: ' + name) }
	}
	for suffix in ['/x86_64-linux-musl/include', '/x86_64-linux-musl/lib', '/lib/gcc/x86_64-linux-musl/14.2.0'] {
		if destination + suffix !in candidates { return error('missing existing relocated search candidate: ' + suffix) }
	}
	return candidates
}
