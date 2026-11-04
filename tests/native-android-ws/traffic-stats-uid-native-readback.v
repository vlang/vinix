// SPDX-License-Identifier: GPL-2.0-or-later
// Retain the complete JNI producer and its original SDK coupling. The two
// admitted raw-source pairs are exact historical DEX formatting changes.
module main

import json2
import mapsaccountstage as stage
import os

const state = '/Users/alex/.local/state/vinix/android/'
const repo = '/Users/alex/code/vinix/'
const native_root = state + 'current-native-build-2026-11-04-framework-jni-load-r1'
const native_seal = '2d9c97030ab7367b487b4a7b3a6b4ed27b1cf4e68cf6567054c7ea03cc667fa0'
const native_dso = '13cf020729373ad8d20cfa4c5588c0878eee4be4fdf85700f2cf911ded08e81e'
const native_build = '16cb572c43e56af969757b9c3296637c5007bf46bab842291fadfe746dc99318'
const sdk_root = state + 'combined-account-webview-framework-boot-framework-2026-11-03-r1'
const sdk_seal = 'af23c13d90f557c4f7f208ae75c39ad8bcf0efd86fc88fddfe399fe2e66a4e91'
const sdk_jar = 'd9633112327093e55d924ad658088f8dd3d0b712d5184bddcf7307bfc51bf974'
const sdk_dex = 'c59bc24f43fcd5c40a18b118872186795127fbe309cd1a523823f01136f6f30b'
// Filled only from the completed, fully sealed TrafficStats SDK producer.
const successor_seal = 'bffa5dedc87d80979b09d517fcfb752b470d7f9e76a8e44bc24452f152d42025'
const successor_jar = 'dd3af0444459410f28d20f04928e37a19eb6b076d433498b05eac9a922b49f0e'
const successor_dex = '64c472412e52f91e5f40277f8077d251ee8de9b61558ecf8eec709227d97bde3'
const traffic_stats = 'android/net/TrafficStats.smali'

fn object(bundle stage.Bundle, path string) !map[string]string {
	if path !in bundle.files { return error('complete sealed object missing: ' + path) }
	return json2.decode[map[string]string](os.read_file(bundle.root + '/' + path)!)
}

fn subtree(files map[string]string, prefix string) map[string]string {
	mut result := map[string]string{}
	for path, pin in files { if path.starts_with(prefix) { result[path] = pin } }
	return result
}

fn delta(before map[string]string, after map[string]string) map[string][]string {
	mut result := map[string][]string{}
	for path, pin in before { if after[path] or { '' } != pin { result[path] = [pin, after[path] or { '' }] } }
	for path, pin in after { if path !in before { result[path] = ['', pin] } }
	return result
}

fn exact_sdk_delta(before map[string]string, after map[string]string) ! {
	if before.len != 2117 || before.keys().sorted() != after.keys().sorted()
		|| traffic_stats !in before || delta(before, after).keys() != [traffic_stats] {
		return error('exactly TrafficStats must change among the same 2117 canonical classes')
	}
}

fn canonical_classes(bundle stage.Bundle) !map[string]string {
	mut result := map[string]string{}
	for path, pin in subtree(bundle.files, 'new-dex/') {
		name := path.all_after('new-dex/')
		if !name.ends_with('.smali') || !stage.relative_file(name) { return error('unexpected canonical SDK member') }
		result[name] = pin
	}
	return result
}

struct ClassPins {
	old_raw       string
	old_canonical string
	new_raw       string
	new_canonical string
}

fn permitted_pairs() map[string]ClassPins {
	return {
		'smali/android/content/res/Resources.smali': ClassPins{
			'f7cd9fbce3ddbb6e59580065ae7fb93f36bf17875054710ea5386648101e1e1d',
			'43bff6c257c83e7a79894eb2ac32b3e927cb213e2c744376d62ea8df628f0d18',
			'43bff6c257c83e7a79894eb2ac32b3e927cb213e2c744376d62ea8df628f0d18',
			'43bff6c257c83e7a79894eb2ac32b3e927cb213e2c744376d62ea8df628f0d18'
		}
		'smali/android/atl/ATLLoadedApp.smali': ClassPins{
			'644d12ccd65fb6ff5d6cb245b0168f8efc9f28e7fad3957519fc1c1a2926f08a',
			'69b03bab991dc30d5808a4e970ad3dc13203f4e8e14b1404d818de1c33387b9b',
			'69b03bab991dc30d5808a4e970ad3dc13203f4e8e14b1404d818de1c33387b9b',
			'69b03bab991dc30d5808a4e970ad3dc13203f4e8e14b1404d818de1c33387b9b'
		}
	}
}

