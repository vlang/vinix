// SPDX-License-Identifier: GPL-2.0-or-later
// Independently compare a pinned replay with qualified Maps350 before launch.
module main
import crypto.sha256
import json2
import os
import time
#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32
const state = '/Users/alex/.local/state/vinix/android/'
const old_root = state + 'maps350-2026-10-25'
const old_pin = 'dc30058a943aea4babe5451df20eb0a967262a09caf7df8aed0c88917e987a2c'
const compiler = '/Users/alex/code/vinix/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const native = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
const jar = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'

struct Review {
	number string
	prelaunch string
	launch string
	native_pin string
	framework_pin string
	receipt string
}

fn canonical(pin string) bool {
	return pin.len == 64 && pin.bytes().all(it in '0123456789abcdef'.bytes())
}
fn digest(mut input os.File) !string {
	mut context := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(unsafe { &context }) == 1
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		assert C.CC_SHA256_Update(unsafe { &context }, buffer.data, u32(n)) == 1
	}
	mut result := [32]u8{}
	assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &context }) == 1
	return result[..].hex()
}
fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	return digest(mut file)!
}
fn inventory(root string, relative string, mut entries map[string]string, typed bool) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory { if typed { entries[key] = 'directory' }; inventory(root, key, mut entries, typed)! }
			.symbolic_link { if typed { entries[key] = 'symlink:' + os.readlink(path)! } }
			else { return error('unexpected entry: ' + path) }
		}
		if typed { entries['@mode:' + key] = (os.lstat(path)!.mode & 0o7777).str() }
	}
}
fn tree(root string, typed bool) !map[string]string {
	mut entries := map[string]string{}
	inventory(root, '', mut entries, typed)!
	return entries
}
fn read_map(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }
fn object(path string) !map[string]json2.Any { return json2.decode[map[string]json2.Any](os.read_file(path)!)! }
fn equal(actual map[string]string, expected map[string]string) {
	assert actual.len == expected.len
	for key, pin in expected { assert actual[key] or { '' } == pin, 'entry differs: ' + key }
}
fn quote(value string) string { return "'" + value.replace("'", r"'\''") + "'" }
fn checked(argv []string) !string {
	r := os.exec(argv)
	if r.exit_code != 0 { return error(argv.str() + ': ' + r.output) }
	return r.output
}
fn stream_hash(command string) !string {
	return checked(['/bin/zsh', '-c', 'set -o pipefail; ' + command + ' | ' + quote(os.executable()) + ' --hash-stdin'])!.trim_space()
}
fn boot_hash(root string, name string) !string {
	return stream_hash(quote('/opt/homebrew/bin/mtype') + ' -i ' + quote(root + '/vm/boot.img') + ' ' + quote('::/boot/' + name))!
}
fn classifier(source string) string {
	assert source.count('fn observation(') == 1 && source.count('// Real companion packages') == 1
	return source.all_after('fn observation(').all_before('// Real companion packages')
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn build_inventory(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory { build_inventory(root, key, mut entries)! }
			else { return error('nonregular build entry: ' + path) }
		}
	}
}

