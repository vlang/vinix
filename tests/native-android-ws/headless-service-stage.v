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
const combined_framework_seal = '798b574b811203313b185480ddfd9349bfc5b7e1863d96e99d9c1afca3be4dd2'
const combined_framework_jar_sha = '296cb0bd9d16801322a18d40bca0facfb0593e50be47d424f199d02ceeb7e15f'
const interaction_framework_seal = 'dc5c0470c4cdc7a075ded61680e4ac89cef056dbcb515ce55a32f74bf82aef87'
const interaction_framework_jar_sha = '86278c9cbe1f25904b760250f34f859206d719cbb23cf5ff5411a75c480ac36f'
const full_native_seal = 'd99195272b8af813679cf54fed9f1e0341e6f1115804ac09c1cd2d5a8f942e3e'
const compiler_pin = '0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe'
const fixture_apk_sha = '4df9e3cd757b463259c73dc038eb84d149d7ec1461a1889bc8f2d531f6980634'
const compiler = '/Users/alex/code/v-tccbin-bootstrap-20261026/v'
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

struct FrameworkProfile {
	name        string
	seal        string
	jar_sha256  string
	class_count int
}

// Only these reviewed complete bundles are eligible; a caller cannot supply
// a new manifest pin or pair a known manifest with a different framework.
fn framework_profile(seal string) !FrameworkProfile {
	return match seal {
		framework_seal {
			FrameworkProfile{'authenticator-base-network-2098', framework_seal, framework_jar_sha, 2098}
		}
		combined_framework_seal {
			FrameworkProfile{'combined-account-webview-2101', combined_framework_seal, combined_framework_jar_sha, 2101}
		}
		interaction_framework_seal {
			FrameworkProfile{'combined-account-webview-interaction-2102', interaction_framework_seal, interaction_framework_jar_sha, 2102}
		}
		else { return error('framework manifest is outside the audited profiles') }
	}
}

fn verify_mode(profile FrameworkProfile, current_native bool, current_executables bool) ! {
	if (profile.seal == interaction_framework_seal && (!current_native || !current_executables))
		|| (current_executables && (profile.seal != interaction_framework_seal || !current_native)) {
		return error('interaction framework requires current native and seven-argument executable bundles together')
	}
}

fn verify_framework(profile FrameworkProfile, jar_sha string, receipt map[string]json2.Any) ! {
	if jar_sha != profile.jar_sha256 || receipt['api_impl_sha256']!.str() != profile.jar_sha256
		|| receipt['class_count']!.int() != profile.class_count {
		return error('framework JAR or build receipt differs from audited profile')
	}
}

fn shared_elf(path string) ! {
	bytes := os.read_bytes(path)!
	if bytes.len < 64 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| bytes[16..20] != [u8(3), 0, 183, 0] {
		return error('current native input is not an AArch64 ELF64 shared library')
	}
}

fn current_native_receipts() []string {
	return ['build.json', 'sha256.json', 'native/exports.json', 'commands/build-native.json',
		'commands/exports.json']
}

fn current_native_destinations() []string {
	return ['current-native-build.json', 'current-native-sha256.json', 'current-native-exports.json',
		'current-native-build-command.json', 'current-native-exports-command.json']
}

fn verify_current_identity(profile FrameworkProfile, framework string, native_seal string,
	baseline string, dso_sha string, receipt map[string]json2.Any) ! {
	if profile.seal !in [combined_framework_seal, interaction_framework_seal] || native_seal != full_native_seal
		|| receipt['framework']!.str() != framework
		|| receipt['framework_sha256']!.str() != profile.seal
		|| receipt['baseline_sha256']!.str() != full_native_seal
		|| receipt['native_sha256']!.str() != dso_sha
		|| receipt['source_revision']!.str() == '' || receipt['completed_utc']!.str() == ''
		|| receipt['baseline']!.str() != baseline {
		return error('current native receipt does not couple the audited framework and full native base')
	}
}

fn verify_current_native(current string, framework string, profile FrameworkProfile,
	baseline string, native_seal string, pins map[string]string) ![]string {
	dso := current + '/native/libvinix-android-native.so'
	shared_elf(dso)!
	receipt := json2.decode[map[string]json2.Any](os.read_file(current + '/build.json')!)!
	verify_current_identity(profile, framework, native_seal, baseline,
		pins['native/libvinix-android-native.so']!, receipt)!
	if hash(current + '/framework-sha256.json')! != profile.seal
		|| hash(current + '/baseline-sha256.json')! != full_native_seal {
		return error('current native retained input manifests differ')
	}
	build := json2.decode[map[string]json2.Any](os.read_file(current + '/commands/build-native.json')!)!
	args := json2.decode[[]string](json2.encode(build['argv']!))!
	if build['exit_code']!.int() != 0 || args.len < 3 || args[0] != cross
		|| args.count(it == '-Werror') != 1 || args.count(it == '-Wl,--no-undefined') != 1
		|| args.count(it == '-shared') != 1 || args.count(it == '-o') != 1
		|| args[args.len - 2..] != ['-o', dso] {
		return error('current native Werror shared-link command receipt differs')
	}
	export_command := json2.decode[map[string]json2.Any](os.read_file(current + '/commands/exports.json')!)!
	export_args := json2.decode[[]string](json2.encode(export_command['argv']!))!
	if export_command['exit_code']!.int() != 0 || export_args != [
		'/opt/homebrew/bin/aarch64-linux-musl-nm', '-D', '--defined-only', dso] {
		return error('current native export command receipt differs')
	}
	exports := json2.decode[[]string](os.read_file(current + '/native/exports.json')!)!
	mut expected := ['_init', '_fini']
	for source in os.ls(current + '/native/atlframework')! {
		if !source.ends_with('.v') { return error('unexpected native source closure member') }
		for line in os.read_file(current + '/native/atlframework/' + source)!.split_into_lines() {
			if line.starts_with("@[export: '") { expected << line.all_after("@[export: '").all_before("'") }
		}
	}
	expected.sort()
	if expected.len <= 2 || expected != exports {
		return error('current native export receipt differs from complete source annotations')
	}
	for i, symbol in exports {
		if symbol == '' || !symbol.bytes().all((it >= `a` && it <= `z`)
			|| (it >= `A` && it <= `Z`) || (it >= `0` && it <= `9`) || it == `_`)
			|| (i > 0 && exports[i - 1] == symbol) {
			return error('unsafe or duplicate current native export')
		}
	}
	return exports
}

