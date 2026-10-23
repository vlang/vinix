// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import crypto.sha256
import encoding.binary
import json2
import os

struct PeProofInput {
	kind string
	target string
	sha256 string
}

struct PeProofRecord {
	format int
	scope string
	compiler string
	mingw_root string
	source string
	environment map[string]string
	inputs map[string]PeProofInput
mut:
	outputs map[string]string
	commands [][]string
}

fn pe_encode[T](value T) string {
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	json2.encode_append(value, mut bytes)
	return bytes.bytestr()
}

// This is an owned local build receipt, not publisher authentication or source
// redistribution admission. Every returned artifact uses an absolute path.
pub struct LocalPeProof {
pub:
	executable string
	artifacts map[string]string
mut:
	closed bool
}

pub fn (mut proof LocalPeProof) close() {
	if proof.closed { return }
	unsafe {
		proof.executable.free()
		for _, value in proof.artifacts { value.free() }
		proof.artifacts.free()
	}
	// Keep the retired map behind the closed guard: constructing an empty map
	// here would itself allocate a fresh owner on every close.
	proof = LocalPeProof{...proof, executable: '', closed: true}
}

fn close_pe_inputs(inputs map[string]PeProofInput) {
	unsafe {
		for _, value in inputs { value.kind.free(); value.target.free(); value.sha256.free() }
		inputs.free()
	}
}

fn close_pe_record(record PeProofRecord) {
	unsafe {
		record.scope.free(); record.compiler.free(); record.mingw_root.free(); record.source.free()
		for _, value in record.environment { value.free() }
		record.environment.free()
		close_pe_inputs(record.inputs)
		for _, value in record.outputs { value.free() }
		record.outputs.free()
		for command in record.commands { command.free() }
		(&array(&record.commands)).free()
	}
}

fn pe_digest(path string) !string {
	fd := C.open(path.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC)
	if fd < 0 { return error('Win64 proof input is missing or linked') }
	defer { C.close(fd) }
	mut before := C.stat{}
	if C.fstat(fd, unsafe { &before }) != 0 || u32(before.st_mode) & 0o170000 != 0o100000 {
		return error('Win64 proof input is not an ordinary file')
	}
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	mut sum := []u8{len: 32}
	defer { unsafe { buffer.free(); sum.free(); hash.free(); free(hash) } }
	for {
		count := C.read(fd, buffer.data, usize(buffer.len))
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('cannot read Win64 proof input') }
		if count == 0 { break }
		hash.write(buffer[..int(count)])!
	}
	mut after := C.stat{}
	if C.fstat(fd, unsafe { &after }) != 0 || before.st_dev != after.st_dev
		|| before.st_ino != after.st_ino || before.st_size != after.st_size
		|| before.st_mtime != after.st_mtime || before.st_ctime != after.st_ctime {
		return error('Win64 proof input changed while hashing')
	}
	hash.checksum_into(mut sum)
	return sum.hex()
}

fn pe_real_path(path string) !string {
	if path.contains('\x00') || path.len >= 4096 { return error('invalid Win64 proof input path') }
	resolved := C.realpath(path.str, unsafe { nil })
	if resolved == unsafe { nil } {
		return error('cannot resolve Win64 proof input path')
	}
	defer { C.free(resolved) }
	return unsafe { tos_clone(&u8(resolved)) }
}

fn pe_within(path string, root string) bool {
	return path == root || (path.len > root.len && path.starts_with(root) && path[root.len] == `/`)
}

