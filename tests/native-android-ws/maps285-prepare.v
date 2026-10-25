// SPDX-License-Identifier: GPL-2.0-or-later
// Prepare an isolated 600-second Maps replay; this tool never launches QEMU.
module main

import crypto.sha256
import json2
import os
import strconv
import time

$if macos {
	#include <CommonCrypto/CommonDigest.h>
}
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const base = 'build/android-maps/'
const target = base + 'maps285'
const external = '/Users/alex/.local/state/vinix/android/maps285-2026-10-25-prelaunch'
const original_root = '/Users/alex/.local/state/vinix/android/maps283-2026-10-25'
const original_pin = '643adb9d5c778a1f388e9334aebebd7955d1efb02e29f9e332fcb4d25aebf43a'
const replica = 'prelaunch/prelaunch/replica/'
const original = replica + base + 'maps283/'
const compiler = target + '/tools/v_old'
const vroot = '/Users/alex/code/v'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const native = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
const jar = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const launcher = 'usr/bin/run-android-calculator'
const driver = base + 'maps-interact-unique258'
const driver_pin = 'abd2dfbb01fddc83ffffae481b5d1fcab35b9ebd279f3f47abae237b00134208'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	$if macos {
		mut state := C.CC_SHA256_CTX{}
		if C.CC_SHA256_Init(unsafe { &state }) != 1 { return error('CC_SHA256_Init failed') }
		for {
			n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
			if n == 0 { break }
			if C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) != 1 { return error('CC_SHA256_Update failed') }
		}
		mut result := [32]u8{}
		if C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) != 1 { return error('CC_SHA256_Final failed') }
		return result[..].hex()
	} $else {
		mut digest := sha256.new()
		defer { unsafe { digest.free() } }
		for {
			n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
			if n == 0 { break }
			if digest.write(buffer[..n])! != n { return error('SHA256 short write') }
		}
		mut result := []u8{len: 32}
		defer { unsafe { result.free() } }
		digest.checksum_into(mut result)
		return result.hex()
	}
}

fn checked(argv []string) !string {
	result := os.exec(argv)
	if result.exit_code != 0 { return error(argv.str() + ': ' + result.output) }
	return result.output
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn read_map(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)!
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn clone(from string, to string) ! {
	if os.exists(to) || os.is_link(to) { return error('fresh destination required: ' + to) }
	os.mkdir_all(os.dir(to))!
	checked([os.find_abs_path_of_executable('cp')!, '-c', '-R', '-P', from, to])!
}

fn clone_file(from string, to string) ! {
	resolved := os.real_path(from)
	if os.lstat(resolved)!.get_filetype() != .regular { return error('regular input required: ' + from) }
	clone(resolved, to)!
	if os.is_link(to) { return error('retained input must contain bytes: ' + to) }
}

fn inventory(root string, relative string, mut entries map[string]string, regular_only bool) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory {
				if !regular_only { entries[key] = 'directory' }
				inventory(root, key, mut entries, regular_only)!
			}
			.symbolic_link { if !regular_only { entries[key] = 'symlink:' + os.readlink(path)! } }
			else { return error('unexpected special file: ' + path) }
		}
	}
}

fn files(root string) !map[string]string {
	mut entries := map[string]string{}
	inventory(root, '', mut entries, true)!
	return entries
}

fn module_tree(root string) !map[string]string {
	mut tree := map[string]string{}
	inventory(root, '', mut tree, false)!
	for path in tree.keys() { tree['@mode:' + path] = (os.lstat(root + '/' + path)!.mode & 0o7777).str() }
	return tree
}

fn equal_maps(actual map[string]string, expected map[string]string) ! {
	if actual.len != expected.len { return error('inventory lengths differ') }
	for path, value in expected {
		if actual[path] or { '' } != value { return error('inventory differs: ' + path) }
	}
}

fn native_delta(before map[string]string, after map[string]string) ! {
	if before.len != 109 || after.len != 109 { return error('complete109 runtime required') }
	mut changed := []string{}
	for path, value in before {
		if path !in after { return error('runtime path removed: ' + path) }
		if after[path]! != value { changed << path }
	}
	if changed != [native] { return error('only native284 overlay permitted: ' + changed.str()) }
	if before[jar]! != '92b069b1dbb31b08960d00d4f33f84b068a3adf53af9339f2ef3c1a6478f0618'
		|| before[launcher]! != '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
		|| before[native]! != '5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca' {
		return error('original283 overlay identity differs')
	}
}