fn executable_items() [][]string {
	return [['native-entry', 'vinix-android-native'], ['launcher', 'run-android'],
		['controller', 'headless-service-controller']]
}

fn executable_receipts() []string {
	mut names := ['build.json', 'sha256.json']
	for item in executable_items() {
		for action in ['generate', 'compile', 'build'] { names << 'commands/' + action + '-' + item[0] + '.json' }
		names << 'commands/compile-' + item[0] + '-runtime.json'
	}
	return names
}

fn executable_destinations() []string {
	return executable_receipts().map('current-launch-' + it.replace('commands/', '').replace('/', '-'))
}

fn executable_outputs(pins map[string]string) !map[string]string {
	mut expected := map[string]string{}
	for item in executable_items() { expected['bin/' + item[1]] = pins['bin/' + item[1]]! }
	return expected
}

fn verify_executable_identity(profile FrameworkProfile, framework string, baseline string,
	pins map[string]string, receipt map[string]json2.Any) ! {
	expected := executable_outputs(pins)!
	if profile.seal != interaction_framework_seal {
		return error('current executable receipt requires the audited interaction framework profile')
	}
	for field, value in {
		'kind': 'vinix-current-launch-v1'
		'framework': framework
		'framework_sha256': profile.seal
		'native_base': baseline
		'native_base_sha256': full_native_seal
		'compiler_sha256': compiler_pin
	} {
		if receipt[field]!.str() != value {
			return error('current executable receipt field differs: ' + field)
		}
	}
	if !seven_arguments(receipt['service_main_argc']!) {
		return error('current executable receipt service_main_argc must be the integer 7')
	}
	for field in ['source_revision', 'completed_utc'] {
		if receipt[field]!.str() == '' {
			return error('current executable receipt field is empty: ' + field)
		}
	}
	if json2.decode[map[string]string](json2.encode(receipt['outputs_sha256']!))! != expected {
		return error('current executable receipt outputs_sha256 differs from the exact sealed output set')
	}
}

fn seven_arguments(value json2.Any) bool {
	// This decoder represents an untagged JSON number as f64, including 7.
	// Compare the numeric value exactly; coercion would accept fractions and
	// wrapped values. Strings, booleans and all other variants remain invalid.
	return match value {
		int { value == 7 }
		i64 { value == 7 }
		u64 { value == 7 }
		f64 { value == 7.0 }
		else { false }
	}
}

fn executable_includes(root string, label string, pins map[string]string) []string {
	mut flags := []string{}
	for name in pins.keys().filter(it.starts_with('closure/' + label + '/') && it.ends_with('.h')) {
		flag := '-I' + os.dir(root + '/' + name)
		if flag !in flags { flags << flag }
	}
	flags.sort()
	return flags
}

fn executable_source(root string, label string, pins map[string]string) !string {
	suffix := match label {
		'native-entry' { '/build-support/android/native-entry.v' }
		'launcher' { '/build-support/android/native-run.v' }
		'controller' { '/tests/native-android-ws/headless-service-controller.v' }
		else { return error('unknown current executable source') }
	}
	sources := pins.keys().filter(it.starts_with('closure/' + label + '/') && it.ends_with(suffix))
	if sources.len != 1 { return error('current executable source closure is ambiguous: ' + label) }
	return root + '/' + sources[0]
}

fn executable_runtime_source(root string, label string, pins map[string]string) !string {
	sources := pins.keys().filter(it.starts_with('closure/' + label + '/')
		&& it.ends_with('/vlib/builtin/segfault_handler_nix.c'))
	if sources.len != 1 { return error('current executable signal runtime closure is ambiguous: ' + label) }
	return root + '/' + sources[0]
}

