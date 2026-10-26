// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

import crypto.sha256
import json2
import os

pub const baseline_seal = 'd99195272b8af813679cf54fed9f1e0341e6f1115804ac09c1cd2d5a8f942e3e'
pub const compiler_seal = '0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe'
pub const sqlite_seal = '5a228127ca3ffa0c88bcae0aa5f7ab10e15b383dfb46822c573013105628bbaa'

pub struct Bundle {
pub:
	root    string
	seal    string
	files   map[string]string
	receipt map[string]json2.Any
}

pub struct Framework {
pub:
	jar     string
	dex     string
	profile string
}

pub fn digest(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut state := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := input.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		state.write(buffer[..n])!
	}
	return state.sum([]u8{}).hex()
}

pub fn valid_pin(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `a` && it <= `f`) || (it >= `0` && it <= `9`))
}

pub fn relative_file(path string) bool {
	return path != '' && !path.starts_with('/') && !path.contains_any('\\\x00\n\r\t')
		&& path.split('/').all(it !in ['', '.', '..'])
}

fn collect_files(root string, relative string, mut result map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		path := if relative == '' { name } else { relative + '/' + name }
		if !relative_file(path) { return error('unsafe sealed bundle path') }
		match os.lstat(root + '/' + path)!.get_filetype() {
			.directory { collect_files(root, path, mut result)! }
			.regular { if path != 'sha256.json' { result[path] = digest(root + '/' + path)! } }
			else { return error('sealed bundle contains a symlink or special inode: ' + path) }
		}
	}
}

pub fn load_inventory(root string, seal string) !map[string]string {
	if os.lstat(root + '/sha256.json')!.size > 32 * 1024 * 1024 {
		return error('bundle manifest exceeds bound')
	}
	if root != os.real_path(root) || !os.is_dir(root) || os.is_link(root) || !valid_pin(seal)
		|| digest(root + '/sha256.json')! != seal {
		return error('canonical sealed bundle and exact manifest pin required: ' + root)
	}
	manifest := os.read_file(root + '/sha256.json')!
	if manifest.len > 32 * 1024 * 1024 { return error('bundle manifest exceeds bound') }
	pins := json2.decode[map[string]string](manifest)!
	if pins.len == 0 || 'sha256.json' in pins { return error('empty or self-referential bundle manifest') }
	for name, pin in pins {
		if !relative_file(name) || !valid_pin(pin) { return error('invalid bundle manifest entry: ' + name) }
	}
	mut actual := map[string]string{}
	collect_files(root, '', mut actual)!
	if actual != pins {
		mut changed := []string{}
		for name, pin in pins { if actual[name] or { '' } != pin { changed << name } }
		for name in actual.keys() { if name !in pins { changed << name + ' (unlisted)' } }
		changed.sort()
		return error('complete sealed bundle inventory differs: ' + root + '; changed=' + changed.join(', '))
	}
	return pins
}

pub fn load_bundle(root string, seal string) !Bundle {
	pins := load_inventory(root, seal)!
	if 'build.json' !in pins { return error('sealed build receipt absent') }
	if os.lstat(root + '/build.json')!.size > 8 * 1024 * 1024 { return error('build receipt exceeds bound') }
	return Bundle{root, seal, pins, json2.decode[map[string]json2.Any](os.read_file(root + '/build.json')!)!}
}

pub fn recheck(bundle Bundle) ! {
	if load_bundle(bundle.root, bundle.seal)!.files != bundle.files {
		return error('sealed input changed during staging')
	}
}

pub fn text_field(value map[string]json2.Any, name string) !string {
	field := value[name] or { return error('missing receipt field: ' + name) }
	if field is string { return field }
	return error('receipt field must be a string: ' + name)
}

fn exact_text(value map[string]json2.Any, name string, expected string) ! {
	if text_field(value, name)! != expected { return error('receipt field differs: ' + name) }
}

fn exact_integer(value json2.Any, expected int) bool {
	return match value {
		int { value == expected }
		i64 { value == i64(expected) }
		u64 { value == u64(expected) }
		f64 { value == f64(expected) }
		else { false }
	}
}

fn output_map(bundle Bundle, field string, names []string) !map[string]string {
	mut expected := map[string]string{}
	for name in names { expected[name] = bundle.files[name] or { return error('sealed output absent: ' + name) } }
	actual := json2.decode[map[string]string](json2.encode(bundle.receipt[field]!))!
	if actual != expected { return error('receipt output set differs: ' + field) }
	return expected
}

fn common_receipt(bundle Bundle, kind string) ! {
	exact_text(bundle.receipt, 'kind', kind)!
	exact_text(bundle.receipt, 'native_base_sha256', baseline_seal)!
	exact_text(bundle.receipt, 'compiler_sha256', compiler_seal)!
	revision := text_field(bundle.receipt, 'source_revision')!
	if revision.len != 40 || !revision.bytes().all((it >= `a` && it <= `f`) || (it >= `0` && it <= `9`)) {
		return error('full source revision required')
	}
}

