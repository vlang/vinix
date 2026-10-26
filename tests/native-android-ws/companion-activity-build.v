// SPDX-License-Identifier: GPL-2.0-or-later
// Build only companion Activity routing over the sealed response framework/native351.
module main

import crypto.sha256
import compress.gzip
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const framework_base = state + 'account-contract-response-build-2026-10-26'
const framework_manifest = '4bfb24a711625e1e627a25c1ad5cea0c1b68090d6b0633179844636f7fce8c21'
const framework_class_count = 2089
const jar_pin = 'f89db07bc2897ca11c1645a39300e84b9f981050c940bd04c4b1dceb19225477'
const native_base = state + 'text-size351-native-build-2026-10-25'
const native_manifest = 'eb0dfe0dd87ea7f5972bddd06ae4c0c45ba8b9e5ad56a39c074142847f4bccd9'
const native_pin = 'd3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'
const old_compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const compiler = '/Users/alex/code/v/v'
const java = '/opt/homebrew/opt/openjdk@25/bin/java'
const cross = '/opt/homebrew/bin/aarch64-linux-musl-gcc'
const smali_tools = repo + '/build/android-framework/tools'
const source_file = repo + '/tests/native-android-ws/companion-activity-build.v'
const provider = repo + '/tests/native-android-tools/androidtools/framework_companion_activity.v'
const replace_helper = repo + '/tests/native-android-tools/androidtools/framework.v'
const recreate = repo + '/build-support/android/atlframework/recreate.v'
const changed_classes = ['android/app/Activity.smali', 'android/app/Activity$2.smali',
	'android/atl/ATLLoadedAppManager.smali']

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

fn command(root string, label string, argv []string) !string {
	executable := if argv[0].contains('/') {
		os.real_path(argv[0])
	} else {
		os.find_abs_path_of_executable(argv[0])!
	}
	pin := hash(executable)!
	started := time.utc().str()
	write_json(root + '/commands/' + label + '-before.json', {
		'argv':              json2.Any(argv)
		'started_utc':       json2.Any(started)
		'executable':        json2.Any(executable)
		'executable_sha256': json2.Any(pin)
		'cwd':               json2.Any(os.getwd())
		'VROOT':             json2.Any(os.getenv('VROOT'))
		'V':                 json2.Any(os.getenv('V'))
		'VINIX_V_COMPILER':  json2.Any(os.getenv('VINIX_V_COMPILER'))
	})!
	r := os.exec(argv)
	os.write_file(root + '/commands/' + label + '.log', r.output)!
	write_json(root + '/commands/' + label + '.json', {
		'argv':              json2.Any(argv)
		'started_utc':       json2.Any(started)
		'completed_utc':     json2.Any(time.utc().str())
		'exit_code':         json2.Any(r.exit_code)
		'executable':        json2.Any(executable)
		'executable_sha256': json2.Any(pin)
		'VROOT':             json2.Any(os.getenv('VROOT'))
		'V':                 json2.Any(os.getenv('V'))
		'VINIX_V_COMPILER':  json2.Any(os.getenv('VINIX_V_COMPILER'))
	})!
	if r.exit_code != 0 { return error(label + ': ' + r.output) }
	if hash(executable)! != pin { return error('executable changed: ' + executable) }
	return r.output
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	mut names := os.ls(root + '/' + prefix)!
	names.sort()
	for name in names {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular input: ' + key) }
		}
	}
}

fn class_delta(old map[string]string, new map[string]string) ! {
	if old.len != framework_class_count || new.len != old.len {
		return error('unexpected framework class count')
	}
	for name in changed_classes {
		if name !in old { return error('missing routing class: ' + name) }
	}
	for name, pin in old {
		if name !in new || ((name in changed_classes) == (pin == new[name]!)) {
			return error('unexpected framework class delta: ' + name)
		}
	}
}

fn jar_delta(old map[string]string, new map[string]string) ! {
	if old.len != 3 || new.len != old.len || 'classes.dex' !in old {
		return error('unexpected JAR members')
	}
	for name, pin in old {
		if name !in new || ((name == 'classes.dex') == (pin == new[name]!)) {
			return error('unexpected JAR member delta: ' + name)
		}
	}
}

