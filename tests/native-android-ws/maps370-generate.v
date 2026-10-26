// SPDX-License-Identifier: GPL-2.0-or-later
// Pinned Maps368 derivative with the separately qualified Intent URI framework.
module main

import crypto.sha256
import json2
import os
import time

$if macos {
	#include <CommonCrypto/CommonDigest.h>
}

@[typedef]
struct C.CC_SHA256_CTX {}

fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const state = '/Users/alex/.local/state/vinix/android/'
const original = state + 'maps368-generation-2026-10-26/maps368-run.v'
const original_pin = '86ec91f319502155d42fc8a1080e0bbacc7affff7045d1167d4b4762569b2509'
const original_generation_pin = '9aaf171bc4abdab25cd9d050d2a150a0f53651949999c74c8449c64d36274bc4'
const baseline_pin = 'dc30058a943aea4babe5451df20eb0a967262a09caf7df8aed0c88917e987a2c'
const work = state + 'maps370-generation-2026-10-26'
const recorded = state + 'maps370-run-build-c-2026-10-26'
const compiler = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const framework_payload = 'framework/api-impl.jar'
const framework_before = 'fece4cb639fb8745557032f872d13d45767768656ae879f065324696bbf99694'
const framework_before_manifest = '933baf6da303aebaf262e280e41769c89b61c2f050b481dd4075900a533ad23b'
const loader_root = state + 'pwrite357-loader-build-2026-10-26'
const loader_manifest = '1aa6d2ad417643229430e3b9b13333b5c0843ed1c81faccc41dde402c0b91561'
const loader_pin = '42c7ac8a276a7eb72a3844e94e182aef8ad7df4c2f8f7313f7061527d077b908'
const prior_generator = 'tests/native-android-ws/maps368-generate.v'
const prior_generator_pin = '324ff8ef4cfd10d777c5c79df32a6b1b374ef9f18cc2bc3b2d92ad11d13b209a'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	$if macos {
		mut context := C.CC_SHA256_CTX{}
		if C.CC_SHA256_Init(unsafe { &context }) != 1 { return error('CC_SHA256_Init failed') }
		for {
			n := file.read(mut buffer) or {
				if err is os.Eof { break }
				return err
			}
			if n == 0 { break }
			if C.CC_SHA256_Update(unsafe { &context }, buffer.data, u32(n)) != 1 {
				return error('CC_SHA256_Update failed')
			}
		}
		mut result := [32]u8{}
		if C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &context }) != 1 {
			return error('CC_SHA256_Final failed')
		}
		return result[..].hex()
	} $else {
		mut digest := sha256.new()
		defer { unsafe { digest.free() } }
		for {
			n := file.read(mut buffer) or {
				if err is os.Eof { break }
				return err
			}
			if n == 0 { break }
			if digest.write(buffer[..n])! != n { return error('SHA256 short write') }
		}
		mut result := []u8{len: 32}
		defer { unsafe { result.free() } }
		digest.checksum_into(mut result)
		return result.hex()
	}
}

fn read_map(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)!
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn write_json(path string, value json2.Any) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn once(text string, before string, after string) string {
	assert text.count(before) == 1, 'unique replacement required: ' + before
	return text.replace(before, after)
}

fn canonical_pin(pin string) bool {
	return pin.len == 64 && pin.bytes().all(it in '0123456789abcdef'.bytes())
}

fn canonical_root(root string) bool {
	return os.dir(root) == state.trim_right('/') && os.real_path(root) == root
		&& !os.is_link(root) && os.base(root).len > 0
		&& os.base(root).bytes().all(it in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_'.bytes())
}

fn full_inventory(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory { full_inventory(root, key, mut entries)! }
			else { return error('unexpected build artifact: ' + path) }
		}
	}
}

