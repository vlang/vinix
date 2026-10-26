// SPDX-License-Identifier: GPL-2.0-or-later
// Build the complete current JNI provider with sealed r5 cross/runtime inputs.
// Preserve exact sources and receipts outside Git; do not rebuild other DSOs.
module main

import androidtools
import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const base = state + 'headless-service-native-build-2026-10-26-r5'
const base_seal = 'd99195272b8af813679cf54fed9f1e0341e6f1115804ac09c1cd2d5a8f942e3e'
const old_compiler = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const compiler = base + '/tools/v_old276'
const cross = '/opt/homebrew/bin/aarch64-linux-musl-gcc'
const self_source = repo + '/tests/native-android-ws/build-current-native.v'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn write_json[T](path string, value T) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn unchanged(pins map[string]string) ! {
	for path, pin in pins {
		if hash(path)! != pin { return error('input changed: ' + path) }
	}
}

fn copy_pin(source string, target string, pin string) ! {
	if hash(source)! != pin { return error('input differs: ' + source) }
	os.mkdir_all(os.dir(target))!
	os.cp(source, target)!
	if hash(target)! != pin || hash(source)! != pin { return error('copy differs: ' + source) }
}

fn sealed_copy(source string, pins map[string]string, relative string, target string) ! {
	pin := pins[relative] or { return error('unsealed input: ' + relative) }
	copy_pin(source + '/' + relative, target, pin)!
}

fn command(root string, label string, argv []string) !string {
	executable := if argv[0].contains('/') { os.real_path(argv[0]) } else {
		os.find_abs_path_of_executable(argv[0])!
	}
	pin := hash(executable)!
	mut receipt := {
		'argv': json2.Any(argv)
		'executable': json2.Any(executable)
		'executable_sha256': json2.Any(pin)
		'started_utc': json2.Any(time.utc().str())
		'cwd': json2.Any(os.getwd())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'V': json2.Any(os.getenv('V'))
		'VINIX_V_COMPILER': json2.Any(os.getenv('VINIX_V_COMPILER'))
		'VEXE': json2.Any(os.getenv('VEXE'))
	}
	write_json(root + '/commands/' + label + '-before.json', receipt)!
	result := os.exec(argv)
	os.write_file(root + '/commands/' + label + '.log', result.output)!
	receipt['exit_code'] = result.exit_code
	receipt['completed_utc'] = time.utc().str()
	write_json(root + '/commands/' + label + '.json', receipt)!
	if result.exit_code != 0 { return error(label + ': ' + result.output) }
	if hash(executable)! != pin { return error('executable changed: ' + executable) }
	return result.output
}

fn freeze_closure(root string, label string, listing string) !map[string]string {
	mut pins := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		if !os.is_abs_path(path) { return error('nonabsolute source path: ' + path) }
		pins[path] = hash(path)!
		// Native helper sources and headers are compiler inputs too.
		for name in os.ls(os.dir(path))!.filter(it.ends_with('.h') || it.ends_with('.c')) {
			header := os.dir(path) + '/' + name
			pins[header] = hash(header)!
		}
	}
	if pins.len == 0 { return error('empty source closure') }
	// #insert resolves these compiler-owned headers outside source directories.
	vroot := os.dir(closure_vlib(pins)!)
	mut support := map[string]string{}
	inventory(vroot, 'thirdparty/stdatomic', mut support)!
	for relative, pin in support {
		if !relative.ends_with('.v') { pins[vroot + '/' + relative] = pin }
	}
	for path in pins.keys() {
		mut directory := os.dir(path)
		for directory != '/' {
			metadata := directory + '/v.mod'
			if os.is_file(metadata) { pins[metadata] = hash(metadata)! }
			directory = os.dir(directory)
		}
	}
	for path, pin in pins {
		copy_pin(path, root + '/closure/' + label + '/' + path.trim_left('/'), pin)!
	}
	unchanged(pins)!
	write_json(root + '/' + label + '-closure.json', pins)!
	return pins
}

fn closure_vlib(pins map[string]string) !string {
	roots := pins.keys().filter(it.ends_with('/vlib/builtin/builtin.v'))
	if roots.len != 1 { return error('expected one retained V standard library') }
	return roots[0].all_before_last('/builtin/builtin.v')
}

fn check_frozen_listing(pins map[string]string, listing string) ! {
	mut consumed := map[string]bool{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		if path !in pins { return error('compiler consumed source outside frozen closure: ' + path) }
		consumed[path] = true
	}
	if consumed.len == 0 { return error('empty frozen compiler source listing') }
	for path in pins.keys().filter(it.ends_with('.v')) {
		if path !in consumed { return error('frozen compiler omitted retained source: ' + path) }
	}
}

