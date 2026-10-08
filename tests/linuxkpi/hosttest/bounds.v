// SPDX-License-Identifier: GPL-2.0-or-later
// Compiler-derived bounds with repeated input checks and atomic publication.
module hosttest

import os
import json2
import math.big
import encoding.utf8

#include <sys/stat.h>
#include <unistd.h>

fn C.mkstemp(&u8) i32
fn C.close(i32) i32
fn C.fdopen(i32, &char) &C.FILE

$if linux {
	#flag -D_GNU_SOURCE
	#include <sys/sysmacros.h>
	struct C.statx_timestamp {
		tv_sec  i64
		tv_nsec u32
	}
	struct C.statx {
		stx_ino       u64
		stx_size      u64
		stx_mtime     C.statx_timestamp
		stx_ctime     C.statx_timestamp
		stx_dev_major u32
		stx_dev_minor u32
	}
	fn C.statx(i32, &char, i32, u32, &C.statx) i32
	fn C.makedev(u32, u32) u64
}

$if macos {
	// V's POSIX stat declaration names the native nanosecond fields flat.
	// These aliases select the SDK's timespec members without copying layout.
	#flag -Dst_mtimensec=st_mtimespec.tv_nsec
	#flag -Dst_ctimensec=st_ctimespec.tv_nsec
}

pub fn resolve_path(path string) !string {
	mut parts := (if os.is_abs_path(path) { path } else { os.getwd() + '/' + path }).split('/')
	mut resolved := '/'
	mut index := 0
	mut links := 0
	for index < parts.len {
		part := parts[index]
		index++
		if part == '' || part == '.' { continue }
		if part == '..' {
			resolved = os.dir(resolved)
			continue
		}
		candidate := os.join_path(resolved, part)
		if os.is_link(candidate) {
			links++
			if links > 40 { return error('Symlink loop from ' + path) }
			target := os.readlink(candidate)!
			if os.is_abs_path(target) { resolved = '/' }
			parts = [...target.split('/'), ...parts[index..]]
			index = 0
		} else {
			resolved = candidate
		}
	}
	return resolved
}

fn bounds_integer(value i64) json2.Any {
	return if value < 0 { json2.Any(value) } else { json2.Any(u64(value)) }
}

pub fn bounds_file_state(path string) !map[string]json2.Any {
	$if macos {
		mut state := C.stat{}
		if unsafe { C.stat(path.str, &state) } != 0 { return os.error_posix() }
		return {
			'st_dev':      bounds_integer(i64(state.st_dev))
			'st_ino':      json2.Any(state.st_ino)
			'st_size':     bounds_integer(state.st_size)
			'st_mtime_ns': bounds_integer(state.st_mtime * i64(1000000000) + state.st_mtimensec)
			'st_ctime_ns': bounds_integer(state.st_ctime * i64(1000000000) + state.st_ctimensec)
		}
	} $else $if linux {
		mut state := C.statx{}
		if unsafe { C.statx(-100, path.str, 0, 0x7ff, &state) } != 0 { return os.error_posix() }
		return {
			'st_dev':      json2.Any(C.makedev(state.stx_dev_major, state.stx_dev_minor))
			'st_ino':      json2.Any(state.stx_ino)
			'st_size':     json2.Any(state.stx_size)
			'st_mtime_ns': bounds_integer(state.stx_mtime.tv_sec * i64(1000000000) + i64(state.stx_mtime.tv_nsec))
			'st_ctime_ns': bounds_integer(state.stx_ctime.tv_sec * i64(1000000000) + i64(state.stx_ctime.tv_nsec))
		}
	} $else {
		return error('Bounds input state requires a POSIX host with nanosecond file metadata')
	}
}

pub fn bounds_snapshot(paths []string) !map[string]json2.Any {
	mut sorted := paths.clone()
	sorted.sort()
	mut result := map[string]json2.Any{}
	for path in sorted {
		before := bounds_file_state(path)!
		checksum := file_digest(path)!
		mut after := bounds_file_state(path)!
		if before != after { return error('compiler inputs changed during bounds generation') }
		after['sha256'] = checksum
		result[path] = after
	}
	return result
}