// This does not normalize arbitrary smali. All four hashes of each exceptional
// class are fixed, and every new raw class must equal the unchanged canonical
// class. The other 68 native inputs retain their exact original raw bytes.
fn consumed_classes(consumed map[string]string, native_files map[string]string,
	before map[string]string, after map[string]string) !map[string]ClassPins {
	if consumed.len != 70 || 'smali/' + traffic_stats in consumed
		|| subtree(native_files, 'framework/smali/').keys().sorted() != consumed.keys().map('framework/' + it).sorted() {
		return error('exact original 70 native-consumed copies, excluding TrafficStats, required')
	}
	pairs := permitted_pairs()
	mut result := map[string]ClassPins{}
	mut raw_delta := map[string][]string{}
	for path, pin in consumed {
		if !path.starts_with('smali/') || !path.ends_with('.smali') || !stage.relative_file(path)
			|| native_files['framework/' + path] or { '' } != pin || before[path] or { '' } != pin {
			return error('native consumed copy differs from the complete original SDK')
		}
		canonical := 'new-dex/' + path.all_after('smali/')
		old_canonical := before[canonical] or { return error('original consumed canonical class absent') }
		new_raw := after[path] or { return error('successor consumed raw class absent') }
		new_canonical := after[canonical] or { return error('successor consumed canonical class absent') }
		actual := ClassPins{pin, old_canonical, new_raw, new_canonical}
		if ![pin, old_canonical, new_raw, new_canonical].all(stage.valid_pin(it))
			|| old_canonical != new_canonical || new_raw != new_canonical {
			return error('all 70 native canonical inputs must remain identical and equal new raw copies')
		}
		if expected := pairs[path] {
			if actual != expected { return error('exact four pinned formatting hashes required: ' + path) }
		} else if pin != old_canonical {
			return error('unreviewed third native raw formatting difference')
		}
		if pin != new_raw { raw_delta[path] = [pin, new_raw] }
		result[path] = actual
	}
	if raw_delta.keys().sorted() != pairs.keys().sorted() { return error('both exact historical raw formatting pairs required') }
	return result
}

fn declarations(source string) ![]string {
	mut result := []string{}
	mut methods := map[string]bool{}
	mut fields := map[string]bool{}
	mut active := false
	mut classes := 0
	mut supers := 0
	for line in source.split_into_lines() {
		text := line.trim_space()
		if text.starts_with('.method ') {
			name := text.all_after_last(' ')
			if active || !name.contains('(') || name in methods { return error('invalid or duplicate method declaration') }
			methods[name] = true
			active = true
			result << text
		} else if text == '.end method' {
			if !active { return error('stray method end') }
			active = false
		} else if text.starts_with('.field ') {
			if active || text in fields { return error('invalid or duplicate field declaration') }
			fields[text] = true
			result << text
		} else if text.starts_with('.class ') || text.starts_with('.super ') || text.starts_with('.implements ') {
			if active { return error('class metadata inside method') }
			if text.starts_with('.class ') { classes++ }
			if text.starts_with('.super ') { supers++ }
			result << text
		}
	}
	if active || classes != 1 || supers != 1 || methods.len == 0 { return error('complete class metadata and methods required') }
	return result.sorted()
}

fn no_native_traffic(source string) ! {
	shape := declarations(source)!
	method_headers := source.split_into_lines().filter(it.fields().len > 0 && it.fields()[0] == '.method')
	if shape.filter(it.starts_with('.class ')) != ['.class public Landroid/net/TrafficStats;']
		|| method_headers.any('native' in it.fields()) {
		return error('TrafficStats must remain a Java-only class outside the native ABI')
	}
}