fn frozen_pins(root string, label string) !map[string]string {
	original := json2.decode[map[string]string](os.read_file(root + '/' + label + '-closure.json')!)!
	mut pins := map[string]string{}
	for path, pin in original { pins[root + '/closure/' + label + '/' + path.trim_left('/')] = pin }
	unchanged(pins)!
	return pins
}

// The compiler's showcc line names the cached native helpers it actually links.
// Discover them once, then guard and retain the inputs of the authoritative build.
fn helper_objects(output string) ![]string {
	mut paths := []string{}
	for line in output.split_into_lines().filter(it.trim_space().starts_with('> ')) {
		for token in line.fields() {
			if !token.trim("'\"").ends_with('.o') { continue }
			if !os.is_abs_path(token) || token.contains("'") || token.contains('"') {
				return error('unsupported compiler object path: ' + token)
			}
			if token !in paths { paths << token }
		}
	}
	if paths.len == 0 { return error('showcc did not identify native helper objects') }
	paths.sort()
	return paths
}

fn compile_host(root string, label string, argv []string, sources map[string]string) ! {
	unchanged(sources)!
	objects := helper_objects(command(root, label + '-discovery', argv)!)!
	unchanged(sources)!
	mut pins := map[string]string{}
	for path in objects {
		pins[path] = hash(path)!
		copy_pin(path, root + '/closure/' + label + '-objects/' + path.trim_left('/'), pins[path]!)!
	}
	cc := os.find_abs_path_of_executable('cc')!
	pins[cc] = hash(cc)!
	copy_pin(cc, root + '/closure/' + label + '-objects/' + cc.trim_left('/'), pins[cc]!)!
	write_json(root + '/' + label + '-native-inputs.json', pins)!
	unchanged(pins)!
	if helper_objects(command(root, label, argv)!)! != objects {
		return error('native helper object set changed during ' + label)
	}
	unchanged(pins)!
	unchanged(sources)!
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	mut names := os.ls(root + '/' + prefix)!
	names.sort()
	for name in names {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular bundle file: ' + key) }
		}
	}
}

// GCC's make dependency output escapes whitespace and line continuations.
fn dependency_paths(text string) ![]string {
	colon := text.index(':') or { return error('missing dependency target') }
	mut paths := []string{}
	mut token := ''
	mut escaped := false
	for ch in text[colon + 1..].bytes() {
		if escaped {
			if ch != `\n` { token += ch.ascii_str() }
			escaped = false
		} else if ch == `\\` {
			escaped = true
		} else if ch.is_space() {
			if token != '' { paths << token; token = '' }
		} else {
			token += ch.ascii_str()
		}
	}
	if escaped { return error('unterminated dependency escape') }
	if token != '' { paths << token }
	if paths.len == 0 { return error('empty dependency closure') }
	return paths
}

fn check_dependencies(root string, reused map[string]string) ! {
	listing := command(root, 'native-headers', [cross, '-D_GNU_SOURCE', '-I' + root + '/native',
		'-M', '-MT', 'android-native', root + '/native/android-native.c'])!
	mut allowed := map[string]string{}
	for path, pin in reused { allowed[os.real_path(path)] = pin }
	mut consumed := map[string]string{}
	for path in dependency_paths(listing)! {
		canonical := os.real_path(path)
		pin := hash(canonical)!
		if canonical.starts_with(root + '/native/') {
			if canonical != root + '/native/android-native.c' && os.dir(canonical) != root + '/native' {
				return error('unexpected local dependency: ' + path)
			}
		} else if canonical !in allowed || pin != allowed[canonical]! {
			return error('C header outside sealed compiler closure: ' + path)
		}
		consumed[canonical] = pin
	}
	write_json(root + '/native/consumed-headers.json', consumed)!
}

