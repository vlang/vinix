// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Only the fixed Linux publisher profiles use this policy. Names/paths borrow
// the packed manifest; object is its content-addressed inventory filename.
struct ProfileElfImage {
	space string
	path string
	object string
	kind string
}

struct ProfileElfLoad {
	offset u64
	address u64
	bytes u64
}

// Dynamic names borrow strings, which owns the only backing allocation.
struct ProfileDynamic {
mut:
	strings []u8
	needed []u64
	soname u64
	has_soname bool
}

fn (mut info ProfileDynamic) close() {
	unsafe { info.strings.free(); (&array(&info.needed)).free() }
	info = ProfileDynamic{}
}

fn (info ProfileDynamic) name(offset u64) !string {
	if offset >= u64(info.strings.len) { return error('ELF closure string offset is outside DT_STRTAB') }
	mut end := int(offset)
	for end < info.strings.len && info.strings[end] != 0 { end++ }
	if end == info.strings.len || end - int(offset) > 4096 {
		return error('ELF closure needs bounded NUL-terminated dynamic names')
	}
	return unsafe { tos(&u8(info.strings.data) + int(offset), end - int(offset)) }
}

fn profile_library_name(name string) bool {
	if name.len == 0 || name.len > 255 || name == '.' || name == '..' { return false }
	for c in name {
		if !((c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`)
			|| c == `.` || c == `_` || c == `-` || c == `+`) { return false }
	}
	return true
}

// A runpath may only repeat the explicit library directories supplied by
// linux-runner. Never consult the publisher host or the guest's system paths.
fn profile_origin_path(path string, image string) bool {
	mut tail := ''
	if path.starts_with('$ORIGIN') { tail = unsafe { tos(path.str + 7, path.len - 7) } }
	else if path.starts_with('\${ORIGIN}') { tail = unsafe { tos(path.str + 9, path.len - 9) } }
	else { return false }
	if image.starts_with('bin/') { return tail == '/../lib' || tail == '/../usr/lib' }
	if image.starts_with('lib/') { return tail == '' || tail == '/../lib' || tail == '/../usr/lib' }
	if image.starts_with('usr/lib/') { return tail == '' || tail == '/../../lib' || tail == '/../lib' }
	return false
}

fn profile_runpath(value string, image string) ! {
	mut start := 0
	for i in 0 .. value.len + 1 {
		if i != value.len && value[i] != `:` { continue }
		part := unsafe { tos(value.str + start, i - start) }
		if !profile_origin_path(part, image) {
			return error('ELF closure refuses a search path outside the packaged library directories')
		}
		start = i + 1
	}
}

// profile_elf runs first, so target and segment structure are already checked.
// Independently bound and map dynamic addresses through file-backed PT_LOADs;
// section headers are optional and are never used to locate runtime metadata.
fn profile_dynamic(root int, image ProfileElfImage) !ProfileDynamic {
	node := import_node(root, image.object)!
	defer { C.close(node.fd) }
	mut header := []u8{len: 64}; mut program := []u8{len: 56}; mut entry := []u8{len: 16}
	defer { unsafe { header.free(); program.free(); entry.free() } }
	profile_read_at(node.fd, 0, mut header)!
	phoff := profile_le(header[32..40]); count := profile_le(header[56..58])
	if count == 0 || count > 1024 || phoff > node.bytes || count * 56 > node.bytes - phoff {
		return error('ELF closure has invalid program headers')
	}
	mut loads := []ProfileElfLoad{cap: int(count)}
	defer { unsafe { (&array(&loads)).free() } }
	mut dynamic_offset := u64(0); mut dynamic_address := u64(0); mut dynamic_bytes := u64(0); mut dynamic := false
	for i in 0 .. int(count) {
		profile_read_at(node.fd, phoff + u64(i) * 56, mut program)!
		type_ := profile_le(program[..4]); offset := profile_le(program[8..16])
		address := profile_le(program[16..24]); bytes := profile_le(program[32..40])
		if type_ == 1 {
			if offset > node.bytes || bytes > node.bytes - offset || bytes > ~u64(0) - address {
				return error('ELF closure has an invalid file-backed load range')
			}
			loads << ProfileElfLoad{offset, address, bytes}
		}
		if type_ != 2 { continue }
		if dynamic || bytes < 16 || bytes > 65536 || bytes % 16 != 0 || offset > node.bytes || bytes > node.bytes - offset {
			return error('ELF closure needs one bounded PT_DYNAMIC table')
		}
		dynamic = true; dynamic_offset = offset; dynamic_address = address; dynamic_bytes = bytes
	}
	if image.kind == 'static' {
		if dynamic { return error('ELF closure static runner contains PT_DYNAMIC') }
		return ProfileDynamic{}
	}
	if !dynamic { return error('ELF closure dynamic image has no PT_DYNAMIC') }
	mut dynamic_mapped := false
	for load in loads {
		if dynamic_address < load.address || dynamic_address - load.address > load.bytes
			|| dynamic_bytes > load.bytes - (dynamic_address - load.address) { continue }
		if load.offset + (dynamic_address - load.address) != dynamic_offset {
			return error('ELF closure PT_DYNAMIC has ambiguous load mappings')
		}
		dynamic_mapped = true
	}
	if !dynamic_mapped { return error('ELF closure PT_DYNAMIC is not file-backed') }
	mut info := ProfileDynamic{needed: []u64{cap: 256}}
	mut transferred := false
	defer { if !transferred { info.close() } }
	mut strtab := u64(0); mut strsz := u64(0); mut has_strtab := false; mut has_strsz := false
	mut rpath := u64(0); mut runpath := u64(0); mut has_rpath := false; mut has_runpath := false
	mut terminated := false
	for i in 0 .. int(dynamic_bytes / 16) {
		profile_read_at(node.fd, dynamic_offset + u64(i) * 16, mut entry)!
		tag := profile_le(entry[..8]); value := profile_le(entry[8..16])
		if tag == 0 { terminated = true; break }
		match tag {
			1 { if info.needed.len == 256 { return error('ELF closure has too many DT_NEEDED entries') }; info.needed << value }
			5 { if has_strtab { return error('ELF closure has duplicate DT_STRTAB') }; has_strtab = true; strtab = value }
			10 { if has_strsz { return error('ELF closure has duplicate DT_STRSZ') }; has_strsz = true; strsz = value }
			14 { if info.has_soname { return error('ELF closure has duplicate DT_SONAME') }; info.has_soname = true; info.soname = value }
			15 { if has_rpath { return error('ELF closure has duplicate DT_RPATH') }; has_rpath = true; rpath = value }
			29 { if has_runpath { return error('ELF closure has duplicate DT_RUNPATH') }; has_runpath = true; runpath = value }
			0x7ffffffd, 0x7fffffff { return error('ELF closure does not support auxiliary/filter dependencies') }
			else {}
		}
	}
	if !terminated || !has_strtab || !has_strsz || strsz == 0 || strsz > 4 * 1024 * 1024 {
		return error('ELF closure needs terminated dynamic metadata and a bounded string table')
	}
	mut string_offset := u64(0); mut mapped := false
	for load in loads {
		if strtab < load.address || strtab - load.address > load.bytes || strsz > load.bytes - (strtab - load.address) { continue }
		offset := load.offset + (strtab - load.address)
		if offset > node.bytes || strsz > node.bytes - offset { return error('ELF closure string table is outside the file') }
		if mapped && string_offset != offset { return error('ELF closure string table has ambiguous load mappings') }
		mapped = true; string_offset = offset
	}
	if !mapped { return error('ELF closure string table is not file-backed') }
	info.strings = []u8{len: int(strsz)}
	profile_read_at(node.fd, string_offset, mut info.strings)!
	if info.strings[0] != 0 { return error('ELF closure string table lacks its initial NUL') }
	for offset in info.needed {
		name := info.name(offset)!
		if !profile_library_name(name) { return error('ELF closure DT_NEEDED must be a library basename') }
	}
	if info.has_soname && !profile_library_name(info.name(info.soname)!) { return error('ELF closure has an invalid DT_SONAME') }
	if has_rpath { profile_runpath(info.name(rpath)!, image.path)! }
	if has_runpath { profile_runpath(info.name(runpath)!, image.path)! }
	transferred = true
	return info
}

fn profile_library_path(path string) bool {
	mut start := 0
	if path.starts_with('lib/') { start = 4 } else if path.starts_with('usr/lib/') { start = 8 } else { return false }
	for i in start .. path.len { if path[i] == `/` { return false } }
	return start < path.len
}

fn profile_basename(path string) string {
	mut start := 0
	for i, c in path { if c == `/` { start = i + 1 } }
	return unsafe { tos(path.str + start, path.len - start) }
}

// images is the exact app/runtime payload seen by one launch. Ambiguity is
// intentionally stricter than musl's first-match order: the publisher must not
// ship competing different objects for the same needed name. Identical copied
// aliases remain legal, including the musl loader/libc pair.
fn profile_elf_closure(root int, images []ProfileElfImage, architecture string) ! {
	if images.len == 0 || images.len > 128 { return error('ELF closure image inventory is empty or too large') }
	mut metadata := []ProfileDynamic{cap: images.len}
	defer { for mut info in metadata { info.close() }; unsafe { (&array(&metadata)).free() } }
	mut libc := -1; mut loader := -1
	mut string_bytes := 0
	loader_name := 'lib/ld-musl-' + architecture + '.so.1'
	defer { unsafe { loader_name.free() } }
	for i, image in images {
		profile_elf(root, image.object, architecture, image.kind, false)!
		mut info := profile_dynamic(root, image)!
		string_bytes += info.strings.len
		if string_bytes > 16 * 1024 * 1024 { info.close(); return error('ELF closure exceeds the total dynamic string budget') }
		unsafe { metadata.push_many(&info, 1) }
		if image.space == 'runtime' && image.path == 'lib/libc.so' { libc = i }
		if image.space == 'runtime' && image.path == loader_name { loader = i }
	}
	if libc < 0 || loader < 0 || images[libc].object != images[loader].object {
		return error('ELF closure needs the exact packaged musl loader/libc object pair')
	}
	for i, info in metadata {
		for offset in info.needed {
			name := info.name(offset)!
			mut found := -1
			for j, candidate in images {
				if !profile_library_path(candidate.path) { continue }
				if profile_basename(candidate.path) != name { continue }
				if found >= 0 && images[found].object != candidate.object {
					return error('ELF closure has ambiguous library ' + name)
				}
				found = j
			}
			if found < 0 { return error('ELF closure missing library ' + name + ' required by ' + images[i].path) }
			// A loaded object's SONAME must not introduce another identity for a
			// different object that this launch will resolve by its filename.
			for j, candidate in metadata {
				if j == found || !candidate.has_soname || images[j].object == images[found].object { continue }
				if candidate.name(candidate.soname)! == name { return error('ELF closure has ambiguous SONAME ' + name) }
			}
		}
	}
}

fn profile_linux_closures(root int, packages []CatalogImport, runtime_id string) ! {
	for app in packages {
		p := app.recipe.manifest
		if p.kind != 'linux' || p.runtime != runtime_id { continue }
		mut images := []ProfileElfImage{cap: 128}
		defer { unsafe { (&array(&images)).free() } }
		for item in packages {
			q := item.recipe.manifest
			if q.architecture != p.architecture || (q.id != p.id && q.id != runtime_id) { continue }
			for file in q.files {
				if !file.executable || (!file.path.starts_with('bin/') && !profile_library_path(file.path)) { continue }
				if images.len == 128 { return error('ELF closure image inventory is too large') }
				images << ProfileElfImage{space: if q.id == p.id { 'app' } else { 'runtime' },
					path: file.path, object: file.sha256,
					kind: if profile_library_path(file.path) { 'shared' } else if q.id == p.id { 'pie' } else { 'static' }}
			}
		}
		profile_elf_closure(root, images, p.architecture)!
	}
}