pub fn verify_static_controller(bundle Bundle, kind string, name string) ! {
	common_receipt(bundle, kind)!
	output_map(bundle, 'outputs_sha256', ['bin/' + name])!
	elf := inspect_elf(os.read_bytes(bundle.root + '/bin/' + name)!)!
	if elf.needed.len != 0 || elf.interpreter != '' || elf.runpath != '' {
		return error('controller must be static AArch64: ' + name)
	}
}

fn retained_manifest(bundle Bundle, name string, seal string) ! {
	if bundle.files[name] or { '' } != seal {
		return error('retained input manifest differs: ' + name)
	}
}

fn receipt_file(bundle Bundle, name string) !map[string]json2.Any {
	if name !in bundle.files { return error('sealed command receipt absent: ' + name) }
	return json2.decode[map[string]json2.Any](os.read_file(bundle.root + '/' + name)!)!
}

fn command_args(bundle Bundle, name string) ![]string {
	receipt := receipt_file(bundle, 'commands/' + name + '.json')!
	if !exact_integer(receipt['exit_code']!, 0) { return error('failed sealed command: ' + name) }
	return json2.decode[[]string](json2.encode(receipt['argv']!))!
}

// Callers supply the audited profile pins; a build's self-reported output hashes
// alone never select a framework. The same selected seal couples both native ABIs.
pub fn verify_framework(bundle Bundle, seal string, jar string, dex string) !Framework {
	if bundle.seal != seal || bundle.files['api-impl.jar']! != jar
		|| bundle.files['classes.dex']! != dex { return error('audited framework profile differs') }
	exact_text(bundle.receipt, 'api_impl_sha256', jar)!
	exact_text(bundle.receipt, 'classes_dex_sha256', dex)!
	if !exact_integer(bundle.receipt['class_count']!, 2102) { return error('expected 2102-class framework') }
	return Framework{jar, dex, text_field(bundle.receipt, 'profile')!}
}

fn coupled_framework(bundle Bundle, framework Bundle) ! {
	exact_text(bundle.receipt, 'framework', framework.root)!
	exact_text(bundle.receipt, 'framework_sha256', framework.seal)!
	retained_manifest(bundle, 'framework-sha256.json', framework.seal)!
}

