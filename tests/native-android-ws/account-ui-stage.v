// SPDX-License-Identifier: GPL-2.0-or-later
// Append the real desktop account UI fixture; original boot modules remain exact.
// Build with -prod to retain the source bytes used by this host executable.
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

const overlay_name = 'account-ui-fixture.tar'
const diagnostic_prefix = 'opt/vinix-account-ui'
const compiler = '/Users/alex/code/v-tccbin-bootstrap-20261026/v'
const cross = '/opt/homebrew/bin/aarch64-linux-musl-gcc'
const compiler_pin = '0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe'
const controller_root = '/Users/alex/.local/state/vinix/android/current-ui-controller-build-2026-10-26-r1'
const controller_seal = '503f4e03edf225311038cc0ecce556b804f6b07a337793ff7a466881fbe0112a'
const controller = controller_root + '/bin/account-ui-controller'
const controller_pin = '5c5d6415f3e97cb2369187a7aa373aca019ae1e085298daf4551789739851f18'
const controller_argv_source_pin = '7655f8175951075501cc3cc395bdf38355bbaaf8d50ede416c208758f77a3282'
const controller_source_pin = '3dcc2e60d5082cf7736c2f363a165f4cba33fabd9b0563599d6662dbbd21f5b2'
const helper_root = '/Users/alex/.local/state/vinix/android/account-ui-2026-10-26/arm64-committed'
const helper_pin = 'eff0ee8da211772f2549a5b39fdb2739cbb746db44e859bc25bd56b854fbd989'
const controller_revision = 'c5fc9065af1e624002eaff6e2f927ce79858a06e'
const helper_revision = '4887c0f13'
const compiled_source = carried($embed_file(@FILE))
const compiled_guest = carried($embed_file("account-ui-guest.v"))
const compiled_collector = carried($embed_file("../android-webview-browser-probe/collect.v"))
const retained_modules = {
	'build-support/android/modulestream/stream.v':    carried($embed_file("../../build-support/android/modulestream/stream.v"))
	'build-support/android/modulestream/spawn_abi.h': carried($embed_file("../../build-support/android/modulestream/spawn_abi.h"))
	'build-support/tarcore/writer.v':                 carried($embed_file("../../build-support/tarcore/writer.v"))
	'build-support/tarcore/gzip.v':                   carried($embed_file("../../build-support/tarcore/gzip.v"))
	'build-support/tarstream/reader.v':               carried($embed_file("../../build-support/tarstream/reader.v"))
	'build-support/tarstream/filter_abi.h':           carried($embed_file("../../build-support/tarstream/filter_abi.h"))
	'build-support/tarstream/sparse.v':               carried($embed_file("../../build-support/tarstream/sparse.v"))
}
// Supplied binaries are not rebuilt here. Their documentary source is
// retrieved from fixed revisions independently of live checkout edits.
const fixture_source_paths = [
	'build-support/android/accountui/bridge.v',
	'build-support/android/accountui/connect.c.v',
	'build-support/android/accountui/control.c.v',
	'build-support/android/accountui/input.c.v',
	'build-support/android/accountui/main.v',
	'build-support/android/accountui/surface.c.v',
	'build-support/android/accountuifd/control.c.v',
	'build-support/android/nativeaccountauth/connect.c.v',
	'build-support/android/nativeaccountauth/dispose.v',
	'build-support/android/nativeaccountauth/launcher_options.v',
	'build-support/android/nativeaccountauth/peer.c.v',
	'build-support/android/nativeaccountauth/redemption.v',
	'build-support/android/nativeaccountauth/registry.v',
	'build-support/android/nativeaccountauth/request.c.v',
	'build-support/android/nativeaccountauth/service.c.v',
	'build-support/android/nativeaccountauth/service_ui.c.v',
	'desktop/sessionruntime/runtime.c.v',
	'desktop/windowfb/client.v',
	'desktop/windowfb/protocol.v',
	'desktop/windowfb/surface.c.v',
	'desktop/windowfb/transport.c.v',
	'tests/native-android-ws/account-ui-controller.v',
]