fn binding_classes(source string) ![]string {
	mut result := map[string]bool{}
	mut rows := map[string]bool{}
	for line in source.split_into_lines() {
		if line.trim_space() == '' || line.starts_with('#') { continue }
		parts := line.split('|')
		if parts.len != 3 || parts[0] == '' || parts[1] == '' || parts[2] == '' || line in rows
			|| !stage.relative_file(parts[0] + '.smali') || parts[0] == 'android/net/TrafficStats' {
			return error('safe original binding rows excluding TrafficStats required')
		}
		rows[line] = true
		result['smali/' + parts[0] + '.smali'] = true
	}
	if result.len != 70 { return error('exact original 70 bound classes required') }
	return result.keys().sorted()
}

fn frozen_closure(bundle stage.Bundle, label string, count int) !map[string]string {
	pins := object(bundle, label + '-closure.json')!
	if pins.len != count { return error('complete frozen helper count differs: ' + label) }
	for path, pin in pins {
		if (!path.starts_with(repo) && !path.starts_with(bundle.root + '/compiler-root/'))
			|| bundle.files['closure/' + label + '/' + path.trim_left('/')] or { '' } != pin {
			return error('complete frozen helper copy differs: ' + label + '/' + path)
		}
	}
	// Historical helper bytes are checked against the frozen copies, never the
	// current checkout, whose SDK provider is intentionally changing.
	return pins
}

fn compiler_root(bundle stage.Bundle) !map[string]string {
	pins := object(bundle, 'compiler-root-inputs.json')!
	if pins.len == 0 { return error('complete restored compiler inputs required') }
	for path, pin in pins {
		if !path.starts_with(bundle.root + '/compiler-root/')
			|| bundle.files[path.all_after(bundle.root + '/')] or { '' } != pin {
			return error('compiler input outside exact frozen root')
		}
	}
	return pins
}

fn native_sources(bundle stage.Bundle) !map[string]string {
	origins := object(bundle, 'native/source-origins.json')!
	pins := object(bundle, 'native/current-inputs.json')!
	if origins.len != 91 || pins.len != 92 { return error('exact 91 native origins and 92 inputs required') }
	mut expected := map[string]string{}
	mut copies := ['native/atlframework/ws_generated.v']
	for name, origin in origins {
		if !name.ends_with('.v') || os.file_name(origin) != name
			|| os.dir(origin) !in [repo + 'build-support/android/atlframework', repo + 'build-support/android/nativews'] {
			return error('native origin outside exact production source roots')
		}
		path := 'native/atlframework/' + name
		expected[origin] = bundle.files[path] or { return error('frozen native source copy absent') }
		copies << path
	}
	expected[repo + 'build-support/android/nativews/bindings.txt'] = bundle.files['native/bindings.txt']!
	if expected != pins || subtree(bundle.files, 'native/atlframework/').keys().sorted() != copies.sorted() {
		return error('complete native input/copy membership or hash differs')
	}
	return pins
}

fn headers(bundle stage.Bundle) !map[string]string {
	pins := object(bundle, 'native/consumed-headers.json')!
	if pins.len != 58 { return error('exactly 58 consumed C/header inputs required') }
	mut owned := []string{}
	for path, pin in pins {
		if path != os.real_path(path) || stage.hash(path)! != pin { return error('consumed C/header input changed') }
		if path.starts_with(bundle.root + '/native/') {
			relative := path.all_after(bundle.root + '/')
			if bundle.files[relative] or { '' } != pin { return error('owned native header is not sealed') }
			owned << relative
		}
	}
	if owned.sorted() != ['native/android-native.c', 'native/androidfw_c_api.h', 'native/sqlite3.h',
		'native/stb_image.h', 'native/stb_truetype.h'] { return error('exact five owned C/header inputs required') }
	return pins
}