fn once(source string, before string, after string) !string {
	if source.count(before) != 1 { return error('expected exactly one source block: ' + before) }
	return source.replace(before, after)
}

fn observation(source string) !string {
	if source.count('fn observation(') != 1 || source.count('// Real companion packages') != 1 {
		return error('missing or duplicate classifier bounds')
	}
	classifier := source.all_after('fn observation(').all_before('// Real companion packages')
	if classifier.len < 1000 { return error('incomplete classifier') }
	return classifier
}

fn suite_source(source string, runtime string, boot string, efivars string) !string {
	mut result := source
	for pair in [['validate_styled283', 'validate_styled285'], ['MAPS283', 'MAPS285'],
		['build/android-maps/maps283/', 'build/android-maps/maps285/']] {
		expected := match pair[0] { 'validate_styled283' { 2 } 'MAPS283' { 2 } else { 9 } }
		if result.count(pair[0]) != expected { return error('unexpected283 source occurrences: ' + pair[0]) }
		result = result.replace(pair[0], pair[1])
	}
	result = once(result, 'startup_seconds"]!.int() == 420', 'startup_seconds"]!.int() == 600')!
	for pair in [
		['7bfb623da6bb5b1485cf8fdb921c67b30c6c1ea4284795e0ee94311098fc211b', runtime],
		['cd30c8e683dc058e86a5663073a1b5aa4499c1e17bb10c41b383deaad8bfa321', boot],
		['1be206ef44de6670d90d27060e88072452cce3930727516d62cce07963547f2d', efivars]] {
		result = once(result, pair[0], pair[1])!
	}
	if observation(result)! != observation(source)! { return error('original classifier changed') }
	return result
}

fn config_source(source map[string]json2.Any) !map[string]json2.Any {
	if source['boot_image']!.str() != base + 'maps283/vm/boot.img'
		|| source['efivars']!.str() != base + 'maps283/vm/efivars.fd'
		|| source['output']!.str() != base + 'attempt283' { return error('wrong283 configuration') }
	mut result := source.clone()
	result['boot_image'] = target + '/vm/boot.img'
	result['efivars'] = target + '/vm/efivars.fd'
	result['output'] = base + 'attempt285'
	mut apps := source['applications']!.as_array().clone()
	if apps.len != 1 || apps[0].as_map()['startup_seconds']!.int() != 420 { return error('wrong283 application window') }
	mut app := apps[0].as_map().clone()
	app['startup_seconds'] = 600
	apps[0] = app
	result['applications'] = apps
	return result
}

fn sealed_input(manifest map[string]string, relative string) !string {
	path := original_root + '/' + relative
	if hash(path)! != manifest[relative]! { return error('consumed283 input differs: ' + relative) }
	return path
}

fn shell_quote(value string) string { return "'" + value.replace("'", r"'\''") + "'" }