fn verify_executable_command(root string, label string, action string, receipt map[string]json2.Any,
	includes []string, source string) ! {
	args := json2.decode[[]string](json2.encode(receipt['argv']!))!
	if receipt['exit_code']!.int() != 0 { return error('current executable command failed') }
	if action == 'generate' {
		if receipt['executable_sha256']!.str() != compiler_pin || args.len != 19
			|| args[1..15] != ['-new-compiler', '-os', 'linux', '-arch', 'arm64', '-cc', cross,
				'-gc', 'none', '-nocache', '-skip-running', '-exclude', '@vlib/crypto/rand/internal/rand.wasm.v', '-path']
			|| !args[15].split('|').all(it.starts_with(root + '/closure/' + label + '/') && relative(it[root.len + 1..]))
			|| args[16..18] != ['-o', root + '/generated/' + label + '.c']
			|| args.last() != source {
			return error('current executable frozen generation command differs')
		}
		return
	}
	mut expected := [cross, '-v']
	if action in ['compile', 'runtime'] {
		expected << ['-D_GNU_SOURCE', '-O2', '-fwrapv', '-pthread', '-Werror=implicit-function-declaration', '-Werror=int-conversion']
		expected << includes
		expected << if action == 'runtime' {
			['-c', source, '-o', root + '/generated/' + label + '-runtime.o']
		} else {
			['-c', root + '/generated/' + label + '.c', '-o', root + '/generated/' + label + '.o']
		}
	} else if action == 'build' {
		expected << ['-no-pie', '-pthread', '-Wl,-t']
		if label != 'native-entry' { expected << '-static' }
		items := executable_items().filter(it[0] == label)
		if items.len != 1 { return error('unknown current executable label') }
		expected << [root + '/generated/' + label + '.o', root + '/generated/' + label + '-runtime.o',
			'-ldl', '-lm', '-o', root + '/bin/' + items[0][1]]
	} else { return error('unknown current executable command action') }
	if args != expected { return error('current executable cross command differs: ' + label + '/' + action) }
}

fn executable_elf(path string, dynamic bool) ! {
	bytes := os.read_bytes(path)!
	if bytes.len < 64 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| bytes[16..20] != [u8(2), 0, 183, 0] { return error('current executable is not AArch64 ELF64 ET_EXEC') }
	mut offset := u64(0)
	for i in 0 .. 8 { offset |= u64(bytes[32 + i]) << (8 * i) }
	stride := int(bytes[54]) | int(bytes[55]) << 8
	count := int(bytes[56]) | int(bytes[57]) << 8
	if count == 0 || stride < 56 || offset < 64 || offset > u64(bytes.len)
		|| u64(stride * count) > u64(bytes.len) - offset { return error('invalid executable program headers') }
	mut loads := 0
	mut interpreters := 0
	for i in 0 .. count {
		at := int(offset) + i * stride
		if bytes[at..at + 4] == [u8(1), 0, 0, 0] { loads++ }
		if bytes[at..at + 4] == [u8(3), 0, 0, 0] {
			interpreters++
			mut start := u64(0)
			mut size := u64(0)
			for j in 0 .. 8 { start |= u64(bytes[at + 8 + j]) << (8 * j); size |= u64(bytes[at + 32 + j]) << (8 * j) }
			if start > u64(bytes.len) || size > u64(bytes.len) - start
				|| bytes[int(start)..int(start + size)] != '/lib/ld-musl-aarch64.so.1\x00'.bytes() {
				return error('current executable interpreter differs')
			}
		}
	}
	if loads == 0 || interpreters != if dynamic { 1 } else { 0 } {
		return error('current executable static/dynamic contract differs')
	}
}

fn verify_service_abi(entry string, implementation string, entry_implementation_sha string,
	native_implementation_sha string) ! {
	if entry_implementation_sha != native_implementation_sha
		|| !entry.contains('type NativeServiceMain = fn (&char, &char, &char, &char, &char, i32, i32) i32')
		|| !entry.contains('launch.action.str, i32(control_fd), i32(ui_fd))')
		|| !implementation.contains('fn ws_service_main(root &char, apk &char, package_name &char, service &char, action &char, control_fd i32, ui_fd i32) i32 {') {
		return error('current native and executable service implementation snapshots differ')
	}
}