fn qualify_build(root string, manifest_pin string, payload string, payload_pin string) !int {
	assert canonical_pin(manifest_pin) && canonical_pin(payload_pin)
	assert hash(root + '/sha256.json')! == manifest_pin
	expected := read_map(root + '/sha256.json')!
	assert expected.len > 0 && 'sha256.json' !in expected && expected[payload] == payload_pin
	mut actual := map[string]string{}
	full_inventory(root, '', mut actual)!
	actual.delete('sha256.json')
	assert actual == expected, 'complete build readback differs: ' + root
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

// BEGIN SHARED FRAMEWORK369 CONTRACT
fn class_delta369(old map[string]json2.Any, new map[string]json2.Any) ! {
	changed := 'android/content/Intent.smali'
	if old.len != 2076 || new.len != 2076 || changed !in old || changed !in new {
		return error('exact intent369 class counts and existing Intent required')
	}
	for name, pin in old {
		if name !in new || (name == changed && pin.str() == new[name]!.str())
			|| (name != changed && pin.str() != new[name]!.str()) {
			return error('intent369 unexpected existing class delta: ' + name)
		}
	}
}

fn qualify_framework369(root string, manifest_pin string, jar_pin string) !int {
	count := qualify_build(root, manifest_pin, 'framework/api-impl.jar', jar_pin)!
	qualify_framework367(root + '/baseline367', '933baf6da303aebaf262e280e41769c89b61c2f050b481dd4075900a533ad23b', 'fece4cb639fb8745557032f872d13d45767768656ae879f065324696bbf99694')!
	changed := ['android/content/Intent.smali']
	delta := object(root + '/framework/dex-delta.json')!
	class_delta369(delta['old_classes']!.as_map(), delta['new_classes']!.as_map())!
	if delta['old_classes']!.as_map() != object(root + '/baseline367/framework/dex-delta.json')!['new_classes']!.as_map()
		|| delta['changed_existing_classes']!.as_array().map(it.str()) != changed
		|| delta['added_classes']!.as_array().len != 0 || delta['removed_classes']!.as_array().len != 0
		|| delta['old_jar_sha256']!.str() != 'fece4cb639fb8745557032f872d13d45767768656ae879f065324696bbf99694'
		|| delta['new_jar_sha256']!.str() != jar_pin || delta['jar_only_changed_member']!.str() != 'classes.dex'
		|| delta['jar_member_count']!.int() < 1 {
		return error('exact intent369 DEX and JAR change required')
	}
	smali := object(root + '/framework/smali-delta.json')!
	class_delta369(smali['before']!.as_map(), smali['after']!.as_map())!
	if smali['before']!.as_map() != object(root + '/baseline367/framework/smali-delta.json')!['after']!.as_map()
		|| smali['changed']!.as_array().map(it.str()) != changed
		|| smali['added']!.as_array().len != 0 || smali['removed']!.as_array().len != 0
		|| !smali['duplicate_guard_unchanged']!.bool() || !smali['malformed_guard_unchanged']!.bool() {
		return error('exact intent369 source change and guards required')
	}
	guard := object(root + '/framework/malformed-guard.json')!
	guard_before := guard['before']!.as_map()
	if guard_before.len != 2076 || changed[0] !in guard_before
		|| guard['after']!.as_map() != guard_before
		|| guard['guard_kind']!.str() != 'malformed-required-class-declaration' {
		return error('intent369 malformed-input guard differs')
	}
	validation := object(root + '/validation.json')!
	if validation['baseline_manifest_sha256']!.str() != '933baf6da303aebaf262e280e41769c89b61c2f050b481dd4075900a533ad23b'
		|| validation['old_framework_sha256']!.str() != 'fece4cb639fb8745557032f872d13d45767768656ae879f065324696bbf99694'
		|| validation['new_framework_sha256']!.str() != jar_pin
		|| validation['changed_classes']!.as_array().map(it.str()) != changed
		|| validation['added_classes']!.as_array().len != 0
		|| validation['old_class_count']!.str() != '2076' || validation['new_class_count']!.str() != '2076' {
		return error('intent369 validation differs')
	}
	return count
}
// END SHARED FRAMEWORK369 CONTRACT

fn framework_contract() !string {
	source := os.read_file(@FILE)!
	mut contracts := []string{}
	for version in ['369'] {
		begin := '\n// BEGIN SHARED FRAMEWORK' + version + ' CONTRACT\n'
		end := '\n// END SHARED FRAMEWORK' + version + ' CONTRACT\n'
		assert source.count(begin) == 1 && source.count(end) == 1
		contracts << source.all_after(begin).all_before(end)
	}
	return contracts.join('\n\n')
}

fn shared_contract(source string, version string) string {
	begin := '\n// BEGIN SHARED FRAMEWORK' + version + ' CONTRACT\n'
	end := '\n// END SHARED FRAMEWORK' + version + ' CONTRACT\n'
	assert source.count(begin) == 1 && source.count(end) == 1
	return source.all_after(begin).all_before(end)
}

fn derive(before string, framework_root string, manifest_pin string, jar_pin string) !string {
	mut text := before
	// Restrict renaming to replay labels; historical hashes and baseline350 stay intact.
	for prefix in ['maps', 'attempt', 'suite', 'MAPS', 'validate_styled', 'fresh'] {
		text = text.replace(prefix + '368', prefix + '370')
	}
	text = once(text, "const framework367_root = '/Users/alex/.local/state/vinix/android/timing-logger367-framework-build-2026-10-26'", "const framework369_root = '" + framework_root + "'")
	text = once(text, "const framework367_manifest = '" + framework_before_manifest + "'", "const framework369_manifest = '" + manifest_pin + "'")
	text = once(text, "const framework367_pin = '" + framework_before + "'", "const framework369_pin = '" + jar_pin + "'")
	text = once(text, "\nfn qualify_loader_build() ! {", '\n' + framework_contract()! + "\n\nfn qualify_loader_build() ! {")
	text = once(text, "\tqualify_framework367(retained + '/framework-replacement-build', framework367_manifest, framework367_pin)!", "\tqualify_framework369(retained + '/framework-replacement-build', framework369_manifest, framework369_pin)!")
	text = once(text, '|| framework_root != framework367_root', '|| framework_root != framework369_root')
	text = once(text, '|| framework_manifest != framework367_manifest', '|| framework_manifest != framework369_manifest')
	text = once(text, '|| jar_pin != framework367_pin', '|| jar_pin != framework369_pin')
	text = once(text, "'framework_replacement_manifest_sha256': framework367_manifest", "'framework_replacement_manifest_sha256': framework369_manifest")
	text = once(text, "'timing-logger367 framework including Bundle, Parcel and Binder identity; pinned native351 and fortified loader357; unchanged diagnostic launcher'", "'intent-uri369 framework including TimingLogger, Bundle, Parcel and Binder identity; pinned native351 and fortified loader357; unchanged diagnostic launcher'")
	text = once(text, "config.replace('368', '350')", "config.replace('370', '350')")
	text = once(text, "'Timing-logger367 framework including Bundle, Parcel and Binder identity with pinned native351 and fortified loader357 against authenticated350prelaunch109 runtime;106 entries, diagnostic launcher, identity256,600second classifier and all350 base boot members unchanged. Complete baseline and replacement builds retained and qualified.'", "'Intent-uri369 framework including TimingLogger, Bundle, Parcel and Binder identity with pinned native351 and fortified loader357 against authenticated350prelaunch109 runtime;106 entries, diagnostic launcher, identity256,600second classifier and all350 base boot members unchanged. Complete baseline and replacement builds retained and qualified.'")
	assert text.count('qualify_replay_builds()!') == 3 && text.count('qualify_loader_build()!') == 3
	assert text.count('qualify_framework369(retained + ') == 1
	assert text.contains("const loader_root = '" + loader_root + "'")
	assert text.contains("const loader_manifest = '" + loader_manifest + "'")
	assert text.contains("const loader_pin = '" + loader_pin + "'")
	assert text.contains("const previous_pin = '" + baseline_pin + "'")
	assert text.contains("settings['applications']!.as_array()[0].as_map()['startup_seconds']!.int() != 600")
	assert text.contains('if classifier(suite_text)! != classifier(original)!')
	assert text.contains("if os.args.len == 8 && os.args[1] == 'prepare'")
	return text
}

fn generate(framework_root string, manifest_pin string, jar_pin string) ! {
	assert canonical_root(framework_root) && canonical_pin(manifest_pin) && canonical_pin(jar_pin)
	assert jar_pin != framework_before
	assert jar_pin != '077bb9f1784e2945accebc9043e0d8d54617bb0e01725e97824807d8cc57b10a'
	assert jar_pin != 'b8b9351c39e28566ba5856bd3b71268e621587c866020d245cd2d738683668aa'
	assert hash(original)! == original_pin && hash(compiler)! == compiler_pin
	original_count := qualify_build(state + 'maps368-generation-2026-10-26', original_generation_pin, 'maps368-run.v', original_pin)!
	assert hash(state + 'maps350-2026-10-25/prelaunch-sha256.json')! == baseline_pin
	count := qualify_framework369(framework_root, manifest_pin, jar_pin)!
	loader_count := qualify_build(loader_root, loader_manifest, 'loader/libdl_bio.so.0', loader_pin)!
	before := os.read_file(original)!
	text := derive(before, framework_root, manifest_pin, jar_pin)!
	for path in [work, recorded, state + 'maps370-2026-10-26', 'build/android-maps/maps370',
		'build/android-maps/maps370-run-recorded', 'build/android-maps/attempt370', 'build/android-maps/attempt370.json'] {
		assert !os.exists(path) && !os.is_link(path), 'fresh destination required: ' + path
	}
	space := os.exec(['/bin/df', '-k', state])
	assert space.exit_code == 0 && space.output.trim_space().split_into_lines().last().fields()[3].u64() >= 1536 * 1024, '1536 MiB free required'
	os.mkdir(work)!
	os.write_file(work + '/maps368-input.v', before)!
	os.cp(@FILE, work + '/generator.v')!
	os.cp(os.executable(), work + '/generator')!
	os.write_file(work + '/disk-before-generation.txt', space.output)!
	os.write_file(work + '/maps370-run.v', text)!
	write_json(work + '/derivation.json', {
		'original_path': json2.Any(original)
		'original_sha256': json2.Any(original_pin)
		'original_generation_manifest_sha256': json2.Any(original_generation_pin)
		'original_generation_files_checked': json2.Any(original_count)
		'baseline_prelaunch_sha256': json2.Any(baseline_pin)
		'generator_sha256': json2.Any(hash(@FILE)!)
		'generator_binary_sha256': json2.Any(hash(os.executable())!)
		'generated_sha256': json2.Any(hash(work + '/maps370-run.v')!)
		'framework_build_root': json2.Any(framework_root)
		'framework_build_manifest_sha256': json2.Any(manifest_pin)
		'framework_payload': json2.Any(framework_payload)
		'framework_sha256': json2.Any(jar_pin)
		'framework_build_files_checked': json2.Any(count)
		'loader_build_manifest_sha256': json2.Any(loader_manifest)
		'loader_sha256': json2.Any(loader_pin)
		'loader_build_files_checked': json2.Any(loader_count)
		'created_utc': json2.Any(time.utc().str())
		'minimum_free_mib': json2.Any(1536)
		'scope': json2.Any('Generation and recorded runner build only. Pinned Maps368 source and authenticated350 baseline; Intent-uri369 framework with complete367,365,361,359 and353 baselines, exact2076 source/DEX class sets, only Intent changed and all2075 other classes unchanged. Unchanged native351 and fortified loader357;109 runtime files,106 unchanged; exact three-member final archive; unchanged launcher/base media/APK/classifier and600seconds. No guest.')
	})!
	build_generated()!
}

fn build_generated() ! {
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	os.mkdir_all(work + '/generated-c')!
	os.setenv('VTMP', work + '/generated-c', true)
	argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', cc, '-cflags', '-O2', '-o', work + '/bootstrap', work + '/maps370-run.v']
	mut receipt := {
		'argv': json2.Any(argv)
		'started_utc': json2.Any(time.utc().str())
		'working_directory': json2.Any(os.getwd())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'compiler_sha256': json2.Any(compiler_pin)
		'cc_sha256': json2.Any(cc_pin)
		'source_sha256': json2.Any(hash(work + '/maps370-run.v')!)
	}
	result := os.exec(argv)
	os.write_file(work + '/bootstrap.log', result.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = result.exit_code
	if result.exit_code == 0 { receipt['binary_sha256'] = hash(work + '/bootstrap')! }
	write_json(work + '/bootstrap-receipt.json', receipt)!
	assert result.exit_code == 0, result.output
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin
	assert hash(work + '/maps370-run.v')! == receipt['source_sha256']!.str()
	rebuilt := os.exec([work + '/bootstrap', 'rebuild'])
	os.write_file(work + '/recorded-build.log', rebuilt.output)!
	assert rebuilt.exit_code == 0, rebuilt.output
	mut pins := map[string]string{}
	full_inventory(work, '', mut pins)!
	write_json(work + '/sha256.json', json2.decode[json2.Any](json2.encode(pins))!)!
	cloned := os.exec(['cp', '-c', '-R', '-P', work, recorded + '/generation'])
	assert cloned.exit_code == 0, cloned.output
	mut cloned_inventory := map[string]string{}
	full_inventory(recorded + '/generation', '', mut cloned_inventory)!
	cloned_inventory.delete('sha256.json')
	assert cloned_inventory == pins
	assert hash(recorded + '/generation/sha256.json')! == hash(work + '/sha256.json')!
	println('MAPS370-GENERATED source=' + hash(work + '/maps370-run.v')! + ' binary=' + hash('build/android-maps/maps370-run-recorded')! + ' generation-manifest=' + hash(work + '/sha256.json')!)
}

fn class_delta_self_test() ! {
	changed := 'android/atl/ATLLoadedApp.smali'
	added := 'android/atl/VinixServiceStop.smali'
	mut old := map[string]json2.Any{}
	for i in 0 .. 2072 { old['class-' + i.str()] = json2.Any('a'.repeat(64)) }
	old[changed] = 'b'.repeat(64)
	mut next := old.clone()
	next[changed] = 'c'.repeat(64)
	next[added] = 'd'.repeat(64)
	class_delta361(old, next)!
	mut rejected := 0
	mut bad := next.clone()
	bad[changed] = old[changed]!
	class_delta361(old, bad) or { rejected += 1 }
	bad = next.clone()
	bad['class-0'] = 'e'.repeat(64)
	class_delta361(old, bad) or { rejected += 1 }
	bad = next.clone()
	bad.delete('class-0')
	class_delta361(old, bad) or { rejected += 1 }
	bad = next.clone()
	bad.delete(added)
	bad['unexpected-added-class'] = 'd'.repeat(64)
	class_delta361(old, bad) or { rejected += 1 }
	bad = next.clone()
	bad['unexpected-added-class'] = 'd'.repeat(64)
	class_delta361(old, bad) or { rejected += 1 }
	mut bad_old := old.clone()
	bad_old.delete(changed)
	bad_old[added] = 'b'.repeat(64)
	class_delta361(bad_old, next) or { rejected += 1 }
	assert rejected == 6
}

fn class_delta365_self_test() ! {
	changed := framework365_changed()
	added := 'android/os/VinixBundleCreator.smali'
	mut old := map[string]json2.Any{}
	for i in 0 .. 2070 { old['class-' + i.str()] = json2.Any('a'.repeat(64)) }
	for name in changed { old[name] = 'b'.repeat(64) }
	mut next := old.clone()
	for name in changed { next[name] = 'c'.repeat(64) }
	next[added] = 'd'.repeat(64)
	class_delta365(old, next)!
	mut rejected := 0
	for name in changed {
		mut invalid := next.clone()
		invalid[name] = old[name]!
		class_delta365(old, invalid) or { rejected++; continue }
		return error('required bundle365 class change accepted unchanged: ' + name)
	}
	for test in 0 .. 7 {
		mut invalid := next.clone()
		mut invalid_old := old.clone()
		match test {
			0 { invalid['class-0'] = 'e'.repeat(64) }
			1 { invalid.delete('class-0') }
			2 { invalid['unexpected-added-class'] = 'd'.repeat(64) }
			3 { invalid.delete(added); invalid['unexpected-added-class'] = 'd'.repeat(64) }
			4 { invalid.delete(changed[0]); invalid['unexpected-added-class'] = 'd'.repeat(64) }
			5 { invalid_old.delete('class-0'); invalid_old[added] = 'd'.repeat(64) }
			6 { invalid.delete('class-0'); invalid['unexpected-existing-class'] = 'a'.repeat(64) }
			else {}
		}
		class_delta365(invalid_old, invalid) or { rejected++; continue }
		return error('bundle365 accepted invalid delta ' + test.str())
	}
	assert rejected == 11
}

fn class_delta367_self_test() ! {
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
			6 { invalid_old.delete('unchanged/0.smali'); invalid_old[added] = 'preexisting TimingLogger' }
			7 { invalid_old.delete('unchanged/0.smali') }
			else {}
		}
		class_delta367(invalid_old, invalid) or { rejected++; continue }
		return error('timing367 accepted invalid delta ' + test.str())
	}
	assert rejected == 8
}