fn self_test() ! {
	mut old := map[string]string{}
	for i in 0 .. framework_class_count - changed_classes.len {
		old['other/' + i.str() + '.smali'] = 'old'
	}
	for name in changed_classes { old[name] = 'old' }
	mut good := old.clone()
	for name in changed_classes { good[name] = 'new' }
	class_delta(old, good)!
	for case in 0 .. 6 {
		mut bad := good.clone()
		match case {
			0 { bad['other/0.smali'] = 'changed' }
			1 { bad.delete('other/0.smali') }
			2 { bad['extra.smali'] = 'new' }
			3 { bad[changed_classes[0]] = 'old' }
			4 { bad.delete(changed_classes[0]) }
			else {
				bad.delete('other/0.smali')
				bad['extra.smali'] = 'new'
			}
		}
		class_delta(old, bad) or { continue }
		return error('invalid class delta accepted: ' + case.str())
	}
	a := {
		'classes.dex': 'old'
		'manifest':    'same'
		'resources':   'same'
	}
	b := {
		'classes.dex': 'new'
		'manifest':    'same'
		'resources':   'same'
	}
	jar_delta(a, b)!
	for case in 0 .. 4 {
		mut bad := b.clone()
		match case {
			0 { bad['classes.dex'] = 'old' }
			1 { bad['manifest'] = 'changed' }
			2 { bad.delete('manifest') }
			else { bad['extra'] = 'new' }
		}
		jar_delta(a, bad) or { continue }
		return error('invalid JAR delta accepted: ' + case.str())
	}
	println('COMPANION-ACTIVITY-BUILD-SELF-TEST-PASS six invalid class deltas and four invalid JAR deltas rejected')
}

fn frozen_copy(pins map[string]string, relative string, to string) ! {
	if relative !in pins || hash(native_base + '/' + relative)! != pins[relative]! {
		return error('native351 input differs: ' + relative)
	}
	os.mkdir_all(os.dir(to))!
	r := os.exec(['/bin/cp', '-c', native_base + '/' + relative, to])
	if r.exit_code != 0 { return error(r.output) }
	if hash(to)! != pins[relative]! { return error('native351 clone differs: ' + relative) }
}

fn freeze_closure(root string, listing string, destination string) !map[string]string {
	mut pins := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		pins[path] = hash(path)!
		target := root + '/' + destination + '/' + path.trim_left('/')
		os.mkdir_all(os.dir(target))!
		os.cp(path, target)!
		if hash(target)! != pins[path]! { return error('closure copy differs: ' + path) }
	}
	if pins.len == 0 { return error('empty V source closure') }
	write_json(root + '/' + destination + '.json', pins)!
	return pins
}

fn elf_identity(path string) ! {
	bytes := os.read_bytes(path)!
	if bytes.len < 64 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| bytes[16..20] != [u8(3), 0, 183, 0] {
		return error('expected AArch64 little endian ELF64 shared library: ' + path)
	}
}

