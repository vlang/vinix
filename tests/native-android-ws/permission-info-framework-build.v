// SPDX-License-Identifier: GPL-2.0-or-later
// Framework-only rebuild from the complete qualified353 bundle; no guest work.
module main

import json2
import os
import time

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const baseline = '/Users/alex/.local/state/vinix/android/screen-reader-focusable353-framework-build-2026-10-25'
const baseline_pin = '22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f'
const old_jar = '1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const checker = '/Users/alex/code/vinix/build/android-maps/build-bundle-check290'
const checker_pin = '52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004'
const java = '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'
const java_pin = '9ef6c1a939343ac850811551a8b88d4b877630ab2c94ac38c541e25ccc8cf0a5'
const cc_pin = '179301dcb41ea78accc3fa0048a7e6f6710d891945a751a34addd622020c1818'
const provider = 'tests/native-android-tools/androidtools/framework_permission_info.v'
const source_name = 'tests/native-android-ws/permission-info-framework-build.v'
const changed_class = 'android/content/pm/PackageManager.smali'

fn hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	mut digest := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(unsafe { &digest }) == 1
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		assert C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) == 1
	}
	mut sum := [32]u8{}
	assert C.CC_SHA256_Final(unsafe { &sum[0] }, unsafe { &digest }) == 1
	return sum[..].hex()
}

fn write_json[T](path string, value T) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
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

fn record(root string, label string, argv []string) !string {
	assert !os.exists(root + '/commands/' + label + '.json'), label
	exe := if argv[0].contains('/') { os.real_path(argv[0]) } else { os.find_abs_path_of_executable(argv[0])! }
	pin := hash(exe)!
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(root + '/commands/' + label + '.log', r.output)!
	write_json(root + '/commands/' + label + '.json', {
		'argv': json2.Any(argv), 'started_utc': json2.Any(started),
		'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(r.exit_code),
		'executable_sha256': json2.Any(pin)
	})!
	assert hash(exe)! == pin, exe
	assert r.exit_code == 0, label + ': ' + r.output
	return r.output
}

fn clone(root string, label string, from string, to string) ! {
	assert !os.exists(to) && !os.is_link(to), to
	os.mkdir_all(os.dir(to))!
	record(root, label, ['/bin/cp', '-c', '-R', os.real_path(from), to])!
}

fn closure(root string, label string, compiler string, paths string, source string) !map[string]string {
	listing := record(root, label + '-closure', [compiler, '-path', paths, '-print-v-files', source])!
	mut pins := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		assert os.real_path(path).starts_with(root + '/'), 'nonfrozen V input: ' + path
		pins[path] = hash(path)!
	}
	assert pins.len > 0
	write_json(root + '/' + label + '-v-files.json', pins)!
	return pins
}

fn same_except(old map[string]string, new map[string]string, changed string) ! {
	assert old.len == new.len && changed in old && changed in new
	for name, pin in old {
		assert name in new, name
		if name == changed { assert pin != new[name]!, name }
		else { assert pin == new[name]!, name }
	}
}

fn freeze_provider(root string, revision string, pin string) ! {
	committed := record(root, 'provider-committed-source', ['git', 'show', revision + ':' + provider])!
	assert committed == os.read_file(provider)! && hash(provider)! == pin
	clone(root, 'retain-provider', provider, root + '/driver/androidtools/framework_permission_info.v')!
	// Preserve the production method helper verbatim without importing the whole
	// generator module. Its authenticated353 definition must still equal live.
	frozen := root + '/baseline353/frozen/vroot/source/androidtools/framework.v'
	marker := 'pub fn framework_replace_method('
	qualified := os.read_file(frozen)!.all_after(marker).all_before('\n// Missing packages')
	live := os.read_file('tests/native-android-tools/androidtools/framework.v')!.all_after(marker).all_before('\n// Missing packages')
	assert qualified == live && qualified.starts_with('source string, name string, declaration string) !string {')
	if os.read_file(provider)!.contains('framework_replace_method(') {
		os.write_file(root + '/driver/androidtools/framework_method.v', 'module androidtools\n\n' + marker + qualified + '\n')!
	}
	write_json(root + '/source/provider-inputs.json', {
		'provider_commit': revision, 'provider_sha256': pin,
		'qualified353_framework_v_sha256': hash(frozen)!,
		'live_framework_v_sha256': hash('tests/native-android-tools/androidtools/framework.v')!
	})!
}