fn carried(data embed_file.EmbedFileData) string {
	// Check before to_string(), which would load today's checkout in a debug
	// build. The pinned compiler's public str() exposes this private pointer.
	if data.str().all_after('uncompressed: ').trim_right(' }') == '0' {
		panic('account UI stage requires embedded source bytes; compile with -prod')
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

struct ControllerBuild {
	kind            string
	profile         string
	source_revision string
	outputs_sha256  map[string]string
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

fn command(root string, label string, argv []string) !string {
	return command_expected(root, label, argv, 0)
}

fn command_expected(root string, label string, argv []string, expected int) !string {
	return command_limit(root, label, argv, expected, 120 * time.second)
}

fn command_limit(root string, label string, argv []string, expected int, timeout time.Duration) !string {
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
	deadline := time.sys_mono_now() + timeout
	for {
		stdout += child.stdout_read()
		stderr += child.stderr_read()
		if stdout.len + stderr.len > 2 * 1024 * 1024 {
			return error('oversized command output: ' + label)
		}
		if !child.is_alive() { break }
		if time.sys_mono_now() >= deadline {
			// Preserve the observed command failure before returning. Killing the
			// owned process group also reaps any compiler child at the deadline.
			if child.pid > 0 { C.kill(-child.pid, 9) }
			child.wait()
			finished = true
			write_json(root + '/commands/' + label + '.json', {
				'argv':       json2.decode[json2.Any](json2.encode(argv))!
				'exit_code':  json2.Any(child.code)
				'stdout':     json2.Any(stdout)
				'stderr':     json2.Any(stderr)
				'timed_out':  json2.Any(true)
				'timeout_ns': json2.Any(i64(timeout))
			})!
			return error('command deadline: ' + label)
		}
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
				mut part := unsafe {
					buffer[..int(if remaining < u64(buffer.len) {
						remaining
					} else {
						u64(buffer.len)
					})]
				}
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
	repo := os.real_path('/Users/alex/code/vinix')
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

fn sealed(root string, expected_pin string) !map[string]string {
	if os.real_path(root) != root || os.is_link(root) || !os.is_dir(root)
		|| !pin(expected_pin) || hash(root + '/sha256.json')! != expected_pin {
		return error('sealed controller inventory pin or canonical root differs')
	}
	if os.file_size(root + '/sha256.json') > 2 * 1024 * 1024 {
		return error('oversized controller inventory')
	}
	expected := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	if expected.len == 0 || expected.len > 4096 || 'sha256.json' in expected {
		return error('invalid controller inventory shape')
	}
	for name, digest in expected {
		if !relative(name) || !pin(digest) { return error('unsafe controller inventory key/hash') }
	}
	mut actual := map[string]string{}
	files(root, '', mut actual)!
	actual.delete('sha256.json')
	if actual != expected { return error('complete controller inventory differs') }
	return expected
}

fn verify_controller() !map[string]string {
	manifest := sealed(controller_root, controller_seal)!
	build := json2.decode[ControllerBuild](os.read_file(controller_root + '/build.json')!)!
	controller_contract(build, manifest)!
	closure := json2.decode[map[string]string](os.read_file(controller_root + '/account-ui-controller-compiled-closure.json')!)!
	prefix := controller_root + '/closure/account-ui-controller/'
	if closure.len == 0 || closure.len > 4096 { return error('controller compiled closure absent or oversized') }
	for path, digest in closure {
		if !path.starts_with(prefix) || !relative(path[controller_root.len + 1..]) || !pin(digest)
			|| manifest[path[controller_root.len + 1..]] != digest {
			return error('controller compiled closure pin differs')
		}
	}
	for name, digest in {
		'build-support/android/accountuifd/control.c.v': controller_argv_source_pin
		'tests/native-android-ws/account-ui-controller.v': controller_source_pin
	} {
		path := prefix + 'Users/alex/code/vinix/' + name
		if closure[path] != digest { return error('controller source or argv lifetime fix differs') }
	}
	return manifest
}

fn controller_contract(build ControllerBuild, manifest map[string]string) ! {
	if build.kind != 'vinix-account-ui-controller-build-v1' || build.profile != 'ui-controller'
		|| build.source_revision != controller_revision
		|| build.outputs_sha256 != {'bin/account-ui-controller': controller_pin}
		|| manifest['bin/account-ui-controller'] != controller_pin {
		return error('controller build kind, revision or output differs')
	}
}

fn retain_controller(root string, manifest map[string]string, mut inputs map[string]string) ! {
	for name, digest in manifest {
		if !name.starts_with('closure/account-ui-controller/') && name !in ['build.json',
			'account-ui-controller-closure.json', 'account-ui-controller-compiled-closure.json',
			'account-ui-controller-linux-compatibility.json'] { continue }
		path := controller_root + '/' + name
		retained := root + '/controller-build/' + name
		os.mkdir_all(os.dir(retained))!
		os.cp(path, retained)!
		if hash(retained)! != digest { return error('retained controller build source differs') }
		inputs[path] = digest
	}
	os.cp(controller_root + '/sha256.json', root + '/controller-build/producer-sha256.json')!
	if hash(root + '/controller-build/producer-sha256.json')! != controller_seal {
		return error('retained controller build inventory differs')
	}
	inputs[controller_root + '/sha256.json'] = controller_seal
}

fn static_elf(path string) ! {
	bytes := os.read_bytes(path)!
	if bytes.len < 64 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| bytes[16..20] != [u8(2), 0, 183, 0] {
		return error('guest wrapper is not AArch64 ELF64')
	}
	mut offset := u64(0)
	for i in 0 .. 8 { offset |= u64(bytes[32 + i]) << (8 * i) }
	stride := int(bytes[54]) | int(bytes[55]) << 8
	count := int(bytes[56]) | int(bytes[57]) << 8
	if stride < 56 || count == 0 || offset > u64(bytes.len) || offset + u64(stride * count) > u64(bytes.len) {
		return error('invalid program headers')
	}
	for i in 0 .. count {
		at := int(offset) + i * stride
		if bytes[at..at + 4] == [u8(3), 0, 0, 0] {
			return error('guest wrapper is dynamically linked')
		}
	}
}

fn pin(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

// A historical alias must not redirect the new diagnostic tree. No file from
// any existing module may occupy that tree, including shadowed old entries.
fn collision(member tarcore.Member) ! {
	name := normalize(member.name)!
	if name == diagnostic_prefix || name.starts_with(diagnostic_prefix + '/') {
		return error('diagnostic destination already exists: ' + name)
	}
	if name != '' && diagnostic_prefix.starts_with(name + '/') && member.kind != `5` {
		return error('diagnostic destination has non-directory ancestor: ' + name)
	}
}

fn scan_module(mcopy string, image string, name string, expected []Entry) ! {
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
	mut actual := []Entry{}
	for {
		member := archive.next() or {
			if err is tarstream.End { break }
			return err
		}
		collision(member)!
		if expected.len > 0 {
			kind := if member.regular() {
				'regular'
			} else if member.kind == `5` {
				'directory'
			} else if member.kind == `2` {
				'symlink'
			} else {
				return error('unexpected base overlay inode')
			}
			actual << Entry{
				name:     normalize(member.name)!
				kind:     kind
				mode:     u32(member.mode) & 0o7777
				size:     u64(member.size)
				sha256:   if member.regular() { archive.digest()! } else { '' }
				linkname: member.linkname
			}
		}
	}
	mut stderr := ''
	for {
		child.stdout_read()
		stderr += child.stderr_read()
		if stderr.len > 1024 * 1024 { return error('oversized module diagnostics') }
		if !child.is_alive() { break }
		time.sleep(time.millisecond)
	}
	for {
		out := child.stdout_read()
		err := child.stderr_read()
		if out == '' && err == '' { break }
		stderr += err
		if stderr.len > 1024 * 1024 { return error('oversized module diagnostics') }
	}
	child.wait()
	finished = true
	if child.code != 0 { return error('module scan failed: ' + stderr) }
	if expected.len > 0 && actual != expected {
		return error('base overlay inventory differs from pinned receipt')
	}
}

fn verify_plan(entries []Entry) ! {
	expected := {
		diagnostic_prefix:                                   'directory'
		diagnostic_prefix + '/bin':                          'directory'
		diagnostic_prefix + '/bin/account-ui-guest':         'regular'
		diagnostic_prefix + '/bin/account-ui-controller':    'regular'
		diagnostic_prefix + '/bin/vinix-android-account-ui': 'regular'
		diagnostic_prefix + '/guest-inputs.json':            'regular'
	}
	mut names := map[string]bool{}
	for entry in entries {
		if !relative(entry.name) || entry.name in names || entry.kind != (expected[entry.name] or {
			return error('overlay entry outside exact addition set')
		}) || entry.mode != if entry.name.ends_with('.json') { u32(0o644) } else { u32(0o755) }
			|| entry.linkname != '' {
			return error('invalid diagnostic overlay entry')
		}
		names[entry.name] = true
	}
	if names.len != expected.len { return error('incomplete diagnostic overlay') }
}

fn retain_sources(root string) ! {
	for name, data in {
		'tests/native-android-ws/account-ui-stage.v':    compiled_source
		'tests/native-android-ws/account-ui-guest.v':    compiled_guest
		'tests/android-webview-browser-probe/collect.v': compiled_collector
	} {
		os.mkdir_all(os.dir(root + '/sources/' + name))!
		os.write_file(root + '/sources/' + name, data)!
	}
	for name, data in retained_modules {
		os.mkdir_all(os.dir(root + '/sources/' + name))!
		os.write_file(root + '/sources/' + name, data)!
	}
	// These files document the source identities supplied with the pinned
	// binaries; this is not a claim that those binaries were rebuilt here.
	for name in fixture_source_paths {
		revision := if name.starts_with('desktop/') || name.starts_with('build-support/android/accountui/') {
			helper_revision
		} else {
			controller_revision
		}
		data := command(root, 'source-' + name.replace('/', '_'), ['/usr/bin/git', '-C',
			'/Users/alex/code/vinix', 'show', revision + ':' + name])!
		os.mkdir_all(os.dir(root + '/sources/' + name))!
		os.write_file(root + '/sources/' + name, data)!
	}
	if hash(root + '/sources/build-support/android/accountuifd/control.c.v')! != controller_argv_source_pin
		|| hash(root + '/sources/tests/native-android-ws/account-ui-controller.v')! != controller_source_pin {
		return error('documentary controller revision differs from compiled source pins')
	}
}

fn build_guest(root string, mut inputs map[string]string) ! {
	if hash(compiler)! != compiler_pin {
		return error('guest compiler pin differs before compilation')
	}
	source := root + '/sources/tests/native-android-ws/account-ui-guest.v'
	flags := [compiler, '-new-compiler', '-prod', '-os', 'linux', '-arch', 'arm64', '-cc', cross,
		'-gc', 'none', '-skip-running', '-exclude', '@vlib/crypto/rand/internal/rand.wasm.v', '-cflags',
		'-static']
	mut listing_args := flags.clone()
	listing_args << ['-print-v-files', source]
	listing := command(root, 'guest-closure', listing_args)!
	mut closure := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		if path in closure { return error('duplicate guest closure source') }
		closure[path] = hash(path)!
		retained := root + '/sources/closure/' + path.trim_left('/')
		os.mkdir_all(os.dir(retained))!
		os.cp(path, retained)!
		if hash(retained)! != closure[path]! { return error('guest closure copy differs') }
		inputs[path] = closure[path]!
	}
	if closure.len == 0 || source !in closure { return error('guest closure absent') }
	write_json(root + '/guest-source-closure.json', closure)!
	mut args := flags.clone()
	args << ['-o', root + '/payload/bin/account-ui-guest', source]
	// Production AArch64 C optimization can exceed the short metadata-command
	// limit on a shared host; retain a separate bounded compilation budget.
	command_limit(root, 'build-guest', args, 0, 900 * time.second)!
	if hash(compiler)! != compiler_pin {
		return error('guest compiler pin differs after compilation')
	}
	static_elf(root + '/payload/bin/account-ui-guest')!
}

fn base_modules(receipt map[string]json2.Any, modules []string) !map[string]string {
	if receipt['format']!.int() != 1
		|| receipt['guest_terminal_command']!.str() != '/opt/vinix-headless-service/bin/headless-service-guest' {
		return error('expected a maintained headless stage receipt')
	}
	mut expected := json2.decode[map[string]string](json2.encode(receipt['preserved_modules_sha256']!))!
	if expected.len == 0 || 'headless-service.tar' in expected {
		return error('invalid original module receipt')
	}
	expected['headless-service.tar'] = receipt['overlay_sha256']!.str()
	if modules.len != expected.len || modules.last() != 'headless-service.tar' {
		return error('headless module order or count differs')
	}
	for name in modules {
		if !pin(expected[name] or { return error('module absent from receipt') }) {
			return error('invalid module digest')
		}
	}
	return expected
}

fn stage() ! {
	if os.args.len != 4 {
		return error('usage: account-ui-stage BASE_STAGE STAGE_JSON_SHA256 FRESH_OUTPUT')
	}
	$if !macos {
		return error('staging requires macOS APFS clonefile')
	}
	base := os.real_path(os.args[1])
	root := external(os.args[3])!
	if base != os.args[1] || !os.is_dir(base) || base == root || base.starts_with(root + '/') || root.starts_with(base + '/') {
		return error('canonical input stage and separate output required')
	}
	if !pin(os.args[2]) || hash(base + '/stage.json')! != os.args[2] {
		return error('headless stage receipt pin differs')
	}
	receipt := json2.decode[map[string]json2.Any](os.read_file(base + '/stage.json')!)!
	controller_manifest := verify_controller()!
	boot, efivars := base + '/boot.img', base + '/efivars.fd'
	if hash(boot)! != receipt['staged_boot_sha256']!.str()
		|| hash(efivars)! != receipt['staged_efivars_sha256']!.str()
		|| hash(compiler)! != compiler_pin || hash(controller)! != controller_pin
		|| hash(helper_root + '/vinix-android-account-ui')! != helper_pin {
		return error('media, compiler or diagnostic binary pin differs')
	}
	static_elf(controller)!
	static_elf(helper_root + '/vinix-android-account-ui')!
	mcopy, mtype, mdir := os.find_abs_path_of_executable('mcopy')!, os.find_abs_path_of_executable('mtype')!, os.find_abs_path_of_executable('mdir')!
	os.setenv('PATH', os.dir(mcopy) + ':' + os.getenv('PATH'), true)
	mut inputs := map[string]string{}
	for path in [base + '/stage.json', boot, efivars, controller,
		helper_root + '/vinix-android-account-ui', helper_root + '/build.json',
		helper_root + '/inputs.json', mcopy, mtype, mdir, compiler, cross, '/usr/bin/git',
		'/usr/bin/shasum', os.executable()] {
		inputs[path] = hash(path)!
	}
	os.mkdir(root, mode: 0o700)!
	for dir in ['commands', 'sources', 'payload', 'payload/bin'] {
		os.mkdir(root + '/' + dir, mode: 0o755)!
	}
	retain_sources(root)!
	retain_controller(root, controller_manifest, mut inputs)!
	os.cp(os.executable(), root + '/stage')!
	os.cp(base + '/stage.json', root + '/base-stage.json')!
	os.cp(helper_root + '/build.json', root + '/helper-build.json')!
	os.cp(helper_root + '/inputs.json', root + '/helper-inputs.json')!
	os.cp(controller, root + '/payload/bin/account-ui-controller')!
	os.cp(helper_root + '/vinix-android-account-ui', root + '/payload/bin/vinix-android-account-ui')!
	if hash(root + '/payload/bin/account-ui-controller')! != controller_pin
		|| hash(root + '/payload/bin/vinix-android-account-ui')! != helper_pin {
		return error('copied controller or helper differs from selected executable')
	}
	build_guest(root, mut inputs)!
	for name in ['account-ui-guest', 'account-ui-controller', 'vinix-android-account-ui'] {
		os.chmod(root + '/payload/bin/' + name, 0o755)!
	}
	write_json(root + '/payload/guest-inputs.json', {
		'kind':            json2.Any('vinix-account-ui-guest-inputs-v1')
		'source_revision': json2.Any(controller_revision)
		'inputs_sha256':   json2.decode[json2.Any](json2.encode({
			'/' + diagnostic_prefix + '/bin/account-ui-controller':    controller_pin
			'/' + diagnostic_prefix + '/bin/vinix-android-account-ui': helper_pin
		}))!
	})!
	os.chmod(root + '/payload/guest-inputs.json', 0o644)!
	mut entries := []Entry{}
	inventory(root + '/payload', '', diagnostic_prefix, mut entries)!
	verify_plan(entries)!
	mut sources := map[string]string{}
	for entry in entries {
		if entry.kind == 'regular' {
			sources[entry.name] = root + '/payload' + entry.name[diagnostic_prefix.len..]
		}
	}
	write_json(root + '/overlay-plan.json', entries)!
	original := command(root, 'read-limine', [mtype, '-i', boot, '::/boot/limine.conf'])!
	if sha256.sum(original.bytes()).hex() != receipt['limine_after_sha256']!.str() {
		return error('base Limine bytes differ from pinned stage receipt')
	}
	config := configure(original)!
	expected := base_modules(receipt, config.modules)!
	base_inventory := json2.decode[[]Entry](json2.encode(receipt['overlay_inventory']!))!
	if base_inventory.len == 0 { return error('base overlay inventory absent') }
	command_expected(root, 'overlay-absent', [mdir, '-i', boot, '::/boot/' + overlay_name], 1)!
	os.write_file(root + '/limine-before.conf', original)!
	os.write_file(root + '/limine-after.conf', config.updated)!
	mut before := map[string]string{}
	for name in config.modules {
		before[name] = module_hash(root, 'original-' + name, boot, name)!
		if before[name] != expected[name]! {
			return error('base module differs from pinned receipt: ' + name)
		}
		scan_module(mcopy, boot, name, if name == 'headless-service.tar' {
			base_inventory
		} else {
			[]Entry{}
		})!
	}
	for pair in [[boot, root + '/boot.img'], [efivars, root + '/efivars.fd']] {
		if C.clonefile(pair[0].str, pair[1].str, 0) != 0 { return error('APFS clonefile failed') }
		if hash(pair[1])! != inputs[pair[0]]! { return error('media clone differs') }
	}
	write_overlay(root + '/' + overlay_name, sources, entries)!
	verify_overlay(root + '/' + overlay_name, entries)!
	overlay_sha := hash(root + '/' + overlay_name)!
	command(root, 'install-overlay', [mcopy, '-i', root + '/boot.img', root + '/' + overlay_name,
		'::/boot/' + overlay_name])!
	command(root, 'install-limine', [mcopy, '-o', '-i', root + '/boot.img',
		root + '/limine-after.conf', '::/boot/limine.conf'])!
	if command(root, 'readback-limine', [mtype, '-i', root + '/boot.img', '::/boot/limine.conf'])! != config.updated {
		return error('staged Limine differs')
	}
	command(root, 'readback-overlay', [mcopy, '-i', root + '/boot.img', '::/boot/' + overlay_name,
		root + '/readback-overlay.tar'])!
	if hash(root + '/readback-overlay.tar')! != overlay_sha {
		return error('staged overlay bytes differ')
	}
	verify_overlay(root + '/readback-overlay.tar', entries)!
	os.rm(root + '/readback-overlay.tar')!
	mut after := map[string]string{}
	for name in config.modules {
		after[name] = module_hash(root, 'preserved-' + name, root + '/boot.img', name)!
		if after[name] != before[name]! { return error('original module changed: ' + name) }
	}
	mut final_entries := []Entry{}
	inventory(root + '/payload', '', diagnostic_prefix, mut final_entries)!
	if final_entries != entries { return error('diagnostic payload changed during staging') }
	if verify_controller()! != controller_manifest { return error('controller build changed during staging') }
	for path, expected_sha in inputs {
		if hash(path)! != expected_sha { return error('input changed during staging: ' + path) }
	}
	write_json(root + '/stage.json', {
		'format':                           json2.Any(1)
		'scope':                            json2.Any('real desktop helper/controller fixture staging; no ART, Google account or sign-in claim')
		'base_stage_receipt_sha256':        json2.Any(os.args[2])
		'compiled_stage_source_sha256':     json2.Any(sha256.sum(compiled_source.bytes()).hex())
		'compiled_guest_source_sha256':     json2.Any(sha256.sum(compiled_guest.bytes()).hex())
		'compiled_collector_source_sha256': json2.Any(sha256.sum(compiled_collector.bytes()).hex())
		'controller_source_revision':       json2.Any(controller_revision)
		'controller_build':                 json2.Any(controller_root)
		'controller_build_sha256':          json2.Any(controller_seal)
		'helper_source_revision':           json2.Any(helper_revision)
		'inputs_sha256':                    json2.decode[json2.Any](json2.encode(inputs))!
		'original_modules_sha256':          json2.decode[json2.Any](json2.encode(before))!
		'preserved_modules_sha256':         json2.decode[json2.Any](json2.encode(after))!
		'overlay_inventory':                json2.decode[json2.Any](json2.encode(entries))!
		'overlay_sha256':                   json2.Any(overlay_sha)
		'limine_before_sha256':             json2.Any(sha256.sum(original.bytes()).hex())
		'limine_after_sha256':              json2.Any(sha256.sum(config.updated.bytes()).hex())
		'staged_boot_sha256':               json2.Any(hash(root + '/boot.img')!)
		'staged_efivars_sha256':            json2.Any(hash(root + '/efivars.fd')!)
		'guest_terminal_command':           json2.Any('/opt/vinix-account-ui/bin/account-ui-guest')
		'guest_results':                    json2.Any('/opt/vinix-account-ui/results')
		'collector':                        json2.Any('tests/android-webview-browser-probe/collect.v --account-ui SERIAL_LOG FRESH_EXTERNAL_RESULTS')
	})!
	mut outputs := map[string]string{}
	files(root, '', mut outputs)!
	write_json(root + '/sha256.json', outputs)!
	println('ACCOUNT-UI-STAGE PASS ' + root + '/stage.json')
}

fn self_test() ! {
	build := ControllerBuild{
		kind: 'vinix-account-ui-controller-build-v1'
		profile: 'ui-controller'
		source_revision: controller_revision
		outputs_sha256: {'bin/account-ui-controller': controller_pin}
	}
	outputs := {'bin/account-ui-controller': controller_pin}
	controller_contract(build, outputs)!
	for bad in [ControllerBuild{...build, kind: 'other'}, ControllerBuild{...build, profile: 'launch'},
		ControllerBuild{...build, source_revision: helper_revision},
		ControllerBuild{...build, outputs_sha256: {'bin/account-ui-controller': helper_pin}}] {
		if _ := controller_contract(bad, outputs) { return error('inexact controller build metadata accepted') }
	}
	if _ := controller_contract(build, {'bin/account-ui-controller': helper_pin}) {
		return error('controller output absent from inventory accepted')
	}
	valid := '/Vinix\n    module_path: boot():/boot/base.tar\n'
	assert configure(valid)!.modules == ['base.tar']
	for bad in ['', valid + '/Other\n', valid + '    module_path: boot():/boot/base.tar\n',
		valid + '    module_path: boot():/boot/' + overlay_name + '\n',
		'/Vinix\n    module_path: boot():/boot/../base.tar\n'] {
		if _ := configure(bad) { return error('invalid configuration accepted') }
	}
	for member in [tarcore.Member{ name: diagnostic_prefix, kind: `5` },
		tarcore.Member{ name: diagnostic_prefix + '/old', kind: `0` },
		tarcore.Member{ name: 'opt', kind: `2`, linkname: 'elsewhere' },
		tarcore.Member{ name: '../opt', kind: `5` }] {
		if _ := collision(member) { return error('colliding or aliased destination accepted') }
	}
	collision(tarcore.Member{ name: 'opt', kind: `5` })!
	collision(tarcore.Member{ name: 'opt/vinix-headless-service/bin/controller', kind: `0` })!
	mut entries := [Entry{ name: diagnostic_prefix, kind: 'directory', mode: 0o755 },
		Entry{ name: diagnostic_prefix + '/bin', kind: 'directory', mode: 0o755 }]
	for name in ['bin/account-ui-guest', 'bin/account-ui-controller', 'bin/vinix-android-account-ui',
		'guest-inputs.json'] {
		entries << Entry{
			name: diagnostic_prefix + '/' + name
			kind: 'regular'
			mode: if name.ends_with('.json') {
				u32(0o644)
			} else {
				u32(0o755)
			}
		}
	}
	verify_plan(entries)!
	mut extra := entries.clone()
	extra << Entry{ name: 'opt/other', kind: 'regular', mode: 0o644 }
	for bad in [entries[..entries.len - 1], entries.repeat(2), extra] {
		if _ := verify_plan(bad) { return error('inexact overlay accepted') }
	}
	mut wrong_mode := entries.clone()
	wrong_mode[2] = Entry{ ...wrong_mode[2], mode: 0o777 }
	if _ := verify_plan(wrong_mode) { return error('writable executable accepted') }
	println('ACCOUNT-UI-STAGE SELFTEST PASS config collision exact-allowlist mode controller-build')
	println('ACCOUNT-UI-STAGE COMPILED-SOURCES ' + sha256.sum(compiled_source.bytes()).hex() + ' ' +
		sha256.sum(compiled_guest.bytes()).hex() + ' ' + sha256.sum(compiled_collector.bytes()).hex())
}

fn deadline_check(root string) ! {
	if _ := command_limit(root, 'deadline-negative', ['/bin/sleep', '1'], 0, 20 * time.millisecond) {
		return error('overdue command accepted')
	}
	deadline_receipt := json2.decode[map[string]json2.Any](os.read_file(root + '/commands/deadline-negative.json')!)!
	if !deadline_receipt['timed_out']!.bool() || deadline_receipt['exit_code']!.int() == 0
		|| deadline_receipt['argv']!.as_array().map(it.str()) != ['/bin/sleep', '1'] {
		return error('deadline command failure receipt differs')
	}
}

fn host_check(path string) ! {
	root := external(path)!
	os.mkdir(root, mode: 0o700)!
	for dir in ['commands', 'sources', 'payload', 'payload/bin'] {
		os.mkdir(root + '/' + dir, mode: 0o755)!
	}
	retain_sources(root)!
	mut inputs := map[string]string{}
	controller_manifest := verify_controller()!
	retain_controller(root, controller_manifest, mut inputs)!
	fixture := root + '/sealed-check'
	os.mkdir(fixture)!
	os.write_file(fixture + '/input', 'original')!
	write_json(fixture + '/sha256.json', {'input': hash(fixture + '/input')!})!
	fixture_seal := hash(fixture + '/sha256.json')!
	sealed(fixture, fixture_seal)!
	if _ := sealed(fixture, '0'.repeat(64)) { return error('wrong controller seal accepted') }
	os.write_file(fixture + '/extra', 'extra')!
	if _ := sealed(fixture, fixture_seal) { return error('extra controller inventory file accepted') }
	os.rm(fixture + '/extra')!
	os.write_file(fixture + '/input', 'changed')!
	if _ := sealed(fixture, fixture_seal) { return error('changed controller inventory file accepted') }
	build_guest(root, mut inputs)!
	self_test()!
	deadline_check(root)!
	if _ := external(root) { return error('existing output accepted') }
	if _ := external(os.dir(root) + '/' + 'x'.repeat(104)) {
		return error('overlong QMP path accepted')
	}
	bad_receipts := [map[string]json2.Any{}, {
		'format':                   json2.Any(1)
		'guest_terminal_command':   json2.Any('/opt/vinix-headless-service/bin/headless-service-guest')
		'preserved_modules_sha256': json2.decode[json2.Any]('{"headless-service.tar":"' + 'a'.repeat(64) + '"}')!
	}]
	for receipt in bad_receipts {
		if _ := base_modules(receipt, ['headless-service.tar']) {
			return error('incomplete baseline receipt accepted')
		}
	}
	data := root + '/test-data'
	os.write_file(data, 'exact archive readback\n')!
	entries := [Entry{ name: diagnostic_prefix, kind: 'directory', mode: 0o755 }, Entry{
		name:   diagnostic_prefix + '/data'
		kind:   'regular'
		mode:   0o644
		size:   os.lstat(data)!.size
		sha256: hash(data)!
	}]
	write_overlay(root + '/test.tar', {
		diagnostic_prefix + '/data': data
	}, entries)!
	verify_overlay(root + '/test.tar', entries)!
	mut changed := entries.clone()
	changed[1] = Entry{ ...changed[1], sha256: 'b'.repeat(64) }
	if _ := verify_overlay(root + '/test.tar', changed) {
		return error('archive digest mismatch accepted')
	}
	if verify_controller()! != controller_manifest { return error('controller build changed during host checks') }
	for input, digest in inputs {
		if hash(input)! != digest { return error('host check source changed') }
	}
	write_json(root + '/checks.json', {
		'kind':         json2.Any('vinix-account-ui-stage-host-check-v1')
		'checks':       json2.Any(['static-AArch64-guest', 'embedded-sources', 'source-revisions',
			'complete-controller-producer', 'compiled-controller-source-pins', 'controller-metadata-rejection',
			'controller-inventory-pin-extra-file-and-mutation-rejection',
			'configuration', 'collision', 'exact-overlay-allowlist', 'archive-readback',
			'digest-rejection', 'fresh-output', 'QMP-path-limit', 'incomplete-baseline-receipt',
			'bounded-command-deadline-receipt'].map(json2.Any(it)))
		'controller_build': json2.Any(controller_root)
		'controller_build_sha256': json2.Any(controller_seal)
		'inputs_sha256': json2.decode[json2.Any](json2.encode(inputs))!
		'guest_sha256': json2.Any(hash(root + '/payload/bin/account-ui-guest')!)
	})!
	println('ACCOUNT-UI-STAGE HOST-CHECK PASS ' + root + '/checks.json')
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--command-check' {
		root := external(os.args[2]) or { eprintln(err) exit(1) }
		os.mkdir(root, mode: 0o700) or { eprintln(err) exit(1) }
		os.mkdir(root + '/commands', mode: 0o755) or { eprintln(err) exit(1) }
		deadline_check(root) or { eprintln(err) exit(1) }
		println('ACCOUNT-UI-STAGE COMMAND-CHECK PASS deadline rejected owned-child reaped receipt retained')
		return
	}
	if os.args.len == 3 && os.args[1] == '--host-check' {
		host_check(os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		return
	}
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
