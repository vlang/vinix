// SPDX-License-Identifier: GPL-2.0-or-later
// Independently compare Maps368's three pinned overlays with qualified Maps350.
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
const loader = 'opt/vinix-android-aarch64/usr/lib/art/native-ws/libdl_bio.so.0'
const framework367_manifest = '933baf6da303aebaf262e280e41769c89b61c2f050b481dd4075900a533ad23b'
const framework367_pin = 'fece4cb639fb8745557032f872d13d45767768656ae879f065324696bbf99694'
const generator_reference = '/Users/alex/code/vinix/tests/native-android-ws/maps368-generate.v'
const generator_source_pin = '324ff8ef4cfd10d777c5c79df32a6b1b374ef9f18cc2bc3b2d92ad11d13b209a'
const generator_commit = '93a869ae09c41147e46cda4f1d64ddb8b5089091'

struct Review {
	number string
	prelaunch string
	launch string
	native_pin string
	framework_pin string
	loader_pin string
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

fn qualify_build(root string, manifest_pin string, payload string, payload_pin string) !int {
	assert canonical(manifest_pin) && canonical(payload_pin)
	assert hash(root + '/sha256.json')! == manifest_pin
	expected := read_map(root + '/sha256.json')!
	assert expected.len > 0 && 'sha256.json' !in expected && expected[payload] == payload_pin
	mut actual := map[string]string{}
	build_inventory(root, '', mut actual)!
	actual.delete('sha256.json')
	equal(actual, expected)
	assert hash(root + '/' + payload)! == payload_pin
	assert hash(root + '/sha256.json')! == manifest_pin
	return actual.len
}

// BEGIN SHARED FRAMEWORK359 CONTRACT
fn qualify_framework359(root string, manifest_pin string, jar_pin string) !int {
	count := qualify_build(root, manifest_pin, 'framework/api-impl.jar', jar_pin)!
	qualify_build(root + '/baseline353', '22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f', 'framework/api-impl.jar', '1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83')!
	delta := object(root + '/framework/dex-delta.json')!
	old := delta['old_classes']!.as_map()
	new := delta['new_classes']!.as_map()
	changed := 'android/content/pm/PackageManager.smali'
	if old.len != 2073 || new.len != 2073
		|| delta['changed_existing_classes']!.as_array().map(it.str()) != [changed]
		|| delta['added_classes']!.as_array().len != 0 || delta['removed_classes']!.as_array().len != 0
		|| delta['old_jar_sha256']!.str() != '1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83'
		|| delta['new_jar_sha256']!.str() != jar_pin || delta['jar_only_changed_member']!.str() != 'classes.dex'
		|| delta['jar_member_count']!.int() < 1 || changed !in old || changed !in new {
		return error('exact permission359 framework delta required')
	}
	for name, pin in old {
		if name !in new || (name == changed && pin.str() == new[name]!.str())
			|| (name != changed && pin.str() != new[name]!.str()) {
			return error('permission359 DEX class delta differs: ' + name)
		}
	}
	smali := object(root + '/framework/smali-delta.json')!
	before := smali['before']!.as_map()
	after := smali['after']!.as_map()
	if before.len != 2073 || after.len != 2073 || changed !in before || changed !in after
		|| smali['changed']!.as_array().map(it.str()) != [changed] || !smali['duplicate_guard_unchanged']!.bool() {
		return error('exact permission359 source and duplicate guard required')
	}
	for name, pin in before {
		if name !in after || (name == changed && pin.str() == after[name]!.str())
			|| (name != changed && pin.str() != after[name]!.str()) {
			return error('permission359 source class delta differs: ' + name)
		}
	}
	validation := read_map(root + '/validation.json')!
	if validation['baseline_manifest_sha256']! != '22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f'
		|| validation['old_framework_sha256']! != '1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83'
		|| validation['new_framework_sha256']! != jar_pin || validation['changed_class']! != changed
		|| validation['class_count']! != '2073' {
		return error('permission359 validation differs')
	}
	return count
}
// END SHARED FRAMEWORK359 CONTRACT

// BEGIN SHARED FRAMEWORK361 CONTRACT
fn class_delta361(old map[string]json2.Any, new map[string]json2.Any) ! {
	changed := 'android/atl/ATLLoadedApp.smali'
	added := 'android/atl/VinixServiceStop.smali'
	if old.len != 2073 || new.len != 2074 || changed !in old || changed !in new
		|| added in old || added !in new {
		return error('exact service361 class counts and identities required')
	}
	for name, pin in old {
		if name !in new || (name == changed && pin.str() == new[name]!.str())
			|| (name != changed && pin.str() != new[name]!.str()) {
			return error('service361 class delta differs: ' + name)
		}
	}
}

fn qualify_framework361(root string, manifest_pin string, jar_pin string) !int {
	count := qualify_build(root, manifest_pin, 'framework/api-impl.jar', jar_pin)!
	qualify_framework359(root + '/baseline359', '7a2ae7763e71f702ccc1a50b3b63cf444a0e37d8b6a800e77c80866d3ba9dccc', '88fdf06964bfbd3815d824ab5ff5517887e58de3eb3eb47986d99806fbe6c2fc')!
	changed := 'android/atl/ATLLoadedApp.smali'
	added := 'android/atl/VinixServiceStop.smali'
	delta := object(root + '/framework/dex-delta.json')!
	class_delta361(delta['old_classes']!.as_map(), delta['new_classes']!.as_map())!
	if delta['changed_existing_classes']!.as_array().map(it.str()) != [changed]
		|| delta['added_classes']!.as_array().map(it.str()) != [added]
		|| delta['removed_classes']!.as_array().len != 0
		|| delta['old_jar_sha256']!.str() != '88fdf06964bfbd3815d824ab5ff5517887e58de3eb3eb47986d99806fbe6c2fc'
		|| delta['new_jar_sha256']!.str() != jar_pin || delta['jar_only_changed_member']!.str() != 'classes.dex'
		|| delta['jar_member_count']!.int() < 1 {
		return error('exact service361 DEX and JAR delta required')
	}
	smali := object(root + '/framework/smali-delta.json')!
	class_delta361(smali['before']!.as_map(), smali['after']!.as_map())!
	if smali['changed']!.as_array().map(it.str()) != [changed]
		|| smali['added']!.as_array().map(it.str()) != [added]
		|| smali['removed']!.as_array().len != 0 || !smali['duplicate_guard_unchanged']!.bool()
		|| !smali['malformed_guard_unchanged']!.bool() {
		return error('exact service361 source and guards required')
	}
	guard := object(root + '/framework/malformed-guard.json')!
	guard_before := guard['before']!.as_map()
	guard_after := guard['after']!.as_map()
	if guard_before.len != 2073 || guard_after != guard_before {
		return error('service361 malformed-input guard differs')
	}
	validation := read_map(root + '/validation.json')!
	if validation['baseline_manifest_sha256']! != '7a2ae7763e71f702ccc1a50b3b63cf444a0e37d8b6a800e77c80866d3ba9dccc'
		|| validation['old_framework_sha256']! != '88fdf06964bfbd3815d824ab5ff5517887e58de3eb3eb47986d99806fbe6c2fc'
		|| validation['new_framework_sha256']! != jar_pin || validation['changed_class']! != changed
		|| validation['added_class']! != added || validation['old_class_count']! != '2073'
		|| validation['new_class_count']! != '2074' {
		return error('service361 validation differs')
	}
	return count
}
// END SHARED FRAMEWORK361 CONTRACT

// BEGIN SHARED FRAMEWORK365 CONTRACT
fn framework365_changed() []string {
	return ['android/os/BaseBundle.smali', 'android/os/Bundle.smali',
		'android/os/Parcel.smali', 'android/os/Parcelable$ClassLoaderCreator.smali']
}

fn class_delta365(old map[string]json2.Any, new map[string]json2.Any) ! {
	changed := framework365_changed()
	added := 'android/os/VinixBundleCreator.smali'
	if old.len != 2074 || new.len != 2075 || added in old || added !in new {
		return error('exact bundle365 class counts and added creator required')
	}
	for name in changed {
		if name !in old || name !in new || old[name]!.str() == new[name]!.str() {
			return error('bundle365 required class change differs: ' + name)
		}
	}
	for name, pin in old {
		if name !in new || (name !in changed && pin.str() != new[name]!.str()) {
			return error('bundle365 unexpected class delta: ' + name)
		}
	}
}

fn qualify_framework365(root string, manifest_pin string, jar_pin string) !int {
	count := qualify_build(root, manifest_pin, 'framework/api-impl.jar', jar_pin)!
	qualify_framework361(root + '/baseline361', '9649ab0f596dcd44ce5979a2e129548ca550d2ad54b4d2995fd3c714e125f8e9', '077bb9f1784e2945accebc9043e0d8d54617bb0e01725e97824807d8cc57b10a')!
	changed := framework365_changed()
	added := ['android/os/VinixBundleCreator.smali']
	delta := object(root + '/framework/dex-delta.json')!
	class_delta365(delta['old_classes']!.as_map(), delta['new_classes']!.as_map())!
	if delta['changed_existing_classes']!.as_array().map(it.str()) != changed
		|| delta['added_classes']!.as_array().map(it.str()) != added
		|| delta['removed_classes']!.as_array().len != 0
		|| delta['old_jar_sha256']!.str() != '077bb9f1784e2945accebc9043e0d8d54617bb0e01725e97824807d8cc57b10a'
		|| delta['new_jar_sha256']!.str() != jar_pin || delta['jar_only_changed_member']!.str() != 'classes.dex'
		|| delta['jar_member_count']!.int() < 1 {
		return error('exact bundle365 DEX and JAR delta required')
	}
	smali := object(root + '/framework/smali-delta.json')!
	class_delta365(smali['before']!.as_map(), smali['after']!.as_map())!
	if smali['changed']!.as_array().map(it.str()) != changed
		|| smali['added']!.as_array().map(it.str()) != added
		|| smali['removed']!.as_array().len != 0 || !smali['duplicate_guard_unchanged']!.bool()
		|| !smali['malformed_guard_unchanged']!.bool() {
		return error('exact bundle365 source and guards required')
	}
	guard := object(root + '/framework/malformed-guard.json')!
	guard_before := guard['before']!.as_map()
	if guard_before.len != 2074 || guard['after']!.as_map() != guard_before {
		return error('bundle365 malformed-input guard differs')
	}
	validation := object(root + '/validation.json')!
	if validation['baseline_manifest_sha256']!.str() != '9649ab0f596dcd44ce5979a2e129548ca550d2ad54b4d2995fd3c714e125f8e9'
		|| validation['old_framework_sha256']!.str() != '077bb9f1784e2945accebc9043e0d8d54617bb0e01725e97824807d8cc57b10a'
		|| validation['new_framework_sha256']!.str() != jar_pin
		|| validation['changed_classes']!.as_array().map(it.str()) != changed
		|| validation['added_classes']!.as_array().map(it.str()) != added
		|| validation['old_class_count']!.str() != '2074' || validation['new_class_count']!.str() != '2075' {
		return error('bundle365 validation differs')
	}
	return count
}
// END SHARED FRAMEWORK365 CONTRACT

// BEGIN SHARED FRAMEWORK367 CONTRACT
fn class_delta367(old map[string]json2.Any, new map[string]json2.Any) ! {
	added := 'android/util/TimingLogger.smali'
	if old.len != 2075 || new.len != 2076 || added in old || added !in new {
		return error('exact timing367 class counts and added TimingLogger required')
	}
	for name, pin in old {
		if name !in new || pin.str() != new[name]!.str() {
			return error('timing367 unexpected existing class delta: ' + name)
		}
	}
}

fn qualify_framework367(root string, manifest_pin string, jar_pin string) !int {
	count := qualify_build(root, manifest_pin, 'framework/api-impl.jar', jar_pin)!
	qualify_framework365(root + '/baseline365', 'b07a32393f8a3e546819b5053516d3cce8c68238ad9ed27f0ce789e76a6d2d99', 'b8b9351c39e28566ba5856bd3b71268e621587c866020d245cd2d738683668aa')!
	added := ['android/util/TimingLogger.smali']
	delta := object(root + '/framework/dex-delta.json')!
	class_delta367(delta['old_classes']!.as_map(), delta['new_classes']!.as_map())!
	if delta['changed_existing_classes']!.as_array().len != 0
		|| delta['added_classes']!.as_array().map(it.str()) != added
		|| delta['removed_classes']!.as_array().len != 0
		|| delta['old_jar_sha256']!.str() != 'b8b9351c39e28566ba5856bd3b71268e621587c866020d245cd2d738683668aa'
		|| delta['new_jar_sha256']!.str() != jar_pin || delta['jar_only_changed_member']!.str() != 'classes.dex'
		|| delta['jar_member_count']!.int() < 1 {
		return error('exact timing367 DEX and JAR addition required')
	}
	smali := object(root + '/framework/smali-delta.json')!
	class_delta367(smali['before']!.as_map(), smali['after']!.as_map())!
	if smali['changed']!.as_array().len != 0
		|| smali['added']!.as_array().map(it.str()) != added
		|| smali['removed']!.as_array().len != 0 || !smali['duplicate_guard_unchanged']!.bool()
		|| !smali['malformed_guard_unchanged']!.bool() {
		return error('exact timing367 source addition and guards required')
	}
	guard := object(root + '/framework/malformed-guard.json')!
	guard_before := guard['before']!.as_map()
	if guard_before.len != 2076 || added[0] !in guard_before
		|| guard['after']!.as_map() != guard_before
		|| guard['guard_kind']!.str() != 'existing-malformed-destination' {
		return error('timing367 malformed-input guard differs')
	}
	validation := object(root + '/validation.json')!
	if validation['baseline_manifest_sha256']!.str() != 'b07a32393f8a3e546819b5053516d3cce8c68238ad9ed27f0ce789e76a6d2d99'
		|| validation['old_framework_sha256']!.str() != 'b8b9351c39e28566ba5856bd3b71268e621587c866020d245cd2d738683668aa'
		|| validation['new_framework_sha256']!.str() != jar_pin
		|| validation['changed_classes']!.as_array().len != 0
		|| validation['added_classes']!.as_array().map(it.str()) != added
		|| validation['old_class_count']!.str() != '2075' || validation['new_class_count']!.str() != '2076' {
		return error('timing367 validation differs')
	}
	return count
}
// END SHARED FRAMEWORK367 CONTRACT

fn shared_contract(source string, version string) string {
	begin := '\n// BEGIN SHARED FRAMEWORK' + version + ' CONTRACT\n'
	end := '\n// END SHARED FRAMEWORK' + version + ' CONTRACT\n'
	assert source.count(begin) == 1 && source.count(end) == 1
	return source.all_after(begin).all_before(end)
}

fn self_test365() !int {
	changed := ['android/os/BaseBundle.smali', 'android/os/Bundle.smali',
		'android/os/Parcel.smali', 'android/os/Parcelable$ClassLoaderCreator.smali']
	added := 'android/os/VinixBundleCreator.smali'
	mut old := map[string]json2.Any{}
	for i in 0 .. 2070 { old['unchanged/' + i.str() + '.smali'] = 'old' }
	for name in changed { old[name] = 'old' }
	mut valid := old.clone()
	for name in changed { valid[name] = 'new' }
	valid[added] = 'added'
	class_delta365(old, valid)!
	mut rejected := 0
	for test in 0 .. 12 {
		mut invalid := valid.clone()
		mut invalid_old := old.clone()
		if test < changed.len {
			invalid[changed[test]] = 'old'
		} else {
			match test {
				4 { invalid['unchanged/0.smali'] = 'unexpected change' }
				5 { invalid.delete('unchanged/0.smali') }
				6 { invalid['unexpected.smali'] = 'unexpected addition' }
				7 { invalid.delete(added); invalid['unexpected.smali'] = 'replacement addition' }
				8 { invalid.delete(changed[0]); invalid['unexpected.smali'] = 'replacement existing class' }
				9 { invalid_old.delete('unchanged/0.smali'); invalid_old[added] = 'preexisting addition' }
				10 { invalid_old.delete(changed[0]); invalid_old['unexpected.smali'] = 'replacement old class' }
				11 { invalid.delete(added) }
				else {}
			}
		}
		class_delta365(invalid_old, invalid) or { rejected++; continue }
		return error('parcel class delta accepted invalid case ' + test.str())
	}
	assert rejected == 12
	return rejected
}

fn self_test367() !int {
	added := 'android/util/TimingLogger.smali'
	mut old := map[string]json2.Any{}
	for i in 0 .. 2075 { old['unchanged/' + i.str() + '.smali'] = 'old' }
	mut valid := old.clone()
	valid[added] = 'added'
	class_delta367(old, valid)!
	mut rejected := 0
	for test in 0 .. 8 {
		mut invalid := valid.clone()
		mut invalid_old := old.clone()
		match test {
			0 { invalid['unchanged/0.smali'] = 'unexpected change' }
			1 { invalid.delete('unchanged/0.smali') }
			2 { invalid['unexpected.smali'] = 'unexpected addition' }
			3 { invalid.delete(added); invalid['unexpected.smali'] = 'replacement addition' }
			4 { invalid.delete(added) }
			5 { invalid.delete('unchanged/0.smali'); invalid['unexpected.smali'] = 'replacement existing class' }
			6 { invalid_old.delete('unchanged/0.smali'); invalid_old[added] = 'preexisting addition' }
			7 { invalid_old.delete('unchanged/0.smali') }
			else {}
		}
		class_delta367(invalid_old, invalid) or { rejected++; continue }
		return error('timing class delta accepted invalid case ' + test.str())
	}
	assert rejected == 8
	return rejected
}

fn self_test() ! {
	committed_generator := checked(['/usr/bin/git', '-C', '/Users/alex/code/vinix', 'show',
		generator_commit + ':tests/native-android-ws/maps368-generate.v'])!
	assert sha256.sum(committed_generator.bytes()).hex() == generator_source_pin
	assert hash(generator_reference)! == generator_source_pin
	source := os.read_file(@FILE)!
	for version in ['359', '361', '365', '367'] {
		assert shared_contract(source, version) == shared_contract(committed_generator, version),
			'shared framework contract differs: ' + version
	}
	println('MAPS368-SHARED-CONTRACTS-PASS versions=359,361,365,367 generator_commit=' + generator_commit
		+ ' generator_source_sha256=' + generator_source_pin)
	changed := 'android/atl/ATLLoadedApp.smali'
	added := 'android/atl/VinixServiceStop.smali'
	mut old := map[string]json2.Any{}
	for i in 0 .. 2072 { old['unchanged/' + i.str() + '.smali'] = 'old' }
	old[changed] = 'old'
	mut valid := old.clone()
	valid[changed] = 'new'
	valid[added] = 'added'
	class_delta361(old, valid)!
	mut rejected := 0
	for test in 0 .. 7 {
		mut invalid := valid.clone()
		mut invalid_old := old.clone()
		match test {
			0 { invalid[changed] = 'old' }
			1 { invalid['unchanged/0.smali'] = 'unexpected change' }
			2 { invalid.delete('unchanged/0.smali') }
			3 { invalid['unexpected.smali'] = 'unexpected addition' }
			4 { invalid.delete(added); invalid['unexpected.smali'] = 'replacement addition' }
			5 { invalid.delete(changed); invalid['unexpected.smali'] = 'replacement existing class' }
			6 { invalid_old.delete('unchanged/0.smali'); invalid_old[added] = 'preexisting addition' }
			else {}
		}
		class_delta361(invalid_old, invalid) or { rejected++; continue }
		return error('class delta accepted invalid case ' + test.str())
	}
	assert rejected == 7
	rejected365 := self_test365()!
	rejected367 := self_test367()!
	assert !canonical('a'.repeat(63)) && !canonical('A'.repeat(64))
	assert canonical('a'.repeat(64))
	println('MAPS368-PRELAUNCH-REVIEW-SELF-TEST-PASS rejected361=' + rejected.str()
		+ ' rejected365=' + rejected365.str() + ' rejected367=' + rejected367.str())
}

fn build(destination string) ! {
	assert os.dir(destination) == state.trim_right('/') && os.abs_path(destination) == destination
	assert !os.exists(destination) && !os.is_link(destination)
	assert hash(compiler)! == compiler_pin
	assert hash(generator_reference)! == generator_source_pin
	os.mkdir(destination)!
	os.cp(@FILE, destination + '/source.v')!
	os.cp(generator_reference, destination + '/generator-reference.v')!
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
	self_test_argv := [destination + '/program', '--self-test']
	self_test_started := time.utc().str()
	self_test_result := os.exec(self_test_argv)
	os.write_file(destination + '/self-test.log', self_test_result.output)!
	write_json(destination + '/self-test-receipt.json', {
		'argv': json2.Any(self_test_argv), 'started_utc': json2.Any(self_test_started),
		'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(self_test_result.exit_code),
		'binary_sha256': json2.Any(hash(destination + '/program')!),
		'generator_commit': json2.Any(generator_commit),
		'generator_source_sha256': json2.Any(hash(destination + '/generator-reference.v')!),
	})!
	assert self_test_result.exit_code == 0, self_test_result.output
	assert hash(destination + '/generator-reference.v')! == generator_source_pin
	assert hash(destination + '/program')! == record['binary_sha256']!.str()
	mut files := map[string]string{}
	build_inventory(destination, '', mut files)!
	write_json(destination + '/sha256.json', files)!
	println('MAPS-PRELAUNCH-REVIEW-BUILD seal=' + hash(destination + '/sha256.json')!)
}
fn check(review Review) ! {
	assert review.number == '368'
	for pin in [review.prelaunch, review.launch, review.native_pin, review.framework_pin, review.loader_pin] {
		assert canonical(pin), 'canonical SHA-256 required'
	}
	assert review.native_pin == 'd3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'
	assert review.framework_pin == framework367_pin
	assert review.loader_pin == '42c7ac8a276a7eb72a3844e94e182aef8ad7df4c2f8f7313f7061527d077b908'
	new_root := state + 'maps368-2026-10-26'
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
	native_files := qualify_build(new_root + '/native-replacement-build',
		'eb0dfe0dd87ea7f5972bddd06ae4c0c45ba8b9e5ad56a39c074142847f4bccd9',
		'native/libvinix-android-native.so', review.native_pin)!
	framework_files := qualify_framework367(new_root + '/framework-replacement-build',
		framework367_manifest, review.framework_pin)!
	loader_files := qualify_build(new_root + '/loader-replacement-build',
		'1aa6d2ad417643229430e3b9b13333b5c0843ed1c81faccc41dde402c0b91561',
		'loader/libdl_bio.so.0', review.loader_pin)!
	assert read_map(new_root + '/references.json')!['framework_replacement_manifest_sha256']! == framework367_manifest
	println('PEER complete native351/loader357 and framework367→365→361→359→353 builds; exact TimingLogger367 addition and retained Bundle/Binder365 source/DEX/guards PASS')
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
	mut expected_changed := [native, jar, loader]
	expected_changed.sort()
	assert changed == expected_changed
	assert before[native]! == '2231ee3def626a72119cd80d646966ec5ba2fa6cd7dd74a790fe9bcb9db5869b'
	assert after[native]! == review.native_pin
	assert before[jar]! == '95aabc17c85a5cda0d643dfa5ef9e618955d422d960ffb3bbc2db74c86a9c37d'
	assert after[jar]! == review.framework_pin
	assert before[loader]! == '206bc086ab1579b59eec865756e7d4ab8e0db5a2537b5fea3df3503de08dc5d4'
	assert after[loader]! == review.loader_pin
	mut typed := tree(old_tree + '/module', true)!
	typed[native] = after[native]!
	typed[jar] = after[jar]!
	typed[loader] = after[loader]!
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
	println('PEER exact 109 runtime entries; sole native+JAR+loader delta; launcher/APK/identity and typed modes/links PASS')
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
	assert checked(['/usr/bin/tar', '-tf', overlay])! == native + '\n' + jar + '\n' + loader + '\n'
	for path in [native, jar, loader] {
		assert stream_hash(quote('/usr/bin/tar') + ' -xOf ' + quote(overlay) + ' ' + quote(path))! == after[path]!
	}
	assert boot_hash(new_tree, 'maps' + review.number + '-diagnostics.tar')! == hash(overlay)!
	println('PEER all five streamed base boot members and final three-member overlay PASS')
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
		'unchanged_runtime_files': json2.Any(106)
		'typed_runtime_modes_and_links_unchanged': json2.Any(true)
		'classifier_sha256': json2.Any(classifier_pin)
		'unchanged_observation_seconds': json2.Any(600)
		'unchanged_launcher_apk_identity': json2.Any(true)
		'external_maps_and_companion_apk_pins_unchanged': json2.Any(true)
		'base_boot_members_sha256': json2.decode[json2.Any](json2.encode(media))!
		'final_overlay_exact_native_framework_and_loader': json2.Any(true)
		'native351_build_files_checked': json2.Any(native_files)
		'framework367_build_files_checked': json2.Any(framework_files)
		'framework367_manifest_sha256': json2.Any(framework367_manifest)
		'complete_framework367_365_361_359_353_chain': json2.Any(true)
		'exact_timing367_addition_and_bundle_binder365_source_dex_and_guards': json2.Any(true)
		'loader357_build_files_checked': json2.Any(loader_files)
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
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or { eprintln(err); exit(1) }
		return
	}
	assert os.args.len == 8, 'usage: maps368-prelaunch-review 368 PRELAUNCH_SHA LAUNCH_SHA NATIVE_SHA FRAMEWORK_SHA LOADER_SHA RECEIPT | build FRESH_EXTERNAL_ROOT | --self-test | --hash-stdin'
	check(Review{number: os.args[1], prelaunch: os.args[2], launch: os.args[3],
		native_pin: os.args[4], framework_pin: os.args[5], loader_pin: os.args[6], receipt: os.args[7]}) or { eprintln(err); exit(1) }
}