fn run() ! {
	if os.args.len != 4 { return error('usage: permission-info-framework-build FRESH_ROOT PROVIDER_COMMIT PROVIDER_SHA256') }
	root := os.abs_path(os.args[1])
	revision := os.args[2]
	provider_pin := os.args[3]
	assert !os.exists(root) && !os.is_link(root), root
	assert revision.len == 40 && provider_pin.len == 64
	assert hash(checker)! == checker_pin && hash(java)! == java_pin && hash('/usr/bin/cc')! == cc_pin
	assert hash(baseline + '/sha256.json')! == baseline_pin
	assert hash(provider)! == provider_pin
	os.mkdir_all(root + '/commands')!
	space := record(root, 'disk-before', ['/bin/df', '-k', root])!
	assert space.trim_space().split_into_lines().last().fields()[3].u64() >= 768 * 1024, 'need at least 768 MiB free'
	clone(root, 'retain-checker', checker, root + '/tools/build-bundle-check290')!
	checked := root + '/tools/build-bundle-check290'
	clone(root, 'retain-bootstrap', os.executable(), root + '/tools/bootstrap')!
	clone(root, 'retain-builder-source', source_name, root + '/source/permission-info-framework-build.v')!
	record(root, 'verify-baseline-original', [checked, baseline, baseline_pin, root + '/qualification/baseline-original.json'])!
	clone(root, 'clone-complete353', baseline, root + '/baseline353')!
	record(root, 'verify-baseline-clone', [checked, root + '/baseline353', baseline_pin, root + '/qualification/baseline-clone.json'])!
	assert hash(root + '/baseline353/framework/api-impl.jar')! == old_jar
	assert hash(root + '/baseline353/frozen/vroot/v')! == compiler_pin
	freeze_provider(root, revision, provider_pin)!
	mut host_tools := map[string]string{}
	for name in ['clang', 'ld'] {
		path := record(root, 'find-host-' + name, ['/usr/bin/xcrun', '--find', name])!.trim_space()
		host_tools[path] = hash(path)!
	}
	host_tools['/usr/bin/cc'] = cc_pin
	host_tools[java] = java_pin
	write_json(root + '/host-tool-inputs.json', host_tools)!
	write_json(root + '/source/revisions.json', {
		'checkout': record(root, 'checkout-revision', ['git', 'rev-parse', 'HEAD'])!.trim_space(),
		'provider_commit': revision, 'provider_sha256': provider_pin, 'baseline_manifest': baseline_pin
	})!
	os.write_file(root + '/driver/main.v', "module main\nimport androidtools\nimport os\nfn main() {\n if os.args.len == 3 {\n  androidtools.framework_permission_info(os.args[1]) or { println('PERMISSION359-DUPLICATE-GUARD-PASS'); return }\n  eprintln('provider accepted duplicate application'); exit(1)\n }\n androidtools.framework_permission_info(os.args[1]) or { eprintln(err); exit(1) }\n}\n")!
	vroot := root + '/baseline353/frozen/vroot'
	compiler := vroot + '/v'
	paths := root + '/driver|' + vroot + '/vlib'
	os.mkdir_all(root + '/generated-c')!
	os.mkdir_all(root + '/vmodules')!
	os.setenv('VROOT', vroot, true)
	os.setenv('VEXE', compiler, true)
	os.setenv('VMODULES', root + '/vmodules', true)
	os.setenv('VTMP', root + '/generated-c', true)
	before_closure := closure(root, 'driver-before', compiler, paths, root + '/driver')!
	builder_closure := closure(root, 'builder-before', compiler, vroot + '/vlib', root + '/source/permission-info-framework-build.v')!
	record(root, 'compile-driver', [compiler, '-path', paths, '-nocache', '-keepc', '-showcc', '-cc', '/usr/bin/cc',
		'-o', root + '/tools/permission-info-provider', root + '/driver'])!
	assert !os.read_file(root + '/commands/compile-driver.log')!.contains('/Users/alex/code/'), 'mutable checkout in C compiler command'
	clone(root, 'clone-smali', root + '/baseline353/framework/smali', root + '/framework/smali')!
	mut before := map[string]string{}
	inventory(root + '/framework/smali', '', mut before)!
	assert before.len == 2073
	record(root, 'apply-provider', [root + '/tools/permission-info-provider', root + '/framework/smali'])!
	mut after := map[string]string{}
	inventory(root + '/framework/smali', '', mut after)!
	same_except(before, after, changed_class)!
	record(root, 'duplicate-guard', [root + '/tools/permission-info-provider', root + '/framework/smali', 'duplicate'])!
	mut duplicate := map[string]string{}
	inventory(root + '/framework/smali', '', mut duplicate)!
	assert after == duplicate, 'duplicate application mutated input'
	write_json(root + '/framework/smali-delta.json', {'before': json2.decode[json2.Any](json2.encode(before))!, 'after': json2.decode[json2.Any](json2.encode(after))!, 'changed': json2.Any([changed_class]), 'duplicate_guard_unchanged': json2.Any(true)})!
	build_dex(root)!
	assert before_closure == closure(root, 'driver-after', compiler, paths, root + '/driver')!
	assert builder_closure == closure(root, 'builder-after', compiler, vroot + '/vlib', root + '/source/permission-info-framework-build.v')!
	assert hash(provider)! == provider_pin && hash(java)! == java_pin && hash('/usr/bin/cc')! == cc_pin
	for path, pin in host_tools { assert hash(path)! == pin, path }
	record(root, 'verify-baseline-after', [checked, root + '/baseline353', baseline_pin, root + '/qualification/baseline-after.json'])!
	write_json(root + '/validation.json', {'scope': 'Framework-only production provider build; complete qualified353 baseline retained unchanged; no native rebuild or guest execution.',
		'baseline_manifest_sha256': baseline_pin, 'old_framework_sha256': old_jar, 'new_framework_sha256': hash(root + '/framework/api-impl.jar')!,
		'changed_class': changed_class, 'class_count': '2073', 'provider_sha256': provider_pin, 'builder_sha256': hash(root + '/source/permission-info-framework-build.v')!})!
	mut pins := map[string]string{}
	inventory(root, '', mut pins)!
	write_json(root + '/sha256.json', pins)!
	seal := hash(root + '/sha256.json')!
	// Final checker output and receipt must stay outside the sealed bundle.
	assert hash(checked)! == checker_pin
	r := os.exec([checked, root, seal, root + '-own-readback.json'])
	os.write_file(root + '-own-readback.log', r.output)!
	assert r.exit_code == 0 && hash(checked)! == checker_pin, r.output
	println('PERMISSION359-FRAMEWORK-BUILD-PASS jar=' + hash(root + '/framework/api-impl.jar')! + ' files=' + pins.len.str() + ' manifest=' + seal)
}

