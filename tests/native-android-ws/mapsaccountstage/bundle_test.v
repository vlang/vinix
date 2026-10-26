// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

import json2
import os

fn test_receipt_numbers_preserve_exact_numeric_contract() {
	for text in ['7', '7.0', '7e0'] {
		value := json2.decode[json2.Any](text) or { panic(err) }
		assert exact_integer(value, 7)
	}
	for text in ['"7"', 'true', 'null', '7.1', '-7', '4294967303', '[]', '{}'] {
		value := json2.decode[json2.Any](text) or { panic(err) }
		assert !exact_integer(value, 7)
	}
}

fn test_framework_requires_exact_selected_pins_and_profile_class_count() ! {
	seal, jar, dex := 'a'.repeat(64), 'b'.repeat(64), 'c'.repeat(64)
	for profile, count in {'cache-2102': 2102, 'descriptions-2104': 2104} {
		valid := Bundle{
			seal: seal
			files: {'api-impl.jar': jar, 'classes.dex': dex}
			receipt: {'profile': json2.Any(profile), 'class_count': json2.Any(count),
				'api_impl_sha256': json2.Any(jar), 'classes_dex_sha256': json2.Any(dex)}
		}
		assert verify_framework(valid, seal, jar, dex)!.profile == profile
		for changed in [count - 1, count + 1, 2103] {
			mut receipt := valid.receipt.clone()
			receipt['class_count'] = changed
			if _ := verify_framework(Bundle{...valid, receipt: receipt}, seal, jar, dex) {
				assert false, 'framework class count mismatch accepted'
			}
		}
		mut unknown := valid.receipt.clone()
		unknown['profile'] = 'unknown'
		if _ := verify_framework(Bundle{...valid, receipt: unknown}, seal, jar, dex) { assert false }
		if _ := verify_framework(valid, 'd'.repeat(64), jar, dex) { assert false }
		if _ := verify_framework(valid, seal, dex, jar) { assert false }
	}
}

fn test_static_zlib_retains_exact_producer_and_consumed_subset() ! {
	root := os.join_path(os.real_path(os.temp_dir()), 'maps-zlib-test-' + os.getpid().str())
	assert !os.exists(root)
	os.mkdir(root, mode: 0o700)!
	defer { os.rmdir_all(root) or {} }
	producer := Bundle{
		files: {'build.json': 'b'.repeat(64), 'lib/libz.a': 'c'.repeat(64),
			'native/zlib.h': 'd'.repeat(64), 'native/zconf.h': 'e'.repeat(64)}
		receipt: {'kind': json2.Any('vinix-account-zlib-static-v1'),
			'source_archive_sha256': json2.Any(zlib_source), 'architecture': json2.Any('aarch64'), 'pic': json2.Any(true)}
	}
	mut files := {'zlib-producer-sha256.json': zlib_seal,
		'zlib-producer-build.json': producer.files['build.json']!, 'zlib-native-inputs.json': 'f'.repeat(64)}
	mut consumed := map[string]string{}
	for name in ['lib/libz.a', 'native/zlib.h', 'native/zconf.h'] {
		files['zlib/' + name] = producer.files[name]!
		consumed[root + '/zlib/' + name] = producer.files[name]!
	}
	os.write_file(root + '/zlib-native-inputs.json', json2.encode(consumed))!
	valid := Bundle{root: root, files: files}
	verify_retained_zlib(valid, producer)!
	for name in files.keys().filter(it != 'zlib-native-inputs.json') {
		mut wrong := files.clone()
		wrong[name] = '0'.repeat(64)
		if _ := verify_retained_zlib(Bundle{...valid, files: wrong}, producer) { assert false, name }
	}
	for name in consumed.keys() {
		mut missing := consumed.clone()
		missing.delete(name)
		os.write_file(root + '/zlib-native-inputs.json', json2.encode(missing))!
		if _ := verify_retained_zlib(valid, producer) { assert false, 'omitted consumed input accepted' }
	}
	consumed[root + '/unexpected'] = '0'.repeat(64)
	os.write_file(root + '/zlib-native-inputs.json', json2.encode(consumed))!
	if _ := verify_retained_zlib(valid, producer) { assert false, 'extra consumed input accepted' }
	verify_zlib_trace('/retained/libz.a\n', '/retained/libz.a')!
	for trace in ['', '/other/libz.a\n', '/retained/libz.a\n/usr/lib/libz.so.1\n'] {
		if _ := verify_zlib_trace(trace, '/retained/libz.a') { assert false, 'missing archive or dynamic fallback accepted' }
	}
}