fn stdin_hash() !string {
	mut input := os.stdin()
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn read_exact(mut input os.File, mut buffer []u8) ! {
	mut offset := 0
	for offset < buffer.len {
		n := input.read(mut buffer[offset..])!
		if n == 0 { return error('truncated tar stream') }
		offset += n
	}
}

// Read only the authoritative runtime tar stream, without extracting historical trees.
fn stdin_tar_tree() !map[string]string {
	mut input := os.stdin()
	mut entries := map[string]string{}
	mut header := []u8{len: 512}
	mut payload := []u8{len: 1024 * 1024}
	mut saw_root := false
	for {
		read_exact(mut input, mut header)!
		if header.all(it == 0) {
			read_exact(mut input, mut header)!
			if !header.all(it == 0) { return error('invalid tar terminator') }
			return entries
		}
		mut checksum := u64(0)
		for i, byte in header { checksum += if i >= 148 && i < 156 { u64(32) } else { u64(byte) } }
		if checksum != strconv.parse_uint(header[148..156].bytestr().trim(' \x00'), 8, 64)! {
			return error('invalid tar header checksum')
		}
		prefix := header[345..500].bytestr().all_before('\x00')
		mut path := header[..100].bytestr().all_before('\x00')
		if prefix != '' { path = prefix + '/' + path }
		size := strconv.parse_uint(header[124..136].bytestr().trim(' \x00'), 8, 64)!
		kind := header[156]
		mode := strconv.parse_uint(header[100..108].bytestr().trim(' \x00'), 8, 64)!
		if path == './' {
			if saw_root || kind != `5` || size != 0 { return error('invalid or duplicate tar root') }
			saw_root = true
			continue
		}
		path = path.trim_string_left('./').trim_right('/')
		if path == '' || path.starts_with('/') || path.starts_with('@mode:') || '..' in path.split('/') || path in entries {
			return error('unsafe or duplicate tar path: ' + path)
		}
		entries['@mode:' + path] = (mode & 0o7777).str()
		if kind == `5` && size == 0 { entries[path] = 'directory'; continue }
		if kind == `2` && size == 0 { entries[path] = 'symlink:' + header[157..257].bytestr().all_before('\x00'); continue }
		if kind != `0` && kind != 0 { return error('unsupported runtime tar member: ' + path) }
		mut digest := sha256.new()
		mut remaining := size
		for remaining > 0 {
			n := int(if remaining > u64(payload.len) { u64(payload.len) } else { remaining })
			read_exact(mut input, mut payload[..n])!
			digest.write(payload[..n])!
			remaining -= u64(n)
		}
		entries[path] = digest.sum([]u8{}).hex()
		padding := int((512 - size % 512) % 512)
		if padding > 0 { read_exact(mut input, mut header[..padding])! }
	}
	return entries
}

fn archive_stage(root string) ! {
	module_path := shell_quote(root + '/module')
	image := shell_quote(root + '/vm/boot.img')
	hasher := shell_quote(os.executable()) + ' --hash-stdin'
	producer := shell_quote(os.find_abs_path_of_executable('tar')!) + ' --format=ustar -b 1 -C ' + module_path + ' -cf - .'
	stage_argv := ['/bin/zsh', '-c', 'set -o pipefail; ' + producer + ' | ' + shell_quote(os.find_abs_path_of_executable('mcopy')!) + ' -o -i ' + image + ' - ::/boot/qemu-runtime.tar']
	producer_argv := ['/bin/zsh', '-c', 'set -o pipefail; ' + producer + ' | ' + hasher]
	readback_argv := ['/bin/zsh', '-c', 'set -o pipefail; ' + shell_quote(os.find_abs_path_of_executable('mtype')!) + ' -i ' + image + ' ::/boot/qemu-runtime.tar | ' + hasher]
	mut receipt := {'stage_argv': json2.Any(stage_argv), 'producer_hash_argv': json2.Any(producer_argv),
		'readback_hash_argv': json2.Any(readback_argv), 'started_utc': json2.Any(time.utc().str())}
	write_json(root + '/archive-stage-before.json', receipt)!
	checked(stage_argv)!
	staged := checked(producer_argv)!.trim_space()
	actual := checked(readback_argv)!.trim_space()
	if staged.len != 64 || actual != staged { return error('actual FAT tar differs from staged runtime') }
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = 0
	write_json(root + '/archive-stage-receipt.json', receipt)!
	write_json(root + '/archive-stream-check.json', {'staged_tar_sha256': staged, 'actual_fat_tar_sha256': actual})!
}

fn freeze_suite_closure() !map[string]string {
	argv := [compiler, '-print-v-files', '-path', target + '/sources|@vlib|@vmodules', target + '/suite285.v']
	listing := checked(argv)!
	os.write_file(target + '/suite-v-files.txt', listing)!
	mut pins := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		pins[path] = hash(path)!
		clone_file(path, target + '/closure-inputs/' + path.trim_left('/'))!
	}
	if pins.len < 10 || os.real_path(target + '/sources/nativeapk/install.v') !in pins { return error('incomplete suite source closure') }
	write_json(target + '/suite-v-files.json', pins)!
	write_json(target + '/suite-closure-receipt.json', {'argv': json2.Any(argv), 'completed_utc': json2.Any(time.utc().str()),
		'exit_code': json2.Any(0), 'source_count': json2.Any(pins.len), 'sources_sha256': json2.Any(hash(target + '/suite-v-files.json')!)})!
	return pins
}