pub fn bounds_native_flags(flags []string) ![]string {
	mut result := []string{}
	for flag in flags {
		if flag in ['-MD', '-MMD', '-MP'] { continue }
		if flag in ['-c', '-S', '-E', '-M', '-MM', '-fsyntax-only']
			|| ['-o', '-MF', '-MT', '-MQ', '-MJ', '--output'].any(flag.starts_with(it)) {
			return error('caller flags contain a compiler output/action: ' + flag)
		}
		result << flag
	}
	return result
}

fn bounds_word(name string) bool {
	return name.len > 0 && name.runes().all(it == `_` || utf8.is_letter(it) || utf8.is_number(it))
}

pub fn bounds_configuration(text string) !map[string]string {
	mut macros := map[string]string{}
	for line in text.split_into_lines() {
		if !line.starts_with('#define ') { continue }
		rest := line[8..]
		name := rest.all_before(' ')
		if bounds_word(name) {
			macros[name] = if rest.contains(' ') { rest.all_after(' ') } else { '' }
		}
	}
	required := {
		'CONFIG_X86':         '1'
		'CONFIG_X86_64':      '1'
		'CONFIG_64BIT':       '1'
		'CONFIG_MMU':         '1'
		'__x86_64__':         '1'
		'__SIZEOF_LONG__':    '8'
		'__SIZEOF_POINTER__': '8'
	}
	for name, value in required {
		if (macros[name] or { '' }) != value {
			return error('unsupported bounds configuration: ${name} must be ${value}')
		}
	}
	if 'CONFIG_SMP' in macros && macros['CONFIG_SMP'] != '1' {
		return error('disabled CONFIG_SMP must be undefined, not defined as zero')
	}
	return macros
}

pub struct BoundNumber {
pub:
	decimal string
}

pub fn (number BoundNumber) to_json() string { return number.decimal }

pub type BoundsValue = json2.Any | map[string]BoundNumber

pub fn bounds_offsets(assembly string, macros map[string]string) !(string, map[string]BoundNumber) {
	mut values := map[string]BoundNumber{}
	mut definitions := []string{}
	for line in assembly.split_into_lines() {
		mut trimmed := line.trim_left(' \t\r\v\f')
		if !trimmed.starts_with('.ascii') || trimmed.len <= 6 || !trimmed[6].is_space() { continue }
		trimmed = trimmed[6..].trim_left(' \t\r\v\f')
		if !trimmed.starts_with('"') { continue }
		tail := trimmed[1..]
		end := tail.index('"') or { continue }
		marker := tail[..end]
		if !marker.starts_with('->') { continue }
		if marker.starts_with('->#') {
			comment := marker[3..]
			if comment.contains('*/') { return error('invalid offsets comment') }
			definitions << '/* ${comment} */'
			continue
		}
		content := marker[2..]
		name := content.all_before(' ')
		remainder := if content.contains(' ') { content.all_after(' ').trim_left('$#') } else { '' }
		value := remainder.all_before(' ')
		expression := if remainder.contains(' ') { remainder.all_after(' ') } else { '' }
		digits := if value.starts_with('-') { value[1..] } else { value }
		if name.len == 0 || !(name[0].is_letter() || name[0] == `_`) || !bounds_word(name)
			|| digits.len == 0 || !digits.bytes().all(it.is_digit()) || expression == '' || expression.contains('*/') {
			return error('invalid compiler offsets marker: ' + marker)
		}
		if name in values { return error('duplicate compiler offsets marker: ' + name) }
		values[name] = BoundNumber{ decimal: big.integer_from_string(value)!.str() }
		definitions << '#define ${name} ${value} /* ${expression} */'
	}
	mut expected := ['NR_PAGEFLAGS', 'MAX_NR_ZONES', 'SPINLOCK_SIZE', 'LRU_GEN_WIDTH',
		'__LRU_REFS_WIDTH']
	if 'CONFIG_SMP' in macros { expected << 'NR_CPUS_BITS' }
	if values.len != expected.len || expected.any(it !in values) {
		return error('compiler offsets marker set differs from pinned kernel/bounds.c')
	}
	return '#ifndef __LINUX_BOUNDS_H__\n#define __LINUX_BOUNDS_H__\n' +
		'/*\n * DO NOT MODIFY.\n * Derived from pinned Linux kernel/bounds.c using its Kbuild offsets format.\n */\n\n' +
		definitions.join('\n') + '\n\n#endif\n', values
}