fn build_framework(root string, classpath string) ! {
	command(root, 'old-disassemble', [java, '-cp', classpath, 'org.jf.baksmali.Main', 'disassemble',
		'--jobs', '2', framework_base + '/api-impl.jar', '-o', root + '/old-dex'])!
	command(root, 'clone-smali', ['/bin/cp', '-c', '-R', root + '/old-dex', root + '/smali'])!
	os.cp(framework_base + '/api-impl.jar', root + '/api-impl.jar')!
	os.mkdir_all(root + '/provider-source/androidtools')!
	os.cp(provider, root + '/provider-source/androidtools/framework_companion_activity.v')!
	// Keep only the transformer dependency, without the broad framework builder.
	helper_source := os.read_file(replace_helper)!
	helper_start := '\npub fn framework_replace_method('
	if helper_source.count(helper_start) != 1 {
		return error('missing bounded method replacement helper')
	}
	helper := helper_source.all_after(helper_start).all_before('\n}')
	if helper == '' || !helper.contains('return text') {
		return error('unterminated bounded method replacement helper')
	}
	os.write_file(root + '/provider-source/androidtools/framework_methods.v', 'module androidtools\n' + helper_start + helper + '\n}\n')!
	os.cp(replace_helper, root + '/framework-helper-source.v')!
	os.write_file(root + '/provider-source/main.v', 'module main\nimport androidtools\nimport os\nfn main() {\nr := os.args[1]\n' +
		'names := androidtools.framework_companion_activity_class_names()\n' +
		'if names != ["android/app/Activity", "android/atl/ATLLoadedAppManager", "android/app/Activity$2"] { panic("unexpected provider class list") }\n' +
		'paths := names.map(r + "/" + it + ".smali")\n' +
		'a,b,c := androidtools.framework_companion_activity_sources(os.read_file(paths[0])!, os.read_file(paths[1])!, os.read_file(paths[2])!)!\n' +
		'for i,s in [a,b,c] { os.write_file(paths[i],s)! }\n}\n')!
	mut old := map[string]string{}
	inventory(root + '/smali', '', mut old)!
	listing := command(root, 'provider-closure', [compiler, '-print-v-files', '-path',
		root + '/provider-source|@vlib', root + '/provider-source'])!
	closure := freeze_closure(root, listing, 'provider-closure-inputs')!
	command(root, 'compile-provider', [compiler, '-cc', 'cc', '-path', root + '/provider-source|@vlib',
		'-o', root + '/provider', root + '/provider-source'])!
	for path, pin in closure {
		if hash(path)! != pin { return error('provider compiler input changed: ' + path) }
	}
	command(root, 'apply-provider', [root + '/provider', root + '/smali'])!
	mut new := map[string]string{}
	inventory(root + '/smali', '', mut new)!
	class_delta(old, new)!
	write_json(root + '/framework-source-before.json', old)!
	write_json(root + '/framework-source-after.json', new)!
	command(root, 'assemble', [java, '-cp', classpath, 'org.jf.smali.Main', 'assemble', '--jobs',
		'2', root + '/smali', '-o', root + '/classes.dex'])!
	if !os.is_file(root + '/classes.dex') || os.file_size(root + '/classes.dex') < 112 {
		return error('assembly produced no fresh DEX')
	}
	command(root, 'replace-dex', ['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar',
		root + '/classes.dex'])!
	for pair in [[framework_base + '/api-impl.jar', 'old'], [root + '/api-impl.jar', 'new']] {
		if pair[1] == 'new' {
			command(root, 'new-disassemble', [java, '-cp', classpath, 'org.jf.baksmali.Main',
				'disassemble', '--jobs', '2', pair[0], '-o', root + '/new-dex'])!
		}
		command(root, pair[1] + '-unzip', ['/usr/bin/unzip', '-q', pair[0], '-d',
			root + '/' + pair[1] + '-jar'])!
	}
	mut old_dex := map[string]string{}
	mut new_dex := map[string]string{}
	inventory(root + '/old-dex', '', mut old_dex)!
	inventory(root + '/new-dex', '', mut new_dex)!
	class_delta(old_dex, new_dex)!
	write_json(root + '/framework-dex-before.json', old_dex)!
	write_json(root + '/framework-dex-after.json', new_dex)!
	mut old_jar := map[string]string{}
	mut new_jar := map[string]string{}
	inventory(root + '/old-jar', '', mut old_jar)!
	inventory(root + '/new-jar', '', mut new_jar)!
	jar_delta(old_jar, new_jar)!
	write_json(root + '/framework-delta.json', {
		'changed_classes': changed_classes
		'added_classes':   []string{}
		'removed_classes': []string{}
	})!
}