fn build_dex(root string) ! {
	// Always assemble to a fresh path: smali may exit zero after syntax errors.
	dex := root + '/framework/classes.dex'
	assert !os.exists(dex)
	jars := root + '/baseline353/tools/framework/*'
	record(root, 'assemble-framework', [java, '-cp', jars, 'org.jf.smali.Main', 'assemble', '--jobs', '2', root + '/framework/smali', '-o', dex])!
	assert os.is_file(dex) && os.file_size(dex) > 0, 'assembly did not produce fresh DEX'
	clone(root, 'clone-old-jar', root + '/baseline353/framework/api-impl.jar', root + '/framework-old.jar')!
	clone(root, 'clone-new-jar', root + '/framework-old.jar', root + '/framework/api-impl.jar')!
	record(root, 'package-framework', ['/usr/bin/zip', '-q', '-j', root + '/framework/api-impl.jar', dex])!
	for kind in ['old', 'new'] {
		jar := if kind == 'old' { root + '/framework-old.jar' } else { root + '/framework/api-impl.jar' }
		record(root, 'disassemble-' + kind, [java, '-cp', jars, 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', jar, '-o', root + '/framework/' + kind + '-dex'])!
		record(root, 'extract-' + kind + '-jar', ['/usr/bin/unzip', '-q', jar, '-d', root + '/framework/' + kind + '-jar'])!
	}
	mut old_dex := map[string]string{}
	mut new_dex := map[string]string{}
	inventory(root + '/framework/old-dex', '', mut old_dex)!
	inventory(root + '/framework/new-dex', '', mut new_dex)!
	assert old_dex.len == 2073
	same_except(old_dex, new_dex, changed_class)!
	mut old_members := map[string]string{}
	mut new_members := map[string]string{}
	inventory(root + '/framework/old-jar', '', mut old_members)!
	inventory(root + '/framework/new-jar', '', mut new_members)!
	same_except(old_members, new_members, 'classes.dex')!
	assert new_members['classes.dex']! == hash(dex)!
	write_json(root + '/framework/dex-delta.json', {
		'old_classes': json2.decode[json2.Any](json2.encode(old_dex))!, 'new_classes': json2.decode[json2.Any](json2.encode(new_dex))!,
		'changed_existing_classes': json2.Any([changed_class]), 'added_classes': json2.Any([]string{}), 'removed_classes': json2.Any([]string{}),
		'old_jar_sha256': json2.Any(old_jar), 'new_jar_sha256': json2.Any(hash(root + '/framework/api-impl.jar')!),
		'jar_member_count': json2.Any(old_members.len), 'jar_only_changed_member': json2.Any('classes.dex')
	})!
}

fn main() {
	$if prod { panic('requires assertions') }
	run() or { eprintln(err); exit(1) }
}