fn test_static_zlib_is_selected_per_retained_consumer_label() {
	bundle := Bundle{root: '/build', files: {
		'closure/broker/frozen/accountmanifest/authenticator_zip.v': 'a'.repeat(64)
		'closure/broker/frozen/header.h': 'b'.repeat(64)
		'closure/controller/frozen/header.h': 'c'.repeat(64)
	}}
	assert uses_zlib(bundle, 'broker')
	assert !uses_zlib(bundle, 'controller')
	assert build_includes(bundle, 'broker') == ['-I/build/zlib/native', '-I/build/closure/broker/frozen']
	assert build_includes(bundle, 'controller') == ['-I/build/closure/controller/frozen']
}

fn test_sealed_bundle_rejects_inventory_and_inode_changes() ! {
	root := os.join_path(os.real_path(os.temp_dir()), 'maps-bundle-test-' + os.getpid().str())
	assert !os.exists(root)
	os.mkdir(root, mode: 0o700)!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/build.json', '{}')!
	os.write_file(root + '/output', 'output')!
	pins := {'build.json': digest(root + '/build.json')!, 'output': digest(root + '/output')!}
	os.write_file(root + '/sha256.json', json2.encode(pins))!
	seal := digest(root + '/sha256.json')!
	bundle := load_bundle(root, seal)!
	assert bundle.files == pins
	recheck(bundle)!
	os.write_file(root + '/unexpected', 'extra')!
	if _ := load_bundle(root, seal) { assert false, 'unlisted file accepted' }
	os.rm(root + '/unexpected')!
	os.write_file(root + '/output', 'modified')!
	if _ := recheck(bundle) { assert false, 'modified output accepted' }
	os.rm(root + '/output')!
	os.symlink(root + '/build.json', root + '/output')!
	if _ := load_bundle(root, seal) { assert false, 'symlink accepted' }
	os.rm(root + '/output')!
	os.write_file(root + '/output', 'output')!
	if _ := load_bundle(root, 'a'.repeat(64)) { assert false, 'wrong manifest seal accepted' }
}

fn test_exact_outputs_and_typed_receipt_fields() ! {
	pin := 'a'.repeat(64)
	mut value := Bundle{
		files: {'bin/first': pin, 'bin/second': pin}
		receipt: {'outputs_sha256': json2.Any({'bin/first': json2.Any(pin)})}
	}
	assert output_map(value, 'outputs_sha256', ['bin/first'])! == {'bin/first': pin}
	if _ := output_map(value, 'outputs_sha256', ['bin/first', 'bin/second']) { assert false, 'incomplete output set accepted' }
	value = Bundle{
		files: value.files
		receipt: {'outputs_sha256': json2.Any({'bin/first': json2.Any(pin), 'bin/second': json2.Any(pin)})}
	}
	if _ := output_map(value, 'outputs_sha256', ['bin/first']) { assert false, 'extra output accepted' }
	for input in [json2.Any(7), json2.Any(true), json2.Any([json2.Any('test')])] {
		if _ := text_field({'name': input}, 'name') { assert false, 'non-string field accepted' }
	}
	for path in ['', '/absolute', '../escape', 'a//b', 'a/./b', 'a/../b', 'a\nb', 'a\\b'] {
		assert !relative_file(path), path
	}
}

fn test_native_and_launch_cannot_change_framework_identity() ! {
	framework := Bundle{root: '/framework', seal: 'a'.repeat(64)}
	valid := Bundle{
		files: {'framework-sha256.json': framework.seal}
		receipt: {'framework': json2.Any(framework.root), 'framework_sha256': json2.Any(framework.seal)}
	}
	coupled_framework(valid, framework)!
	for field in ['framework', 'framework_sha256'] {
		mut changed := valid.receipt.clone()
		changed[field] = 'different'
		invalid := Bundle{files: valid.files, receipt: changed}
		if _ := coupled_framework(invalid, framework) { assert false, 'changed framework coupling accepted' }
	}
	invalid := Bundle{files: {'framework-sha256.json': 'b'.repeat(64)}, receipt: valid.receipt}
	if _ := coupled_framework(invalid, framework) { assert false, 'wrong retained framework manifest accepted' }
}