fn build_native(root string) ! {
	if hash(native_base + '/sha256.json')! != native_manifest {
		return error('native351 seal differs')
	}
	pins := json2.decode[map[string]string](os.read_file(native_base + '/sha256.json')!)!
	os.cp(native_base + '/sha256.json', root + '/native351-sha256.json')!
	if hash(root + '/native351-sha256.json')! != native_manifest {
		return error('native351 seal copy differs')
	}
	if hash(native_base + '/native/libvinix-android-native.so')! != native_pin {
		return error('native351 library differs')
	}
	for relative in ['frozen-inputs.json', 'native-generator-v-files.json', 'crosscompiler-specs.txt',
		'source/find-v.sh'] {
		frozen_copy(pins, relative, root + '/native351/' + relative)!
	}
	for name in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h', 'bindings.txt',
		'sources.json', 'exact-sources.json.gz', 'libvinix-android-native.so'] {
		frozen_copy(pins, 'native/' + name, root + '/baseline-native/' + name)!
	}
	old := json2.decode[map[string]string](os.read_file(root + '/baseline-native/sources.json')!)!
	mut exact := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + '/baseline-native/exact-sources.json.gz')!)!.bytestr())!
	if old.len != 85 || exact.len != old.len || 'recreate.v' !in old {
		return error('unexpected native351 source set')
	}
	mut new := map[string]string{}
	for name, pin in old {
		frozen_copy(pins, 'native/atlframework/' + name, root + '/native/atlframework/' + name)!
		if pin != hash(root + '/native/atlframework/' + name)! {
			return error('native351 source pin differs')
		}
		if sha256.sum(exact[name]!.bytes()).hex() != pin {
			return error('native351 exact source differs: ' + name)
		}
		if name == 'recreate.v' { os.cp(recreate, root + '/native/atlframework/' + name)! }
		exact[name] = os.read_file(root + '/native/atlframework/' + name)!
		new[name] = hash(root + '/native/atlframework/' + name)!
		if (name == 'recreate.v') == (pin == new[name]!) {
			return error('unexpected native source delta: ' + name)
		}
	}
	for name in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
		os.cp(root + '/baseline-native/' + name, root + '/native/' + name)!
	}
	write_json(root + '/native/sources.json', new)!
	os.cp(root + '/baseline-native/bindings.txt', root + '/native/bindings.txt')!
	os.write_file_array(root + '/native/exact-sources.json.gz', gzip.compress(json2.encode(exact).bytes())!)!
	write_json(root + '/native/source-delta.json', {
		'changed': ['recreate.v']
		'added':   []string{}
		'removed': []string{}
	})!
	commit := command(root, 'recreate-revision', ['/usr/bin/git', '-C', repo, 'log', '-1', '--format=%H',
		'--', recreate])!.trim_space()
	committed := command(root, 'recreate-committed', ['/usr/bin/git', '-C', repo, 'show',
		commit + ':build-support/android/atlframework/recreate.v'])!
	parent := command(root, 'recreate-parent', ['/usr/bin/git', '-C', repo, 'show',
		commit + '^:build-support/android/atlframework/recreate.v'])!
	if committed != os.read_file(recreate)! || sha256.sum(parent.bytes()).hex() != old['recreate.v']! {
		return error('recreate.v must be committed directly over native351 source bytes')
	}
	os.mkdir_all(root + '/native-source')!
	os.write_file(root + '/native-source/recreate-parent.v', parent)!
	os.write_file(root + '/native-source/recreate-committed.v', committed)!
	write_json(root + '/native-source/revision.json', {
		'commit':           commit
		'parent_sha256':    old['recreate.v']!
		'committed_sha256': new['recreate.v']!
	})!
	inputs := json2.decode[map[string]string](os.read_file(root + '/native351/frozen-inputs.json')!)!
	for path, pin in inputs {
		relative := os.norm_path('inputs/' + path.trim_left('/'))
		frozen_copy(pins, relative, root + '/' + relative)!
		if hash(path)! != pin || hash(root + '/' + relative)! != pin {
			return error('live cross/runtime input differs: ' + path)
		}
	}
	closure := json2.decode[map[string]string](os.read_file(root + '/native351/native-generator-v-files.json')!)!
	for path, pin in closure {
		relative := 'closure-inputs/' + path.trim_left('/')
		frozen_copy(pins, relative, root + '/' + relative)!
		if hash(path)! != pin { return error('live generator closure differs: ' + path) }
	}
	frozen_copy(pins, 'tools/v_old276', root + '/tools/v_old276')!
	if hash(root + '/tools/v_old276')! != old_compiler_pin {
		return error('native compiler differs')
	}
	if hash(repo + '/build-support/find-v.sh')! != hash(root + '/native351/source/find-v.sh')! {
		return error('find-v helper differs')
	}
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('V', root + '/tools/v_old276', true)
	os.setenv('VINIX_V_COMPILER', root + '/tools/v_old276', true)
	specs := command(root, 'crosscompiler-specs', [cross, '-dumpspecs'])!
	if specs != os.read_file(root + '/native351/crosscompiler-specs.txt')! {
		return error('crosscompiler specs differ')
	}
	listing := command(root, 'native-generator-closure', [root + '/tools/v_old276', '-print-v-files',
		repo + '/tests/linuxkpi/generate_module.v'])!
	mut actual := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) { actual[path] = hash(path)! }
	if actual != closure { return error('native generator V closure differs') }
	command(root, 'generate-native', [root + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags',
		'-O2', '-showcc', 'run', repo + '/tests/linuxkpi/generate_module.v',
		root + '/native/atlframework', root + '/native/android-native.c', '--arch', 'arm64'])!
	if os.read_file(root + '/native/android-native.c')!.contains('v_fixed_index(') {
		return error('unexpected native fixed index helper')
	}
	runtime := root + '/inputs/build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
	command(root, 'build-native', [cross, '-v', '-D_GNU_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden',
		'-shared', '-fPIC', '-I' + root + '/native', '-Wl,-z,max-page-size=65536',
		'-Wl,--allow-shlib-undefined', root + '/native/android-native.c',
		runtime + '/usr/lib/art/libandroidfw.so', '-Wl,--no-as-needed',
		runtime + '/usr/lib/libpng16.so.16', runtime + '/usr/lib/libsqlite3.so.0', '-ldl', '-lm',
		'-o', root + '/native/libvinix-android-native.so'])!
	for path, pin in inputs {
		if hash(path)! != pin { return error('cross/runtime input changed: ' + path) }
	}
	for path, pin in closure {
		if hash(path)! != pin { return error('generator input changed: ' + path) }
	}
	// Require the complete defined dynamic symbol set and JNI names to match.
	mut exports := [][]string{}
	mut all_exports := [][]string{}
	for pair in [[root + '/baseline-native/libvinix-android-native.so', 'old'],
		[root + '/native/libvinix-android-native.so', 'new']] {
		elf_identity(pair[0])!
		out := command(root, pair[1] + '-jni-exports', [
			'/opt/homebrew/bin/aarch64-linux-musl-nm',
			'-D',
			'--defined-only',
			pair[0],
		])!
		mut all := out.split_into_lines().filter(it.fields().len >= 3).map(it.fields().last())
		all.sort()
		all_exports << all
		mut names := all.filter(it.starts_with('Java_'))
		names.sort()
		if names.len != 604 { return error('unexpected JNI export count') }
		exports << names
	}
	if exports[0] != exports[1] { return error('JNI export set changed') }
	if all_exports[0] != all_exports[1] { return error('defined dynamic export set changed') }
	write_json(root + '/native/defined-dynamic-exports.json', all_exports[1])!
	write_json(root + '/native/elf.json', {
		'class':        'ELF64'
		'byte_order':   'little endian'
		'type':         'shared object'
		'machine':      'AArch64'
		'export_delta': 'none'
	})!
	write_json(root + '/native/jni-exports.json', exports[1])!
	write_json(root + '/native/jni-export-delta.json', {
		'added':   []string{}
		'removed': []string{}
	})!
}