pub fn make_escape(path string) string {
	return path.replace('$', '$$').replace('#', '\\#').replace(' ', '\\ ')
}

pub fn bounds_dependencies(data string, source string, output string, additional []string) !string {
	if additional.len == 0 || !data.contains(make_escape(source)) {
		return error('compiler dependency output omits bounds.c')
	}
	result := data.replace(make_escape(source), make_escape(additional[0])).trim_right(' \t\n\r\v\f') +
		' \\\n  ' + additional[1..].map(make_escape(it)).join(' \\\n  ') + '\n'
	if result.contains(os.dir(source)) {
		return error('compiler dependency output retains temporary paths')
	}
	if !result.starts_with(make_escape(output) + ':') {
		return error('compiler dependency target differs from the output header')
	}
	return result
}

pub fn dependency_paths(data string, output string) ![]string {
	prefix := make_escape(output) + ':'
	if !data.starts_with(prefix) {
		return error('compiler dependency target differs from the output header')
	}
	body := data[prefix.len..]
	mut paths := []string{}
	mut word := ''
	mut index := 0
	for index < body.len {
		ch := body[index]
		if ch == `\\` {
			index++
			if index == body.len { return error('incomplete compiler dependency escape') }
			if body[index] != `\n` { word += body[index].ascii_str() }
		} else if ch == `$` {
			if index + 1 >= body.len || body[index + 1] != `$` {
				return error('unexpected compiler dependency Make variable')
			}
			word += '$'
			index++
		} else if ch.is_space() {
			if word != '' {
				paths << resolve_path(word)!
				word = ''
			}
		} else {
			word += ch.ascii_str()
		}
		index++
	}
	if word != '' { paths << resolve_path(word)! }
	return paths
}

fn bounds_profile(macros map[string]string) map[string]string {
	mut result := map[string]string{}
	for name, value in macros {
		if name.starts_with('CONFIG_') || name in ['__x86_64__', '__SIZEOF_LONG__', '__SIZEOF_POINTER__'] {
			result[name] = value
		}
	}
	return result
}

pub fn bounds_compiler(compiler string) !([]string, string) {
	argv := shell_split(compiler)!
	if argv.len == 0 { return error('compiler command is empty') }
	executable := os.find_abs_path_of_executable(argv[0]) or { return error('compiler executable was not found: ' + argv[0]) }
	return argv, resolve_path(executable)!
}

fn bounds_checked_snapshot(paths []string, command []string, compiler_path string) !map[string]json2.Any {
	_, before := bounds_compiler(shell_join(command))!
	if before != compiler_path { return error('compiler inputs changed during bounds generation') }
	result := bounds_snapshot(paths)!
	_, after := bounds_compiler(shell_join(command))!
	if after != compiler_path { return error('compiler inputs changed during bounds generation') }
	return result
}

fn sorted_json(value json2.Any) json2.Any {
	return match value {
		map[string]json2.Any {
			mut result := map[string]json2.Any{}
			mut names := value.keys()
			names.sort()
			for name in names {
				result[name] = sorted_json(value[name] or { json2.Any(json2.Null{}) })
			}
			json2.Any(result)
		}
		[]json2.Any { json2.Any(value.map(sorted_json(it))) }
		else { value }
	}
}

pub fn bounds_json(value json2.Any) string {
	return json2.encode(sorted_json(value),
		prettify:       true
		indent_string:  '  '
		escape_unicode: true
	) + '\n'
}

fn bounds_sorted_numbers(numbers map[string]BoundNumber) map[string]BoundNumber {
	mut keys := numbers.keys()
	keys.sort()
	mut result := map[string]BoundNumber{}
	for key in keys { result[key] = numbers[key] }
	return result
}