fn verify_current_executables(root string, framework string, profile FrameworkProfile,
	baseline string, pins map[string]string, native_pins map[string]string) ! {
	receipt := json2.decode[map[string]json2.Any](os.read_file(root + '/build.json')!)!
	verify_executable_identity(profile, framework, baseline, pins, receipt)!
	if hash(root + '/framework-sha256.json')! != profile.seal
		|| hash(root + '/baseline-sha256.json')! != full_native_seal {
		return error('current executable retained input manifests differ')
	}
	// The same implementation snapshot must underlie both sides of the ABI.
	verify_service_abi(os.read_file(executable_source(root, 'native-entry', pins)!)!, os.read_file(root + '/abi/headless.v')!,
		pins['abi/headless.v']!, native_pins['native/atlframework/headless.v']!)!
	for item in executable_items() {
		executable_elf(root + '/bin/' + item[1], item[0] == 'native-entry')!
		for generated in ['generated/' + item[0] + '.c', 'generated/' + item[0] + '.o',
			'generated/' + item[0] + '-runtime.o', 'generated/' + item[0] + '-runtime-headers.json'] {
			if generated !in pins { return error('current executable generated artifact missing: ' + generated) }
		}
		includes := executable_includes(root, item[0], pins)
		source := executable_source(root, item[0], pins)!
		for action in ['generate', 'compile', 'build'] {
			command_receipt := json2.decode[map[string]json2.Any](os.read_file(root + '/commands/' + action + '-' + item[0] + '.json')!)!
			verify_executable_command(root, item[0], action, command_receipt, includes, source)!
			if action == 'generate' {
				args := json2.decode[[]string](json2.encode(command_receipt['argv']!))!
				if !args[0].starts_with(root + '/closure/' + item[0] + '/')
					|| pins[args[0][root.len + 1..]]! != compiler_pin
					|| args.last()[root.len + 1..] !in pins {
					return error('current executable generator compiler is outside its pinned closure')
				}
			}
		}
		runtime_receipt := json2.decode[map[string]json2.Any](os.read_file(root + '/commands/compile-' + item[0] + '-runtime.json')!)!
		verify_executable_command(root, item[0], 'runtime', runtime_receipt, includes,
			executable_runtime_source(root, item[0], pins)!)!
	}
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

fn baseline_members() map[string]Entry {
	return {
		jar_member:    Entry{ name: jar_member, kind: 'regular', mode: 0o644, size: 1170131, sha256: baseline_jar_sha }
		native_member: Entry{ name: native_member, kind: 'regular', mode: 0o755, size: 809288, sha256: baseline_native_sha }
		entry_member:  Entry{ name: entry_member, kind: 'regular', mode: 0o755, size: 236592, sha256: '611b0e74b21c669aad9d17cef0d3e83d93be6cb57c103cc3f1d3444015e4b5da' }
	}
}

fn verify_baseline(effective map[string]Entry) ! {
	// The launcher is a new runtime file; the other three must exactly match
	// their qualified baseline metadata. Equality also requires launcher absence.
	if effective != baseline_members() {
		return error('baseline effective replacement/addition set differs')
	}
}

// Three existing runtime members are replaced and one new launcher is added.
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

fn verify_guest_compiler(path string) ! {
	if hash(path)! != compiler_pin { return error('guest compiler pin differs') }
}

fn build_guest(root string, mut inputs map[string]string) ! {
	verify_guest_compiler(compiler)!
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
	verify_guest_compiler(compiler)!
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

fn verify_plan(entries []Entry, current_native bool, current_executables bool) ! {
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
	if current_native {
		for name in current_native_destinations() { expected[diagnostic_prefix + '/' + name] = 'regular' }
	}
	if current_executables {
		for name in executable_destinations() { expected[diagnostic_prefix + '/' + name] = 'regular' }
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
	if os.args.len !in [8, 10, 12] {
		return error('usage: headless-service-stage BASE_BOOT BASE_EFIVARS FRAMEWORK_BUILD NATIVE_BUILD NATIVE_SEAL FIXTURE_DIR FRESH_OUTPUT [CURRENT_DSO_BUILD CURRENT_DSO_SEAL [CURRENT_EXECUTABLES_BUILD CURRENT_EXECUTABLES_SEAL]]')
	}
	$if !macos {
		return error('staging requires macOS APFS clonefile')
	}
	boot, efivars := os.real_path(os.args[1]), os.real_path(os.args[2])
	framework, native, fixture := os.real_path(os.args[3]), os.real_path(os.args[4]), os.real_path(os.args[6])
	current_native := os.args.len >= 10
	current := if current_native { os.real_path(os.args[8]) } else { '' }
	current_executables := os.args.len == 12
	executables := if current_executables { os.real_path(os.args[10]) } else { '' }
	root := external(os.args[7])!
	mut input_roots := [boot, efivars, framework, native, fixture]
	if current_native { input_roots << current }
	if current_executables { input_roots << executables }
	for input in input_roots {
		if root == input || input.starts_with(root + '/') || root.starts_with(input + '/') {
			return error('output overlaps an input')
		}
	}
	profile := framework_profile(hash(framework + '/sha256.json')!)!
	verify_mode(profile, current_native, current_executables)!
	if hash(compiler)! != compiler_pin || hash(boot)! != baseline_boot_sha
		|| hash(fixture + '/probe.apk')! != fixture_apk_sha {
		return error('fixed baseline/fixture pin differs')
	}
	mcopy, mtype, mdir := os.find_abs_path_of_executable('mcopy')!, os.find_abs_path_of_executable('mtype')!, os.find_abs_path_of_executable('mdir')!
	os.setenv('PATH', os.dir(mcopy) + ':' + os.getenv('PATH'), true)
	mut inputs := map[string]string{}
	for path in [boot, efivars, mcopy, mtype, mdir, '/usr/bin/shasum', '/usr/bin/git', compiler,
		cross, os.executable()] {
		inputs[path] = hash(path)!
	}
	framework_pins := sealed_bundle(framework, profile.seal, mut inputs)!
	native_pins := sealed_bundle(native, os.args[5], mut inputs)!
	framework_receipt := json2.decode[map[string]json2.Any](os.read_file(framework + '/build.json')!)!
	native_receipt := json2.decode[map[string]json2.Any](os.read_file(native + '/build.json')!)!
	verify_framework(profile, hash(framework + '/api-impl.jar')!, framework_receipt)!
	if native_receipt['baseline_native_sha256']!.str() != 'aa460c06686e2d1f60ea6dd27ab8f158a3b9794440499c6cdc5e7840cafda0cb'
		|| native_receipt['native_sha256']!.str() != native_pins['native/libvinix-android-native.so']! {
		return error('native build receipt identity differs')
	}
	mut current_pins := map[string]string{}
	mut executable_pins := map[string]string{}
	mut current_exports := []string{}
	if current_native {
		current_pins = sealed_bundle(current, os.args[9], mut inputs)!
		current_exports = verify_current_native(current, framework, profile, native, os.args[5], current_pins)!
		inputs['/opt/homebrew/bin/aarch64-linux-musl-nm'] = hash('/opt/homebrew/bin/aarch64-linux-musl-nm')!
	}
	if current_executables {
		executable_pins = sealed_bundle(executables, os.args[11], mut inputs)!
		verify_current_executables(executables, framework, profile, native, executable_pins, current_pins)!
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
	if current_native {
		listing := command(root, 'verify-current-native-exports', [
			'/opt/homebrew/bin/aarch64-linux-musl-nm', '-D', '--defined-only',
			current + '/native/libvinix-android-native.so'])!
		mut exports := listing.split_into_lines().filter(it.fields().len >= 3).map(it.fields().last())
		exports.sort()
		if exports != current_exports { return error('current native ELF exports differ from audited receipt') }
		for i, name in current_native_receipts() {
			os.cp(current + '/' + name, root + '/payload/' + current_native_destinations()[i])!
		}
	}
	if current_executables {
		for i, name in executable_receipts() {
			os.cp(executables + '/' + name, root + '/payload/' + executable_destinations()[i])!
		}
	}
	for pair in [
		[(if current_executables { executables } else { native }) + '/bin/headless-service-controller',
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
	if current_native { sources[native_member] = current + '/native/libvinix-android-native.so' }
	if current_executables {
		sources[entry_member] = executables + '/bin/vinix-android-native'
		sources[launcher_member] = executables + '/bin/run-android'
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
	verify_plan(entries, current_native, current_executables)!
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
	write_json(root + '/runtime-replacements-before.json', effective)!
	verify_baseline(effective)!
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
	if sealed_bundle(framework, profile.seal, mut inputs)! != framework_pins
		|| sealed_bundle(native, os.args[5], mut inputs)! != native_pins {
		return error('bundle changed during staging')
	}
	if current_native && sealed_bundle(current, os.args[9], mut inputs)! != current_pins {
		return error('current native bundle changed during staging')
	}
	if current_executables && sealed_bundle(executables, os.args[11], mut inputs)! != executable_pins {
		return error('current executable bundle changed during staging')
	}
	revision := command(root, 'source-revision', ['/usr/bin/git', 'rev-parse', 'HEAD'])!.trim_space()
	write_json(root + '/stage.json', {
		'format':                           json2.Any(1)
		'scope':                            json2.Any('synthetic headless lifecycle staging only; no guest launched or Google authentication claim')
		'preparation_checkout_revision':    json2.Any(revision)
		'compiled_stage_source_sha256':     json2.Any(sha256.sum(compiled_source.bytes()).hex())
		'compiled_guest_source_sha256':     json2.Any(sha256.sum(compiled_guest.bytes()).hex())
		'compiled_collector_source_sha256': json2.Any(sha256.sum(compiled_collector.bytes()).hex())
		'framework_profile':                json2.Any(profile.name)
		'framework_manifest_sha256':        json2.Any(profile.seal)
		'framework_jar_sha256':             json2.Any(profile.jar_sha256)
		'framework_class_count':            json2.Any(profile.class_count)
		'native_base_manifest_sha256':      json2.Any(os.args[5])
		'current_native_manifest_sha256':   json2.Any(if current_native { os.args[9] } else { '' })
		'current_native_sha256':            json2.Any(if current_native { current_pins['native/libvinix-android-native.so']! } else { '' })
		'current_executables_manifest_sha256': json2.Any(if current_executables { os.args[11] } else { '' })
		'current_executables_sha256':       json2.decode[json2.Any](json2.encode(if current_executables { executable_outputs(executable_pins)! } else { map[string]string{} }))!
		'service_main_argc':               json2.Any(if current_executables { 7 } else { 6 })
		'inputs_sha256':                    json2.decode[json2.Any](json2.encode(inputs))!
		'original_modules_sha256':          json2.decode[json2.Any](json2.encode(before))!
		'preserved_modules_sha256':         json2.decode[json2.Any](json2.encode(after))!
		'overlay_inventory':                json2.decode[json2.Any](json2.encode(entries))!
		'runtime_replaced':                 json2.Any([json2.Any(jar_member), json2.Any(native_member),
			json2.Any(entry_member)])
		'runtime_added':                    json2.Any([json2.Any(launcher_member)])
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
	verify_guest_compiler(compiler)!
	if _ := verify_guest_compiler(os.executable()) { return error('untrusted guest compiler accepted') }
	for seal in [framework_seal, combined_framework_seal, interaction_framework_seal] {
		profile := framework_profile(seal)!
		assert profile.seal == seal
		if profile.class_count != match seal { framework_seal { 2098 } combined_framework_seal { 2101 } else { 2102 } } {
			return error('audited framework class count differs')
		}
		receipt := {
			'api_impl_sha256': json2.Any(profile.jar_sha256)
			'class_count': json2.Any(profile.class_count)
		}
		verify_framework(profile, profile.jar_sha256, receipt)!
		other := framework_profile(if seal == framework_seal { combined_framework_seal } else { framework_seal })!
		if _ := verify_framework(profile, other.jar_sha256, receipt) {
			return error('cross-paired framework JAR accepted')
		}
		for bad in [{
			'api_impl_sha256': json2.Any(other.jar_sha256)
			'class_count': json2.Any(profile.class_count)
		}, {
			'api_impl_sha256': json2.Any(profile.jar_sha256)
			'class_count': json2.Any(other.class_count)
		}, map[string]json2.Any{}] {
			if _ := verify_framework(profile, profile.jar_sha256, bad) {
				return error('cross-paired or incomplete framework receipt accepted')
			}
		}
	}
	for bad in ['', '0'.repeat(64), combined_framework_seal.to_upper()] {
		if _ := framework_profile(bad) { return error('unknown framework profile accepted') }
	}
	combined := framework_profile(combined_framework_seal)!
	current_receipt := {
		'framework': json2.Any('/framework')
		'framework_sha256': json2.Any(combined_framework_seal)
		'baseline': json2.Any('/native-base')
		'baseline_sha256': json2.Any(full_native_seal)
		'native_sha256': json2.Any('a'.repeat(64))
		'source_revision': json2.Any('reviewed-source')
		'completed_utc': json2.Any('2026-10-26 00:00:00')
	}
	verify_current_identity(combined, '/framework', full_native_seal, '/native-base', 'a'.repeat(64), current_receipt)!
	for field in current_receipt.keys() {
		mut bad := json2.decode[map[string]json2.Any](json2.encode(current_receipt))!
		bad[field] = json2.Any(if field == 'baseline' { '/current' } else { '' })
		if _ := verify_current_identity(combined, '/framework', full_native_seal, '/native-base', 'a'.repeat(64), bad) {
			return error('incomplete or mismatched current native identity accepted: ' + field)
		}
	}
	if _ := verify_current_identity(framework_profile(framework_seal)!, '/framework', full_native_seal,
		'/native-base', 'a'.repeat(64), current_receipt) { return error('current DSO paired with old framework') }
	if _ := verify_current_identity(combined, '/framework', '0'.repeat(64), '/native-base',
		'a'.repeat(64), current_receipt) { return error('current DSO paired with unknown full native base') }
	interaction := framework_profile(interaction_framework_seal)!
	verify_mode(framework_profile(framework_seal)!, false, false)!
	verify_mode(combined, true, false)!
	verify_mode(interaction, true, true)!
	for mode in [[false, false], [true, false], [false, true]] {
		if _ := verify_mode(interaction, mode[0], mode[1]) { return error('interaction framework accepted without matching native/entry pair') }
	}
	for old in [framework_profile(framework_seal)!, combined] {
		if _ := verify_mode(old, true, true) { return error('seven-argument executable bundle accepted with historical framework') }
	}
	mut executable_pins := map[string]string{}
	for item in executable_items() { executable_pins['bin/' + item[1]] = 'b'.repeat(64) }
	executable_receipt := {
		'kind': json2.Any('vinix-current-launch-v1')
		'framework': json2.Any('/framework')
		'framework_sha256': json2.Any(interaction_framework_seal)
		'native_base': json2.Any('/native-base')
		'native_base_sha256': json2.Any(full_native_seal)
		'service_main_argc': json2.Any(7)
		'compiler_sha256': json2.Any(compiler_pin)
		'outputs_sha256': json2.decode[json2.Any](json2.encode(executable_pins))!
		'source_revision': json2.Any('reviewed-source')
		'completed_utc': json2.Any('2026-10-26 00:00:00')
	}
	verify_executable_identity(interaction, '/framework', '/native-base', executable_pins, executable_receipt)!
	parsed_executable_receipt := json2.decode[map[string]json2.Any](json2.encode(executable_receipt))!
	verify_executable_identity(interaction, '/framework', '/native-base', executable_pins, parsed_executable_receipt)!
	for valid in ['7', '7.0', '7e0'] {
		assert seven_arguments(json2.decode[json2.Any](valid)!)
	}
	for invalid in ['6', '7.9', '"7"', 'true', 'null', '4294967303', '-4294967289'] {
		mut bad := json2.decode[map[string]json2.Any](json2.encode(parsed_executable_receipt))!
		bad['service_main_argc'] = json2.decode[json2.Any](invalid)!
		if _ := verify_executable_identity(interaction, '/framework', '/native-base', executable_pins, bad) {
			return error('non-integer or wrong current executable argument count accepted: ' + invalid)
		}
	}
	for field in executable_receipt.keys() {
		mut bad := json2.decode[map[string]json2.Any](json2.encode(executable_receipt))!
		bad[field] = if field == 'service_main_argc' { json2.Any(6) } else { json2.Any('') }
		if _ := verify_executable_identity(interaction, '/framework', '/native-base', executable_pins, bad) {
			return error('mismatched or incomplete current executable identity accepted: ' + field)
		}
	}
	mut extra_outputs := executable_pins.clone()
	extra_outputs['bin/unlisted'] = 'b'.repeat(64)
	mut extra_receipt := json2.decode[map[string]json2.Any](json2.encode(executable_receipt))!
	extra_receipt['outputs_sha256'] = json2.decode[json2.Any](json2.encode(extra_outputs))!
	if _ := verify_executable_identity(interaction, '/framework', '/native-base', executable_pins, extra_receipt) {
		return error('unlisted current executable accepted')
	}
	for item in executable_items() {
		mut link := [cross, '-v', '-no-pie', '-pthread', '-Wl,-t']
		if item[0] != 'native-entry' { link << '-static' }
		link << ['/current/generated/' + item[0] + '.o', '/current/generated/' + item[0] + '-runtime.o',
			'-ldl', '-lm', '-o', '/current/bin/' + item[1]]
		receipt := {'argv': json2.Any(link), 'exit_code': json2.Any(0)}
		verify_executable_command('/current', item[0], 'build', receipt, [], '')!
		mut bad := json2.decode[map[string]json2.Any](json2.encode(receipt))!
		bad['argv'] = json2.Any(link.filter(it != '-no-pie'))
		if _ := verify_executable_command('/current', item[0], 'build', bad, [], '') { return error('altered executable link command accepted') }
		header_pins := {
			'closure/' + item[0] + '/vlib/builtin/a.h': 'a'.repeat(64)
			'closure/' + item[0] + '/vlib/builtin/b.h': 'b'.repeat(64)
			'closure/' + item[0] + '/vlib/x/c.h': 'c'.repeat(64)
			'closure/unrelated/vlib/foreign.h': 'd'.repeat(64)
		}
		includes := executable_includes('/current', item[0], header_pins)
		if includes != ['-I/current/closure/' + item[0] + '/vlib/builtin', '-I/current/closure/' + item[0] + '/vlib/x'] {
			return error('current executable include directories differ from exact sorted closure')
		}
		mut compile_args := [cross, '-v', '-D_GNU_SOURCE', '-O2', '-fwrapv', '-pthread', '-Werror=implicit-function-declaration', '-Werror=int-conversion']
		compile_args << includes
		compile_args << ['-c', '/current/generated/' + item[0] + '.c', '-o', '/current/generated/' + item[0] + '.o']
		compile_receipt := {'argv': json2.Any(compile_args), 'exit_code': json2.Any(0)}
		verify_executable_command('/current', item[0], 'compile', compile_receipt, includes, '')!
		mut bad_compile := json2.decode[map[string]json2.Any](json2.encode(compile_receipt))!
		bad_compile['argv'] = json2.Any(compile_args.filter(it != '-Werror=int-conversion'))
		if _ := verify_executable_command('/current', item[0], 'compile', bad_compile, includes, '') { return error('altered executable compile command accepted') }
		if _ := verify_executable_command('/current', item[0], 'compile', compile_receipt, [], '') { return error('unsealed executable header include accepted') }
		runtime_source := '/current/closure/' + item[0] + '/vlib/builtin/segfault_handler_nix.c'
		mut runtime_args := compile_args[..compile_args.len - 4].clone()
		runtime_args << ['-c', runtime_source, '-o', '/current/generated/' + item[0] + '-runtime.o']
		runtime_receipt := {'argv': json2.Any(runtime_args), 'exit_code': json2.Any(0)}
		verify_executable_command('/current', item[0], 'runtime', runtime_receipt, includes, runtime_source)!
		if _ := verify_executable_command('/current', item[0], 'runtime', runtime_receipt, includes, runtime_source + '.unsealed') {
			return error('unsealed executable signal runtime source accepted')
		}
		mut missing_runtime := json2.decode[map[string]json2.Any](json2.encode(receipt))!
		missing_runtime['argv'] = json2.Any(link.filter(!it.ends_with('-runtime.o')))
		if _ := verify_executable_command('/current', item[0], 'build', missing_runtime, [], '') {
			return error('missing executable signal runtime object accepted')
		}
		generation := {
			'argv': json2.Any(['/current/closure/' + item[0] + '/v', '-new-compiler', '-os', 'linux', '-arch', 'arm64', '-cc', cross,
				'-gc', 'none', '-nocache', '-skip-running', '-exclude', '@vlib/crypto/rand/internal/rand.wasm.v', '-path', '/current/closure/' + item[0] + '/vlib',
				'-o', '/current/generated/' + item[0] + '.c', '/current/closure/' + item[0] + '/source.v'])
			'exit_code': json2.Any(0)
			'executable_sha256': json2.Any(compiler_pin)
		}
		verify_executable_command('/current', item[0], 'generate', generation, [], '/current/closure/' + item[0] + '/source.v')!
		if _ := verify_executable_command('/current', item[0], 'generate', generation, [], '/current/closure/' + item[0] + '/other.v') {
			return error('unrelated generation source accepted under matching ABI closure')
		}
		mut bad_generation := json2.decode[map[string]json2.Any](json2.encode(generation))!
		bad_generation['executable_sha256'] = json2.Any('0'.repeat(64))
		if _ := verify_executable_command('/current', item[0], 'generate', bad_generation, [], '/current/closure/' + item[0] + '/source.v') { return error('untrusted executable generator compiler accepted') }
	}
	entry_abi := 'type NativeServiceMain = fn (&char, &char, &char, &char, &char, i32, i32) i32\nlaunch.action.str, i32(control_fd), i32(ui_fd))'
	implementation_abi := 'fn ws_service_main(root &char, apk &char, package_name &char, service &char, action &char, control_fd i32, ui_fd i32) i32 {'
	verify_service_abi(entry_abi, implementation_abi, 'same-sha', 'same-sha')!
	for bad in [[entry_abi, implementation_abi, 'different-sha', 'same-sha'],
		[entry_abi.replace(', i32, i32)', ', i32)'), implementation_abi, 'same-sha', 'same-sha'],
		[entry_abi.replace(', i32(ui_fd)', ''), implementation_abi, 'same-sha', 'same-sha'],
		[entry_abi, implementation_abi.replace(', ui_fd i32', ''), 'same-sha', 'same-sha']] {
		if _ := verify_service_abi(bad[0], bad[1], bad[2], bad[3]) { return error('incompatible or mixed seven-argument service ABI accepted') }
	}
	config := '/Vinix\n    protocol: limine\n    module_path: boot():/boot/initramfs.tar\n    module_path: boot():/boot/runtime.tar\n'
	parsed := configure(config)!
	assert parsed.modules == ['initramfs.tar', 'runtime.tar']
	assert parsed.updated == config + '    module_path: boot():/boot/' + overlay_name + '\n'
	assert configure(config.trim_right('\n'))!.updated == parsed.updated
	verify_baseline(baseline_members())!
	mut baseline_missing := baseline_members()
	baseline_missing.delete(entry_member)
	mut baseline_extra := baseline_members()
	baseline_extra[launcher_member] = Entry{ name: launcher_member, kind: 'regular', mode: 0o755 }
	mut baseline_changed := baseline_members()
	baseline_changed[entry_member] = Entry{ name: entry_member, kind: 'regular', mode: 0o755, size: 236592, sha256: '0'.repeat(64) }
	mut baseline_mode := baseline_members()
	baseline_mode[entry_member] = Entry{ name: entry_member, kind: 'regular', mode: 0o644, size: 236592, sha256: '611b0e74b21c669aad9d17cef0d3e83d93be6cb57c103cc3f1d3444015e4b5da' }
	for bad in [baseline_missing, baseline_extra, baseline_changed, baseline_mode] {
		mut rejected := false
		verify_baseline(bad) or { rejected = true }
		assert rejected
	}
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
	verify_plan(entries, false, false)!
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
		verify_plan(bad, false, false) or { rejected = true }
		assert rejected
	}
	mut current_entries := entries.clone()
	for name in current_native_destinations() {
		current_entries << Entry{ name: diagnostic_prefix + '/' + name, kind: 'regular', mode: 0o644 }
	}
	verify_plan(current_entries, true, false)!
	assert current_entries.len == 20
	if _ := verify_plan(current_entries, false, false) { return error('current native receipts leaked into old exact allowlist') }
	if _ := verify_plan(entries, true, false) { return error('missing current native receipts accepted') }
	for i in entries.len .. current_entries.len {
		mut missing_receipt := current_entries.clone()
		missing_receipt.delete(i)
		if _ := verify_plan(missing_receipt, true, false) { return error('incomplete current native receipt set accepted') }
	}
	mut executable_entries := current_entries.clone()
	for name in executable_destinations() {
		executable_entries << Entry{ name: diagnostic_prefix + '/' + name, kind: 'regular', mode: 0o644 }
	}
	verify_plan(executable_entries, true, true)!
	if executable_entries.len != 34 { return error('current executable receipt count differs') }
	if _ := verify_plan(executable_entries, true, false) { return error('executable receipts leaked into historical native-only allowlist') }
	for i in current_entries.len .. executable_entries.len {
		mut missing_receipt := executable_entries.clone()
		missing_receipt.delete(i)
		if _ := verify_plan(missing_receipt, true, true) { return error('incomplete current executable receipt set accepted') }
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
	elf[16] = 3
	elf[32] = 64
	elf[54] = 56
	elf[56] = 1
	os.write_file_array(root + '/static', elf)!
	static_elf(root + '/static')!
	shared_elf(root + '/static')!
	mut launch_elf := []u8{len: 240}
	for i, value in [u8(0x7f), `E`, `L`, `F`, 2, 1] { launch_elf[i] = value }
	launch_elf[16] = 2
	launch_elf[18] = 183
	launch_elf[32] = 64
	launch_elf[54] = 56
	launch_elf[56] = 1
	launch_elf[64] = 1
	os.write_file_array(root + '/launch-static', launch_elf)!
	executable_elf(root + '/launch-static', false)!
	if _ := executable_elf(root + '/launch-static', true) { return error('static current native entry accepted') }
	launch_elf[56] = 2
	launch_elf[120] = 3
	launch_elf[128] = 176
	interpreter := '/lib/ld-musl-aarch64.so.1\x00'.bytes()
	launch_elf[152] = u8(interpreter.len)
	for i, value in interpreter { launch_elf[176 + i] = value }
	os.write_file_array(root + '/launch-dynamic', launch_elf)!
	executable_elf(root + '/launch-dynamic', true)!
	if _ := executable_elf(root + '/launch-dynamic', false) { return error('dynamic current launcher/controller accepted') }
	for at in [16, 18, 56, 64, 120, 128, 152, 176] {
		mut invalid := launch_elf.clone()
		invalid[at] = 0
		os.write_file_array(root + '/launch-invalid', invalid)!
		if _ := executable_elf(root + '/launch-invalid', true) { return error('invalid current executable accepted: ' + at.str()) }
	}
	for bad in [16, 18] {
		mut invalid := elf.clone()
		invalid[bad] = 0
		os.write_file_array(root + '/invalid-shared', invalid)!
		if _ := shared_elf(root + '/invalid-shared') { return error('invalid current native ELF accepted') }
	}
	elf[64] = 3
	os.write_file_array(root + '/dynamic', elf)!
	mut rejected_dynamic := false
	static_elf(root + '/dynamic') or { rejected_dynamic = true }
	assert rejected_dynamic
	println('HEADLESS-STAGE SELF-TEST PASS audited-framework-profiles mixed-framework-rejection current-native-coupling current-native-exact-receipts seven-argument-pairing executable-exact-receipts compile-link-receipts matching-service-source executable-interpreter config-prefix baseline-existing added-launcher collision caches exact-allowlist streamed-archive modes fresh-output QMP-limit full-seal static-ELF shared-ELF')
	println('HEADLESS-STAGE COMPILED-SOURCES ' + sha256.sum(compiled_source.bytes()).hex() +
		' ' + sha256.sum(compiled_guest.bytes()).hex() + ' ' + sha256.sum(compiled_collector.bytes()).hex())
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--inspect-baseline' {
		inspect_baseline(os.args[2]) or {
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

// Read-only diagnostic for the effective targets, including targets absent
// from the original modules. Keep failed staging roots unchanged.
fn inspect_baseline(boot string) ! {
	if hash(boot)! != baseline_boot_sha { return error('qualified baseline boot differs') }
	mcopy := os.find_abs_path_of_executable('mcopy')!
	mut effective := map[string]Entry{}
	for name in ['initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar',
		'maps350-diagnostics.tar', 'maps372-diagnostics.tar'] {
		check_module(mcopy, boot, name, mut effective)!
	}
	verify_baseline(effective)!
	println(json2.encode(effective, prettify: true))
}