fn fresh_root(root string) ! {
	if os.exists(root) || os.is_link(root) || !root.starts_with(state + 'account-contract-') || os.real_path(os.dir(root)) != os.dir(root) || root.contains_any(' \n\t') {
		return error('fresh canonical external account-contract directory required')
	}
	os.mkdir_all(root + '/commands')!
	os.chdir(repo)!
	capacity_fields := command(root, 'disk-before', ['/bin/df', '-k', root])!.trim_space().split_into_lines().last().fields()
	if capacity_fields.len < 6 || capacity_fields[3].u64() < 640 * 1024 {
		return error('build requires 640 MiB available')
	}
}

fn native_only(root string) ! {
	fresh_root(root)!
	mut inputs := map[string]string{}
	for path in [source_file, recreate, repo + '/build-support/find-v.sh', compiler, os.executable()] {
		inputs[path] = hash(path)!
	}
	os.cp(source_file, root + '/builder-source.v')!
	os.cp(os.executable(), root + '/builder')!
	write_json(root + '/native-stage-inputs.json', inputs)!
	build_native(root)!
	for path, pin in inputs {
		if hash(path)! != pin { return error('native stage build input changed: ' + path) }
	}
	write_json(root + '/native-stage.json', {
		'scope':                     'Companion Activity native recreation only; no framework or authentication claim.'
		'source_revision':           command(root, 'revision', ['/usr/bin/git', '-C', repo, 'rev-parse',
			'HEAD'])!.trim_space()
		'native_sha256':             hash(root + '/native/libvinix-android-native.so')!
		'native_base_sha256':        native_pin
		'native351_manifest_sha256': native_manifest
		'environmental_inputs':      'System SDK and dynamic libraries remain environmental dependencies; copied frozen351 V, crosscompiler and runtime inputs guarded before and after generation.'
	})!
	println('COMPANION-ACTIVITY-NATIVE-STAGE-PASS native=' + root + '/native/libvinix-android-native.so')
}

