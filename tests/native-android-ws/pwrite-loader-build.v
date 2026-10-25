// SPDX-License-Identifier: GPL-2.0-or-later
// Standalone production Bionic loader build; no JNI, framework or guest work.
module main

import crypto.sha256
import json2
import os
import time

const audit = '/Users/alex/.local/state/vinix/android/pwrite357-loader-build-2026-10-26'
const native351 = '/Users/alex/.local/state/vinix/android/text-size351-native-build-2026-10-25'
const native351_pin = 'eb0dfe0dd87ea7f5972bddd06ae4c0c45ba8b9e5ad56a39c074142847f4bccd9'
const host_proof = '/Users/alex/.local/state/vinix/android/pwrite-fortify357-host-2026-10-26'
const host_pin = 'ac847e5693bcbe02563c753086555f623d68206cf4689d3cf28bb7555e989bfe'
const maps356 = '/Users/alex/.local/state/vinix/android/maps356-2026-10-25'
const old_loader_pin = '206bc086ab1579b59eec865756e7d4ab8e0db5a2537b5fea3df3503de08dc5d4'
const old_revision = 'a8721ba11b691df980eb7a96309f7351efc6f550'
const compiler = '/Users/alex/code/vinix/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const cross = '/opt/homebrew/bin/aarch64-linux-musl-gcc'
const source_name = 'tests/native-android-ws/pwrite-loader-build.v'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn write_json[T](path string, value T) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn clone(from string, to string) ! {
	os.mkdir_all(os.dir(to))!
	if os.exists(to) { assert hash(from)! == hash(to)!, to; return }
	r := os.exec(['/bin/cp', '-c', os.real_path(from), to])
	assert r.exit_code == 0, r.output
	assert hash(from)! == hash(to)!, from
}

fn command(label string, argv []string) !string {
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(audit + '/' + label + '.log', r.output)!
	write_json(audit + '/' + label + '.json', {
		'argv': json2.Any(argv), 'started_utc': json2.Any(started),
		'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(r.exit_code),
		'executable_sha256': json2.Any(hash(if argv[0].contains('/') { os.real_path(argv[0]) } else { os.find_abs_path_of_executable(argv[0])! })!)
	})!
	assert r.exit_code == 0, label + ': ' + r.output
	return r.output
}

fn closure(label string, source string) !map[string]string {
	listing := command(label + '-closure', [compiler, '-print-v-files', source])!
	mut pins := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		pins[path] = hash(path)!
		clone(path, audit + '/closure-inputs/' + path.trim_left('/'))!
	}
	assert pins.len > 0
	write_json(audit + '/' + label + '-v-files.json', pins)!
	return pins
}

fn verify_inputs(pins map[string]string) ! {
	for path, pin in pins {
		assert hash(path)! == pin, path
		assert hash(os.norm_path(audit + '/inputs/' + path.trim_left('/')))! == pin, path
	}
}

fn exports(text string) []string {
	mut result := []string{}
	for line in text.split_into_lines() {
		fields := line.fields()
		if fields.len >= 8 && fields[4] in ['GLOBAL', 'WEAK'] && fields[6] != 'UND' {
			result << fields.last()
		}
	}
	result.sort()
	return result
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular bundle entry: ' + key) }
		}
	}
}

