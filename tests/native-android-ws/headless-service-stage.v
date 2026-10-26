// SPDX-License-Identifier: GPL-2.0-or-later
// Append an exact headless lifecycle overlay without extracting the runtime.
// Build with -prod so the binary carries its exact source inputs.
module main

import crypto.sha256
import json2
import modulestream
import os
import tarcore
import tarstream
import time
import v.embed_file

#include <sys/clonefile.h>
#include <signal.h>

fn C.clonefile(&char, &char, int) int
fn C.kill(int, int) int

const overlay_name = 'headless-service.tar'
const diagnostic_prefix = 'opt/vinix-headless-service'
const runtime_prefix = 'opt/vinix-android-aarch64'
const jar_member = runtime_prefix + '/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const native_member = runtime_prefix + '/usr/lib/art/libvinix-android-native.so'
const entry_member = runtime_prefix + '/usr/bin/vinix-android-native'
const launcher_member = runtime_prefix + '/usr/bin/run-android'
const baseline_boot_sha = '176094564fba09181b1a2f334f240dc49f0e5f25032696a84db12c2316d0445c'
const baseline_jar_sha = '3b345e1661ca9f5b616f5abe25c9f4abc1df383204d25333477dae69221a8d21'
const baseline_native_sha = 'd3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'
const framework_seal = '36a472320e71eb459896c1d52a8f211f475362fb2c6dada682870bf43b6a2b7b'
const framework_jar_sha = '9e643451d4d82fc3839c91415947f04d3726aa81967a784d4d26db63e2c88cb1'
const fixture_apk_sha = '4df9e3cd757b463259c73dc038eb84d149d7ec1461a1889bc8f2d531f6980634'
const compiler = '/Users/alex/code/v/v'
const cross = '/opt/homebrew/bin/aarch64-linux-musl-gcc'
const compiled_source = carried($embed_file(@FILE))
const compiled_guest = carried($embed_file('headless-service-guest.v'))
const compiled_collector = carried($embed_file('../android-webview-browser-probe/collect.v'))
const compiled_stream = carried($embed_file('../../build-support/android/modulestream/stream.v'))
const compiled_stream_header = carried($embed_file('../../build-support/android/modulestream/spawn_abi.h'))
const compiled_writer = carried($embed_file('../../build-support/tarcore/writer.v'))
const compiled_gzip = carried($embed_file('../../build-support/tarcore/gzip.v'))
const compiled_reader = carried($embed_file('../../build-support/tarstream/reader.v'))
const compiled_reader_header = carried($embed_file('../../build-support/tarstream/filter_abi.h'))
const compiled_sparse = carried($embed_file('../../build-support/tarstream/sparse.v'))

fn carried(data embed_file.EmbedFileData) string {
	// Check before to_string(), which would load today's checkout in a debug
	// build. The pinned compiler's public str() exposes this private pointer.
	if data.str().all_after('uncompressed: ').trim_right(' }') == '0' {
		panic('headless stage requires embedded source bytes; compile with -prod')
	}
	return data.to_string()
}

struct Entry {
	name     string
	kind     string
	mode     u32
	size     u64
	sha256   string
	linkname string
}