fn build(root string) ! {
	fresh_root(root)!
	mut inputs := map[string]string{}
	for path in [source_file, provider, replace_helper, recreate, compiler, os.real_path(java),
		os.executable(), repo + '/build-support/find-v.sh', framework_base + '/api-impl.jar',
		framework_base + '/sha256.json'] {
		inputs[path] = hash(path)!
	}
	mut private_tools := []string{}
	os.mkdir_all(root + '/smali-tools')!
	mut jars := os.ls(smali_tools)!.filter(it.ends_with('.jar') || it.ends_with('.JAR'))
	jars.sort()
	if jars.len == 0 { return error('missing smali tool JARs') }
	for name in jars {
		inputs[smali_tools + '/' + name] = hash(smali_tools + '/' + name)!
		target := root + '/smali-tools/' + name
		os.cp(smali_tools + '/' + name, target)!
		inputs[target] = hash(target)!
		if inputs[target]! != inputs[smali_tools + '/' + name]! {
			return error('smali tool copy differs')
		}
		private_tools << target
	}
	if inputs[framework_base + '/api-impl.jar']! != jar_pin || inputs[framework_base + '/sha256.json']! != framework_manifest {
		return error('sealed response framework differs')
	}
	command(root, 'check-framework-baseline', [
		repo + '/build/android-maps/account-contract-retain',
		'check',
		framework_base,
		framework_manifest,
	])!
	os.cp(source_file, root + '/builder-source.v')!
	os.cp(os.executable(), root + '/builder')!
	write_json(root + '/compiler-reference.json', {
		'native_compiler_sha256': old_compiler_pin
		'VROOT':                  '/Users/alex/code/v'
		'scope':                  'Frozen351 consumed V, crosscompiler and runtime inputs copied; original paths guarded before and after generation. System SDK and dynamic libraries remain environmental dependencies.'
	})!
	write_json(root + '/baseline-reference.json', {
		'framework_path':            framework_base
		'framework_manifest_sha256': framework_manifest
		'native_path':               native_base
		'native_manifest_sha256':    native_manifest
		'scope':                     'Framework baseline fully verified. Native baseline consumed sources, headers, library, compiler and generator/crosscompiler/runtime inputs verified against sealed inventory; no historical mutation or full historical rescan.'
	})!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('V', compiler, true)
	os.setenv('VINIX_V_COMPILER', compiler, true)
	command(root, 'java-version', [java, '--version'])!
	command(root, 'v-version', [compiler, 'version'])!
	driver_listing := command(root, 'builder-closure', [compiler, '-print-v-files', source_file])!
	driver_closure := freeze_closure(root, driver_listing, 'builder-closure-inputs')!
	write_json(root + '/builder-compilation-recipe.json', {
		'argv':  json2.Any([compiler, '-cc', 'cc', '-cflags', '-O2', '-o', os.executable(),
			source_file])
		'scope': json2.Any('Recipe for the retained builder source and compiler; this receipt records no additional compilation execution.')
	})!
	build_framework(root, private_tools.join(':'))!
	build_native(root)!
	for path, pin in driver_closure {
		if hash(path)! != pin { return error('builder source closure changed: ' + path) }
	}
	for path, pin in inputs {
		if hash(path)! != pin { return error('build input changed: ' + path) }
	}
	write_json(root + '/build.json', {
		'scope':                     json2.Any('Companion Activity launch/result/recreation contract only; Google authentication remains unavailable')
		'source_revision':           json2.Any(command(root, 'revision', [
			'/usr/bin/git',
			'-C',
			repo,
			'rev-parse',
			'HEAD',
		])!.trim_space())
		'input_sha256':              json2.decode[json2.Any](json2.encode(inputs))!
		'baseline_manifest_sha256':  json2.Any(framework_manifest)
		'native351_manifest_sha256': json2.Any(native_manifest)
		'api_impl_sha256':           json2.Any(hash(root + '/api-impl.jar')!)
		'classes_dex_sha256':        json2.Any(hash(root + '/classes.dex')!)
		'native_sha256':             json2.Any(hash(root + '/native/libvinix-android-native.so')!)
		'native_base_sha256':        json2.Any(native_pin)
		'changed_classes':           json2.Any(changed_classes)
		'added_classes':             json2.Any([]string{})
		'class_count':               json2.Any(framework_class_count)
	})!
	println('COMPANION-ACTIVITY-BUILD-PASS jar=' + root + '/api-impl.jar native=' + root + '/native/libvinix-android-native.so')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len == 3 && os.args[1] == '--native-only' {
		native_only(os.abs_path(os.args[2])) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len != 2 {
		eprintln('usage: companion-activity-build [--native-only] FRESH_EXTERNAL_ROOT | --self-test')
		exit(2)
	}
	build(os.abs_path(os.args[1])) or {
		eprintln(err)
		exit(1)
	}
}