fn pe_inventory(path string, root string, depth int, mut inputs map[string]PeProofInput) ! {
	if depth > 256 || inputs.len >= 100000 { return error('Win64 proof input inventory exceeds its bound') }
	if path in inputs { return error('overlapping Win64 proof input trees') }
	mut info := C.stat{}
	if C.lstat(path.str, unsafe { &info }) != 0 { return error('missing Win64 proof input') }
	mode := u32(info.st_mode) & 0o170000
	if mode == 0o120000 {
		target := pe_real_path(path)!
		defer { unsafe { target.free() } }
		if !pe_within(target, root) {
			return error('Win64 proof input link is dangling or escapes its tree')
		}
		inputs[path] = PeProofInput{kind: 'symlink', target: os.readlink(path)!}
		return
	}
	if mode == 0o040000 {
		inputs[path] = PeProofInput{kind: 'directory'}
		fd := C.open(path.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_DIRECTORY | C.O_CLOEXEC)
		if fd < 0 { return error('cannot open Win64 proof input directory') }
		stream := C.fdopendir(fd)
		if stream == unsafe { nil } { C.close(fd); return error('cannot enumerate Win64 proof input directory') }
		defer { C.closedir(stream) }
		for {
			C.errno = 0
			entry := C.readdir(stream)
			if entry == unsafe { nil } {
				if C.errno != 0 { return error('cannot finish Win64 proof input inventory') }
				break
			}
			name := unsafe { tos(&u8(&entry.d_name[0]), int(C.strlen(&char(&entry.d_name[0])))) }
			if name == '.' || name == '..' { continue }
			next := path + '/' + name
			pe_inventory(next, root, depth + 1, mut inputs) or { unsafe { next.free() }; return err }
			unsafe { next.free() }
		}
		return
	}
	if mode != 0o100000 { return error('Win64 proof input is not an ordinary file') }
	inputs[path] = PeProofInput{kind: 'file', sha256: pe_digest(path)!}
}

fn pe_header(text string) ! {
	bytes := text.bytes()
	defer { unsafe { bytes.free() } }
	if bytes.len < 256 || bytes[0] != `M` || bytes[1] != `Z` { return error('Win64 proof output lacks a DOS header') }
	header := u64(binary.little_endian_u32(bytes[60..64]))
	if header > u64(bytes.len) - 94 { return error('Win64 proof PE header is outside its file') }
	start := int(header)
	if bytes[start] != `P` || bytes[start + 1] != `E` || bytes[start + 2] != 0 || bytes[start + 3] != 0
		|| binary.little_endian_u16(bytes[start + 4..start + 6]) != 0x8664
		|| binary.little_endian_u16(bytes[start + 20..start + 22]) < 70
		|| binary.little_endian_u16(bytes[start + 22..start + 24]) & 0x2002 != 2
		|| binary.little_endian_u16(bytes[start + 24..start + 26]) != 0x20b
		|| binary.little_endian_u16(bytes[start + 92..start + 94]) != 3 {
		return error('Win64 proof output is not an executable AMD64 PE32+ console program')
	}
}

// Successful compilers can produce an empty diagnostic log. Unlike source
// notices, receipt outputs therefore permit zero bytes; descriptor, size and
// identity checks remain the same, including a final EOF check.
fn pe_output_bytes(directory int, name string) !string {
	fd := C.openat(directory, name.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC)
	if fd < 0 { return error('Win64 proof output is missing or linked') }
	defer { C.close(fd) }
	mut before := C.stat{}
	if C.fstat(fd, unsafe { &before }) != 0 || u32(before.st_mode) & 0o170000 != 0o100000
		|| before.st_nlink != 1 || before.st_size < 0 || before.st_size > 16 * 1024 * 1024 {
		return error('Win64 proof output needs a bounded ordinary single-link file')
	}
	mut bytes := []u8{len: int(before.st_size)}
	defer { unsafe { bytes.free() } }
	mut count := 0
	for count < bytes.len {
		n := C.read(fd, unsafe { &bytes[count] }, usize(bytes.len - count))
		if n < 0 && C.errno == C.EINTR { continue }
		if n <= 0 { return error('Win64 proof output is incomplete') }
		count += int(n)
	}
	mut sentinel := u8(0)
	mut after := C.stat{}
	if C.read(fd, unsafe { &sentinel }, 1) != 0 || C.fstat(fd, unsafe { &after }) != 0
		|| before.st_dev != after.st_dev || before.st_ino != after.st_ino || before.st_size != after.st_size
		|| before.st_mtime != after.st_mtime || before.st_ctime != after.st_ctime {
		return error('Win64 proof output changed while reading')
	}
	return bytes.bytestr()
}