fn self_test() ! {
	assert dependency_paths('android-native: /a/one.h /a/two\\ words.h \\\n /a/three.h\n')! ==
		['/a/one.h', '/a/two words.h', '/a/three.h']
	for malformed in ['missing target', 'target:', 'target: /a/b\\'] {
		mut rejected := false
		dependency_paths(malformed) or { rejected = true }
		assert rejected, 'accepted malformed dependency list'
	}
	pins := {'/retained/a.v': 'a', '/retained/b.v': 'b', '/retained/header.h': 'h'}
	check_frozen_listing(pins, '/retained/a.v\n/retained/b.v\n')!
	for malformed in ['', '/retained/a.v\n', '/retained/a.v\n/retained/b.v\n/live/c.v\n'] {
		mut rejected := false
		check_frozen_listing(pins, malformed) or { rejected = true }
		assert rejected, 'accepted incomplete or live source closure'
	}
	assert helper_objects('  > cc src.c /tmp/helper.o /tmp/second.o -lm\n')! ==
		['/tmp/helper.o', '/tmp/second.o']
	for malformed in ['no compiler line', '> cc relative.o', '> cc src.c -lm',
		"> cc /tmp/valid.o '/tmp/quoted.o'"] {
		mut rejected := false
		helper_objects(malformed) or { rejected = true }
		assert rejected, 'accepted unsupported native helper listing'
	}
	directory := state + 'current-native-source-set-selftest-' + os.getpid().str()
	os.mkdir(directory)!
	defer { os.rmdir_all(directory) or {} }
	os.write_file(directory + '/a.v', 'module test')!
	os.write_file(directory + '/ignore.txt', '')!
	check_source_names(directory, ['a.v'])!
	os.write_file(directory + '/concurrent.v', 'module test')!
	mut rejected := false
	check_source_names(directory, ['a.v']) or { rejected = true }
	assert rejected, 'accepted concurrently added production source'
	println('CURRENT-NATIVE-BUILDER-SELF-PASS escaped-header-paths exact-retained-source-closure native-helper-inputs source-set-race')
}

fn source_names(directory string) ![]string {
	mut names := os.ls(directory)!.filter(it.ends_with('.v'))
	names.sort()
	return names
}

fn check_source_names(directory string, expected []string) ! {
	if source_names(directory)! != expected { return error('native source set changed: ' + directory) }
}

fn current_sources(root string, framework string, framework_pins map[string]string) !map[string]string {
	mut inputs := map[string]string{}
	mut names := map[string]string{}
	mut directory_names := map[string][]string{}
	for dir in ['atlframework', 'nativews'] {
		directory := repo + '/build-support/android/' + dir
		files := source_names(directory)!
		directory_names[directory] = files
		for name in files {
			if name in names { return error('native source filename collision: ' + name) }
			source := repo + '/build-support/android/' + dir + '/' + name
			names[name] = source
			inputs[source] = hash(source)!
			copy_pin(source, root + '/native/atlframework/' + name, inputs[source]!)!
		}
	}
	if 'ws_generated.v' in names { return error('generated JNI source in production input directory') }
	spec_path := repo + '/build-support/android/nativews/bindings.txt'
	inputs[spec_path] = hash(spec_path)!
	copy_pin(spec_path, root + '/native/bindings.txt', inputs[spec_path]!)!
	spec := os.read_file(root + '/native/bindings.txt')!
	mut smali_pins := map[string]string{}
	for line in spec.split_into_lines() {
		if line.trim_space() == '' || line.starts_with('#') { continue }
		parts := line.split('|')
		if parts.len != 3 { return error('invalid binding: ' + line) }
		relative := 'smali/' + parts[0] + '.smali'
		if relative in smali_pins { continue }
		sealed_copy(framework, framework_pins, relative, root + '/framework/' + relative)!
		smali_pins[relative] = framework_pins[relative]!
	}
	generated := androidtools.native_ws_bindings(spec, root + '/framework/smali')!
	os.write_file(root + '/native/atlframework/ws_generated.v', generated)!
	write_json(root + '/native/source-origins.json', names)!
	write_json(root + '/native/current-inputs.json', inputs)!
	write_json(root + '/framework/consumed-smali.json', smali_pins)!
	// Take one coherent input snapshot, then build exclusively from the copies.
	unchanged(inputs)!
	for directory, expected in directory_names {
		check_source_names(directory, expected)!
	}
	return inputs
}