fn safe_symbol(name string) bool {
	return name != '' && name.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`)
		|| (it >= `0` && it <= `9`) || it == `_`)
}

fn annotation_exports(bundle Bundle, prefix string, account bool) ![]string {
	mut names := if account { []string{} } else { ['_init', '_fini'] }
	for path in bundle.files.keys().filter(it.starts_with(prefix) && it.ends_with('.v')
		&& (!account || it.contains('/accountclient/'))) {
		for line in os.read_file(bundle.root + '/' + path)!.split_into_lines() {
			trimmed := line.trim_space()
			if trimmed.starts_with("@[export: '") && trimmed.ends_with("']") {
				names << trimmed.all_after("@[export: '").all_before("'")
			}
		}
	}
	names.sort()
	if names.len <= 2 { return error('source export annotations absent') }
	for index, name in names {
		if !safe_symbol(name) || (index > 0 && names[index - 1] == name) { return error('unsafe or duplicate source export') }
	}
	return names
}

pub fn verify_native(bundle Bundle, framework Bundle) ! {
	coupled_framework(bundle, framework)!
	exact_text(bundle.receipt, 'baseline_sha256', baseline_seal)!
	retained_manifest(bundle, 'baseline-sha256.json', baseline_seal)!
	name := 'native/libvinix-android-native.so'
	exact_text(bundle.receipt, 'native_sha256', bundle.files[name]!)!
	bytes := os.read_bytes(bundle.root + '/' + name)!
	if bytes.len < 18 || u16_at(bytes, 16) != 3 { return error('native output must be a shared object') }
	elf := inspect_elf(bytes)!
	if elf.interpreter != '' || elf.runpath != '' { return error('native DSO has unexpected interpreter or search path') }
	args := command_args(bundle, 'build-native')!
	if args.len < 3 || args[0] != '/opt/homebrew/bin/aarch64-linux-musl-gcc'
		|| args.count(it == '-Werror') != 1 || args.count(it == '-Wl,--no-undefined') != 1
		|| args.count(it == '-shared') != 1 || args.count(it == '-o') != 1
		|| args[args.len - 2..] != ['-o', bundle.root + '/' + name] {
		return error('native DSO strict shared-link receipt differs')
	}
	if command_args(bundle, 'exports')! != ['/opt/homebrew/bin/aarch64-linux-musl-nm', '-D', '--defined-only', bundle.root + '/' + name] {
		return error('native export command differs')
	}
	exports := json2.decode[[]string](os.read_file(bundle.root + '/native/exports.json')!)!
	if exports != annotation_exports(bundle, 'native/atlframework/', false)! { return error('native exports differ from frozen source') }
}

fn includes(bundle Bundle, label string) []string {
	mut result := []string{}
	for path in bundle.files.keys().filter(it.starts_with('closure/' + label + '/') && it.ends_with('.h')) {
		flag := '-I' + os.dir(bundle.root + '/' + path)
		if flag !in result { result << flag }
	}
	result.sort()
	return result
}

fn closure_source(bundle Bundle, label string, suffix string) !string {
	names := bundle.files.keys().filter(it.starts_with('closure/' + label + '/') && it.ends_with(suffix))
	if names.len != 1 { return error('source closure is absent or ambiguous: ' + label + suffix) }
	return bundle.root + '/' + names[0]
}

const cross = '/opt/homebrew/bin/aarch64-linux-musl-gcc'

fn launch_items() [][]string {
	return [['native-entry', 'vinix-android-native', '/build-support/android/native-entry.v'],
		['launcher', 'run-android', '/build-support/android/native-run.v'],
		['controller', 'headless-service-controller', '/tests/native-android-ws/headless-service-controller.v'],
		['broker', 'native-account-broker', '/build-support/android/native-account-broker.v']]
}

fn verify_generated(bundle Bundle, label string, source string, extra []string) ! {
	receipt := receipt_file(bundle, 'commands/generate-' + label + '.json')!
	args := command_args(bundle, 'generate-' + label)!
	mut flags := ['-new-compiler', '-os', 'linux', '-arch', 'arm64', '-cc', cross,
		'-gc', 'none', '-nocache', '-skip-running', '-exclude', '@vlib/crypto/rand/internal/rand.wasm.v', '-path']
	if args.len != flags.len + extra.len + 5 || args[1..flags.len + 1] != flags
		|| text_field(receipt, 'executable_sha256')! != compiler_seal {
		return error('frozen generation flags differ: ' + label)
	}
	imports := args[flags.len + 1]
	if !imports.split('|').all(it.starts_with(bundle.root + '/closure/' + label + '/') && relative_file(it[bundle.root.len + 1..])) {
		return error('generation import root escapes frozen closure: ' + label)
	}
	if args[flags.len + 2..args.len - 3] != extra || args[args.len - 3..] != ['-o', bundle.root + '/generated/' + label + '.c', source]
		|| !args[0].starts_with(bundle.root + '/closure/' + label + '/')
		|| bundle.files[args[0][bundle.root.len + 1..]] or { '' } != compiler_seal {
		return error('generation source or compiler differs: ' + label)
	}
}

fn verify_compile(bundle Bundle, label string, source string, header_flags []string, pic bool, runtime bool) ! {
	name := label + if runtime { '-runtime' } else { '' }
	mut expected := [cross, '-v', '-D_GNU_SOURCE', '-O2', '-fwrapv', '-pthread']
	if pic { expected << '-fPIC' }
	expected << ['-Werror=implicit-function-declaration', '-Werror=int-conversion']
	expected << header_flags
	expected << ['-c', source, '-o', bundle.root + '/generated/' + name + '.o']
	if command_args(bundle, 'compile-' + name)! != expected { return error('cross compile receipt differs: ' + name) }
	for path in ['generated/' + name + '.o', 'generated/' + name + '-headers.json'] {
		if path !in bundle.files { return error('generated closure artifact absent: ' + path) }
	}
}

pub fn verify_launch(bundle Bundle, framework Bundle, native Bundle) ! {
	common_receipt(bundle, 'vinix-current-launch-v1')!
	coupled_framework(bundle, framework)!
	retained_manifest(bundle, 'baseline-sha256.json', baseline_seal)!
	if !exact_integer(bundle.receipt['service_main_argc']!, 7) { return error('seven-argument service ABI required') }
	output_map(bundle, 'outputs_sha256', launch_items().map('bin/' + it[1]))!
	if bundle.files['abi/headless.v']! != native.files['native/atlframework/headless.v']! {
		return error('native/executable service implementation snapshots differ')
	}
	entry := os.read_file(closure_source(bundle, 'native-entry', launch_items()[0][2])!)!
	implementation := os.read_file(bundle.root + '/abi/headless.v')!
	if !entry.contains('type NativeServiceMain = fn (&char, &char, &char, &char, &char, i32, i32) i32')
		|| !entry.contains('launch.action.str, i32(control_fd), i32(ui_fd))')
		|| !implementation.contains('fn ws_service_main(root &char, apk &char, package_name &char, service &char, action &char, control_fd i32, ui_fd i32) i32 {') {
		return error('service ABI declarations differ')
	}
	for item in launch_items() {
		label, output := item[0], 'bin/' + item[1]
		elf := inspect_elf(os.read_bytes(bundle.root + '/' + output)!)!
		if elf.runpath != '' || elf.interpreter != if label == 'native-entry' { '/lib/ld-musl-aarch64.so.1' } else { '' }
			|| (label != 'native-entry' && elf.needed.len != 0) { return error('launch static/dynamic contract differs: ' + label) }
		verify_generated(bundle, label, closure_source(bundle, label, item[2])!, [])!
		header_flags := includes(bundle, label)
		verify_compile(bundle, label, bundle.root + '/generated/' + label + '.c', header_flags, false, false)!
		verify_compile(bundle, label, closure_source(bundle, label, '/vlib/builtin/segfault_handler_nix.c')!, header_flags, false, true)!
		mut expected := [cross, '-v', '-no-pie', '-pthread', '-Wl,-t']
		if label != 'native-entry' { expected << '-static' }
		expected << [bundle.root + '/generated/' + label + '.o', bundle.root + '/generated/' + label + '-runtime.o', '-ldl', '-lm', '-o', bundle.root + '/' + output]
		if command_args(bundle, 'build-' + label)! != expected { return error('launch link receipt differs: ' + label) }
	}
}

pub fn verify_account(bundle Bundle) !map[string]string {
	common_receipt(bundle, 'vinix-current-account-v1')!
	retained_manifest(bundle, 'baseline-sha256.json', baseline_seal)!
	output_map(bundle, 'outputs_sha256', ['lib/libvinix-android-account.so'])!
	dependencies := json2.decode[map[string]string](json2.encode(bundle.receipt['runtime_dependencies_sha256']!))!
	if dependencies != {'lib/libsqlite3.so.0': sqlite_seal} { return error('store account transport requires the sealed SQLite runtime') }
	if bundle.files['lib/libsqlite3.so.0']! != sqlite_seal { return error('SQLite output hash differs') }
	output := bundle.root + '/lib/libvinix-android-account.so'
	bytes := os.read_bytes(output)!
	if bytes.len < 18 || u16_at(bytes, 16) != 3 { return error('account output must be a shared object') }
	elf := inspect_elf(bytes)!
	if elf.interpreter != '' || elf.runpath != '' || 'libsqlite3.so.0' !in elf.needed {
		return error('store transport ELF dependency or search path differs')
	}
	sqlite := inspect_elf(os.read_bytes(bundle.root + '/lib/libsqlite3.so.0')!)!
	if sqlite.interpreter != '' || sqlite.soname != 'libsqlite3.so.0' || sqlite.runpath != '/usr/lib'
		|| sqlite.needed != ['libc.musl-aarch64.so.1'] { return error('sealed SQLite dynamic contract differs') }
	exports := json2.decode[[]string](json2.encode(bundle.receipt['exports']!))!
	if exports != annotation_exports(bundle, 'closure/account/', true)! { return error('account exports differ from frozen source') }
	nm_inputs := json2.decode[map[string]string](os.read_file(bundle.root + '/nm-input.json')!)!
	if nm_inputs.len != 1 { return error('exact account export tool receipt required') }
	nm := nm_inputs.keys()[0]
	if !nm.starts_with('/') || !valid_pin(nm_inputs[nm]!)
		|| bundle.files['additional-cross/' + nm.trim_left('/')] or { '' } != nm_inputs[nm]!
		|| command_args(bundle, 'account-exports')! != [nm, '-D', '--defined-only', output] {
		return error('account export command differs')
	}
	source := bundle.root + '/closure/account/Users/alex/code/vinix/build-support/android/accountclient'
	verify_generated(bundle, 'account', source, ['-enable-globals', '-manualfree', '-shared', '-d', 'no_backtrace', '-d', 'no_segfault_handler'])!
	mut header_flags := includes(bundle, 'account')
	header_flags << '-I' + bundle.root + '/native'
	verify_compile(bundle, 'account', bundle.root + '/generated/account.c', header_flags, true, false)!
	verify_compile(bundle, 'account', closure_source(bundle, 'account', '/vlib/builtin/segfault_handler_nix.c')!, header_flags, true, true)!
	expected := [cross, '-v', '-shared', '-pthread', '-Wl,-z,defs', '-Wl,-z,max-page-size=65536', '-Wl,-t',
		bundle.root + '/generated/account.o', bundle.root + '/generated/account-runtime.o', bundle.root + '/lib/libsqlite3.so.0', '-ldl', '-lm', '-o', output]
	if command_args(bundle, 'build-account')! != expected { return error('account strict shared-link receipt differs') }
	return dependencies
}