// Only exact canonical receipts emitted by wine-pe-check are accepted. Reencode
// equality rejects omitted, duplicate, unknown and coerced JSON fields as well
// as noncanonical spellings; this is deliberately not a general JSON interface.
pub fn admit_local_pe_proof(directory string, program_source string, producer_source string) !LocalPeProof {
	root := pe_real_path(directory)!
	defer { unsafe { root.free() } }
	fd := absolute_directory(root)!
	defer { C.close(fd) }
	mut captured := C.stat{}
	if C.fstat(fd, unsafe { &captured }) != 0 { return error('cannot capture Win64 proof directory') }
	text := source_offer_bytes(fd, 'proof.json', 16 * 1024 * 1024)!
	defer { unsafe { text.free() } }
	record := pe_decode(text)!
	defer { close_pe_record(record) }
	encoded := pe_encode(record)
	canonical := encoded + '\n'
	defer { unsafe { encoded.free(); canonical.free() } }
	if text != canonical || record.format != 1
		|| record.scope != 'local real Win64 probe producer; input pins are not a hermetic build or a Wine execution result'
		|| record.source != program_source || !os.is_abs_path(record.compiler) || !os.is_abs_path(record.mingw_root)
		|| record.inputs.len < 8 || record.inputs.len > 100000 {
		return error('Win64 proof schema, scope or selected source differs')
	}
	for path in [record.compiler, record.mingw_root]! {
		resolved := pe_real_path(path)!
		defer { unsafe { resolved.free() } }
		if path != resolved { return error('Win64 proof requires canonical input paths') }
	}
	vroot := os.dir(record.compiler)
	defer { unsafe { vroot.free() } }
	roots := [vroot + '/vlib', vroot + '/thirdparty', record.mingw_root]
	defer { unsafe { roots[0].free(); roots[1].free(); (&array(&roots)).free() } }
	mut observed := map[string]PeProofInput{}
	defer { close_pe_inputs(observed) }
	for index, path in roots {
		inside := pe_within(root, path) || pe_within(path, root)
		if !os.is_abs_path(path) || inside { return error('invalid Win64 proof toolchain tree') }
		for prior in roots[..index] {
			if pe_within(path, prior) || pe_within(prior, path) { return error('overlapping Win64 proof toolchain roots') }
		}
		mut info := C.stat{}
		if C.lstat(path.str, unsafe { &info }) != 0 || u32(info.st_mode) & 0o170000 != 0o040000 {
			return error('Win64 proof requires ordinary toolchain roots')
		}
		pe_inventory(path, path, 0, mut observed)!
	}
	mut files := 0
	mut compiler_seen := false
	mut source_seen := false
	mut producer_seen := false
	for path, value in record.inputs {
		defer { unsafe { path.free() } }
		if pe_within(path, root) { return error('Win64 proof input overlaps its output directory') }
		if path in observed { continue }
		if !os.is_abs_path(path) || value.kind != 'file' || value.target != '' { return error('invalid Win64 proof standalone input') }
		resolved := pe_real_path(path)!
		defer { unsafe { resolved.free() } }
		if path != resolved { return error('Win64 proof standalone input path is not canonical') }
		files++
		compiler_seen = compiler_seen || path == record.compiler
		source_seen = source_seen || path == program_source
		producer_seen = producer_seen || path == producer_source
		observed[path] = PeProofInput{kind: 'file', sha256: pe_digest(path)!}
	}
	mut inventory_same := observed.len == record.inputs.len
	for path, value in observed {
		defer { unsafe { path.free() } }
		other := record.inputs[path] or { inventory_same = false; continue }
		if value.kind != other.kind || value.target != other.target || value.sha256 != other.sha256 { inventory_same = false }
	}
	if files != 4 || !compiler_seen || !source_seen || !producer_seen || !inventory_same {
		return error('Win64 proof complete input inventory differs')
	}
	env_path := record.mingw_root + '/bin:/usr/bin:/bin'
	env_home := root + '/home'
	env_tmp := root + '/tmp'
	env_modules := root + '/modules'
	defer { unsafe { env_path.free(); env_home.free(); env_tmp.free(); env_modules.free() } }
	expected_env := {
		'PATH': env_path
		'HOME': env_home, 'TMPDIR': env_tmp, 'VMODULES': env_modules
		'LANG': 'C', 'LC_ALL': 'C', 'TZ': 'UTC', 'SOURCE_DATE_EPOCH': '0'
		'VEXE': record.compiler, 'V_MACOS_V3_CALLER_VEXE': record.compiler
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0'
		'V_MACOS_V3_NO_FALLBACK': '1', 'V_C_ERROR_BUG_REPORT_DISABLED': '1'
	}
	defer { unsafe { expected_env.free() } }
	if record.environment != expected_env { return error('Win64 proof build environment differs') }
	cfile := root + '/program.c'
	pe := root + '/program.exe'
	copy_source := root + '/program.v'
	gcc := record.mingw_root + '/bin/x86_64-w64-mingw32-gcc'
	link_map := '-Wl,-Map,' + root + '/program.map'
	core := vroot + '/vlib/builtin/core_windows.c'
	objdump := record.mingw_root + '/bin/x86_64-w64-mingw32-objdump'
	defer { unsafe { cfile.free(); pe.free(); copy_source.free(); gcc.free(); link_map.free(); core.free(); objdump.free() } }
	expected_commands := [
		[record.compiler, '-backend', 'c', '-prod', '-os', 'windows', '-arch', 'amd64', '-gc', 'none',
			'-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-path', '@vlib', '-o', cfile, copy_source],
		[gcc, '-v', '-O2', '-w', '-static', '-municode', '-Wl,--no-insert-timestamp',
			link_map, '-o', pe, cfile, core, '-lws2_32', '-ladvapi32', '-lshell32'],
		[objdump, '-p', pe],
	]
	defer { unsafe {
		for command in expected_commands { (&array(&command)).free() }
		(&array(&expected_commands)).free()
	} }
	if record.commands != expected_commands { return error('Win64 proof literal producer commands differ') }
	names := ['program.v', 'producer.v', 'program.c', 'program.exe', 'program.map', 'environment.json',
		'inputs-before-build.json', 'inputs-verified.json', 'v.log', 'v.log.argv.json', 'cc.log', 'cc.log.argv.json', 'pe-headers.log', 'pe-headers.log.argv.json']!
	if record.outputs.len != names.len { return error('Win64 proof output inventory differs') }
	mut artifacts := map[string]string{}
	mut accepted := false
	defer { if !accepted { unsafe { for _, value in artifacts { value.free() }; artifacts.free() } } }
	for name in names {
		path := root + '/' + name
		bytes := pe_output_bytes(fd, name) or { unsafe { path.free() }; return err }
		if name == 'program.exe' {
			pe_header(bytes) or { unsafe { bytes.free(); path.free() }; return err }
		}
		if name == 'environment.json' {
			value := pe_encode(record.environment)
			canonical_value := value + '\n'
			same := bytes == canonical_value
			unsafe { value.free(); canonical_value.free() }
			if !same { unsafe { bytes.free(); path.free() }; return error('Win64 proof retained environment differs') }
		}
		for index, log in ['v.log.argv.json', 'cc.log.argv.json', 'pe-headers.log.argv.json']! {
			if name != log { continue }
			value := pe_encode(record.commands[index])
			canonical_value := value + '\n'
			same := bytes == canonical_value
			unsafe { value.free(); canonical_value.free() }
			if !same { unsafe { bytes.free(); path.free() }; return error('Win64 proof retained command differs') }
		}
		actual := local_source_digest(bytes)
		unsafe { bytes.free() }
		if name !in record.outputs || actual != record.outputs[name] {
			unsafe { path.free(); actual.free() }
			return error('Win64 proof retained output digest differs')
		}
		artifacts[path] = actual
		unsafe { path.free() }
	}
	if record.outputs['program.v'] != record.inputs[program_source].sha256
		|| record.outputs['producer.v'] != record.inputs[producer_source].sha256 {
		return error('Win64 proof retained program or producer source differs')
	}
	inventory := pe_encode(record.inputs)
	inventory_text := inventory + '\n'
	defer { unsafe { inventory.free(); inventory_text.free() } }
	for name in ['inputs-before-build.json', 'inputs-verified.json']! {
		bytes := source_offer_bytes(fd, name, 16 * 1024 * 1024)!
		defer { unsafe { bytes.free() } }
		if bytes != inventory_text { return error('Win64 proof before/after input inventory differs') }
	}
	for path, input in record.inputs {
		defer { unsafe { path.free() } }
		if input.kind == 'file' { artifacts[path] = input.sha256.clone() }
	}
	check := absolute_directory(root)!
	defer { C.close(check) }
	mut current := C.stat{}
	if C.fstat(check, unsafe { &current }) != 0 || captured.st_dev != current.st_dev || captured.st_ino != current.st_ino {
		return error('Win64 proof directory was replaced')
	}
	repeated := source_offer_bytes(fd, 'proof.json', 16 * 1024 * 1024)!
	defer { unsafe { repeated.free() } }
	if repeated != text { return error('Win64 proof changed during admission') }
	proof_path := root + '/proof.json'
	defer { unsafe { proof_path.free() } }
	artifacts[proof_path] = local_source_digest(text)
	accepted = true
	return LocalPeProof{executable: pe.clone(), artifacts: artifacts}
}