fn sdk_profile(before stage.Bundle, after stage.Bundle) ! {
	if ![successor_seal, successor_jar, successor_dex].all(stage.valid_pin(it))
		|| before.files['api-impl.jar']! != sdk_jar || before.files['classes.dex']! != sdk_dex
		|| after.files['api-impl.jar']! != successor_jar || after.files['classes.dex']! != successor_dex {
		return error('completed SDK manifest/JAR/DEX pins required')
	}
	for name, expected in {'profile': 'traffic-stats-2117', 'baseline_path': sdk_root,
		'baseline_manifest_sha256': sdk_seal, 'baseline_api_impl_sha256': sdk_jar,
		'api_impl_sha256': successor_jar, 'classes_dex_sha256': successor_dex,
		'compiler_sha256': stage.compiler_seal} {
		if stage.text_field(after.receipt, name)! != expected { return error('exact TrafficStats SDK profile differs: ' + name) }
	}
	if json2.encode(after.receipt['class_count']!) != '2117'
		|| json2.decode[[]string](json2.encode(after.receipt['changed_classes']!))! != [traffic_stats]
		|| json2.decode[[]string](json2.encode(after.receipt['added_classes']!))!.len != 0
		|| json2.decode[map[string]int](json2.encode(after.receipt['changed_method_counts']!))! != {traffic_stats: 2}
		|| json2.decode[map[string]int](json2.encode(after.receipt['added_method_counts']!))! != {traffic_stats: 2}
		|| json2.decode[map[string][]string](json2.encode(after.receipt['added_fields']!))!
			!= {traffic_stats: ['.field private static uids:Ljava/lang/ThreadLocal;']} {
		return error('exact one-class two-changed/two-added/one-private-field SDK receipt required')
	}
	exact_sdk_delta(canonical_classes(before)!, canonical_classes(after)!)!
}

fn self_test() ! {
	mut consumed := map[string]string{}
	mut native_files := map[string]string{}
	mut before := map[string]string{}
	mut after := map[string]string{}
	for path, pair in permitted_pairs() {
		consumed[path] = pair.old_raw
		native_files['framework/' + path] = pair.old_raw
		before[path] = pair.old_raw
		before['new-dex/' + path.all_after('smali/')] = pair.old_canonical
		after[path] = pair.new_raw
		after['new-dex/' + path.all_after('smali/')] = pair.new_canonical
	}
	for i in 0 .. 68 {
		path := 'smali/other/' + i.str() + '.smali'
		consumed[path] = 'a'.repeat(64)
		native_files['framework/' + path] = 'a'.repeat(64)
		before[path] = 'a'.repeat(64)
		before['new-dex/' + path.all_after('smali/')] = 'a'.repeat(64)
		after[path] = 'a'.repeat(64)
		after['new-dex/' + path.all_after('smali/')] = 'a'.repeat(64)
	}
	if consumed_classes(consumed, native_files, before, after)!.len != 70 { return error('complete consumed positive failed') }
	mut controls := 0
	for path in consumed.keys() {
		canonical := 'new-dex/' + path.all_after('smali/')
		for case in 0 .. 10 {
			mut bad_consumed := consumed.clone()
			mut bad_native := native_files.clone()
			mut bad_before := before.clone()
			mut bad_after := after.clone()
			match case {
				0 { bad_consumed.delete(path) }
				1 { bad_native.delete('framework/' + path) }
				2 { bad_before.delete(path) }
				3 { bad_before.delete(canonical) }
				4 { bad_after.delete(path) }
				5 { bad_after.delete(canonical) }
				6 { bad_after[path] = 'b'.repeat(64) }
				7 { bad_after[canonical] = 'b'.repeat(64) }
				8 { bad_before[canonical] = 'b'.repeat(64); bad_after[canonical] = 'b'.repeat(64); bad_after[path] = 'b'.repeat(64) }
				else { bad_consumed[path] = 'b'.repeat(64); bad_native['framework/' + path] = 'b'.repeat(64); bad_before[path] = 'b'.repeat(64) }
			}
			consumed_classes(bad_consumed, bad_native, bad_before, bad_after) or { controls++; continue }
			return error('consumed missing-copy/raw/canonical/pinned-pair mutation accepted')
		}
	}
	for case in 0 .. 4 {
		mut bad := native_files.clone()
		mut bad_consumed := consumed.clone()
		match case {
			0 { bad['framework/smali/unlisted.smali'] = 'a'.repeat(64) }
			1 { bad_consumed['smali/extra.smali'] = 'a'.repeat(64) }
			2 { bad_consumed.delete('smali/other/0.smali'); bad_consumed['smali/' + traffic_stats] = 'a'.repeat(64) }
			else { bad['framework/smali/other/0.smali'] = 'b'.repeat(64) }
		}
		consumed_classes(bad_consumed, bad, before, after) or { controls++; continue }
		return error('unlisted, extra or TrafficStats native consumed class accepted')
	}
	mut old_classes := {traffic_stats: 'a'.repeat(64)}
	for i in 0 .. 2116 { old_classes['other/' + i.str() + '.smali'] = 'a'.repeat(64) }
	mut new_classes := old_classes.clone()
	new_classes[traffic_stats] = 'b'.repeat(64)
	exact_sdk_delta(old_classes, new_classes)!
	for case in 0 .. 5 {
		mut bad := new_classes.clone()
		match case {
			0 { bad[traffic_stats] = old_classes[traffic_stats]! }
			1 { bad['other/0.smali'] = 'b'.repeat(64) }
			2 { bad.delete(traffic_stats) }
			3 { bad['extra.smali'] = 'a'.repeat(64) }
			else { bad.delete('other/0.smali'); bad['substitution.smali'] = 'a'.repeat(64) }
		}
		exact_sdk_delta(old_classes, bad) or { controls++; continue }
		return error('SDK-only class-scope mutation accepted')
	}
	good := '.class public Landroid/net/TrafficStats;\n.super Ljava/lang/Object;\n' +
		'.field private static uids:Ljava/lang/ThreadLocal;\n.method public static getThreadStatsUid()I\n.locals 1\nconst/4 v0, -1\nreturn v0\n.end method\n'
	no_native_traffic(good)!
	if declarations(good)! != declarations(good.replace('\n', '\n  '))! { return error('declaration whitespace positive failed') }
	for bad in [good.replace('public static getThread', 'public static native getThread'),
		good + '.method\tpublic static native extra()V\n.end method\n',
		good.replace('Landroid/net/TrafficStats;', 'Lother/TrafficStats;'), good + '.end method\n',
		good.replace('.end method', ''), good + '.method public static broken()V\n',
		good.replace('.method public static ', '.method public static duplicate()V\n.method public static ')] {
		if bad == good { return error('inactive TrafficStats native-declaration mutation') }
		no_native_traffic(bad) or { controls++; continue }
		return error('native or malformed TrafficStats declaration accepted')
	}
	mut spec := ''
	for path in consumed.keys() { spec += path.all_after('smali/').all_before_last('.smali') + '|method|body\n' }
	if binding_classes(spec)! != consumed.keys().sorted() { return error('complete binding positive failed') }
	for bad in [spec + spec.split_into_lines()[0] + '\n', spec + 'android/net/TrafficStats|method|body\n',
		spec + 'malformed\n', spec + 'other/extra|method|body\n', spec.all_after('\n')] {
		if bad == spec { return error('inactive binding mutation') }
		binding_classes(bad) or { controls++; continue }
		return error('duplicate, missing, extra or TrafficStats native binding accepted')
	}
	println('TRAFFIC-STATS-UID-NATIVE-SELFTEST-PASS controls=' + controls.str() + ' exact-four-pins native70 canonical2116 unchanged-Java-ABI no-TrafficStats-JNI')
}