fn test_controller_receipt_requires_selected_static_output_and_build_identity() ! {
	root := os.join_path(os.real_path(os.temp_dir()), 'maps-controller-test-' + os.getpid().str())
	assert !os.exists(root)
	os.mkdir_all(root + '/bin')!
	defer { os.rmdir_all(root) or {} }
	mut bytes := []u8{len: 120}
	for index, value in [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] { bytes[index] = value }
	bytes[16] = 2
	bytes[18] = 183
	bytes[20] = 1
	bytes[32] = 64
	bytes[52] = 64
	bytes[54] = 56
	bytes[56] = 1
	bytes[64] = 1
	bytes[96] = 120
	bytes[104] = 120
	os.write_file_array(root + '/bin/controller', bytes)!
	pin := digest(root + '/bin/controller')!
	valid := Bundle{
		root: root
		files: {'bin/controller': pin}
		receipt: {
			'kind': json2.Any('controller-kind')
			'source_revision': json2.Any('a'.repeat(40))
			'native_base_sha256': json2.Any(baseline_seal)
			'compiler_sha256': json2.Any(compiler_seal)
			'outputs_sha256': json2.Any({'bin/controller': json2.Any(pin)})
		}
	}
	verify_static_controller(valid, 'controller-kind', 'controller')!
	for field in ['kind', 'source_revision', 'native_base_sha256', 'compiler_sha256'] {
		mut receipt := valid.receipt.clone()
		receipt[field] = 'changed'
		if _ := verify_static_controller(Bundle{root: root, files: valid.files, receipt: receipt}, 'controller-kind', 'controller') {
			assert false, 'controller build identity mutation accepted: ' + field
		}
	}
	if _ := verify_static_controller(Bundle{root: root, files: valid.files, receipt: {
		...valid.receipt
		'outputs_sha256': json2.Any({'bin/controller': json2.Any('b'.repeat(64))})
	}}, 'controller-kind', 'controller') { assert false, 'controller output mutation accepted' }
}

fn browser_test_u64(mut bytes []u8, at int, value u64) {
	for index in 0 .. 8 { bytes[at + index] = u8(value >> (8 * index)) }
}

fn browser_test_elf(needed []string, runpath string) []u8 {
	mut bytes := []u8{len: 1024}
	for index, value in [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] { bytes[index] = value }
	bytes[16] = 3
	bytes[18] = 183
	bytes[20] = 1
	bytes[32] = 64
	bytes[52] = 64
	bytes[54] = 56
	bytes[56] = 2
	bytes[64] = 1
	browser_test_u64(mut bytes, 80, 0x1000)
	browser_test_u64(mut bytes, 96, 1024)
	browser_test_u64(mut bytes, 104, 1024)
	bytes[120] = 2
	browser_test_u64(mut bytes, 128, 256)
	browser_test_u64(mut bytes, 136, 0x1100)
	browser_test_u64(mut bytes, 152, 16 * u64(3 + needed.len + if runpath != '' { 1 } else { 0 }))
	browser_test_u64(mut bytes, 256, 5)
	browser_test_u64(mut bytes, 264, 0x1200)
	browser_test_u64(mut bytes, 272, 10)
	browser_test_u64(mut bytes, 280, 512)
	mut cursor := 1
	mut at := 288
	for name in needed {
		browser_test_u64(mut bytes, at, 1)
		browser_test_u64(mut bytes, at + 8, u64(cursor))
		for index, value in name.bytes() { bytes[512 + cursor + index] = value }
		cursor += name.len + 1
		at += 16
	}
	if runpath != '' {
		browser_test_u64(mut bytes, at, 29)
		browser_test_u64(mut bytes, at + 8, u64(cursor))
		for index, value in runpath.bytes() { bytes[512 + cursor + index] = value }
	}
	return bytes
}

fn browser_test_json(root string, name string, value json2.Any, mut files map[string]string) ! {
	os.mkdir_all(os.dir(root + '/' + name))!
	os.write_file(root + '/' + name, json2.encode(value))!
	files[name] = digest(root + '/' + name)!
}