fn class_delta369_self_test() ! {
	changed := 'android/content/Intent.smali'
	mut old := map[string]json2.Any{}
	for i in 0 .. 2075 { old['unchanged/' + i.str() + '.smali'] = 'old' }
	old[changed] = 'old'
	mut valid := old.clone()
	valid[changed] = 'new'
	class_delta369(old, valid)!
	mut rejected := 0
	for test in 0 .. 10 {
		mut invalid := valid.clone()
		mut invalid_old := old.clone()
		match test {
			0 { invalid[changed] = 'old' }
			1 { invalid['unchanged/0.smali'] = 'unexpected change' }
			2 { invalid.delete('unchanged/0.smali') }
			3 { invalid['unexpected.smali'] = 'unexpected addition' }
			4 { invalid.delete(changed); invalid['unexpected.smali'] = 'replacement Intent' }
			5 { invalid.delete('unchanged/0.smali'); invalid['unexpected.smali'] = 'replacement existing class' }
			6 { invalid_old.delete(changed); invalid_old['unexpected.smali'] = 'replacement old Intent' }
			7 { invalid_old.delete('unchanged/0.smali') }
			8 { invalid_old['unexpected.smali'] = 'unexpected old class' }
			9 { invalid_old.delete('unchanged/0.smali'); invalid_old['unexpected.smali'] = 'replacement old class' }
			else {}
		}
		class_delta369(invalid_old, invalid) or { rejected++; continue }
		return error('intent369 accepted invalid delta ' + test.str())
	}
	assert rejected == 10
}