pub fn bounds_metadata_json(metadata map[string]BoundsValue) string {
	mut names := metadata.keys()
	names.sort()
	mut sorted := map[string]BoundsValue{}
	for name in names {
		value := metadata[name] or { continue }
		sorted[name] = match value {
			json2.Any { BoundsValue(sorted_json(value)) }
			map[string]BoundNumber { BoundsValue(bounds_sorted_numbers(value)) }
		}
	}
	return json2.encode(sorted, prettify: true, indent_string: '  ', escape_unicode: true) + '\n'
}

pub fn bounds_publish(path string, data []u8) ! {
	if os.exists(path) && os.read_bytes(path)! == data { return }
	os.mkdir_all(os.dir(path))!
	mut pattern := (os.join_path(os.dir(path), '.bounds-publish-XXXXXX') + '\x00').bytes()
	descriptor := unsafe { C.mkstemp(pattern.data) }
	if descriptor < 0 { return os.error_posix() }
	temporary := unsafe { (&char(pattern.data)).vstring() }
	defer { os.rm(temporary) or {} }
	stream := C.fdopen(descriptor, c'wb')
	if stream == unsafe { nil } {
		C.close(descriptor)
		return os.error_posix()
	}
	mut closed := false
	defer { if !closed { C.fclose(stream) } }
	if C.fwrite(data.data, 1, usize(data.len), stream) != usize(data.len) {
		return os.error_posix()
	}
	status := C.fclose(stream)
	closed = true
	if status != 0 { return os.error_posix() }
	if unsafe { C.rename(temporary.str, path.str) } != 0 { return os.error_posix() }
}

fn bounds_sources() []string {
	return [os.join_path(root(), 'tests/linuxkpi/generate_bounds.v'),
		os.join_path(root(), 'tests/linuxkpi/hosttest/bounds.v'),
		os.join_path(root(), 'tests/linuxkpi/hosttest/upstream.v'),
		os.join_path(root(), 'tests/linuxkpi/hosttest/archive_abi.h'),
		os.join_path(root(), 'tests/linuxkpi/hosttest/compiler.v'),
		os.join_path(root(), 'tests/linuxkpi/hosttest/core.v')]
}

fn unique_paths(items []string) []string {
	mut result := []string{}
	for item in items { if item !in result { result << item } }
	result.sort()
	return result
}

fn bounds_protected(archive string, compiler string) []string {
	return unique_paths([archive, compiler, os.join_path(upstream_here(), 'generate-bounds.py'),
		os.join_path(upstream_here(), 'upstream.py'), os.join_path(upstream_here(), 'upstream.json'),
		...bounds_sources()])
}

fn inside_import(path string, source string) bool {
	return path == source || path.starts_with(source.trim_right('/') + '/')
}

pub fn bounds_command_stamp(path_arg string, compiler string, flags_arg []string, source_arg string, archive_arg string) !map[string]json2.Any {
	path := resolve_path(path_arg)!
	source := resolve_path(source_arg)!
	archive := resolve_path(archive_arg)!
	command, compiler_path := bounds_compiler(compiler)!
	if path in bounds_protected(archive, compiler_path) {
		return error('command stamp overlaps protected inputs')
	}
	if inside_import(path, source) {
		return error('command stamp must be outside the verified import')
	}
	flags := bounds_native_flags(flags_arg)!
	mut identity := bounds_file_state(compiler_path)!
	mut previous := map[string]json2.Any{}
	if os.exists(path) {
		if decoded := decode_json(os.read_file(path) or { '' }) { previous = decoded.as_map() }
	}
	previous_hash := (previous['compiler_sha256'] or { json2.Any('') }).str()
	mut compiler_hash := ''
	if (previous['compiler_path'] or { json2.Any('') }).str() == compiler_path
		&& (previous['compiler_state'] or { json2.Any(map[string]json2.Any{}) }).as_map() == identity
		&& previous_hash.len == 64 && previous_hash.bytes().all(it.is_digit() || it in [
		`a`,
		`b`,
		`c`,
		`d`,
		`e`,
		`f`,
	]) {
		compiler_hash = previous_hash
	} else {
		snapshot := bounds_checked_snapshot([compiler_path], command, compiler_path)!
		identity = (snapshot[compiler_path] or { return error('Missing compiler snapshot') }).as_map()
		compiler_hash = (identity['sha256'] or { return error('Missing compiler digest') }).str()
		identity.delete('sha256')
	}
	_, resolved := bounds_compiler(shell_join(command))!
	if resolved != compiler_path || bounds_file_state(compiler_path)! != identity {
		return error('compiler inputs changed during command stamp generation')
	}
	metadata := {
		'compiler':        json2.Any(strings([compiler_path, ...command[1..]]))
		'compiler_path':   json2.Any(compiler_path)
		'compiler_state':  json2.Any(identity)
		'compiler_sha256': json2.Any(compiler_hash)
		'flags':           json2.Any(strings(flags))
	}
	bounds_publish(path, bounds_json(metadata).bytes())!
	return metadata
}