fn run() ! {
	assert !os.exists(audit) && !os.is_link(audit), audit
	assert hash(native351 + '/sha256.json')! == native351_pin
	assert hash(host_proof + '/sha256.json')! == host_pin
	assert hash(compiler)! == compiler_pin
	os.mkdir_all(audit + '/source/wsloader')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('V', compiler, true)
	os.setenv('VINIX_V_COMPILER', compiler, true)
	os.setenv('VINIX_PWRITE_BUILD_ROOT', audit, true)
	clone(source_name, audit + '/source/pwrite-loader-build.v')!
	clone(os.executable(), audit + '/tools/pwrite-loader-build')!
	clone(compiler, audit + '/tools/v_old276')!
	clone(native351 + '/sha256.json', audit + '/reference/native351-sha256.json')!
	clone(host_proof + '/sha256.json', audit + '/reference/host-proof-sha256.json')!
	write_json(audit + '/source/revisions.json', {
		'current': command('source-revision', ['git', 'rev-parse', 'HEAD'])!.trim_space(),
		'baseline_wsloader': old_revision,
		'native351_manifest': native351_pin, 'host_proof_manifest': host_pin
	})!
	mut changed := []string{}
	mut production := map[string]string{}
	old_names := command('baseline-source-list', ['git', 'ls-tree', '-r', '--name-only', old_revision,
		'build-support/android/wsloader'])!.split_into_lines().filter(it.ends_with('.v') && !it.ends_with('_test.v'))
	mut live_names := []string{}
	for name in os.ls('build-support/android/wsloader')! {
		if name.ends_with('.v') && !name.ends_with('_test.v') { live_names << 'build-support/android/wsloader/' + name }
	}
	live_names.sort()
	assert old_names == live_names
	host_pins := json2.decode[map[string]string](os.read_file(host_proof + '/sha256.json')!)!
	for path in old_names {
		name := os.file_name(path)
		old := os.exec(['git', 'show', old_revision + ':' + path])
		assert old.exit_code == 0
		current := os.read_file(path)!
		assert hash(path)! == host_pins['source/wsloader/' + name]!, path
		os.mkdir_all(audit + '/baseline/wsloader')!
		os.write_file(audit + '/baseline/wsloader/' + name, old.output)!
		clone(path, audit + '/source/wsloader/' + name)!
		production[path] = hash(path)!
		if current != old.output { changed << name }
	}
	assert changed == ['fortify.v']
	write_json(audit + '/source/wsloader-delta.json', {'changed': changed, 'added': []string{}, 'removed': []string{}})!
	for path in ['tests/native-android-tools/androidtools/native_bionic.v', 'build-support/android/bionic16k.patch'] {
		baseline := os.exec(['git', 'show', old_revision + ':' + path])
		assert baseline.exit_code == 0 && baseline.output == os.read_file(path)!, path
	}
	clone('tests/native-android-tools/androidtools/native_bionic.v', audit + '/driver/androidtools/native_bionic.v')!
	clone('build-support/android/bionic16k.patch', audit + '/source/repo/build-support/android/bionic16k.patch')!
	production['tests/native-android-tools/androidtools/native_bionic.v'] = hash('tests/native-android-tools/androidtools/native_bionic.v')!
	production['build-support/android/bionic16k.patch'] = hash('build-support/android/bionic16k.patch')!
	write_json(audit + '/source/production-inputs.json', production)!
	// Use the production builder verbatim. This helper only records commands.
	os.write_file(audit + '/driver/androidtools/recorded.v', "module androidtools\nimport crypto.sha256\nimport json2\nimport os\nimport time\nstruct Output { stdout string }\nfn root() string { return os.getenv('VINIX_PWRITE_BUILD_ROOT') + '/source/repo' }\nfn checked(argv []string) !Output {\n root := os.getenv('VINIX_PWRITE_BUILD_ROOT')\n label := sha256.sum(json2.encode(argv).bytes()).hex()\n started := time.utc().str()\n r := os.exec(argv)\n os.write_file(root + '/commands/' + label + '.log', r.output)!\n executable := if argv[0].contains('/') { os.real_path(argv[0]) } else { os.find_abs_path_of_executable(argv[0])! }\n os.write_file(root + '/commands/' + label + '.json', json2.encode({'argv': json2.Any(argv), 'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(r.exit_code), 'executable_sha256': json2.Any(sha256.sum(os.read_bytes(executable)!).hex())}, prettify: true) + '\n')!\n if r.exit_code != 0 { return error(argv.str() + '\n' + r.output) }\n return Output{r.output}\n}\n")!
	os.write_file(audit + '/driver/main.v', "module main\nimport androidtools\nimport os\nfn main() { androidtools.build_native_bionic(os.args[1], os.args[2], os.args[3], 'arm64') or { eprintln(err); exit(1) } }\n")!
	os.mkdir_all(audit + '/commands')!
	native_pins := json2.decode[map[string]string](os.read_file(native351 + '/sha256.json')!)!
	for name in ['frozen-inputs.json', 'native-generator-v-files.json'] {
		assert hash(native351 + '/' + name)! == native_pins[name]!, name
		clone(native351 + '/' + name, audit + '/reference/' + name)!
	}
	inputs := json2.decode[map[string]string](os.read_file(native351 + '/frozen-inputs.json')!)!
	os.mkdir_all(audit + '/inputs')!
	bulk := os.exec(['/bin/cp', '-cR', native351 + '/inputs/opt', audit + '/inputs/opt'])
	assert bulk.exit_code == 0, bulk.output
	mut consumed := map[string]string{}
	for path, pin in inputs {
		if !path.starts_with('/opt/homebrew/') { continue }
		relative := os.norm_path('inputs/' + path.trim_left('/'))
		assert native_pins[relative]! == pin && hash(native351 + '/' + relative)! == pin, path
		assert hash(path)! == pin, path
		clone(native351 + '/' + relative, audit + '/' + relative)!
		consumed[path] = pin
	}
	assert consumed.len > 100
	write_json(audit + '/frozen-cross-inputs.json', consumed)!
	command('cross-specs', [cross, '-dumpspecs'])!
	assert hash(audit + '/cross-specs.log')! == native_pins['crosscompiler-specs.txt']!
	// Reuse pinned downloads; the verbatim production builder checks each hash.
	for name in ['bionic.tar.gz', 'libunwind-dev-1.8.3-r0.apk', 'elfutils-dev-0.195-r0.apk',
		'bsd-compat-headers-0.7.2-r6.apk', 'headers/usr/include/EGL/egl.h',
		'headers/usr/include/EGL/eglplatform.h', 'headers/usr/include/KHR/khrplatform.h'] {
		clone('build/android-maps/native/bionic-ws/' + name, audit + '/loader/bionic-ws/' + name)!
	}
	clone('build/android-framework/calculator/overlay/opt/vinix-android-aarch64/usr/lib/libunwind.so.8', audit + '/runtime/usr/lib/libunwind.so.8')!
	assert hash(audit + '/runtime/usr/lib/libunwind.so.8')! == 'c9ced059daebc46f44dbb8cf4077ee341438495163aca4ffb438a4692b39cafe'
	clone(maps356 + '/prelaunch/maps356/module/opt/vinix-android-aarch64/usr/lib/art/native-ws/libdl_bio.so.0', audit + '/baseline/libdl_bio.so.0')!
	assert hash(audit + '/baseline/libdl_bio.so.0')! == old_loader_pin
	gen_closure := closure('loader-generator', 'tests/linuxkpi/generate_module.v')!
	assert gen_closure == json2.decode[map[string]string](os.read_file(native351 + '/native-generator-v-files.json')!)!
	build_closure := closure('loader-builder', audit + '/driver')!
	command('compile-builder', [compiler, '-nocache', '-cc', 'cc', '-showcc', '-o', audit + '/tools/production-loader-build', audit + '/driver'])!
	command('generate-loader', [compiler, '-nocache', '-cc', 'cc', 'run', 'tests/linuxkpi/generate_module.v',
		audit + '/source/wsloader', audit + '/loader/android-loader.c', '--arch', 'arm64'])!
	assert hash(audit + '/loader/android-loader.c')! == host_pins['android-loader.c']!
	verify_inputs(consumed)!
	command('build-loader', [audit + '/tools/production-loader-build', audit + '/loader', audit + '/runtime', cross])!
	verify_inputs(consumed)!
	for pins in [gen_closure, build_closure] {
		for path, pin in pins {
			assert hash(path)! == pin, path
			assert hash(audit + '/closure-inputs/' + path.trim_left('/'))! == pin, path
		}
	}
	for path, pin in production { assert hash(path)! == pin, path }
	readelf := os.find_abs_path_of_executable('aarch64-linux-musl-readelf')!
	old := exports(command('baseline-symbols', [readelf, '--dyn-syms', '--wide', audit + '/baseline/libdl_bio.so.0'])!)
	new_text := command('loader-symbols', [readelf, '--dyn-syms', '--wide', audit + '/loader/libdl_bio.so.0'])!
	new := exports(new_text)
	assert old.filter(it !in new).len == 0
	added := new.filter(it !in old)
	assert added == ['bionic___pwrite64_chk', 'bionic___pwrite_chk',
		'wsloader__checked_pwrite', 'wsloader__checked_pwrite64']
	assert added.filter(it.starts_with('bionic_')) == ['bionic___pwrite64_chk', 'bionic___pwrite_chk']
	for symbol in ['bionic___pwrite_chk', 'bionic___pwrite64_chk'] {
		rows := new_text.split_into_lines().filter(it.fields().len >= 8 && it.fields().last() == symbol)
		assert rows.len == 1, symbol
		fields := rows[0].fields()
		assert fields[3] == 'FUNC' && fields[4] == 'GLOBAL' && fields[5] == 'DEFAULT' && fields[6] != 'UND', symbol
	}
	assert new_text.split_into_lines().any(it.contains(' UND ') && it.fields().last() == 'pwrite')
	elf := command('loader-elf', [readelf, '-h', '-l', '-d', '--wide', audit + '/loader/libdl_bio.so.0'])!
	assert elf.contains('ELF64') && elf.contains('AArch64')
	assert elf.contains('Library soname: [libdl_bio.so.0]')
	needed := elf.split_into_lines().filter(it.contains('(NEEDED)')).map(it.all_after('[').all_before(']'))
	assert needed == ['libunwind.so.8', 'libc.so']
	write_json(audit + '/validation.json', {'loader_sha256': hash(audit + '/loader/libdl_bio.so.0')!,
		'old_loader_sha256': old_loader_pin, 'changed_wsloader_source': 'fortify.v',
		'export_delta': 'bionic___pwrite_chk,bionic___pwrite64_chk,wsloader__checked_pwrite,wsloader__checked_pwrite64',
		'scope': 'Standalone production loader build; JNI/framework untouched; no guest execution.'})!
	mut inventory_pins := map[string]string{}
	inventory(audit, '', mut inventory_pins)!
	write_json(audit + '/sha256.json', inventory_pins)!
	println('PWRITE357-LOADER-BUILD-PASS loader=' + hash(audit + '/loader/libdl_bio.so.0')! + ' files=' + inventory_pins.len.str() + ' manifest=' + hash(audit + '/sha256.json')!)
}

fn main() {
	$if prod { panic('requires assertions') }
	run() or { eprintln(err); exit(1) }
}
