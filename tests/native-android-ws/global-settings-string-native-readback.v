// SPDX-License-Identifier: GPL-2.0-or-later
// Retain the complete process-package JNI producer and its direct SDK coupling.
// This successor changes only the Java Global settings class, outside that ABI.
module main

import json2
import mapsaccountstage as stage
import os

const state = '/Users/alex/.local/state/vinix/android/'
const repo = '/Users/alex/code/vinix/'
const native_root = state + 'current-native-build-2026-11-04-process-packages-r1'
const native_seal = '0b8ad44d408b90824a69fa7d42c9376965eaa34a93dc81b056050ef227bc3d7f'
const native_dso = 'b69c62304448c1aa0fd5f0cc660acf81cfdd8614b280dad691f53a07d8abcc5f'
const native_build = 'b2235db3cebb559f8aef6aea9693beaea4db59022c2cbca89e9cdb7e548e830b'
const sdk_root = state + 'combined-account-webview-process-packages-framework-2026-11-04-r2'
const sdk_seal = '4a354ead173048b39fb26cce709922f8954e27e53e2d3a5d92ecdf427db0645d'
const sdk_build = 'a72f6b55ea908182d7d4fd331a71290c62eb8367cc9cd3250d6eefb65b696335'
const sdk_jar = '875f854ddf662dcaf55ebe05df06f5833eb5ca1e15f94066ffdf0fef18e829a8'
const sdk_dex = '6e7f03d2fe6951d172f04bbd67993f9e8e00f23a4e794994849b3555e8d77837'
const successor_root = state + 'combined-account-webview-global-settings-string-framework-2026-11-05-r1'
const successor_seal = 'cadfaa0105eb24580f1cdcef590f707e52aab334e9d7bf164524a403f1b43cbc'
const successor_build = '29300cf133e8786b1d7e80a101129d6664a0ce6a0af5315e7eee39ab97d57c37'
const successor_jar = '9207dab7a6a37e09fb049bb636ba6ebad3e63e43bfe7fd95821f67fc2aebeeb7'
const successor_dex = 'ac3f264e0dc77918845bb6ab2015e8c37724cbfaa47339f86f55e5750f7ccc32'
const global_settings = 'android/provider/Settings$Global.smali'

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
		|| global_settings !in before || delta(before, after).keys() != [global_settings] {
		return error('exactly Global settings must change among the same 2117 canonical classes')
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

// The process-package native producer consumed canonical copies already. Each
// of its seventy raw and canonical classes must match across both complete SDKs.
// Historical formatting exceptions belong to the unchanged predecessor proof.
fn consumed_classes(consumed map[string]string, native_files map[string]string,
	before map[string]string, after map[string]string) !map[string]ClassPins {
	if consumed.len != 70 || 'smali/' + global_settings in consumed
		|| subtree(native_files, 'framework/smali/').keys().sorted() != consumed.keys().map('framework/' + it).sorted() {
		return error('exact original 70 native-consumed copies, excluding Global settings, required')
	}
	mut result := map[string]ClassPins{}
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
			|| pin != old_canonical || old_canonical != new_canonical || new_raw != new_canonical {
			return error('all 70 native raw/canonical inputs must remain identical without formatting exceptions')
		}
		result[path] = actual
	}
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

fn no_native_global(source string) ! {
	shape := declarations(source)!
	method_headers := source.split_into_lines().filter(it.fields().len > 0 && it.fields()[0] == '.method')
	if shape.filter(it.starts_with('.class ')) != ['.class public final Landroid/provider/Settings$Global;']
		|| method_headers.any('native' in it.fields()) {
		return error('Global settings must remain a Java-only class outside the native ABI')
	}
}

fn binding_classes(source string) ![]string {
	mut result := map[string]bool{}
	mut rows := map[string]bool{}
	for line in source.split_into_lines() {
		if line.trim_space() == '' || line.starts_with('#') { continue }
		parts := line.split('|')
		if parts.len != 3 || parts[0] == '' || parts[1] == '' || parts[2] == '' || line in rows
			|| !stage.relative_file(parts[0] + '.smali') || parts[0] == 'android/provider/Settings$Global' {
			return error('safe original binding rows excluding Global settings required')
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
	if ![successor_seal, successor_build, successor_jar, successor_dex].all(stage.valid_pin(it))
		|| before.root != sdk_root || before.seal != sdk_seal || after.root != successor_root || after.seal != successor_seal
		|| before.files['build.json']! != sdk_build || before.files['api-impl.jar']! != sdk_jar || before.files['classes.dex']! != sdk_dex
		|| after.files['build.json']! != successor_build || after.files['api-impl.jar']! != successor_jar || after.files['classes.dex']! != successor_dex {
		return error('completed exact SDK manifest/build/JAR/DEX pins required')
	}
	for name, expected in {'profile': 'global-settings-string-2117', 'baseline_path': sdk_root,
		'baseline_manifest_sha256': sdk_seal, 'baseline_api_impl_sha256': sdk_jar,
		'api_impl_sha256': successor_jar, 'classes_dex_sha256': successor_dex,
		'compiler_sha256': stage.compiler_seal} {
		if stage.text_field(after.receipt, name)! != expected { return error('exact Global settings string SDK profile differs: ' + name) }
	}
	if json2.encode(after.receipt['class_count']!) != '2117'
		|| json2.decode[[]string](json2.encode(after.receipt['changed_classes']!))! != [global_settings]
		|| json2.decode[[]string](json2.encode(after.receipt['added_classes']!))!.len != 0
		|| json2.decode[map[string]int](json2.encode(after.receipt['changed_method_counts']!))! != {global_settings: 0}
		|| json2.decode[map[string]int](json2.encode(after.receipt['added_method_counts']!))! != {global_settings: 1}
		|| json2.decode[map[string][]string](json2.encode(after.receipt['added_fields']!))!.len != 0 {
		return error('exact one-class added-writer, zero changed methods/fields/classes SDK receipt required')
	}
	exact_sdk_delta(canonical_classes(before)!, canonical_classes(after)!)!
}

fn self_test() ! {
	mut consumed := map[string]string{}
	mut native_files := map[string]string{}
	mut before := map[string]string{}
	mut after := map[string]string{}
	for i in 0 .. 70 {
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
			return error('consumed missing-copy/raw/canonical/no-exception mutation accepted')
		}
	}
	for case in 0 .. 4 {
		mut bad := native_files.clone()
		mut bad_consumed := consumed.clone()
		match case {
			0 { bad['framework/smali/unlisted.smali'] = 'a'.repeat(64) }
			1 { bad_consumed['smali/extra.smali'] = 'a'.repeat(64) }
			2 { bad_consumed.delete('smali/other/0.smali'); bad_consumed['smali/' + global_settings] = 'a'.repeat(64) }
			else { bad['framework/smali/other/0.smali'] = 'b'.repeat(64) }
		}
		consumed_classes(bad_consumed, bad, before, after) or { controls++; continue }
		return error('unlisted, extra or Global settings native consumed class accepted')
	}
	mut old_classes := {global_settings: 'a'.repeat(64)}
	for i in 0 .. 2116 { old_classes['other/' + i.str() + '.smali'] = 'a'.repeat(64) }
	mut new_classes := old_classes.clone()
	new_classes[global_settings] = 'b'.repeat(64)
	exact_sdk_delta(old_classes, new_classes)!
	for case in 0 .. 5 {
		mut bad := new_classes.clone()
		match case {
			0 { bad[global_settings] = old_classes[global_settings]! }
			1 { bad['other/0.smali'] = 'b'.repeat(64) }
			2 { bad.delete(global_settings) }
			3 { bad['extra.smali'] = 'a'.repeat(64) }
			else { bad.delete('other/0.smali'); bad['substitution.smali'] = 'a'.repeat(64) }
		}
		exact_sdk_delta(old_classes, bad) or { controls++; continue }
		return error('SDK-only class-scope mutation accepted')
	}
	good := '.class public final Landroid/provider/Settings$Global;\n.super Landroid/provider/Settings$NameValueTable;\n' +
		'.field public static final CONTENT_URI:Landroid/net/Uri;\n.method public static putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z\n.registers 3\nconst/4 v0, 0x0\nreturn v0\n.end method\n'
	no_native_global(good)!
	if declarations(good)! != declarations(good.replace('\n', '\n  '))! { return error('declaration whitespace positive failed') }
	for bad in [good.replace('public static putString', 'public static native putString'),
		good + '.method\tpublic static native extra()V\n.end method\n',
		good.replace('Landroid/provider/Settings$Global;', 'Landroid/provider/Settings$Secure;'), good + '.end method\n',
		good.replace('.end method', ''), good + '.method public static broken()V\n',
		good.replace('.method public static ', '.method public static duplicate()V\n.method public static ')] {
		if bad == good { return error('inactive Global settings native-declaration mutation') }
		no_native_global(bad) or { controls++; continue }
		return error('native or malformed Global settings declaration accepted')
	}
	mut spec := ''
	for path in consumed.keys() { spec += path.all_after('smali/').all_before_last('.smali') + '|method|body\n' }
	if binding_classes(spec)! != consumed.keys().sorted() { return error('complete binding positive failed') }
	for bad in [spec + spec.split_into_lines()[0] + '\n', spec + 'android/provider/Settings$Global|method|body\n',
		spec + 'malformed\n', spec + 'other/extra|method|body\n', spec.all_after('\n')] {
		if bad == spec { return error('inactive binding mutation') }
		binding_classes(bad) or { controls++; continue }
		return error('duplicate, missing, extra or Global settings native binding accepted')
	}
	println('GLOBAL-SETTINGS-STRING-NATIVE-SELFTEST-PASS controls=' + controls.str() + ' no-formatting-exceptions native70 canonical2116 unchanged-Java-ABI no-Global-JNI')
}

fn run(new_sdk_root string, output string) ! {
	if ![successor_seal, successor_build, successor_jar, successor_dex].all(stage.valid_pin(it))
		|| new_sdk_root != successor_root || new_sdk_root != os.real_path(new_sdk_root)
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
		for prefix in ['smali/', 'new-dex/'] { no_native_global(os.read_file(bundle.root + '/' + prefix + global_settings)!)! }
	}
	generated := os.read_file(native.root + '/native/atlframework/ws_generated.v')!
	exports := json2.decode[[]string](os.read_file(native.root + '/native/exports.json')!)!
	if generated.contains('Java_android_provider_Settings_00024Global_') || generated.contains('Settings$Global')
		|| exports.len != 721 || exports.any(it.starts_with('Java_android_provider_Settings_00024Global_')) {
		return error('exact retained JNI exports excluding Global settings required')
	}
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
		'kind': json2.Any('vinix-global-settings-string-native-readback-v1'),
		'native_root': json2.Any(native.root), 'native_manifest_sha256': json2.Any(native.seal),
		'native_build_sha256': json2.Any(native_build), 'native_dso_sha256': json2.Any(native_dso),
		'parent_framework_root': json2.Any(old_sdk.root), 'parent_framework_manifest_sha256': json2.Any(old_sdk.seal),
		'parent_framework_build_sha256': json2.Any(sdk_build),
		'parent_framework_jar_sha256': json2.Any(sdk_jar), 'parent_framework_dex_sha256': json2.Any(sdk_dex),
		'native_framework_manifest_sha256': json2.Any(old_sdk.seal),
		'framework_root': json2.Any(new_sdk.root), 'framework_manifest_sha256': json2.Any(new_sdk.seal),
		'framework_build_sha256': json2.Any(successor_build),
		'framework_jar_sha256': json2.Any(successor_jar), 'framework_dex_sha256': json2.Any(successor_dex),
		'consumed_class_pins': json2.decode[json2.Any](json2.encode(proof))!,
		'permitted_raw_formatting_pairs': json2.decode[json2.Any](json2.encode(map[string][]string{}))!,
		'native_source_delta': json2.decode[json2.Any](json2.encode(map[string][]string{}))!,
		'generated_c_function_delta': json2.decode[json2.Any](json2.encode(map[string][]string{}))!,
		'builder_helper_delta': json2.decode[json2.Any](json2.encode(map[string][]string{}))!,
		'consumed_headers_delta': json2.decode[json2.Any](json2.encode(map[string][]string{}))!,
		'native_bindings_sha256': json2.Any(native.files['native/bindings.txt']!),
		'generated_jni_sha256': json2.Any(native.files['native/atlframework/ws_generated.v']!),
		'generated_c_sha256': json2.Any(native.files['native/android-native.c']!),
		'exports_sha256': json2.Any(native.files['native/exports.json']!),
		'consumed_headers_sha256': json2.Any(native.files['native/consumed-headers.json']!),
		'needed': json2.decode[json2.Any](json2.encode(elf.needed))!,
		'canonical_native_class_count': json2.Any(proof.len), 'unchanged_parent_canonical_class_count': json2.Any(2116),
		'retained_native_unchanged': json2.Any(true), 'complete_inventory_rechecks': json2.Any(true),
	}, prettify: true) + '\n')!
	println('GLOBAL-SETTINGS-STRING-NATIVE-READBACK-PASS retained-process-DSO original-SDK-coupling native70-raw-canonical-unchanged raw-pairs0 exports721 headers58 origins91 inputs92 generator340 builder660 canonical2116-unchanged complete-rechecks')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len != 3 { eprintln('usage: global-settings-string-native-readback NEW_SDK FRESH_EXTERNAL_JSON | --self-test'); exit(2) }
	run(os.args[1], os.args[2]) or { eprintln(err); exit(1) }
}