fn bounds_run(command []string) !string {
	result := capture(command, '', -1, os.environ())!
	if result.stderr != '' { eprint(result.stderr) }
	if result.code != 0 {
		if result.stdout != '' { eprint(result.stdout) }
		return error('compiler failed with exit status ${result.code}')
	}
	return result.stdout
}

pub fn generate_bounds(source_arg string, archive_arg string, output_arg string, depfile_arg string, provenance_arg string, compiler string, flags_arg []string) !map[string]BoundsValue {
	source_root := resolve_path(source_arg)!
	archive := resolve_path(archive_arg)!
	output := resolve_path(output_arg)!
	depfile := resolve_path(depfile_arg)!
	provenance := resolve_path(provenance_arg)!
	command, compiler_path := bounds_compiler(compiler)!
	pin_path := resolve_path(os.join_path(upstream_here(), 'upstream.json'))!
	generator := bounds_sources()[0]
	verifier := bounds_sources()[2]
	protected := bounds_protected(archive, compiler_path)
	destinations := unique_paths([output, depfile, provenance])
	if destinations.len != 3 || destinations.any(it in protected) {
		return error('bounds outputs overlap each other or protected inputs')
	}
	if destinations.any(inside_import(it, source_root)) {
		return error('bounds outputs must be outside the verified import')
	}
	flags := bounds_native_flags(flags_arg)!
	pin := upstream_pin()!
	protected_state := bounds_checked_snapshot(protected, command, compiler_path)!
	archive_state := (protected_state[archive] or { return error('Missing archive snapshot') }).as_map()
	if (archive_state['sha256'] or { return error('Missing archive digest') }).str() != (pin['sha256'] or { return error('sha256') }).str() {
		return error('archive SHA256 differs from upstream.json')
	}
	if decode_json(os.read_file(pin_path)!)!.as_map() != pin {
		return error('compiler inputs changed during bounds generation')
	}
	verify_upstream(source_root, pin)!
	member := 'linux-' + (pin['version'] or { return error('version') }).str() + '/kernel/bounds.c'
	selected := archive_members(archive, [member])!
	source_bytes := selected[member] or { return error('pinned archive has no kernel/bounds.c') }
	version := bounds_run([...command, '--version'])!
	if bounds_checked_snapshot(protected, command, compiler_path)! != protected_state {
		return error('compiler inputs changed during bounds generation')
	}
	os.mkdir_all(os.dir(output))!
	mut pattern := (os.join_path(os.dir(output), '.bounds-build-XXXXXX') + '\x00').bytes()
	pointer := unsafe { C.mkdtemp(&char(pattern.data)) }
	if pointer == unsafe { nil } { return os.error_posix() }
	work := unsafe { pointer.vstring() }
	defer { os.rmdir_all(work) or {} }
	source := os.join_path(work, 'bounds.c')
	os.write_file_array(source, source_bytes)!
	preprocess_dep := os.join_path(work, 'preprocess.d')
	preprocess := [...command, ...flags, '-MD', '-MF', preprocess_dep, '-MQ', output, '-E', '-dM',
		source]
	macros := bounds_configuration(bounds_run(preprocess)!)!
	preliminary := unique_paths(dependency_paths(os.read_file(preprocess_dep)!, output)!)
	if destinations.any(it in preliminary) {
		return error('bounds outputs overlap discovered compiler inputs')
	}
	initial_state := bounds_checked_snapshot(unique_paths([
		...preliminary.filter(it != source),
		...protected,
	]), command, compiler_path)!
	for path, state in protected_state {
		if (initial_state[path] or { return error('Missing protected input') }) != state {
			return error('compiler inputs changed during bounds generation')
		}
	}
	mut input_hashes := map[string]string{}
	for path, state in initial_state {
		input_hashes[path] = (state.as_map()['sha256'] or { return error('Missing input digest') }).str()
	}
	assembly := os.join_path(work, 'bounds.s')
	dependency := os.join_path(work, 'bounds.d')
	bounds_run([...command, ...flags, '-MD', '-MF', dependency, '-MQ', output, '-S', source, '-o',
		assembly])!
	header, values := bounds_offsets(os.read_file(assembly)!, macros)!
	dependency_text := os.read_file(dependency)!
	inputs := unique_paths(dependency_paths(dependency_text, output)!)
	if destinations.any(it in inputs) {
		return error('bounds outputs overlap discovered compiler inputs')
	}
	if inputs != preliminary || bounds_checked_snapshot(unique_paths([
		...inputs.filter(it != source),
		...protected,
	]), command, compiler_path)! != initial_state {
		return error('compiler inputs changed during bounds generation')
	}
	final_macros := bounds_configuration(bounds_run(preprocess)!)!
	final_inputs := unique_paths(dependency_paths(os.read_file(preprocess_dep)!, output)!)
	if bounds_profile(final_macros) != bounds_profile(macros) {
		return error('preprocessed configuration changed during bounds generation')
	}
	if final_inputs != inputs || bounds_checked_snapshot(unique_paths([
		...final_inputs.filter(it != source),
		...protected,
	]), command, compiler_path)! != initial_state {
		return error('compiler inputs changed during bounds generation')
	}
	dep := bounds_dependencies(dependency_text, source, output,
		[archive, pin_path, os.join_path(upstream_here(), 'generate-bounds.py'),
			os.join_path(upstream_here(), 'upstream.py'), compiler_path, ...bounds_sources()])!
	mut config := map[string]string{}
	mut target := map[string]string{}
	for name, value in macros {
		if name.starts_with('CONFIG_') { config[name] = value }
		if name in ['__x86_64__', '__SIZEOF_LONG__', '__SIZEOF_POINTER__'] { target[name] = value }
	}
	metadata := map[string]json2.Any{
		'scope':             json2.Any('Compiler-derived bounds only; no Linux page or DMA runtime is supplied')
		'linux_version':     pin['version'] or { return error('version') }
		'archive':           json2.Any(archive)
		'archive_sha256':    archive_state['sha256'] or { return error('sha256') }
		'manifest_sha256':   pin['manifest_sha256'] or { return error('manifest_sha256') }
		'source_sha256':     json2.Any(text_sha(source_bytes.bytestr()))
		'generator_sha256':  json2.Any(input_hashes[generator])
		'verifier_sha256':   json2.Any(input_hashes[verifier])
		'pin_sha256':        json2.Any(input_hashes[pin_path])
		'header_sha256':     json2.Any(text_sha(header))
		'dependency_sha256': json2.Any(text_sha(dep))
		'assembly_sha256':   json2.Any(file_digest(assembly)!)
		'compiler':          json2.Any(strings(command))
		'compiler_path':     json2.Any(compiler_path)
		'compiler_sha256':   json2.Any(input_hashes[compiler_path])
		'compiler_version':  json2.Any(version)
		'input_sha256':      json2.Any(string_map(input_hashes))
		'input_state':       json2.Any(initial_state)
		'input_validation':  json2.Any('Repeated profile/dependency/hash/file-state checks; caller must isolate mutable inputs. No transactional snapshot or ABA immunity is claimed.')
		'flags':             json2.Any(strings(flags))
		'configuration':     json2.Any(string_map(config))
		'target':            json2.Any(string_map(target))
	}
	mut complete := map[string]BoundsValue{}
	for name, value in metadata { complete[name] = BoundsValue(value) }
	complete['bounds'] = BoundsValue(values)
	bounds_publish(depfile, dep.bytes())!
	bounds_publish(provenance, bounds_metadata_json(complete).bytes())!
	bounds_publish(output, header.bytes())!
	return complete
}