fn run(new_sdk_root string, output string) ! {
	if ![successor_seal, successor_jar, successor_dex].all(stage.valid_pin(it))
		|| new_sdk_root != os.real_path(new_sdk_root) || !new_sdk_root.starts_with(state + 'combined-account-webview-traffic-stats-')
		|| os.exists(output) || os.is_link(output) || !output.starts_with(state)
		|| os.real_path(os.dir(output)) != os.dir(output)
		|| [native_root, sdk_root, new_sdk_root].any(output.starts_with(it + '/')) {
		return error('pinned completed SDK and fresh canonical external output outside all input bundles required')
	}
	native := stage.load_bundle(native_root, native_seal)!
	old_sdk := stage.load_bundle(sdk_root, sdk_seal)!
	new_sdk := stage.load_bundle(new_sdk_root, successor_seal)!
	// Retain strict historical provenance. No receipt is rewritten to suggest
	// this DSO was compiled against the successor SDK.
	stage.verify_native(native, old_sdk)!
	if native.files['build.json']! != native_build || native.files['native/libvinix-android-native.so']! != native_dso {
		return error('exact retained native build receipt and DSO required')
	}
	sdk_profile(old_sdk, new_sdk)!
	consumed := object(native, 'framework/consumed-smali.json')!
	proof := consumed_classes(consumed, native.files, old_sdk.files, new_sdk.files)!
	bindings := os.read_file(native.root + '/native/bindings.txt')!
	if binding_classes(bindings)! != consumed.keys().sorted() { return error('native binding classes differ from complete consumed inventory') }
	for path in consumed.keys() {
		canonical := 'new-dex/' + path.all_after('smali/')
		shape := declarations(os.read_file(native.root + '/framework/' + path)!)!
		for source in [old_sdk.root + '/' + path, old_sdk.root + '/' + canonical,
			new_sdk.root + '/' + path, new_sdk.root + '/' + canonical] {
			if declarations(os.read_file(source)!)! != shape { return error('native class metadata, fields or method declarations changed: ' + path) }
		}
	}
	for bundle in [old_sdk, new_sdk] {
		for prefix in ['smali/', 'new-dex/'] { no_native_traffic(os.read_file(bundle.root + '/' + prefix + traffic_stats)!)! }
	}
	generated := os.read_file(native.root + '/native/atlframework/ws_generated.v')!
	exports := json2.decode[[]string](os.read_file(native.root + '/native/exports.json')!)!
	if generated.contains('Java_android_net_TrafficStats_') || exports.len != 721
		|| exports.any(it.starts_with('Java_android_net_TrafficStats_')) { return error('exact retained JNI exports excluding TrafficStats required') }
	inputs := native_sources(native)!
	generator := frozen_closure(native, 'native-generator', 340)!
	builder := frozen_closure(native, 'builder', 660)!
	compiler := compiler_root(native)!
	consumed_headers := headers(native)!
	elf := stage.inspect_elf(os.read_bytes(native.root + '/native/libvinix-android-native.so')!)!
	for bundle in [native, old_sdk, new_sdk] { stage.recheck(bundle)! }
	if native_sources(native)! != inputs || frozen_closure(native, 'native-generator', 340)! != generator
		|| frozen_closure(native, 'builder', 660)! != builder || compiler_root(native)! != compiler
		|| headers(native)! != consumed_headers { return error('complete frozen native inputs changed during readback') }
	os.write_file(output, json2.encode({
		'kind': json2.Any('vinix-traffic-stats-uid-native-readback-v1'),
		'native_root': json2.Any(native.root), 'native_manifest_sha256': json2.Any(native.seal),
		'native_build_sha256': json2.Any(native_build), 'native_dso_sha256': json2.Any(native_dso),
		'original_framework_root': json2.Any(old_sdk.root), 'original_framework_manifest_sha256': json2.Any(old_sdk.seal),
		'framework_root': json2.Any(new_sdk.root), 'framework_manifest_sha256': json2.Any(new_sdk.seal),
		'framework_jar_sha256': json2.Any(successor_jar), 'framework_dex_sha256': json2.Any(successor_dex),
		'consumed_class_pins': json2.decode[json2.Any](json2.encode(proof))!,
		'permitted_raw_formatting_pairs': json2.decode[json2.Any](json2.encode(permitted_pairs()))!,
		'native_bindings_sha256': json2.Any(native.files['native/bindings.txt']!),
		'generated_jni_sha256': json2.Any(native.files['native/atlframework/ws_generated.v']!),
		'generated_c_sha256': json2.Any(native.files['native/android-native.c']!),
		'exports_sha256': json2.Any(native.files['native/exports.json']!),
		'consumed_headers_sha256': json2.Any(native.files['native/consumed-headers.json']!),
		'needed': json2.decode[json2.Any](json2.encode(elf.needed))!,
		'canonical_native_class_count': json2.Any(proof.len), 'unchanged_other_canonical_class_count': json2.Any(2116),
		'native_unchanged': json2.Any(true), 'complete_inventory_rechecks': json2.Any(true),
	}, prettify: true) + '\n')!
	println('TRAFFIC-STATS-UID-NATIVE-READBACK-PASS retained-DSO original-SDK-coupling native70-canonical-unchanged raw-pairs2 exports721 headers58 origins91 inputs92 generator340 builder660 canonical2116-unchanged complete-rechecks')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len != 3 { eprintln('usage: traffic-stats-uid-native-readback NEW_SDK FRESH_EXTERNAL_JSON | --self-test'); exit(2) }
	run(os.args[1], os.args[2]) or { eprintln(err); exit(1) }
}