struct Config {
	modules []string
	updated string
}

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn safe_name(name string) bool {
	return name != '' && name !in ['.', '..'] && name.len <= 255
		&& name.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`)
			|| (it >= `0` && it <= `9`) || it in [`_`, `-`, `.`])
}

fn configure(original string) !Config {
	if original == '' || original.contains_any('\x00\r') {
		return error('expected an LF-delimited Limine configuration')
	}
	mut modules := []string{}
	mut indent := ''
	mut entries := 0
	for line in original.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with('/') || trimmed.starts_with(':') {
			entries++
		}
		if !trimmed.starts_with('module_path:') { continue }
		if entries != 1 || !trimmed.starts_with('module_path: boot():/boot/') {
			return error('unsupported or ambiguous Limine module path')
		}
		name := trimmed.all_after('module_path: boot():/boot/')
		if !safe_name(name) || !name.ends_with('.tar') || name == overlay_name
			|| name in modules {
			return error('unsafe, duplicate, non-tar or existing overlay module: ' + name)
		}
		prefix := line[..line.len - line.trim_left(' \t').len]
		if prefix == '' || (indent != '' && indent != prefix) {
			return error('Limine module indentation is ambiguous')
		}
		indent = prefix
		modules << name
	}
	if entries != 1 || modules.len == 0 {
		return error('exactly one populated Limine entry required')
	}
	separator := if original.ends_with('\n') { '' } else { '\n' }
	return Config{modules, original + separator + indent + 'module_path: boot():/boot/' + overlay_name + '\n'}
}

fn normalize(name string) !string {
	if name.starts_with('/') || name.contains_any('\x00\n\r\\') {
		return error('unsafe archive name: ' + name)
	}
	mut clean := name
	for clean.starts_with('./') { clean = clean[2..] }
	clean = clean.trim_right('/')
	if clean == '.' || clean == '' { return '' }
	if clean.split('/').any(it in ['', '.', '..']) { return error('unsafe archive name: ' + name) }
	return clean
}

fn replacements() []string { return [jar_member, native_member, entry_member, launcher_member] }

// Existing runtime members may be replaced only at these four regular paths.
// Inspect every historical entry, including shadowed ancestors, so an alias
// cannot redirect a later overlay outside the intended tree.
fn collision(member tarcore.Member) ! {
	name := normalize(member.name)!
	if name.starts_with(runtime_prefix + '/') && member.regular()
		&& (name.ends_with('.oat') || name.ends_with('.odex') || name.ends_with('.vdex')
			|| name.contains('/dalvik-cache/')) {
		return error('compiled cache could shadow framework DEX: ' + name)
	}
	if name == diagnostic_prefix || name.starts_with(diagnostic_prefix + '/') {
		return error('original module already contains diagnostic destination: ' + name)
	}
	mut targets := replacements()
	targets << diagnostic_prefix
	for target in targets {
		if name != '' && target.starts_with(name + '/') && member.kind != `5` {
			return error('overlay destination has non-directory ancestor: ' + name)
		}
		if name == target && !member.regular() {
			return error('replacement is not regular: ' + name)
		}
	}
}

fn command(root string, label string, argv []string) !string {
	return command_expected(root, label, argv, 0)
}

fn command_expected(root string, label string, argv []string, expected int) !string {
	mut child := os.new_process(argv[0])
	child.use_pgroup = true
	child.set_args(argv[1..])
	child.set_stdin_path('/dev/null')
	child.set_redirect_stdio()
	child.run()
	defer { child.close() }
	mut finished := false
	defer {
		if !finished {
			if child.pid > 0 { C.kill(-child.pid, 9) }
			child.wait()
		}
	}
	mut stdout := ''
	mut stderr := ''
	deadline := time.sys_mono_now() + 120 * time.second
	for {
		stdout += child.stdout_read()
		stderr += child.stderr_read()
		if stdout.len + stderr.len > 2 * 1024 * 1024 {
			return error('oversized command output: ' + label)
		}
		if !child.is_alive() { break }
		if time.sys_mono_now() >= deadline { return error('command deadline: ' + label) }
		time.sleep(10 * time.millisecond)
	}
	for {
		out := child.stdout_read()
		err := child.stderr_read()
		if out == '' && err == '' { break }
		stdout += out
		stderr += err
		if stdout.len + stderr.len > 2 * 1024 * 1024 {
			return error('oversized command output: ' + label)
		}
	}
	child.wait()
	finished = true
	os.write_file(root + '/commands/' + label + '.json', json2.encode({
		'argv':      json2.decode[json2.Any](json2.encode(argv))!
		'exit_code': json2.Any(child.code)
		'stdout':    json2.Any(stdout)
		'stderr':    json2.Any(stderr)
	}, prettify: true))!
	if child.code != expected {
		return error(label + ' unexpected exit ' + child.code.str() + ': ' + stderr)
	}
	return stdout
}

// Parse tar directly from mcopy's pipe. Do not extract or retain original modules.
fn check_module(mcopy string, image string, name string, mut effective map[string]Entry) ! {
	mut child := os.new_process(mcopy)
	child.use_pgroup = true
	child.set_args(['-i', image, '::/boot/' + name, '-'])
	child.set_stdin_path('/dev/null')
	child.set_redirect_stdio()
	child.run()
	defer { child.close() }
	mut finished := false
	defer {
		if !finished {
			if child.pid > 0 { C.kill(-child.pid, 9) }
			child.wait()
		}
	}
	mut archive := tarstream.from_descriptor(i32(child.stdio_fd[1]))!
	defer { archive.close() }
	for {
		member := archive.next() or {
			if err is tarstream.End { break }
			return err
		}
		collision(member)!
		clean := normalize(member.name)!
		if clean in replacements() {
			effective[clean] = Entry{
				name:   clean
				kind:   'regular'
				mode:   u32(member.mode) & 0o7777
				size:   u64(member.size)
				sha256: archive.digest()!
			}
		}
	}
	// Tar stops at the first zero block; consume the producer's remaining padding.
	mut stderr := ''
	for {
		child.stdout_read()
		stderr += child.stderr_read()
		if stderr.len > 1024 * 1024 { return error('oversized mcopy diagnostics') }
		if !child.is_alive() { break }
		time.sleep(time.millisecond)
	}
	for {
		out := child.stdout_read()
		err := child.stderr_read()
		if out == '' && err == '' { break }
		stderr += err
		if stderr.len > 1024 * 1024 { return error('oversized mcopy diagnostics') }
	}
	child.wait()
	finished = true
	if child.code != 0 { return error('collision scan mcopy failed: ' + stderr) }
}

fn inventory(root string, relative string, prefix string, mut result []Entry) ! {
	path := if relative == '' { root } else { root + '/' + relative }
	stat := os.lstat(path)!
	name := if relative == '' { prefix } else { prefix + '/' + relative }
	mode := stat.mode & 0o7777
	match stat.get_filetype() {
		.directory {
			result << Entry{ name: name, kind: 'directory', mode: mode }
			mut children := os.ls(path)!
			children.sort()
			for child in children {
				if child.contains_any('\x00\n\r\\') { return error('unsafe bundle filename') }
				next := if relative == '' { child } else { relative + '/' + child }
				inventory(root, next, prefix, mut result)!
			}
		}
		.regular {
			result << Entry{ name: name, kind: 'regular', mode: mode, size: stat.size, sha256: hash(path)! }
		}
		.symbolic_link {
			target := os.readlink(path)!
			if target == '' || target.contains_any('\x00\n\r') {
				return error('unsafe bundle symlink')
			}
			result << Entry{ name: name, kind: 'symlink', mode: mode, linkname: target }
		}
		else { return error('unsupported bundle inode: ' + name) }
	}
}

fn write_overlay(path string, sources map[string]string, entries []Entry) ! {
	mut writer := tarcore.create_stream(path)!
	defer { writer.close() }
	mut buffer := []u8{len: 1024 * 1024}
	for entry in entries {
		member := tarcore.Member{
			name:     entry.name
			mode:     i64(entry.mode)
			size:     if entry.kind == 'regular' { i64(entry.size) } else { 0 }
			kind:     match entry.kind {
				'directory' { u8(`5`) }
				'symlink' { u8(`2`) }
				else { u8(`0`) }
			}
			linkname: entry.linkname
		}
		writer.write(tarcore.header(member)!)!
		if entry.kind == 'regular' {
			source := sources[entry.name] or { return error('overlay entry has no source') }
			mut file := os.open(source)!
			mut remaining := entry.size
			for remaining > 0 {
				mut part := unsafe { buffer[..int(if remaining < u64(buffer.len) {
					remaining
				} else {
					u64(buffer.len)
				})] }
				n := file.read(mut part) or {
					file.close()
					return err
				}
				if n == 0 {
					file.close()
					return error('bundle file truncated')
				}
				writer.write(part[..n])!
				remaining -= u64(n)
			}
			file.close()
		}
		writer.padding(member.size)!
	}
	writer.finish()!
	writer.close_checked()!
}

fn verify_overlay(path string, expected []Entry) ! {
	mut reader := tarstream.open_plain(path)!
	defer { reader.close() }
	mut actual := []Entry{}
	for {
		member := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		kind := if member.regular() {
			'regular'
		} else if member.kind == `5` {
			'directory'
		} else if member.kind == `2` {
			'symlink'
		} else {
			return error('unexpected overlay inode')
		}
		actual << Entry{
			name:     normalize(member.name)!
			kind:     kind
			mode:     u32(member.mode) & 0o7777
			size:     u64(member.size)
			sha256:   if member.regular() { reader.digest()! } else { '' }
			linkname: member.linkname
		}
	}
	if actual != expected { return error('overlay readback inventory differs') }
}

fn module_hash(root string, label string, image string, name string) !string {
	result := modulestream.hash_member(image, name, root + '/commands/' + label + '.sha256')!
	if result.statuses.producer != 0 || result.statuses.consumer != 0 {
		return error('module hash stream failed: ' + name)
	}
	return result.sha256
}

fn external(path string) !string {
	requested := os.abs_path(path)
	if !os.is_dir(os.dir(requested)) { return error('output parent directory must exist') }
	absolute := os.real_path(os.dir(requested)) + '/' + os.file_name(requested)
	repo := os.real_path(os.dir(os.dir(os.dir(@FILE))))
	if absolute != path || absolute == repo || absolute.starts_with(repo + '/') || absolute.contains_any(' \t\x00\n\r') {
		return error('fresh output must be outside the repository')
	}
	if os.exists(absolute) || os.is_link(absolute) { return error('fresh output required') }
	if (absolute + '/qmp.sock').len >= 104 {
		return error('QMP Unix socket path exceeds 103 bytes')
	}
	return absolute
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn relative(path string) bool {
	return path != '' && !path.starts_with('/') && !path.contains_any('\x00\n\r\\')
		&& !path.split('/').any(it in ['', '.', '..'])
}

fn files(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		if !relative(key) { return error('unsafe bundle path') }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { files(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('bundle requires regular files and directories: ' + key) }
		}
	}
}

fn sealed_bundle(root string, seal string, mut inputs map[string]string) !map[string]string {
	if seal.len != 64 || !seal.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		|| hash(root + '/sha256.json')! != seal {
		return error('bundle manifest pin differs')
	}
	pins := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	mut actual := map[string]string{}
	files(root, '', mut actual)!
	actual.delete('sha256.json')
	if pins.len == 0 || actual != pins {
		return error('complete bundle inventory differs: ' + root)
	}
	inputs[root + '/sha256.json'] = seal
	for name, pin in pins { inputs[root + '/' + name] = pin }
	return pins
}

fn retain_sources(root string) ! {
	for name, data in {
		'headless-service-stage.v': compiled_source
		'headless-service-guest.v': compiled_guest
		'collect.v':                compiled_collector
		'modulestream.v':           compiled_stream
		'spawn_abi.h':              compiled_stream_header
		'tar-writer.v':             compiled_writer
		'tar-gzip.v':               compiled_gzip
		'tar-reader.v':             compiled_reader
		'filter_abi.h':             compiled_reader_header
		'tar-sparse.v':             compiled_sparse
	} {
		os.write_file(root + '/sources/' + name, data)!
	}
}

fn build_guest(root string, mut inputs map[string]string) ! {
	source := root + '/sources/headless-service-guest.v'
	flags := [compiler, '-new-compiler', '-prod', '-os', 'linux', '-arch', 'arm64', '-cc', cross,
		'-gc', 'none', '-skip-running', '-cflags', '-static']
	mut closure_args := flags.clone()
	closure_args << ['-print-v-files', source]
	listing := command(root, 'guest-closure', closure_args)!
	mut closure := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		closure[path] = hash(path)!
		retained := root + '/sources/closure/' + path.trim_left('/')
		os.mkdir_all(os.dir(retained))!
		os.cp(path, retained)!
		if hash(retained)! != closure[path]! { return error('guest source closure copy differs') }
		inputs[path] = closure[path]!
	}
	if closure.len == 0 || source !in closure { return error('guest source closure absent') }
	write_json(root + '/guest-source-closure.json', closure)!
	mut build_args := flags.clone()
	build_args << ['-o', root + '/payload/bin/headless-service-guest', source]
	command(root, 'build-guest', build_args)!
	static_elf(root + '/payload/bin/headless-service-guest')!
}

fn static_elf(path string) ! {
	bytes := os.read_bytes(path)!
	if bytes.len < 64 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| bytes[18..20] != [u8(183), 0] {
		return error('guest wrapper is not AArch64 ELF64')
	}
	mut offset := u64(0)
	for i in 0 .. 8 { offset |= u64(bytes[32 + i]) << (8 * i) }
	stride := int(bytes[54]) | int(bytes[55]) << 8
	count := int(bytes[56]) | int(bytes[57]) << 8
	if stride < 56 || offset > u64(bytes.len) || offset + u64(stride * count) > u64(bytes.len) {
		return error('invalid program headers')
	}
	for i in 0 .. count {
		at := int(offset) + i * stride
		if bytes[at..at + 4] == [u8(3), 0, 0, 0] {
			return error('guest wrapper is dynamically linked')
		}
	}
}

fn replacement_entry(name string, source string, mode u32) !Entry {
	if os.lstat(source)!.get_filetype() != .regular {
		return error('regular overlay input required')
	}
	return Entry{ name: name, kind: 'regular', mode: mode, size: os.lstat(source)!.size, sha256: hash(source)! }
}

fn verify_plan(entries []Entry) ! {
	mut names := map[string]bool{}
	mut expected := {
		diagnostic_prefix:          'directory'
		diagnostic_prefix + '/bin': 'directory'
	}
	for name in replacements() { expected[name] = 'regular' }
	for name in ['bin/headless-service-controller', 'bin/headless-service-guest', 'fixture.apk',
		'fixture-build.json', 'native-build.json', 'native-sha256.json', 'framework-build.json',
		'framework-sha256.json', 'guest-inputs.json'] {
		expected[diagnostic_prefix + '/' + name] = 'regular'
	}
	for entry in entries {
		if !relative(entry.name) || entry.name in names || entry.mode > 0o777 {
			return error('unsafe or duplicate overlay entry/mode')
		}
		names[entry.name] = true
		if entry.kind != (expected[entry.name] or { return error('overlay path outside exact allowlist') }) {
			return error('overlay inode differs from exact allowlist')
		}
	}
	if names.len != expected.len { return error('exact overlay replacement/addition set required') }
}

fn stage() ! {
	if os.args.len != 8 {
		return error('usage: headless-service-stage BASE_BOOT BASE_EFIVARS FRAMEWORK_BUILD NATIVE_BUILD NATIVE_SEAL FIXTURE_DIR FRESH_OUTPUT')
	}
	$if !macos {
		return error('staging requires macOS APFS clonefile')
	}
	boot, efivars := os.real_path(os.args[1]), os.real_path(os.args[2])
	framework, native, fixture := os.real_path(os.args[3]), os.real_path(os.args[4]), os.real_path(os.args[6])
	root := external(os.args[7])!
	for input in [boot, efivars, framework, native, fixture] {
		if root == input || input.starts_with(root + '/') || root.starts_with(input + '/') {
			return error('output overlaps an input')
		}
	}
	if hash(boot)! != baseline_boot_sha || hash(framework + '/api-impl.jar')! != framework_jar_sha
		|| hash(fixture + '/probe.apk')! != fixture_apk_sha {
		return error('fixed baseline/framework/fixture pin differs')
	}
	mcopy, mtype, mdir := os.find_abs_path_of_executable('mcopy')!, os.find_abs_path_of_executable('mtype')!, os.find_abs_path_of_executable('mdir')!
	os.setenv('PATH', os.dir(mcopy) + ':' + os.getenv('PATH'), true)
	mut inputs := map[string]string{}
	for path in [boot, efivars, mcopy, mtype, mdir, '/usr/bin/shasum', '/usr/bin/git', compiler,
		cross, os.executable()] {
		inputs[path] = hash(path)!
	}
	framework_pins := sealed_bundle(framework, framework_seal, mut inputs)!
	native_pins := sealed_bundle(native, os.args[5], mut inputs)!
	framework_receipt := json2.decode[map[string]json2.Any](os.read_file(framework + '/build.json')!)!
	native_receipt := json2.decode[map[string]json2.Any](os.read_file(native + '/build.json')!)!
	if framework_receipt['api_impl_sha256']!.str() != framework_jar_sha
		|| framework_receipt['class_count']!.int() != 2098
		|| native_receipt['baseline_native_sha256']!.str() != 'aa460c06686e2d1f60ea6dd27ab8f158a3b9794440499c6cdc5e7840cafda0cb'
		|| native_receipt['native_sha256']!.str() != native_pins['native/libvinix-android-native.so']! {
		return error('framework/native build receipt identity differs')
	}
	fixture_receipt := json2.decode[map[string]json2.Any](os.read_file(fixture + '/build.json')!)!
	if fixture_receipt['apk_sha256']!.str() != fixture_apk_sha
		|| fixture_receipt['package_name']!.str() != 'org.vinix.headless'
		|| fixture_receipt['service_name']!.str() != 'org.vinix.headless.ProbeService'
		|| fixture_receipt['bind_action']!.str() != 'org.vinix.headless.BIND' {
		return error('fixture identity differs')
	}
	inputs[fixture + '/build.json'] = hash(fixture + '/build.json')!
	inputs[fixture + '/probe.apk'] = fixture_apk_sha
	os.mkdir(root, mode: 0o700)!
	for dir in ['commands', 'sources', 'payload', 'payload/bin'] {
		os.mkdir(root + '/' + dir, mode: 0o755)!
	}
	retain_sources(root)!
	os.cp(os.executable(), root + '/stage')!
	for pair in [
		[native + '/bin/headless-service-controller',
			root + '/payload/bin/headless-service-controller'],
		[fixture + '/probe.apk', root + '/payload/fixture.apk'],
		[fixture + '/build.json', root + '/payload/fixture-build.json'],
		[native + '/build.json', root + '/payload/native-build.json'],
		[native + '/sha256.json', root + '/payload/native-sha256.json'],
		[framework + '/build.json', root + '/payload/framework-build.json'],
		[framework + '/sha256.json', root + '/payload/framework-sha256.json'],
	] {
		os.cp(pair[0], pair[1])!
	}
	os.chmod(root + '/payload/bin/headless-service-controller', 0o755)!
	build_guest(root, mut inputs)!
	mut guest_inputs := map[string]string{}
	mut sources := {
		jar_member:      framework + '/api-impl.jar'
		native_member:   native + '/native/libvinix-android-native.so'
		entry_member:    native + '/bin/vinix-android-native'
		launcher_member: native + '/bin/run-android'
	}
	mut entries := []Entry{}
	for name in replacements() {
		entry := replacement_entry(name, sources[name]!, if name in [entry_member, launcher_member] {
			u32(0o755)
		} else {
			u32(0o644)
		})!
		entries << entry
		guest_inputs['/' + name] = entry.sha256
	}
	for name in ['bin/headless-service-controller', 'bin/headless-service-guest', 'fixture.apk'] {
		guest_inputs['/' + diagnostic_prefix + '/' + name] = hash(root + '/payload/' + name)!
	}
	write_json(root + '/payload/guest-inputs.json', {
		'inputs_sha256': guest_inputs
	})!
	inventory(root + '/payload', '', diagnostic_prefix, mut entries)!
	for entry in entries {
		if entry.kind == 'regular' && entry.name.starts_with(diagnostic_prefix + '/') {
			sources[entry.name] = root + '/payload' + entry.name[diagnostic_prefix.len..]
		}
	}
	verify_plan(entries)!
	write_json(root + '/overlay-plan.json', entries)!
	original := command(root, 'read-limine', [mtype, '-i', boot, '::/boot/limine.conf'])!
	config := configure(original)!
	if config.modules != ['initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar',
		'maps350-diagnostics.tar', 'maps372-diagnostics.tar'] {
		return error('qualified baseline module order differs')
	}
	command_expected(root, 'overlay-absent', [mdir, '-i', boot, '::/boot/' + overlay_name], 1)!
	os.write_file(root + '/limine-before.conf', original)!
	os.write_file(root + '/limine-after.conf', config.updated)!
	mut before := map[string]string{}
	mut effective := map[string]Entry{}
	for name in config.modules {
		before[name] = module_hash(root, 'original-' + name, boot, name)!
		check_module(mcopy, boot, name, mut effective)!
	}
	if effective.len != 4 || effective[jar_member]!.sha256 != baseline_jar_sha
		|| effective[native_member]!.sha256 != baseline_native_sha {
		return error('baseline effective replacement set differs')
	}
	write_json(root + '/runtime-replacements-before.json', effective)!
	for pair in [[boot, root + '/boot.img'], [efivars, root + '/efivars.fd']] {
		if C.clonefile(pair[0].str, pair[1].str, 0) != 0 {
			return error('APFS clonefile failed: ' + pair[0])
		}
		if hash(pair[1])! != inputs[pair[0]]! { return error('media clone differs') }
	}
	write_overlay(root + '/' + overlay_name, sources, entries)!
	verify_overlay(root + '/' + overlay_name, entries)!
	overlay_hash := hash(root + '/' + overlay_name)!
	command(root, 'install-overlay', [mcopy, '-i', root + '/boot.img', root + '/' + overlay_name,
		'::/boot/' + overlay_name])!
	command(root, 'install-limine', [mcopy, '-o', '-i', root + '/boot.img',
		root + '/limine-after.conf', '::/boot/limine.conf'])!
	if command(root, 'readback-limine', [mtype, '-i', root + '/boot.img', '::/boot/limine.conf'])! != config.updated {
		return error('staged Limine differs')
	}
	command(root, 'readback-overlay', [mcopy, '-i', root + '/boot.img', '::/boot/' + overlay_name,
		root + '/readback-overlay.tar'])!
	if hash(root + '/readback-overlay.tar')! != overlay_hash {
		return error('staged overlay bytes differ')
	}
	verify_overlay(root + '/readback-overlay.tar', entries)!
	os.rm(root + '/readback-overlay.tar')!
	mut after := map[string]string{}
	for name in config.modules {
		after[name] = module_hash(root, 'preserved-' + name, root + '/boot.img', name)!
		if after[name] != before[name] { return error('original module changed: ' + name) }
	}
	mut final_entries := entries[..4].clone()
	inventory(root + '/payload', '', diagnostic_prefix, mut final_entries)!
	if final_entries != entries { return error('diagnostic payload changed during staging') }
	for path, expected in inputs {
		if hash(path)! != expected { return error('input changed during staging: ' + path) }
	}
	// Full bundle inventories are checked twice, including absence of extra files.
	if sealed_bundle(framework, framework_seal, mut inputs)! != framework_pins
		|| sealed_bundle(native, os.args[5], mut inputs)! != native_pins {
		return error('bundle changed during staging')
	}
	revision := command(root, 'source-revision', ['/usr/bin/git', 'rev-parse', 'HEAD'])!.trim_space()
	write_json(root + '/stage.json', {
		'format':                           json2.Any(1)
		'scope':                            json2.Any('synthetic headless lifecycle staging only; no guest launched or Google authentication claim')
		'preparation_checkout_revision':    json2.Any(revision)
		'compiled_stage_source_sha256':     json2.Any(sha256.sum(compiled_source.bytes()).hex())
		'compiled_guest_source_sha256':     json2.Any(sha256.sum(compiled_guest.bytes()).hex())
		'compiled_collector_source_sha256': json2.Any(sha256.sum(compiled_collector.bytes()).hex())
		'inputs_sha256':                    json2.decode[json2.Any](json2.encode(inputs))!
		'original_modules_sha256':          json2.decode[json2.Any](json2.encode(before))!
		'preserved_modules_sha256':         json2.decode[json2.Any](json2.encode(after))!
		'overlay_inventory':                json2.decode[json2.Any](json2.encode(entries))!
		'overlay_sha256':                   json2.Any(overlay_hash)
		'limine_before_sha256':             json2.Any(sha256.sum(original.bytes()).hex())
		'limine_after_sha256':              json2.Any(sha256.sum(config.updated.bytes()).hex())
		'staged_boot_sha256':               json2.Any(hash(root + '/boot.img')!)
		'staged_efivars_sha256':            json2.Any(hash(root + '/efivars.fd')!)
		'guest_terminal_command':           json2.Any('/opt/vinix-headless-service/bin/headless-service-guest')
		'guest_results':                    json2.Any('/opt/vinix-headless-service/results')
		'collector':                        json2.Any('tests/android-webview-browser-probe/collect.v --headless SERIAL_LOG FRESH_EXTERNAL_RESULTS')
	})!
	println('HEADLESS-STAGE PASS ' + root + '/stage.json')
}

fn self_test() ! {
	config := '/Vinix\n    protocol: limine\n    module_path: boot():/boot/initramfs.tar\n    module_path: boot():/boot/runtime.tar\n'
	parsed := configure(config)!
	assert parsed.modules == ['initramfs.tar', 'runtime.tar']
	assert parsed.updated == config + '    module_path: boot():/boot/' + overlay_name + '\n'
	assert configure(config.trim_right('\n'))!.updated == parsed.updated
	for bad in [config + '/Other\n', config + '    module_path: boot():/boot/runtime.tar\n',
		config + '    module_path: boot():/boot/../escape.tar\n', parsed.updated] {
		mut rejected := false
		configure(bad) or {
			rejected = true
			Config{}
		}
		assert rejected
	}
	collision(tarcore.Member{ name: './opt/', kind: `5` })!
	collision(tarcore.Member{ name: jar_member, kind: `0` })!
	for bad in [tarcore.Member{ name: 'opt', kind: `2` },
		tarcore.Member{ name: diagnostic_prefix + '/bin/probe' },
		tarcore.Member{ name: runtime_prefix + '/usr', kind: `2` },
		tarcore.Member{ name: jar_member, kind: `1`, linkname: 'elsewhere' },
		tarcore.Member{ name: runtime_prefix + '/usr/lib/art/stale.odex' },
		tarcore.Member{ name: runtime_prefix + '/dalvik-cache/arm64/cache' },
		tarcore.Member{ name: './opt/../escape' }] {
		mut rejected := false
		collision(bad) or { rejected = true }
		assert rejected
	}
	root := os.join_path(os.real_path(os.temp_dir()), 'vinix-headless-stage-selftest-' + os.getpid().str())
	if os.exists(root) { return error('self-test path exists') }
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	os.mkdir(root + '/sources')!
	retain_sources(root)!
	assert hash(root + '/sources/headless-service-stage.v')! == sha256.sum(compiled_source.bytes()).hex()
	assert hash(root + '/sources/headless-service-guest.v')! == sha256.sum(compiled_guest.bytes()).hex()
	assert hash(root + '/sources/collect.v')! == sha256.sum(compiled_collector.bytes()).hex()
	os.mkdir(root + '/bundle')!
	os.mkdir(root + '/bundle/bin')!
	for name in ['bin/headless-service-controller', 'bin/headless-service-guest', 'fixture.apk',
		'fixture-build.json', 'native-build.json', 'native-sha256.json', 'framework-build.json',
		'framework-sha256.json', 'guest-inputs.json'] {
		os.write_file(root + '/bundle/' + name, name + '\x00exact-bytes')!
	}
	os.chmod(root + '/bundle/bin/headless-service-guest', 0o751)!
	mut entries := []Entry{}
	mut sources := map[string]string{}
	for name in replacements() {
		entries << replacement_entry(name, root + '/bundle/fixture.apk', 0o644)!
		sources[name] = root + '/bundle/fixture.apk'
	}
	inventory(root + '/bundle', '', diagnostic_prefix, mut entries)!
	verify_plan(entries)!
	assert entries.len == 15
	for entry in entries {
		if entry.kind == 'regular' && entry.name.starts_with(diagnostic_prefix + '/') {
			sources[entry.name] = root + '/bundle' + entry.name[diagnostic_prefix.len..]
		}
	}
	write_overlay(root + '/overlay.tar', sources, entries)!
	verify_overlay(root + '/overlay.tar', entries)!
	mut missing := entries.clone()
	missing.delete(0)
	mut duplicate := entries.clone()
	duplicate << entries[0]
	mut extra := entries.clone()
	extra << Entry{ name: diagnostic_prefix + '/unlisted', kind: 'regular' }
	mut alias := entries.clone()
	alias[0] = Entry{ name: jar_member, kind: 'symlink', linkname: 'elsewhere' }
	for bad in [missing, duplicate, extra, alias] {
		mut rejected := false
		verify_plan(bad) or { rejected = true }
		assert rejected
	}
	assert external(root + '/fresh')! == root + '/fresh'
	for bad in [root, root + '/./alias', root + '/' + 'x'.repeat(110)] {
		mut rejected := false
		external(bad) or {
			rejected = true
			''
		}
		assert rejected
	}
	os.mkdir(root + '/sealed')!
	os.write_file(root + '/sealed/build.json', '{}\n')!
	write_json(root + '/sealed/sha256.json', {
		'build.json': hash(root + '/sealed/build.json')!
	})!
	seal := hash(root + '/sealed/sha256.json')!
	mut inputs := map[string]string{}
	assert sealed_bundle(root + '/sealed', seal, mut inputs)!.len == 1
	os.write_file(root + '/sealed/unlisted', 'extra')!
	mut rejected_extra := false
	sealed_bundle(root + '/sealed', seal, mut inputs) or {
		rejected_extra = true
		map[string]string{}
	}
	assert rejected_extra
	os.rm(root + '/sealed/unlisted')!
	os.write_file(root + '/sealed/build.json', '{"changed":true}\n')!
	mut rejected_change := false
	sealed_bundle(root + '/sealed', seal, mut inputs) or {
		rejected_change = true
		map[string]string{}
	}
	assert rejected_change
	mut elf := []u8{len: 120}
	for i, value in [u8(0x7f), `E`, `L`, `F`, 2, 1] { elf[i] = value }
	elf[18] = 183
	elf[32] = 64
	elf[54] = 56
	elf[56] = 1
	os.write_file_array(root + '/static', elf)!
	static_elf(root + '/static')!
	elf[64] = 3
	os.write_file_array(root + '/dynamic', elf)!
	mut rejected_dynamic := false
	static_elf(root + '/dynamic') or { rejected_dynamic = true }
	assert rejected_dynamic
	println('HEADLESS-STAGE SELF-TEST PASS config-prefix collision caches exact-allowlist streamed-archive modes fresh-output QMP-limit full-seal static-ELF')
	println('HEADLESS-STAGE COMPILED-SOURCES ' + sha256.sum(compiled_source.bytes()).hex() +
		' ' + sha256.sum(compiled_guest.bytes()).hex() + ' ' + sha256.sum(compiled_collector.bytes()).hex())
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	stage() or {
		eprintln(err)
		exit(1)
	}
}