fn suite_assertion_probe(source string, argv []string) ! {
	directory := target + '/assertion-probe'
	os.mkdir_all(directory)!
	probe := once(source, "assert observation('no application launch', 'a')['outcome']!.str() == 'harness_failure'",
		"assert observation('no application launch', 'a')['outcome']!.str() == 'intentionally-wrong'")!
	os.write_file(directory + '/suite285-negative.v', probe)!
	mut probe_argv := argv.clone()
	probe_argv[probe_argv.len - 2] = directory + '/suite285-negative'
	probe_argv[probe_argv.len - 1] = directory + '/suite285-negative.v'
	mut receipt := {'argv': json2.Any(probe_argv), 'started_utc': json2.Any(time.utc().str()),
		'compiler_sha256': json2.Any(hash(compiler)!), 'source_sha256': json2.Any(hash(directory + '/suite285-negative.v')!)}
	write_json(directory + '/build-before.json', receipt)!
	build := os.exec(probe_argv)
	os.write_file(directory + '/build.log', build.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = build.exit_code
	if build.exit_code == 0 { receipt['binary_sha256'] = hash(directory + '/suite285-negative')! }
	write_json(directory + '/build-receipt.json', receipt)!
	if build.exit_code != 0 { return error('negative suite build failed') }
	negative := os.exec([directory + '/suite285-negative', '--self-test'])
	os.write_file(directory + '/run.log', negative.output)!
	write_json(directory + '/run-receipt.json', {'argv': json2.Any([directory + '/suite285-negative', '--self-test']),
		'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(negative.exit_code),
		'output_sha256': json2.Any(hash(directory + '/run.log')!)})!
	if negative.exit_code == 0 || !negative.output.contains('FAIL') || !negative.output.contains('intentionally-wrong') {
		return error('assertion-enabled suite negative was not rejected')
	}
}

fn prepare(native_root string, native_manifest_pin string) ! {
	started := time.utc().str()
	preparer_pin := hash(os.executable())!
	preparer_source_pin := hash(@FILE)!
	if os.exists(target) || os.exists(external) || os.exists(base + 'attempt285.json') || os.exists(base + 'attempt285') {
		return error('fresh285 destinations required')
	}
	if hash(original_root + '/sha256.json')! != original_pin { return error('wrong sealed283 reference') }
	manifest := read_map(original_root + '/sha256.json')!
	compiler_source := sealed_input(manifest, replica + 'Users/alex/code/v/v_old')!
	if hash(compiler_source)! != compiler_pin { return error('wrong retained assertion-enabled suite compiler') }
	// Only the consumed subset is checked. The full historical bundle stays sealed.
	original_suite := sealed_input(manifest, original + 'suite283.v')!
	original_config := sealed_input(manifest, replica + base + 'attempt283.json')!
	original_runtime := sealed_input(manifest, original + 'runtime-after.json')!
	before := read_map(original_runtime)!
	equal_maps(files(base + 'maps283/module')!, before)!
	if os.base(native_root) != 'compound284-2026-10-25' { return error('queue284 bundle required') }
	if native_manifest_pin.len != 64 || hash(native_root + '/prelaunch-sha256.json')! != native_manifest_pin { return error('wrong queue284 prelaunch pin') }
	native_manifest := read_map(native_root + '/prelaunch-sha256.json')!
	native_library := native_root + '/prelaunch/native/libvinix-android-native.so'
	native_pin := hash(native_library)!
	if native_pin != native_manifest['prelaunch/native/libvinix-android-native.so']! { return error('queue284 native differs') }
	native_receipt := object(native_root + '/prelaunch/build-native-receipt.json')!
	if native_receipt['exit_code']!.int() != 0 || native_receipt['completed_utc']!.str() == ''
		|| native_receipt['output_sha256']!.str() != native_pin { return error('queue284 native build incomplete') }
	for label in ['generate-native', 'build-native'] {
		for suffix in ['-before.json', '-receipt.json', '.log'] {
			name := label + suffix
			if hash(native_root + '/prelaunch/' + name)! != native_manifest['prelaunch/' + name]! { return error('queue284 receipt differs: ' + name) }
		}
		receipt := object(native_root + '/prelaunch/' + label + '-receipt.json')!
		if receipt['exit_code']!.int() != 0 || receipt['completed_utc']!.str() == '' { return error('queue284 incomplete build: ' + label) }
	}
	os.setenv('COPYFILE_DISABLE', '1', true)
	os.setenv('VROOT', vroot, true)
	os.mkdir_all(target + '/vm')!
	clone_file(compiler_source, compiler)!
	mut staging_tools := map[string]string{}
	for name in ['cp', 'tar', 'mcopy', 'mtype', 'zsh', 'unzip'] {
		path := os.find_abs_path_of_executable(name)!
		staging_tools[path] = hash(path)!
	}
	write_json(target + '/staging-tools.json', staging_tools)!
	clone(base + 'maps283/module', target + '/module')!
	equal_maps(files(target + '/module')!, before)!
	write_json(target + '/runtime-before.json', before)!
	os.cp(native_library, target + '/module/' + native)!
	after := files(target + '/module')!
	native_delta(before, after)!
	if after[native]! != native_pin { return error('copied native differs from queue284 output') }
	write_json(target + '/runtime-after.json', after)!
	mut media := map[string]string{}
	for name in ['boot.img', 'efivars.fd'] {
		path := sealed_input(manifest, original + 'vm/' + name)!
		clone(path, target + '/vm/' + name)!
		media[name] = hash(target + '/vm/' + name)!
		if media[name]! != manifest[original + 'vm/' + name]! { return error('initial media clone differs') }
	}
	write_json(target + '/initial-media-clones.json', media)!
	// Bind every directory and symlink target as well as regular file bytes to sealed283.
	tree_argv := ['/bin/zsh', '-c', 'set -o pipefail; ' + shell_quote(os.find_abs_path_of_executable('mtype')!) + ' -i ' + shell_quote(target + '/vm/boot.img') + ' ::/boot/qemu-runtime.tar | ' + shell_quote(os.executable()) + ' --tar-tree-stdin']
	write_json(target + '/original-module-tree-before.json', {'argv': json2.Any(tree_argv), 'started_utc': json2.Any(time.utc().str()), 'sealed283_boot_sha256': json2.Any(media['boot.img']!)})!
	old_tree := json2.decode[map[string]string](checked(tree_argv)!)!
	mut expected_tree := old_tree.clone()
	if expected_tree[native]! != before[native]! { return error('sealed283 archive native differs') }
	expected_tree[native] = native_pin
	actual_tree := module_tree(target + '/module')!
	equal_maps(actual_tree, expected_tree)!
	write_json(target + '/module-before-typed.json', old_tree)!
	write_json(target + '/module-after-typed.json', actual_tree)!
	write_json(target + '/original-module-tree-receipt.json', {'argv': json2.Any(tree_argv), 'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(0), 'original_typed_sha256': json2.Any(hash(target + '/module-before-typed.json')!), 'overlaid_typed_sha256': json2.Any(hash(target + '/module-after-typed.json')!), 'changed_paths': json2.Any([native])})!
	archive_stage(target)!
	boot_pin := hash(target + '/vm/boot.img')!
	efivars_pin := hash(target + '/vm/efivars.fd')!
	if efivars_pin != media['efivars.fd']! { return error('efivars changed while staging') }
	source := os.read_file(original_suite)!
	os.write_file(target + '/suite285.v', suite_source(source, hash(target + '/runtime-after.json')!, boot_pin, efivars_pin)!)!
	config := config_source(object(original_config)!)!
	write_json(base + 'attempt285.json', config)!
	clone_file(sealed_input(manifest, original + 'sources/nativeapk/install.v')!, target + '/sources/nativeapk/install.v')!
	closure := freeze_suite_closure()!
	cc := os.find_abs_path_of_executable('cc')!
	argv := [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-path', target + '/sources|@vlib|@vmodules', '-o', target + '/suite285', target + '/suite285.v']
	mut build := {'argv': json2.Any(argv), 'VROOT': json2.Any(vroot), 'started_utc': json2.Any(time.utc().str()), 'compiler_sha256': json2.Any(hash(compiler)!), 'cc_path': json2.Any(cc), 'cc_sha256': json2.Any(hash(cc)!), 'source_sha256': json2.Any(hash(target + '/suite285.v')!), 'nativeapk_sha256': json2.Any(hash(target + '/sources/nativeapk/install.v')!)}
	write_json(target + '/build-before.json', build)!
	result := os.exec(argv)
	os.write_file(target + '/build.log', result.output)!
	build['completed_utc'] = time.utc().str()
	build['exit_code'] = result.exit_code
	if result.exit_code == 0 { build['binary_sha256'] = hash(target + '/suite285')! }
	write_json(target + '/build-receipt.json', build)!
	if result.exit_code != 0 { return error('suite285 compilation failed') }
	os.write_file(target + '/suite-self-test.log', checked([target + '/suite285', '--self-test'])!)!
	suite_assertion_probe(os.read_file(target + '/suite285.v')!, argv)!
	for path, expected in closure {
		if hash(path)! != expected || hash(target + '/closure-inputs/' + path.trim_left('/'))! != expected {
			return error('suite compile source changed: ' + path)
		}
	}
	mut pins := map[string]string{}
	for path, expected in staging_tools {
		if hash(path)! != expected { return error('staging tool changed: ' + path) }
		pins[path] = expected
	}
	if hash(os.executable())! != preparer_pin || hash(@FILE)! != preparer_source_pin {
		return error('preparation source or binary changed during staging')
	}
	for path in [target + '/vm/boot.img', target + '/vm/efivars.fd', target + '/suite285.v', target + '/suite285', target + '/runtime-before.json', target + '/runtime-after.json', base + 'attempt285.json', compiler, cc, os.executable(), @FILE, driver, config['aapt2']!.str(), config['apksigner']!.str(), config['java']!.str(), config['firmware']!.str(), config['qemu']!.str(), config['input_tool']!.str()] { pins[path] = hash(path)! }
	for name in ['GoogleMaps.apk', 'GooglePlayServices.apk', 'GooglePlayStore.apk', 'run-android-identity256', 'attempt244/companion-packages.json'] {
		path := base + name
		if hash(path)! != manifest[replica + path]! { return error('original Maps APK/identity/companions differ: ' + name) }
		pins[path] = hash(path)!
	}
	if pins[driver]! != driver_pin { return error('wrong bounded capture driver') }
	for name, path in {'qemu': config['qemu']!.str(), 'firmware': config['firmware']!.str(), 'aapt2': config['aapt2']!.str(), 'apksigner': config['apksigner']!.str(), 'java': config['java']!.str(), 'input_tool': config['input_tool']!.str()} {
		if pins[path]! != manifest[replica + path.trim_left('/')]! { return error('original launch tool differs: ' + name) }
	}
	write_json(target + '/prelaunch-sha256.json', pins)!
	write_json(target + '/references.json', {'maps283_root': original_root, 'maps283_manifest_sha256': original_pin, 'queue284_root': native_root, 'queue284_prelaunch_sha256': native_manifest_pin})!
	write_json(target + '/preparation-receipt.json', {'argv': json2.Any(os.args), 'started_utc': json2.Any(started), 'completed_before_launch_utc': json2.Any(time.utc().str()), 'source_revision': json2.Any(checked(['git', 'rev-parse', 'HEAD'])!.trim_space()), 'observation_seconds': json2.Any(600), 'classifier_sha256': json2.Any(sha256.sum(observation(source)!.bytes()).hex()), 'native_sha256': json2.Any(native_pin), 'runtime_changed_paths': json2.Any([native]), 'prelaunch_sha256': json2.Any(hash(target + '/prelaunch-sha256.json')!)})!
	// Retain only newly consumed inputs, plus references to full sealed originals.
	clone(target, external + '/prelaunch/maps285')!
	clone_file(base + 'attempt285.json', external + '/prelaunch/attempt285.json')!
	for path, _ in pins {
		if path.starts_with(target + '/') || path == base + 'attempt285.json' { continue }
		clone_file(path, external + '/prelaunch/inputs/' + path.trim_left('/'))!
	}
	for name in ['sha256.json'] { clone_file(original_root + '/' + name, external + '/prelaunch/reference283/' + name)! }
	for path in [original_suite, original_config, original_runtime] { clone_file(path, external + '/prelaunch/consumed283/' + os.base(path))! }
	clone_file(native_root + '/prelaunch-sha256.json', external + '/prelaunch/reference284/prelaunch-sha256.json')!
	for label in ['generate-native', 'build-native'] {
		for suffix in ['-before.json', '-receipt.json', '.log'] { clone_file(native_root + '/prelaunch/' + label + suffix, external + '/prelaunch/reference284/' + label + suffix)! }
	}
	mut retained := map[string]string{}
	inventory(external + '/prelaunch', '', mut retained, false)!
	for path, value in pins {
		key := if path.starts_with(target + '/') { 'maps285/' + path.all_after(target + '/') }
			else if path == base + 'attempt285.json' { 'attempt285.json' }
			else { 'inputs/' + path.trim_left('/') }
		if retained[key]! != value { return error('retained launch input differs: ' + path) }
	}
	mut retained_runtime := map[string]string{}
	for path, value in retained {
		if path.starts_with('maps285/module/') && value.len == 64 {
			retained_runtime[path.all_after('maps285/module/')] = value
		}
	}
	equal_maps(retained_runtime, after)!
	write_json(external + '/prelaunch-sha256.json', retained)!
	println('MAPS285 PREPARED no VM launch; native-only delta;600seconds; manifest=' + hash(external + '/prelaunch-sha256.json')!)
}

fn self_test() ! {
	if hash(original_root + '/sha256.json')! != original_pin { return error('wrong original283 pin') }
	manifest := read_map(original_root + '/sha256.json')!
	source := os.read_file(sealed_input(manifest, original + 'suite283.v')!)!
	generated := suite_source(source, 'runtime', 'boot', 'efivars')!
	assert observation(source)! == observation(generated)!
	assert generated.contains('startup_seconds"]!.int() == 600')
	mut rejected := false
	suite_source(source + '\nfn validate_styled283() {}', 'r', 'b', 'e') or { rejected = true }
	assert rejected
	mut before := map[string]string{}
	for i in 0 .. 106 { before['fixture-' + i.str()] = 'same' }
	before[native] = '5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca'
	before[jar] = '92b069b1dbb31b08960d00d4f33f84b068a3adf53af9339f2ef3c1a6478f0618'
	before[launcher] = '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
	mut after := before.clone()
	after[native] = 'new-native284'
	native_delta(before, after)!
	after[jar] = 'wrong'
	rejected = false
	native_delta(before, after) or { rejected = true }
	assert rejected
	after = before.clone()
	after[native] = 'new'
	after.delete('fixture-0')
	after['unexpected'] = 'same'
	rejected = false
	native_delta(before, after) or { rejected = true }
	assert rejected
	config := object(sealed_input(manifest, replica + base + 'attempt283.json')!)!
	updated := config_source(config)!
	assert updated['applications']!.as_array()[0].as_map()['startup_seconds']!.int() == 600
	assert updated['native_dir']! == config['native_dir']! && updated['base_module']! == config['base_module']!
	println('MAPS285 HELPER SELF-TEST PASS bounded source edits; unchanged classifier; native-only109 delta; unexpected paths rejected')
}

fn main() {
	$if prod { eprintln('Maps285 preparation requires assertions'); exit(2) }
	if os.args.len == 2 && os.args[1] == '--hash-stdin' { println(stdin_hash() or { eprintln(err); exit(1) }); return }
	if os.args.len == 2 && os.args[1] == '--tar-tree-stdin' { println(json2.encode(stdin_tar_tree() or { eprintln(err); exit(1) })); return }
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len == 4 && os.args[1] == 'prepare' { prepare(os.args[2], os.args[3]) or { eprintln(err); exit(1) }; return }
	eprintln('usage: maps285-prepare --self-test | prepare QUEUE284_BUNDLE PRELAUNCH_SHA256')
	exit(2)
}