fn build(root string, framework string) ! {
	if hash(base + '/sha256.json')! != base_seal { return error('sealed r5 baseline differs') }
	base_pins := json2.decode[map[string]string](os.read_file(base + '/sha256.json')!)!
	framework_seal := hash(framework + '/sha256.json')!
	framework_pins := json2.decode[map[string]string](os.read_file(framework + '/sha256.json')!)!
	copy_pin(base + '/sha256.json', root + '/baseline-sha256.json', base_seal)!
	copy_pin(framework + '/sha256.json', root + '/framework-sha256.json', framework_seal)!
	frozen_source := root + '/closure/builder/' + self_source.trim_left('/')
	copy_pin(frozen_source, root + '/builder-source.v', hash(frozen_source)!)!
	copy_pin(os.executable(), root + '/builder', hash(os.executable())!)!
	revision := command(root, 'revision', ['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!.trim_space()
	command(root, 'working-tree', ['/usr/bin/git', '-C', repo, 'status', '--porcelain=v1'])!
	builder_closure := frozen_pins(root, 'builder')!
	current_sources(root, framework, framework_pins)!
	for name in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
		sealed_copy(base, base_pins, 'native/' + name, root + '/native/' + name)!
	}
	sealed_copy(base, base_pins, 'tools/v_old276', root + '/tools/v_old276')!
	os.chmod(root + '/tools/v_old276', 0o755)!
	if hash(root + '/tools/v_old276')! != old_compiler { return error('old compiler differs') }
	sealed_copy(base, base_pins, 'reused-inputs.json', root + '/reused-inputs.json')!
	reused := json2.decode[map[string]string](os.read_file(root + '/reused-inputs.json')!)!
	unchanged(reused)!
	if cross !in reused { return error('cross compiler absent from sealed closure') }
	sealed_copy(base, base_pins, 'native351/crosscompiler-specs.txt', root + '/crosscompiler-specs.txt')!
	if command(root, 'cross-specs', [cross, '-dumpspecs'])! != os.read_file(root + '/crosscompiler-specs.txt')! {
		return error('cross compiler specs differ')
	}
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('VEXE', root + '/tools/v_old276', true)
	os.setenv('V', root + '/tools/v_old276', true)
	os.setenv('VINIX_V_COMPILER', root + '/tools/v_old276', true)
	original := freeze_closure(root, 'native-generator', command(root, 'native-generator-closure', [
		root + '/tools/v_old276', '-gc', 'none', '-nocache', '-print-v-files', repo + '/tests/linuxkpi/generate_module.v',
	])!)!
	closure := frozen_pins(root, 'native-generator')!
	unchanged(original)!
	compile_host(root, 'compile-native-generator', [root + '/tools/v_old276', '-gc', 'none', '-nocache',
		'-cc', 'cc', '-cflags', '-O2', '-showcc', '-o', root + '/tools/native-generator',
		repo + '/tests/linuxkpi/generate_module.v'], original)!
	unchanged(original)!
	check_frozen_listing(original, command(root, 'native-generator-closure-after', [root + '/tools/v_old276',
		'-gc', 'none', '-nocache', '-print-v-files', repo + '/tests/linuxkpi/generate_module.v'])!)!
	unchanged(original)!
	find_v := repo + '/build-support/find-v.sh'
	find_v_pin := base_pins['native351/source/find-v.sh']!
	copy_pin(find_v, root + '/tools/find-v.sh', find_v_pin)!
	command(root, 'generate-native', [root + '/tools/native-generator',
		root + '/native/atlframework', root + '/native/android-native.c', '--arch', 'arm64'])!
	if hash(find_v)! != find_v_pin { return error('compiler selector changed') }
	unchanged(closure)!
	check_dependencies(root, reused)!
	runtime := state + 'account-contract-companion-build-2026-10-26/inputs/build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
	for name in ['usr/lib/art/libandroidfw.so', 'usr/lib/libpng16.so.16', 'usr/lib/libsqlite3.so.0'] {
		if runtime + '/' + name !in reused { return error('runtime DSO absent from sealed closure: ' + name) }
	}
	command(root, 'build-native', [cross, '-v', '-D_GNU_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden',
		'-shared', '-fPIC', '-I' + root + '/native', '-Wl,-z,max-page-size=65536', '-Wl,--no-undefined',
		'-Wl,--allow-shlib-undefined', root + '/native/android-native.c',
		runtime + '/usr/lib/art/libandroidfw.so', '-Wl,--no-as-needed',
		runtime + '/usr/lib/libpng16.so.16', runtime + '/usr/lib/libsqlite3.so.0', '-ldl', '-lm',
		'-o', root + '/native/libvinix-android-native.so'])!
	bytes := os.read_bytes(root + '/native/libvinix-android-native.so')!
	if bytes.len < 64 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| bytes[16..20] != [u8(3), 0, 183, 0] { return error('not AArch64 ELF64 shared library') }
	listing := command(root, 'exports', ['/opt/homebrew/bin/aarch64-linux-musl-nm', '-D',
		'--defined-only', root + '/native/libvinix-android-native.so'])!
	mut exports := listing.split_into_lines().filter(it.fields().len >= 3).map(it.fields().last())
	exports.sort()
	// The sealed GCC startup/termination objects supply these ELF exports.
	mut expected := ['_init', '_fini']
	for source in os.ls(root + '/native/atlframework')! {
		for line in os.read_file(root + '/native/atlframework/' + source)!.split_into_lines() {
			if line.starts_with("@[export: '") { expected << line.all_after("@[export: '").all_before("'") }
		}
	}
	expected.sort()
	if expected.len == 0 || exports != expected {
		return error('exported symbols differ from complete source annotations; missing=' +
			expected.filter(it !in exports).join(',') + '; extra=' + exports.filter(it !in expected).join(',') +
			'; expected=${expected.len} actual=${exports.len}')
	}
	write_json(root + '/native/exports.json', exports)!
	unchanged(reused)!
	unchanged(builder_closure)!
	if hash(base + '/sha256.json')! != base_seal || hash(framework + '/sha256.json')! != framework_seal {
		return error('sealed manifest changed')
	}
	write_json(root + '/build.json', {
		'scope': 'Complete current JNI provider; AArch64 Werror shared link, no guest or account login claim.'
		'compiler_source_policy': 'Retained source copies; live driver compilation guarded by exact source listings and before/after hashes; JNI generated only from copied native inputs.'
		'source_revision': revision
		'baseline': base
		'baseline_sha256': base_seal
		'framework': framework
		'framework_sha256': framework_seal
		'native_sha256': hash(root + '/native/libvinix-android-native.so')!
		'completed_utc': time.utc().str()
	})!
	write_json(root + '/frozen-execution.json', {
		'argv': json2.Any(os.args)
		'executable_sha256': json2.Any(hash(os.executable())!)
		'completed_utc': json2.Any(time.utc().str())
	})!
	mut bundle := map[string]string{}
	inventory(root, '', mut bundle)!
	write_json(root + '/sha256.json', bundle)!
	println('CURRENT-NATIVE-BUILD-PASS bundle=' + root + ' seal=' + hash(root + '/sha256.json')!)
}

fn bootstrap(root string, framework string) ! {
	os.mkdir_all(root + '/commands')!
	os.mkdir_all(root + '/tools')!
	if hash(compiler)! != old_compiler { return error('sealed builder compiler differs') }
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('VEXE', compiler, true)
	copy_pin(os.executable(), root + '/bootstrap-builder', hash(os.executable())!)!
	original := freeze_closure(root, 'builder', command(root, 'builder-closure', [
		compiler, '-gc', 'none', '-nocache', '-path', '@vlib|' + repo + '/tests/native-android-tools', '-print-v-files', self_source,
	])!)!
	unchanged(original)!
	compile_host(root, 'compile-frozen-builder', [compiler, '-gc', 'none', '-nocache', '-cc', 'cc', '-showcc',
		'-path', '@vlib|' + repo + '/tests/native-android-tools', '-o',
		root + '/tools/frozen-builder', self_source], original)!
	unchanged(original)!
	check_frozen_listing(original, command(root, 'builder-closure-after', [compiler, '-gc', 'none', '-nocache',
		'-path', '@vlib|' + repo + '/tests/native-android-tools', '-print-v-files', self_source])!)!
	unchanged(original)!
	frozen_pins(root, 'builder')!
	argv := [root + '/tools/frozen-builder', '--frozen-build', framework, root]
	write_json(root + '/frozen-launch.json', {
		'argv': json2.Any(argv)
		'executable_sha256': json2.Any(hash(argv[0])!)
		'started_utc': json2.Any(time.utc().str())
	})!
	result := os.exec(argv)
	if result.exit_code != 0 { return error(result.output) }
	print(result.output)
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 4 && os.args[1] == '--frozen-build' {
		framework := os.abs_path(os.args[2])
		root := os.abs_path(os.args[3])
		if os.executable() != root + '/tools/frozen-builder' || !root.starts_with(state + 'current-native-build-') {
			eprintln('internal frozen build requires its retained executable')
			exit(2)
		}
		os.chdir(repo)!
		build(root, framework) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 3 {
		eprintln('usage: build-current-native SEALED_FRAMEWORK_BUNDLE FRESH_EXTERNAL_OUTPUT')
		exit(2)
	}
	framework := os.abs_path(os.args[1])
	root := os.abs_path(os.args[2])
	if !framework.starts_with(state) || os.real_path(framework) != framework
		|| !root.starts_with(state + 'current-native-build-') || os.exists(root)
		|| os.is_link(root) || os.real_path(os.dir(root)) != os.dir(root) {
		eprintln('canonical sealed framework and fresh external current-native-build output required')
		exit(2)
	}
	os.chdir(repo)!
	bootstrap(root, framework) or { eprintln(err); exit(1) }
}