fn browser_test_pins(pins map[string]string) json2.Any {
	mut fields := map[string]json2.Any{}
	for path, pin in pins { fields[path] = pin }
	return fields
}

fn browser_test_command(root string, name string, argv []string, mut files map[string]string) ! {
	browser_test_json(root, 'commands/' + name + '.json', json2.Any({
		'argv': json2.Any(argv)
		'exit_code': json2.Any(0)
		'executable_sha256': json2.Any(compiler_seal)
	}), mut files)!
}

fn browser_test_bundle(root string, sqlite bool) !Bundle {
	os.mkdir_all(root + '/lib')!
	os.mkdir_all(root + '/generated')!
	output := 'lib/libvinix-android-browser.so'
	os.write_file_array(root + '/' + output, browser_test_elf(if sqlite { ['libsqlite3.so.0'] } else { []string{} }, ''))!
	mut files := {output: digest(root + '/' + output)!, 'baseline-sha256.json': baseline_seal}
	source := 'closure/browser/Users/alex/code/vinix/build-support/android/browserclient'
	os.mkdir_all(root + '/' + source)!
	os.write_file(root + '/' + source + '/abi.v', browser_abi().map("@[export: '" + it + "']").join('\n'))!
	files[source + '/abi.v'] = digest(root + '/' + source + '/abi.v')!
	v := root + '/closure/browser/frozen/v'
	files[v[root.len + 1..]] = compiler_seal
	runtime_source := 'closure/browser/frozen/vlib/builtin/segfault_handler_nix.c'
	for name in [runtime_source, 'generated/browser.c', 'generated/browser.o', 'generated/browser-runtime.o'] {
		os.mkdir_all(os.dir(root + '/' + name))!
		os.write_file(root + '/' + name, name)!
		files[name] = digest(root + '/' + name)!
	}
	mut dependencies := map[string]string{}
	mut headers := []string{}
	if sqlite {
		files['closure/browser/frozen/accountstore/store.v'] = 'a'.repeat(64)
		files['lib/libsqlite3.so.0'] = sqlite_seal
		dependencies['lib/libsqlite3.so.0'] = sqlite_seal
		headers << '-I' + root + '/native'
	}
	mut generate := [v, '-new-compiler', '-os', 'linux', '-arch', 'arm64', '-cc', cross,
		'-gc', 'none', '-nocache', '-skip-running', '-exclude', '@vlib/crypto/rand/internal/rand.wasm.v', '-path',
		root + '/closure/browser/frozen', '-enable-globals', '-manualfree', '-shared', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
		'-o', root + '/generated/browser.c', root + '/' + source]
	browser_test_command(root, 'generate-browser', generate, mut files)!
	for pair in [['browser', root + '/generated/browser.c'], ['browser-runtime', root + '/' + runtime_source]] {
		mut compile := [cross, '-v', '-D_GNU_SOURCE', '-O2', '-fwrapv', '-pthread', '-fPIC',
			'-Werror=implicit-function-declaration', '-Werror=int-conversion']
		compile << headers
		compile << ['-c', pair[1], '-o', root + '/generated/' + pair[0] + '.o']
		browser_test_command(root, 'compile-' + pair[0], compile, mut files)!
		mut scan := [cross, '-D_GNU_SOURCE', '-O2', '-fwrapv', '-pthread', '-M', '-MT', pair[0], '-fPIC']
		scan << headers
		scan << pair[1]
		browser_test_command(root, pair[0] + '-headers', scan, mut files)!
		browser_test_json(root, 'generated/' + pair[0] + '-headers.json', browser_test_pins({pair[1]: files[pair[1][root.len + 1..]]!}), mut files)!
		log := 'commands/' + pair[0] + '-headers.log'
		os.write_file(root + '/' + log, pair[0] + ': ' + pair[1] + '\n')!
		files[log] = digest(root + '/' + log)!
	}
	objects := [root + '/generated/browser.o', root + '/generated/browser-runtime.o']
	mut link := [cross, '-v', '-shared', '-pthread', '-Wl,-z,defs', '-Wl,-z,max-page-size=65536', '-Wl,-t']
	link << objects
	if sqlite { link << root + '/lib/libsqlite3.so.0' }
	link << ['-ldl', '-lm', '-o', root + '/' + output]
	browser_test_command(root, 'build-browser', link, mut files)!
	mut linked := map[string]string{}
	for path in objects { linked[path] = files[path[root.len + 1..]]! }
	if sqlite { linked[root + '/lib/libsqlite3.so.0'] = sqlite_seal }
	for name in ['crti.o', 'crtbeginS.o', 'crtn.o'] {
		path := 'cross/' + name
		os.mkdir_all(root + '/cross')!
		os.write_file(root + '/' + path, name)!
		files[path] = digest(root + '/' + path)!
		linked[root + '/' + path] = files[path]!
	}
	browser_test_json(root, 'generated/browser-link-inputs.json', browser_test_pins(linked), mut files)!
	browser_test_json(root, 'cross-inputs.json', browser_test_pins(map[string]string{}), mut files)!
	os.write_file(root + '/commands/build-browser.log', linked.keys().join('\n') + '\n')!
	files['commands/build-browser.log'] = digest(root + '/commands/build-browser.log')!
	nm := '/retained/cross/nm'
	files['additional-cross/' + nm.trim_left('/')] = 'b'.repeat(64)
	browser_test_json(root, 'nm-input.json', browser_test_pins({nm: 'b'.repeat(64)}), mut files)!
	browser_test_command(root, 'browser-exports', [nm, '-D', '--defined-only', root + '/' + output], mut files)!
	os.write_file(root + '/commands/browser-exports.log', browser_abi().map('00000000 T ' + it).join('\n') + '\n')!
	files['commands/browser-exports.log'] = digest(root + '/commands/browser-exports.log')!
	return Bundle{root: root, files: files, receipt: {
		'kind': json2.Any('vinix-current-browser-v1'), 'source_revision': json2.Any('a'.repeat(40)),
		'native_base_sha256': json2.Any(baseline_seal), 'compiler_sha256': json2.Any(compiler_seal),
		'exports': json2.Any(browser_abi()), 'outputs_sha256': browser_test_pins({output: files[output]!}),
		'runtime_dependencies_sha256': browser_test_pins(dependencies),
	}}
}