fn self_test(output string) ! {
	for pin in [original_pin, original_generation_pin, baseline_pin, compiler_pin,
		framework_before, framework_before_manifest, loader_manifest, loader_pin] {
		assert canonical_pin(pin)
	}
	assert hash(original)! == original_pin
	assert hash(prior_generator)! == prior_generator_pin
	prior := os.read_file(prior_generator)!
	source := os.read_file(@FILE)!
	for version in ['359', '361', '365', '367'] {
		assert shared_contract(source, version) == shared_contract(prior, version),
			'inherited framework contract changed: ' + version
	}
	before := os.read_file(original)!
	text := derive(before, state + 'test-framework369-build', 'a'.repeat(64), 'b'.repeat(64))!
	assert text.contains("const target = base + 'maps370'")
	assert text.contains("const previous_tree = previous + '/prelaunch/maps350'")
	assert text.contains("config.replace('370', '350')")
	assert !text.contains('maps368') && !text.contains('MAPS368')
	assert text.contains("'unchanged_runtime_entries': '106'")
	assert text.contains("'d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'")
	assert text.contains("const framework369_manifest = '" + 'a'.repeat(64) + "'")
	assert text.contains("const framework369_pin = '" + 'b'.repeat(64) + "'")
	assert text.contains("const source = '" + work + "/maps370-run.v'")
	assert text.contains("const outer_build = '" + recorded + "'")
	assert text.contains("const retained = '" + state + "maps370-2026-10-26'")
	assert text.contains('equal(actual, read_map(retained + \'/sha256.json\')!)!')
	assert text.contains('equal(tree(target + \'/module\', true)!, read_map(target + \'/module-after-typed.json\')!)!')
	assert text.contains("['vinix', 'initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar', 'maps350-diagnostics.tar']")
	assert text.contains("for name, pin in media { if media_hash(name)! != pin")
	assert text.contains("exact native SO, framework JAR and loader tar members required")
	mut normalized := text
	for prefix in ['maps', 'attempt', 'suite', 'MAPS', 'validate_styled', 'fresh'] {
		normalized = normalized.replace(prefix + '370', prefix + '368')
	}
	for name in ['hash', 'inventory', 'tree', 'build_inventory', 'qualify_build', 'equal',
		'receipt', 'classifier', 'qualify_runner_build', 'qualify_builds', 'qualify_parent_framework',
		'qualify_framework359', 'class_delta361', 'qualify_framework361', 'framework365_changed',
		'class_delta365', 'qualify_framework365', 'class_delta367', 'qualify_framework367',
		'qualify_loader_build', 'disk_space', 'qualify_launcher', 'qualify_baseline', 'media_hash',
		'gate', 'results', 'run', 'verify'] {
		start := '\nfn ' + name + '('
		assert before.count(start) == 1 && normalized.count(start) == 1
		assert before.all_after(start).all_before('\nfn ') == normalized.all_after(start).all_before('\nfn '),
			'inherited replay function changed: ' + name
	}
	if output != '' {
		path := os.abs_path(output)
		assert os.dir(path) == state.trim_right('/') && !os.exists(path) && !os.is_link(path)
		os.write_file(path, text)!
	}
	class_delta_self_test()!
	class_delta365_self_test()!
	class_delta367_self_test()!
	class_delta369_self_test()!
	println('MAPS370-GENERATOR-SELF-TEST-PASS')
}