fn build(destination string) ! {
	assert os.dir(destination) == state.trim_right('/') && os.abs_path(destination) == destination
	assert !os.exists(destination) && !os.is_link(destination)
	assert hash(compiler)! == compiler_pin
	os.mkdir(destination)!
	os.cp(@FILE, destination + '/source.v')!
	os.cp(os.executable(), destination + '/bootstrap')!
	os.cp(compiler, destination + '/v_old276')!
	os.mkdir(destination + '/generated-c')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('VTMP', destination + '/generated-c', true)
	listing_argv := [compiler, '-print-v-files', @FILE]
	listing_started := time.utc().str()
	listing := os.exec(listing_argv)
	os.write_file(destination + '/closure-v-files.txt', listing.output)!
	write_json(destination + '/closure-receipt.json', {
		'argv': json2.Any(listing_argv), 'started_utc': json2.Any(listing_started),
		'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(listing.exit_code),
		'compiler_sha256': json2.Any(compiler_pin),
	})!
	assert listing.exit_code == 0, listing.output
	mut before := map[string]string{}
	for path in listing.output.split_into_lines().filter(it.ends_with('.v')) {
		before[path] = hash(path)!
		copy_path := destination + '/closure/' + os.abs_path(path).trim_left('/')
		os.mkdir_all(os.dir(copy_path))!
		os.cp(path, copy_path)!
	}
	assert before.len >= 10
	write_json(destination + '/closure-before.json', before)!
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', cc, '-cflags', '-O2', '-o', destination + '/program', @FILE]
	mut record := {
		'argv': json2.Any(argv), 'cwd': json2.Any(os.getwd()),
		'started_utc': json2.Any(time.utc().str()), 'VROOT': json2.Any(os.getenv('VROOT')),
		'compiler_sha256': json2.Any(compiler_pin), 'cc_path': json2.Any(cc),
		'cc_sha256': json2.Any(cc_pin), 'source_sha256': json2.Any(hash(@FILE)!),
		'bootstrap_sha256': json2.Any(hash(os.executable())!),
		'closure_before_sha256': json2.Any(hash(destination + '/closure-before.json')!),
	}
	write_json(destination + '/build-before.json', record)!
	result := os.exec(argv)
	os.write_file(destination + '/build.log', result.output)!
	record['completed_utc'] = time.utc().str()
	record['exit_code'] = result.exit_code
	mut after := map[string]string{}
	for path, pin in before {
		after[path] = hash(path)!
		assert after[path] == pin && hash(destination + '/closure/' + os.abs_path(path).trim_left('/'))! == pin
	}
	write_json(destination + '/closure-after.json', after)!
	record['closure_after_sha256'] = hash(destination + '/closure-after.json')!
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin
	assert hash(destination + '/source.v')! == hash(@FILE)!
	if result.exit_code == 0 { record['binary_sha256'] = hash(destination + '/program')! }
	write_json(destination + '/build-receipt.json', record)!
	assert result.exit_code == 0, result.output
	mut files := map[string]string{}
	build_inventory(destination, '', mut files)!
	write_json(destination + '/sha256.json', files)!
	println('MAPS-PRELAUNCH-REVIEW-BUILD seal=' + hash(destination + '/sha256.json')!)
}
fn check(review Review) ! {
	assert review.number.int().str() == review.number && review.number.int() > 350
	for pin in [review.prelaunch, review.launch, review.native_pin, review.framework_pin] {
		assert canonical(pin), 'canonical SHA-256 required'
	}
	new_root := state + 'maps' + review.number + '-2026-10-25'
	new_pin := review.prelaunch
	launch_pin := review.launch
	receipt := review.receipt
	assert os.dir(receipt) == state.trim_right('/') && !os.exists(receipt) && !os.is_link(receipt)
	started := time.utc().str()
	for root, pin in {old_root: old_pin, new_root: new_pin} {
		assert os.real_path(root) == root && !os.is_link(root)
		assert hash(root + '/prelaunch-sha256.json')! == pin
		equal(tree(root + '/prelaunch', true)!, read_map(root + '/prelaunch-sha256.json')!)
		assert hash(root + '/prelaunch-sha256.json')! == pin
	}
	println('PEER typed old/new prelaunch inventories PASS')
	old_tree := old_root + '/prelaunch/maps350'
	new_tree := new_root + '/prelaunch/maps' + review.number
	before := read_map(old_tree + '/runtime-after.json')!
	after := read_map(new_tree + '/runtime-after.json')!
	assert before.len == 109 && after.len == 109
	equal(tree(old_tree + '/module', false)!, before)
	equal(tree(new_tree + '/module', false)!, after)
	equal(read_map(new_tree + '/runtime-before.json')!, before)
	mut changed := []string{}
	for key, pin in before { if after[key] or { '' } != pin { changed << key } }
	changed.sort()
	mut expected_changed := [native, jar]
	expected_changed.sort()
	assert changed == expected_changed
	assert before[native]! == '2231ee3def626a72119cd80d646966ec5ba2fa6cd7dd74a790fe9bcb9db5869b'
	assert after[native]! == review.native_pin
	assert before[jar]! == '95aabc17c85a5cda0d643dfa5ef9e618955d422d960ffb3bbc2db74c86a9c37d'
	assert after[jar]! == review.framework_pin
	mut typed := tree(old_tree + '/module', true)!
	typed[native] = after[native]!
	typed[jar] = after[jar]!
	equal(tree(new_tree + '/module', true)!, typed)
	equal(read_map(new_tree + '/module-after-typed.json')!, typed)
	assert after['usr/bin/run-android-calculator']! == '52e305950821e56d85bb9c4d6ba51a3c5f74ccf2b15b158d1fd47279cb70ef56'
	assert after['usr/bin/run-android-identity']! == before['usr/bin/run-android-identity']!
	assert after['opt/android-test/application.apk']! == '6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2'
	assert hash(new_tree + '/launch-pins.json')! == launch_pin
	old_launch := read_map(old_tree + '/launch-pins.json')!
	new_launch := read_map(new_tree + '/launch-pins.json')!
	for apk in ['GoogleMaps.apk', 'GooglePlayServices.apk', 'GooglePlayStore.apk'] {
		key := 'build/android-maps/' + apk
		assert new_launch[key]! == old_launch[key]!, 'external APK input differs: ' + key
	}
	println('PEER exact 109 runtime entries; sole SO+JAR delta; launcher/APK/identity and typed modes/links PASS')
	old_config := object(old_root + '/prelaunch/inputs/Users/alex/code/vinix/build/android-maps/attempt350.json')!
	new_config := object(new_root + '/prelaunch/inputs/Users/alex/code/vinix/build/android-maps/attempt' + review.number + '.json')!
	assert old_config.len == new_config.len
	for key, value in old_config {
		if key in ['boot_image', 'efivars', 'output'] {
			assert new_config[key]!.str() == value.str().replace('350', review.number)
		} else { assert json2.encode(new_config[key]!) == json2.encode(value), 'configuration differs: ' + key }
	}
	assert new_config['applications']!.as_array()[0].as_map()['startup_seconds']!.int() == 600
	old_suite := os.read_file(old_tree + '/suite350.v')!
	new_suite := os.read_file(new_tree + '/suite' + review.number + '.v')!
	assert classifier(old_suite) == classifier(new_suite)
	classifier_pin := sha256.sum(classifier(old_suite).bytes()).hex()
	assert classifier_pin == read_map(new_root + '/references.json')!['classifier_sha256']!
	equal(tree(old_tree + '/sources', true)!, tree(new_tree + '/sources', true)!)
	println('PEER exact classifier, 600-second app configuration and source overrides PASS')
	mut media := map[string]string{}
	for name in ['vinix', 'initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar', 'maps350-diagnostics.tar'] {
		old_hash := boot_hash(old_tree, name)!
		new_hash := boot_hash(new_tree, name)!
		assert old_hash == new_hash, 'base boot member differs: ' + name
		media[name] = new_hash
	}
	equal(media, read_map(new_root + '/base-media-unchanged.json')!)
	old_conf := checked(['/opt/homebrew/bin/mtype', '-i', old_tree + '/vm/boot.img', '::/boot/limine.conf'])!
	new_conf := checked(['/opt/homebrew/bin/mtype', '-i', new_tree + '/vm/boot.img', '::/boot/limine.conf'])!
	assert new_conf == old_conf + '    module_path: boot():/boot/maps' + review.number + '-diagnostics.tar\n'
	assert old_conf == os.read_file(new_tree + '/limine-before.conf')!
	assert new_conf == os.read_file(new_tree + '/limine-after.conf')!
	assert old_conf.count('module_path:') == 4 && new_conf.count('module_path:') == 5
	overlay := new_tree + '/maps' + review.number + '-diagnostics.tar'
	assert checked(['/usr/bin/tar', '-tf', overlay])! == native + '\n' + jar + '\n'
	for path in [native, jar] {
		assert stream_hash(quote('/usr/bin/tar') + ' -xOf ' + quote(overlay) + ' ' + quote(path))! == after[path]!
	}
	assert boot_hash(new_tree, 'maps' + review.number + '-diagnostics.tar')! == hash(overlay)!
	println('PEER all five streamed base boot members and final two-member overlay PASS')
	assert hash(old_root + '/prelaunch-sha256.json')! == old_pin
	assert hash(new_root + '/prelaunch-sha256.json')! == new_pin
	os.write_file(receipt, json2.encode({
		'exit_code': json2.Any(0)
		'old_root': json2.Any(old_root)
		'new_root': json2.Any(new_root)
		'old_prelaunch_manifest_sha256': json2.Any(old_pin)
		'new_prelaunch_manifest_sha256': json2.Any(new_pin)
		'launch_pins_sha256': json2.Any(launch_pin)
		'exact_typed_prelaunch_inventories': json2.Any(true)
		'runtime_regular_files': json2.Any(109)
		'changed_runtime_paths': json2.Any(changed)
		'unchanged_runtime_files': json2.Any(107)
		'typed_runtime_modes_and_links_unchanged': json2.Any(true)
		'classifier_sha256': json2.Any(classifier_pin)
		'unchanged_observation_seconds': json2.Any(600)
		'unchanged_launcher_apk_identity': json2.Any(true)
		'external_maps_and_companion_apk_pins_unchanged': json2.Any(true)
		'base_boot_members_sha256': json2.decode[json2.Any](json2.encode(media))!
		'final_overlay_exact_native_and_framework': json2.Any(true)
		'checker_sha256': json2.Any(hash(os.executable())!)
		'checker_source_sha256': json2.Any(hash(@FILE)!)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
	}, prettify: true) + '\n')!
	println('MAPS' + review.number + ' PRELAUNCH PEER REVIEW PASS ' + receipt)
}
fn main() {
	$if prod { panic('assertions required') }
	if os.args.len == 2 && os.args[1] == '--hash-stdin' {
		mut input := os.stdin()
		println(digest(mut input)!)
		return
	}
	if os.args.len == 3 && os.args[1] == 'build' {
		build(os.args[2])!
		return
	}
	assert os.args.len == 7, 'usage: maps-prelaunch-review NUMBER PRELAUNCH_SHA LAUNCH_SHA NATIVE_SHA FRAMEWORK_SHA RECEIPT | build FRESH_EXTERNAL_ROOT | --hash-stdin'
	check(Review{number: os.args[1], prelaunch: os.args[2], launch: os.args[3],
		native_pin: os.args[4], framework_pin: os.args[5], receipt: os.args[6]}) or { eprintln(err); exit(1) }
}