fn test_browser_bundle_requires_its_abi_build_closure_and_selected_dependencies() ! {
	root := os.join_path(os.real_path(os.temp_dir()), 'maps-browser-test-' + os.getpid().str())
	assert !os.exists(root)
	os.mkdir(root, mode: 0o700)!
	defer { os.rmdir_all(root) or {} }
	available := {'lib/libsqlite3.so.0': sqlite_seal}
	for sqlite in [false, true] {
		valid := browser_test_bundle(root + '/' + sqlite.str(), sqlite)!
		verify_browser_client(valid, available)!
		if sqlite {
			for missing in [map[string]string{}, {'lib/libsqlite3.so.0': 'f'.repeat(64)}] {
				if _ := verify_browser_client(valid, missing) { assert false, 'unprovided runtime accepted' }
			}
		}
		for field in ['kind', 'source_revision', 'native_base_sha256', 'compiler_sha256'] {
			mut receipt := valid.receipt.clone()
			receipt[field] = 'changed'
			if _ := verify_browser_client(Bundle{...valid, receipt: receipt}, available) { assert false, field }
		}
		for outputs in [map[string]string{}, {'lib/libvinix-android-browser.so': 'f'.repeat(64)},
			{'lib/libvinix-android-browser.so': valid.files['lib/libvinix-android-browser.so']!, 'lib/extra.so': 'f'.repeat(64)}] {
			mut receipt := valid.receipt.clone()
			receipt['outputs_sha256'] = browser_test_pins(outputs)
			if _ := verify_browser_client(Bundle{...valid, receipt: receipt}, available) { assert false, 'output mutation accepted' }
		}
		for exports in [browser_abi()[..3], [browser_abi()[0], browser_abi()[0], browser_abi()[2], browser_abi()[3]],
			['vinix_android_browser_extra', ...browser_abi()]] {
			mut receipt := valid.receipt.clone()
			receipt['exports'] = exports
			if _ := verify_browser_client(Bundle{...valid, receipt: receipt}, available) { assert false, 'ABI receipt mutation accepted' }
		}
		for name in ['baseline-sha256.json', 'generated/browser.c', 'generated/browser.o', 'generated/browser-runtime.o',
			'generated/browser-headers.json', 'generated/browser-runtime-headers.json', 'generated/browser-link-inputs.json',
			'commands/build-browser.log', 'commands/browser-exports.log', 'commands/browser-headers.log',
			'commands/browser-runtime-headers.log', 'nm-input.json'] {
			mut files := valid.files.clone()
			files.delete(name)
			if _ := verify_browser_client(Bundle{...valid, files: files}, available) { assert false, 'absent retained artifact accepted: ' + name }
		}
		mut extra_dependencies := valid.receipt.clone()
		extra_dependencies['runtime_dependencies_sha256'] = browser_test_pins({'lib/extra.so': 'f'.repeat(64)})
		if _ := verify_browser_client(Bundle{...valid, receipt: extra_dependencies}, available) { assert false, 'extra dependency accepted' }
		for name in ['generate-browser', 'compile-browser', 'compile-browser-runtime', 'browser-headers',
			'browser-runtime-headers', 'build-browser', 'browser-exports'] {
			path := valid.root + '/commands/' + name + '.json'
			before := os.read_file(path)!
			mut receipt := json2.decode[map[string]json2.Any](before)!
			mut argv := json2.decode[[]string](json2.encode(receipt['argv']!))!
			argv[1] = 'changed'
			receipt['argv'] = argv
			os.write_file(path, json2.encode(receipt))!
			if _ := verify_browser_client(valid, available) { assert false, 'build command mutation accepted: ' + name }
			os.write_file(path, before)!
		}
		for name in ['commands/browser-exports.log', 'commands/build-browser.log', 'commands/browser-headers.log',
			'commands/browser-runtime-headers.log', 'generated/browser-headers.json',
			'generated/browser-link-inputs.json', 'nm-input.json'] {
			path := valid.root + '/' + name
			before := os.read_file(path)!
			for bad in if name.ends_with('.log') { ['', before + '00000000 T vinix_android_browser_extra\n'] }
				else { ['{}', '{"/unretained/input":"' + 'a'.repeat(64) + '"}'] } {
				// Extra unrelated link trace lines are allowed; the consumed map
				// still pins every object. Export listings must remain exact.
				if name == 'commands/build-browser.log' && bad != '' { continue }
				os.write_file(path, bad)!
				if _ := verify_browser_client(valid, available) { assert false, 'retained input mutation accepted: ' + name }
			}
			os.write_file(path, before)!
		}
		link_inventory := valid.root + '/generated/browser-link-inputs.json'
		before_link := os.read_file(link_inventory)!
		linked := json2.decode[map[string]string](before_link)!
		for removed in linked.keys() {
			mut sparse := linked.clone()
			sparse.delete(removed)
			os.write_file(link_inventory, json2.encode(sparse))!
			if _ := verify_browser_client(valid, available) { assert false, 'omitted link input accepted' }
		}
		os.write_file(link_inventory, before_link)!
		link_trace := valid.root + '/commands/build-browser.log'
		before_trace := os.read_file(link_trace)!
		os.write_file(link_trace, before_trace + '/unretained/input\n')!
		if _ := verify_browser_client(valid, available) { assert false, 'unretained trace input accepted' }
		os.write_file(link_trace, before_trace)!
		abi := valid.root + '/closure/browser/Users/alex/code/vinix/build-support/android/browserclient/abi.v'
		before_abi := os.read_file(abi)!
		for bad in ['', before_abi + "\n@[export: 'vinix_android_browser_extra']", before_abi + "\n@[export: 'vinix_android_browser_open']"] {
			os.write_file(abi, bad)!
			if _ := verify_browser_client(valid, available) { assert false, 'source ABI mutation accepted' }
		}
		os.write_file(abi, before_abi)!
		output := valid.root + '/lib/libvinix-android-browser.so'
		original := os.read_bytes(output)!
		mut executable := original.clone()
		executable[16] = 2
		for bad in [executable, browser_test_elf(['libz.so.1'], ''), browser_test_elf([], '/unselected'),
			browser_test_elf(if sqlite { []string{} } else { ['libsqlite3.so.0'] }, '')] {
			os.write_file_array(output, bad)!
			if _ := verify_browser_client(valid, available) { assert false, 'ELF policy mutation accepted' }
		}
		os.write_file_array(output, original)!
		verify_browser_client(valid, available)!
	}
}