fn main() {
	$if prod { panic('requires assertions') }
	if os.args.len == 4 && os.args[1] == 'rebuild' {
		build_tool(os.abs_path(os.args[2]), os.args[3])!
		return
	}
	if os.args.len in [2, 3] && os.args[1] == '--self-test' {
		self_test(if os.args.len == 3 { os.args[2] } else { '' })!
		return
	}
	assert os.args.len == 4, 'usage: maps370-generate FRAMEWORK_ROOT MANIFEST_SHA FRAMEWORK_SHA | rebuild BUILD_ROOT OUTPUT | --self-test [CHECK_SOURCE]'
	generate(os.abs_path(os.args[1]), os.args[2], os.args[3])!
}

fn build_tool(destination string, output string) ! {
	assert os.dir(destination) == state.trim_right('/') && os.abs_path(destination) == destination
	assert os.dir(output) == 'build/android-maps' && !os.exists(output) && !os.is_link(output)
	assert !os.exists(destination) && !os.is_link(destination) && hash(compiler)! == compiler_pin
	assert hash(prior_generator)! == prior_generator_pin
	os.mkdir(destination)!
	os.cp(@FILE, destination + '/source.v')!
	os.cp(prior_generator, destination + '/prior-generator-reference.v')!
	os.cp(os.executable(), destination + '/bootstrap')!
	os.cp(compiler, destination + '/v_old276')!
	os.mkdir(destination + '/generated-c')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('VTMP', destination + '/generated-c', true)
	listing_argv := [compiler, '-print-v-files', @FILE]
	started := time.utc().str()
	listing := os.exec(listing_argv)
	os.write_file(destination + '/closure-v-files.txt', listing.output)!
	write_json(destination + '/closure-receipt.json', {
		'argv': json2.Any(listing_argv)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(listing.exit_code)
		'compiler_sha256': json2.Any(compiler_pin)
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
	write_json(destination + '/closure-before.json', json2.decode[json2.Any](json2.encode(before))!)!
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', cc, '-cflags', '-O2', '-o', output, @FILE]
	mut receipt := {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(time.utc().str())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'compiler_sha256': json2.Any(compiler_pin)
		'cc_path': json2.Any(cc)
		'cc_sha256': json2.Any(cc_pin)
		'source_sha256': json2.Any(hash(@FILE)!)
		'prior_generator_sha256': json2.Any(hash(destination + '/prior-generator-reference.v')!)
		'closure_before_sha256': json2.Any(hash(destination + '/closure-before.json')!)
	}
	write_json(destination + '/build-before.json', receipt)!
	result := os.exec(argv)
	os.write_file(destination + '/build.log', result.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = result.exit_code
	mut after := map[string]string{}
	for path, pin in before {
		after[path] = hash(path)!
		assert after[path] == pin && hash(destination + '/closure/' + os.abs_path(path).trim_left('/'))! == pin
	}
	write_json(destination + '/closure-after.json', json2.decode[json2.Any](json2.encode(after))!)!
	receipt['closure_after_sha256'] = hash(destination + '/closure-after.json')!
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin
	if result.exit_code == 0 {
		receipt['binary_sha256'] = hash(output)!
		os.cp(output, destination + '/program')!
	}
	write_json(destination + '/build-receipt.json', receipt)!
	assert result.exit_code == 0, result.output
	self_started := time.utc().str()
	tested := os.exec([output, '--self-test'])
	os.write_file(destination + '/self-test.log', tested.output)!
	write_json(destination + '/self-test-receipt.json', {
		'argv': json2.Any([output, '--self-test'])
		'started_utc': json2.Any(self_started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(tested.exit_code)
		'binary_sha256': json2.Any(hash(output)!)
		'source_sha256': json2.Any(hash(@FILE)!)
		'output_sha256': json2.Any(hash(destination + '/self-test.log')!)
	})!
	assert tested.exit_code == 0 && tested.output.contains('MAPS370-GENERATOR-SELF-TEST-PASS'), tested.output
	assert hash(destination + '/source.v')! == hash(@FILE)!
	mut inventory := map[string]string{}
	full_inventory(destination, '', mut inventory)!
	write_json(destination + '/sha256.json', json2.decode[json2.Any](json2.encode(inventory))!)!
	println('MAPS-REPLAY-GENERATOR-BUILD source=' + hash(@FILE)! + ' binary=' + hash(output)! + ' seal=' + hash(destination + '/sha256.json')!)
}
