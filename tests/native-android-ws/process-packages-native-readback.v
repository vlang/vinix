// SPDX-License-Identifier: GPL-2.0-or-later
// Read back a fresh, coupled process-package SDK/native pair. Historical
// producers keep their original SDK coupling and complete inventories.
module main

import crypto.sha256
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
const traffic_root = state + 'combined-account-webview-traffic-stats-framework-2026-11-04-r1'
const traffic_seal = 'bffa5dedc87d80979b09d517fcfb752b470d7f9e76a8e44bc24452f152d42025'
const traffic_jar = 'dd3af0444459410f28d20f04928e37a19eb6b076d433498b05eac9a922b49f0e'
const traffic_dex = '64c472412e52f91e5f40277f8077d251ee8de9b61558ecf8eec709227d97bde3'
// Filled only from completed SDK/native production and independent C review.
// Invalid constants prevent draft qualification against an arbitrary bundle.
const successor_root = state + 'combined-account-webview-process-packages-framework-2026-11-04-r2'
const successor_seal = '4a354ead173048b39fb26cce709922f8954e27e53e2d3a5d92ecdf427db0645d'
const successor_jar = '875f854ddf662dcaf55ebe05df06f5833eb5ca1e15f94066ffdf0fef18e829a8'
const successor_dex = '6e7f03d2fe6951d172f04bbd67993f9e8e00f23a4e794994849b3555e8d77837'
const fresh_native_root = state + 'current-native-build-2026-11-04-process-packages-r1'
const fresh_native_seal = '0b8ad44d408b90824a69fa7d42c9376965eaa34a93dc81b056050ef227bc3d7f'
const fresh_native_dso = 'b69c62304448c1aa0fd5f0cc660acf81cfdd8614b280dad691f53a07d8abcc5f'
const fresh_native_build = 'b2235db3cebb559f8aef6aea9693beaea4db59022c2cbca89e9cdb7e548e830b'
const fresh_native_c = 'e04800dcc13f7dddfa34ee3e135cf7c9df1acba33b2cc6bb7f6983555dcd8aa8'
const reviewed_running_c = 'd43aed9f589856ee5877c4a9ec4b843dc68459eab6a06a4c28c5a911dd1e4f2a'
const importance_before = 'd46cacc7df6b7633d65a6341ed80787ad837e367ed89472e7a2bda2988b879ce'
const importance_after = 'e02a4a4a29682bda67c6702fc0dc5eee728553d66bebd5b8a60eab12660c11a1'
const traffic_stats = 'android/net/TrafficStats.smali'
const process_info = 'android/app/ActivityManager$RunningAppProcessInfo.smali'
const package_field = '.field public pkgList:[Ljava/lang/String;'

// The builder imports the SDK provider module. Only measured, independently
// reviewed changes are admitted; an unresolved map deliberately fails closed.
fn permitted_builder_delta() map[string][]string {
	return {
		repo + 'tests/native-android-tools/androidtools/framework_activity_manager.v': [
			'8bad80cd655997fe12f99d5afe7b2f881b76e1aee42e6ea44526d35894431f8e',
			'8e57ed7e4f164059a54e5746754ff14c93d7d557813a66c6ad02cd958022c3f8']
		repo + 'tests/native-android-tools/androidtools/framework_atomic_file.v': [
			'3d7244523d1efcbaff1c4f471097379351dc8b620c7a2113cb6297a36f7347c8',
			'c06d12cf549d6e8b23e17f7eb9e1bd6545ee1bf0f0d4348fa811fc687b2c7e2e']
	}
}

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

fn exact_sdk_delta(before map[string]string, after map[string]string, target string) ! {
	if before.len != 2117 || before.keys().sorted() != after.keys().sorted()
		|| target !in before || delta(before, after).keys() != [target] {
		return error('exactly the selected class must change among the same 2117 canonical classes')
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
	if consumed.len != 70 || 'smali/' + traffic_stats in consumed || 'smali/' + process_info in consumed
		|| subtree(native_files, 'framework/smali/').keys().sorted() != consumed.keys().map('framework/' + it).sorted() {
		return error('exact original 70 consumed copies, excluding TrafficStats and process info, required')
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

struct ClassParts {
	metadata []string
	methods map[string]string
}

fn class_parts(source string) !ClassParts {
	mut metadata := []string{}
	mut methods := map[string]string{}
	mut body := []string{}
	mut signature := ''
	for line in source.split_into_lines() {
		text := line.trim_space()
		if text.starts_with('.method ') {
			if signature != '' { return error('nested method in field-only class') }
			signature = text.all_after_last(' ')
			if signature in methods { return error('duplicate method in field-only class') }
		}
		if signature != '' {
			body << line
			if text == '.end method' {
				methods[signature] = body.join('\n')
				body = []string{}
				signature = ''
			}
		} else if text != '' && !text.starts_with('#') {
			if text == '.end method' { return error('stray method terminator in field-only class') }
			metadata << text
		}
	}
	if signature != '' { return error('unterminated method in field-only class') }
	return ClassParts{metadata, methods}
}

fn field_only(before string, after string) ! {
	old, new := class_parts(before)!, class_parts(after)!
	if old.methods.len == 0 || old.methods != new.methods || package_field in old.metadata
		|| new.metadata.filter(it == package_field).len != 1
		|| old.metadata != new.metadata.filter(it != package_field)
		|| old.metadata.filter(it.starts_with('.class ')) != ['.class public Landroid/app/ActivityManager$RunningAppProcessInfo;']
		|| old.metadata.filter(it.starts_with('.super ')) != ['.super Ljava/lang/Object;'] {
		return error('only one public instance String[] pkgList field may change in the complete class')
	}
	if declarations(after)!.any(it.starts_with('.method ') && 'native' in it.fields()) {
		return error('process info must retain Java-only method declarations')
	}
}

fn binding_classes(source string) ![]string {
	mut result := map[string]bool{}
	mut rows := map[string]bool{}
	for line in source.split_into_lines() {
		if line.trim_space() == '' || line.starts_with('#') { continue }
		parts := line.split('|')
		if parts.len != 3 || parts[0] == '' || parts[1] == '' || parts[2] == '' || line in rows
			|| !stage.relative_file(parts[0] + '.smali') || parts[0] in ['android/net/TrafficStats', process_info.all_before_last('.smali')] {
			return error('safe original binding rows excluding both Java-only targets required')
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

fn normalized_closure(bundle stage.Bundle, label string, count int) !map[string]string {
	mut result := map[string]string{}
	for path, pin in frozen_closure(bundle, label, count)! {
		name := if path.starts_with(bundle.root + '/compiler-root/') {
			'@compiler/' + path.all_after(bundle.root + '/compiler-root/')
		} else { path }
		if name in result { return error('normalized helper collision') }
		result[name] = pin
	}
	return result
}

fn normalized_compiler(bundle stage.Bundle) !map[string]string {
	mut result := map[string]string{}
	for path, pin in compiler_root(bundle)! { result[path.all_after(bundle.root + '/compiler-root/')] = pin }
	return result
}

fn normalized_headers(bundle stage.Bundle) !map[string]string {
	mut result := map[string]string{}
	for path, pin in headers(bundle)! {
		name := if path.starts_with(bundle.root + '/native/') { '@native/' + path.all_after(bundle.root + '/native/') } else { path }
		if name in result { return error('normalized consumed-header collision') }
		result[name] = pin
	}
	return result
}

fn command(bundle stage.Bundle, name string) ![]string {
	value := json2.decode[map[string]json2.Any](os.read_file(bundle.root + '/commands/' + name + '.json')!)!
	if json2.encode(value['exit_code']!) != '0' { return error('successful exact native command required') }
	return json2.decode[[]string](json2.encode(value['argv']!))!
}

fn importance_scope(before string, after string) ! {
	start := 'fn ws_running_processes(e voidptr) voidptr {\n'
	end := '\n// Called with the VinixUidImportance class monitor held'
	if sha256.sum(before.bytes()).hex() != importance_before || sha256.sum(after.bytes()).hex() != importance_after
		|| before.count(start) != 1 || after.count(start) != 1 || before.count(end) != 1 || after.count(end) != 1 {
		return error('exact independently reviewed process-query source pair required')
	}
	old_begin := before.index(start) or { return error('original process-query source absent') }
	new_begin := after.index(start) or { return error('successor process-query source absent') }
	old_end := before.index(end) or { return error('original process-query boundary absent') }
	new_end := after.index(end) or { return error('successor process-query boundary absent') }
	if old_begin >= old_end || new_begin >= new_end
		|| before[..old_begin] + '@@RUNNING@@' + before[old_end..] != after[..new_begin] + '@@RUNNING@@' + after[new_end..] {
		return error('importance.v changed beyond ws_running_processes; memory-state and all other helpers must remain exact')
	}
}

// Lexical matching admits exactly one complete generated C function. Quotes,
// character literals and comments cannot hide a change to adjacent functions.
fn c_function(source string, signature string) !string {
	anchor := signature + ' {'
	if source.count(anchor) != 1 { return error('one exact generated function definition required') }
	start := source.index(anchor) or { return error('generated C function missing') }
	mut offset := start + signature.len + 1
	mut depth := 0
	mut quote := u8(0)
	mut escape := false
	mut line_comment := false
	mut block_comment := false
	for offset < source.len {
		ch := source[offset]
		next := if offset + 1 < source.len { source[offset + 1] } else { u8(0) }
		if line_comment {
			if ch == `\n` { line_comment = false }
		} else if block_comment {
			if ch == `*` && next == `/` { block_comment = false; offset++ }
		} else if quote != 0 {
			if escape { escape = false } else if ch == `\\` { escape = true } else if ch == quote { quote = 0 }
		} else if ch == `/` && next == `/` { line_comment = true; offset++
		} else if ch == `/` && next == `*` { block_comment = true; offset++
		} else if ch == `"` || ch == `'` { quote = ch
		} else if ch == `{` { depth++
		} else if ch == `}` {
			depth--
			if depth == 0 {
				mut end := offset + 1
				if end >= source.len || source[end] != `\n` { return error('generated C function newline required') }
				end++
				if end < source.len && source[end] == `\n` { end++ }
				return source[start..end]
			}
			if depth < 0 { return error('unbalanced generated C function') }
		}
		offset++
	}
	return error('unterminated generated C function')
}

fn c_delta(before string, after string, reviewed_pin string) !map[string][]string {
	signature := 'void* atlframework__ws_running_processes(void* e)'
	old := c_function(before, signature)!
	new := c_function(after, signature)!
	if !stage.valid_pin(reviewed_pin) || sha256.sum(new.bytes()).hex() != reviewed_pin || old == new
		|| new.count('atlframework__ws_memory_state(e, info);') != 1
		|| new.count('"pkgList", "[Ljava/lang/String;"') != 1 || new.count('"packageName"') != 1
		|| new.contains('"processName"') || old.contains('"pkgList"') {
		return error('exact independently reviewed C package-array body required')
	}
	if before.replace(old, '@@RUNNING@@\n\n') != after.replace(new, '@@RUNNING@@\n\n') {
		return error('generated C changed outside ws_running_processes, including memory-state or another helper')
	}
	return {'ws_running_processes': [sha256.sum(old.bytes()).hex(), reviewed_pin]}
}

fn admitted_builder_delta(actual map[string][]string, expected map[string][]string) ! {
	if expected.len == 0 || actual != expected { return error('exact independently reviewed builder helper delta required') }
	for path, pair in expected {
		if !path.starts_with(repo + 'tests/native-android-tools/androidtools/') || !path.ends_with('.v')
			|| pair.len != 2 || !stage.valid_pin(pair[0]) || !stage.valid_pin(pair[1]) || pair[0] == pair[1] {
			return error('resolved exact existing provider helper pin pair required')
		}
	}
}

fn sdk_profile(before stage.Bundle, after stage.Bundle) ! {
	if ![successor_seal, successor_jar, successor_dex].all(stage.valid_pin(it))
		|| before.files['api-impl.jar']! != traffic_jar || before.files['classes.dex']! != traffic_dex
		|| after.files['api-impl.jar']! != successor_jar || after.files['classes.dex']! != successor_dex {
		return error('completed SDK manifest/JAR/DEX pins required')
	}
	for name, expected in {'profile': 'process-packages-2117', 'baseline_path': traffic_root,
		'baseline_manifest_sha256': traffic_seal, 'baseline_api_impl_sha256': traffic_jar,
		'api_impl_sha256': successor_jar, 'classes_dex_sha256': successor_dex,
		'compiler_sha256': stage.compiler_seal} {
		if stage.text_field(after.receipt, name)! != expected { return error('exact field-only process-packages SDK profile differs: ' + name) }
	}
	if json2.encode(after.receipt['class_count']!) != '2117'
		|| json2.decode[[]string](json2.encode(after.receipt['changed_classes']!))! != [process_info]
		|| json2.decode[[]string](json2.encode(after.receipt['added_classes']!))!.len != 0
		|| json2.decode[map[string]int](json2.encode(after.receipt['changed_method_counts']!))! != {process_info: 0}
		|| json2.decode[map[string]int](json2.encode(after.receipt['added_method_counts']!))! != {process_info: 0}
		|| json2.decode[map[string][]string](json2.encode(after.receipt['added_fields']!))!
			!= {process_info: [package_field]} {
		return error('exact one-class zero-method-change and one-public-instance-field SDK receipt required')
	}
	exact_sdk_delta(canonical_classes(before)!, canonical_classes(after)!, process_info)!
	old := os.read_file(before.root + '/new-dex/' + process_info)!
	for prefix in ['smali/', 'new-dex/'] { field_only(old, os.read_file(after.root + '/' + prefix + process_info)!)! }
}

fn fresh_scope_self_test() ! {
	old := '.class public Landroid/app/ActivityManager$RunningAppProcessInfo;\n.super Ljava/lang/Object;\n'
		+ '.field public pid:I\n.field public uid:I\n.field public processName:Ljava/lang/String;\n'
		+ '.method public constructor <init>()V\n.registers 1\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n'
	good := old + package_field + '\n'
	field_only(old, good)!
	mut controls := 0
	for bad in [old, good + package_field + '\n', good.replace(package_field, '.field private pkgList:[Ljava/lang/String;'),
		good.replace(package_field, '.field public static pkgList:[Ljava/lang/String;'),
		good.replace(package_field, '.field public pkgList:Ljava/lang/String;'),
		good.replace('pid:I', 'pid:J'), good.replace('uid:I', 'uid:J'),
		good.replace('processName:Ljava/lang/String;', 'name:Ljava/lang/String;'),
		good.replace('return-void', 'nop\nreturn-void'), good.replace('public constructor', 'private constructor'),
		good.replace('.registers 1', '.registers 2'), good.replace('.super Ljava/lang/Object;', '.super Ljava/lang/Throwable;'),
		good + '.field public unrelated:I\n', good + '.method public static extra()V\n.registers 0\nreturn-void\n.end method\n'] {
		if bad == good { return error('inactive field-only mutation') }
		field_only(old, bad) or { controls++; continue }
		return error('process-info field-only, metadata or complete method preservation mutation accepted')
	}
	if _ := field_only(good, good) { return error('preexisting pkgList field accepted') }
	controls++
	signature := 'void* atlframework__ws_running_processes(void* e)'
	old_function := signature + ' {\nreturn old_list;\n}\n\n'
	new_function := signature + ' {\n'
		+ 'get_field("packageName");\natlframework__ws_memory_state(e, info);\n'
		+ 'set_field("pkgList", "[Ljava/lang/String;", packages);\nreturn new_list;\n}\n\n'
	prefix := 'int untouched = 7;\nvoid atlframework__ws_memory_state(void* e, void* info) { return; }\n'
	trailer := 'void atlframework__ws_save(void) { return; }\n'
	before, after := prefix + old_function + trailer, prefix + new_function + trailer
	pin := sha256.sum(new_function.bytes()).hex()
	c_delta(before, after, pin)!
	for bad in [after.replace('untouched = 7', 'untouched = 8'), after.replace('void* info) { return;', 'void* info) { abort();'),
		after.replace('ws_save(void) { return;', 'ws_save(void) { abort();'), after + 'void unrelated() {}\n',
		after.replace('"packageName"', '"processName"'), after.replace('"pkgList"', '"wrongField"'),
		after.replace('[Ljava/lang/String;', 'Ljava/lang/String;'), after.replace('return new_list;', 'return wrong_list;'),
		after.replace('atlframework__ws_memory_state(e, info);', 'atlframework__ws_memory_state(e, other);'),
		after.replace(signature, 'void* atlframework__ws_running_processes(int e)'), after + new_function] {
		if bad == after { return error('inactive generated C mutation') }
		c_delta(before, bad, pin) or { controls++; continue }
		return error('process-query body or surrounding generated C mutation accepted')
	}
	for bad_pin in ['', 'f'.repeat(64)] {
		c_delta(before, after, bad_pin) or { controls++; continue }
		return error('unreviewed generated C body pin accepted')
	}
	for bad in [signature + ' {\n"unterminated }\n', signature + ' {\n/* unterminated }\n', signature + ' {\nreturn value;\n'] {
		c_function(bad, signature) or { controls++; continue }
		return error('unterminated generated C lexical state accepted')
	}
	lexical := new_function.replace(signature + ' {\n', signature + ' {\n// } ignored\n/* { ignored */\nconst char* s = "}";\nchar c = \'}\';\n')
	c_delta(before, prefix + lexical + trailer, sha256.sum(lexical.bytes()).hex())!
	path := repo + 'tests/native-android-tools/androidtools/example.v'
	expected := {path: ['a'.repeat(64), 'b'.repeat(64)]}
	admitted_builder_delta(expected, expected)!
	for bad in [map[string][]string{}, {path: ['b'.repeat(64), 'a'.repeat(64)]},
		{path: ['a'.repeat(64), 'c'.repeat(64)]}, {path: ['a'.repeat(64), 'b'.repeat(64)], repo + 'tests/native-android-tools/androidtools/extra.v': ['a'.repeat(64), 'b'.repeat(64)]}] {
		admitted_builder_delta(bad, expected) or { controls++; continue }
		return error('unreviewed builder-helper delta accepted')
	}
	for bad in [{path: ['', 'b'.repeat(64)]}, {path: ['a'.repeat(64), 'a'.repeat(64)]},
		{repo + 'outside/example.v': ['a'.repeat(64), 'b'.repeat(64)]}] {
		admitted_builder_delta(bad, bad) or { controls++; continue }
		return error('unresolved, unchanged or unrelated helper pin pair accepted')
	}
	println('PROCESS-PACKAGES-FRESH-SCOPE-SELFTEST-PASS controls=' + controls.str() + ' one-public-field exact-methods reviewed-C-body one-C-function memory-state-preserved exact-builder-pairs')
}

fn self_test() ! {
	fresh_scope_self_test()!
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
	exact_sdk_delta(old_classes, new_classes, traffic_stats)!
	for case in 0 .. 5 {
		mut bad := new_classes.clone()
		match case {
			0 { bad[traffic_stats] = old_classes[traffic_stats]! }
			1 { bad['other/0.smali'] = 'b'.repeat(64) }
			2 { bad.delete(traffic_stats) }
			3 { bad['extra.smali'] = 'a'.repeat(64) }
			else { bad.delete('other/0.smali'); bad['substitution.smali'] = 'a'.repeat(64) }
		}
		exact_sdk_delta(old_classes, bad, traffic_stats) or { controls++; continue }
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
	println('PROCESS-PACKAGES-COMPATIBILITY-SELFTEST-PASS controls=' + controls.str() + ' exact-four-pins native70 canonical2116 unchanged-Java-ABI no-Java-only-target-JNI')
}

fn inspection_disjoint(output string, roots []string) ! {
	if roots.any(output == it || output.starts_with(it + '/') || it.starts_with(output + '/')) {
		return error('diagnostic output must not overlap any input bundle')
	}
}

fn inspection_scope_self_test() ! {
	roots := [state + 'diagnostic-old-input', state + 'diagnostic-new-input']
	inspection_disjoint(state + 'diagnostic-output', roots)!
	mut controls := 0
	for root in roots {
		for bad in [root, root + '/output', os.dir(root)] {
			inspection_disjoint(bad, roots) or { controls++; continue }
			return error('diagnostic equal, nested or ancestor output accepted')
		}
	}
	println('PROCESS-PACKAGES-INSPECTION-SCOPE-SELFTEST-PASS controls=' + controls.str() + ' disjoint-output diagnostic-only')
}

// Diagnostics expose candidate bytes for independent review. They cannot fill
// reviewed_running_c or permitted_builder_delta(), and never call run().
fn inspect_fresh(output string) ! {
	if ![sdk_seal, sdk_jar, sdk_dex, traffic_seal, traffic_jar, traffic_dex, successor_seal, successor_jar, successor_dex,
		native_seal, native_dso, native_build, fresh_native_seal, fresh_native_dso,
		fresh_native_build, fresh_native_c].all(stage.valid_pin(it))
		|| successor_root != os.real_path(successor_root) || !successor_root.starts_with(state + 'combined-account-webview-process-packages-')
		|| fresh_native_root != os.real_path(fresh_native_root) || !fresh_native_root.starts_with(state + 'current-native-build-')
		|| os.exists(output) || os.is_link(output) || !output.starts_with(state)
		|| os.real_path(os.dir(output)) != os.dir(output) {
		return error('diagnostic requires exact native/SDK literals and a fresh canonical directory outside all five bundles')
	}
	inspection_disjoint(output, [native_root, sdk_root, traffic_root, successor_root, fresh_native_root])!
	native := stage.load_bundle(native_root, native_seal)!
	fresh := stage.load_bundle(fresh_native_root, fresh_native_seal)!
	old_sdk := stage.load_bundle(sdk_root, sdk_seal)!
	new_sdk := stage.load_bundle(successor_root, successor_seal)!
	stage.verify_native(native, old_sdk)!
	stage.verify_native(fresh, new_sdk)!
	if native.files['build.json']! != native_build || native.files['native/libvinix-android-native.so']! != native_dso
		|| fresh.files['build.json']! != fresh_native_build || fresh.files['native/libvinix-android-native.so']! != fresh_native_dso
		|| fresh.files['native/android-native.c']! != fresh_native_c || fresh_native_dso == native_dso {
		return error('diagnostic native artifacts differ from completed exact producer pins')
	}
	if old_sdk.files['api-impl.jar']! != sdk_jar || old_sdk.files['classes.dex']! != sdk_dex
		|| new_sdk.files['api-impl.jar']! != successor_jar || new_sdk.files['classes.dex']! != successor_dex {
		return error('diagnostic requires the literal original and successor SDK artifact identities')
	}
	signature := 'void* atlframework__ws_running_processes(void* e)'
	old_c := os.read_file(native.root + '/native/android-native.c')!
	new_c := os.read_file(fresh.root + '/native/android-native.c')!
	old_function := c_function(old_c, signature)!
	new_function := c_function(new_c, signature)!
	if old_function == new_function
		|| old_c.replace(old_function, '@@RUNNING@@\n\n') != new_c.replace(new_function, '@@RUNNING@@\n\n') {
		return error('diagnostic requires one changed process-query C function and exact surrounding C bytes')
	}
	old_builder := normalized_closure(native, 'builder', 660)!
	new_builder := normalized_closure(fresh, 'builder', 660)!
	candidate := delta(old_builder, new_builder)
	candidate_json := json2.encode(candidate, prettify: true) + '\n'
	for bundle in [native, fresh, old_sdk, new_sdk] { stage.recheck(bundle)! }
	if normalized_closure(native, 'builder', 660)! != old_builder
		|| normalized_closure(fresh, 'builder', 660)! != new_builder {
		return error('diagnostic complete frozen builder inputs changed during readback')
	}
	files := {
		'old-c-function.c': sha256.sum(old_function.bytes()).hex()
		'new-c-function.c': sha256.sum(new_function.bytes()).hex()
		'candidate-builder-delta.json': sha256.sum(candidate_json.bytes()).hex()
	}
	os.mkdir(output)!
	os.write_file(output + '/old-c-function.c', old_function)!
	os.write_file(output + '/new-c-function.c', new_function)!
	os.write_file(output + '/candidate-builder-delta.json', candidate_json)!
	os.write_file(output + '/metadata.json', json2.encode({
		'kind': json2.Any('vinix-process-packages-native-inspection-v1'),
		'diagnostic_only': json2.Any(true), 'qualification': json2.Any(false),
		'scope': json2.Any('Candidate extraction for independent review only; no production C/helper pins are selected or accepted'),
		'previous_native_root': json2.Any(native.root), 'previous_native_manifest_sha256': json2.Any(native.seal),
		'previous_native_build_sha256': json2.Any(native_build), 'previous_native_dso_sha256': json2.Any(native_dso),
		'previous_generated_c_sha256': json2.Any(native.files['native/android-native.c']!),
		'native_root': json2.Any(fresh.root), 'native_manifest_sha256': json2.Any(fresh.seal),
		'native_build_sha256': json2.Any(fresh_native_build), 'native_dso_sha256': json2.Any(fresh_native_dso),
		'generated_c_sha256': json2.Any(fresh_native_c),
		'original_framework_root': json2.Any(sdk_root), 'original_framework_manifest_sha256': json2.Any(sdk_seal),
		'framework_root': json2.Any(successor_root), 'framework_manifest_sha256': json2.Any(successor_seal),
		'framework_jar_sha256': json2.Any(successor_jar), 'framework_dex_sha256': json2.Any(successor_dex),
		'old_c_function_sha256': json2.Any(files['old-c-function.c']!),
		'candidate_c_function_sha256': json2.Any(files['new-c-function.c']!),
		'candidate_builder_delta_sha256': json2.Any(files['candidate-builder-delta.json']!),
		'candidate_builder_delta_count': json2.Any(candidate.len),
		'old_builder_input_count': json2.Any(old_builder.len), 'new_builder_input_count': json2.Any(new_builder.len),
		'outside_c_function_unchanged': json2.Any(true), 'complete_native_inventory_rechecks': json2.Any(true),
		'complete_coupled_sdk_inventory_rechecks': json2.Any(true),
		'files_sha256': json2.decode[json2.Any](json2.encode(files))!,
	}, prettify: true) + '\n')!
	println('PROCESS-PACKAGES-NATIVE-DIAGNOSTIC-ONLY extracted-C-functions candidate-builder-delta complete-two-native-and-coupled-SDK-rechecks qualification=false')
}

fn run(output string) ! {
	if ![successor_seal, successor_jar, successor_dex, fresh_native_seal, fresh_native_dso, fresh_native_build, fresh_native_c, reviewed_running_c].all(stage.valid_pin(it))
		|| successor_root != os.real_path(successor_root) || !successor_root.starts_with(state + 'combined-account-webview-process-packages-')
		|| fresh_native_root != os.real_path(fresh_native_root) || !fresh_native_root.starts_with(state + 'current-native-build-')
		|| os.exists(output) || os.is_link(output) || !output.starts_with(state)
		|| os.real_path(os.dir(output)) != os.dir(output)
		|| [native_root, sdk_root, traffic_root, successor_root, fresh_native_root].any(output.starts_with(it + '/')) {
		return error('completed exact fresh SDK/native pins and output outside all five bundles required')
	}
	native := stage.load_bundle(native_root, native_seal)!
	fresh := stage.load_bundle(fresh_native_root, fresh_native_seal)!
	old_sdk := stage.load_bundle(sdk_root, sdk_seal)!
	traffic_sdk := stage.load_bundle(traffic_root, traffic_seal)!
	new_sdk := stage.load_bundle(successor_root, successor_seal)!
	// Both native producers retain their exact original/direct SDK coupling.
	stage.verify_native(native, old_sdk)!
	stage.verify_native(fresh, new_sdk)!
	if native.files['build.json']! != native_build || native.files['native/libvinix-android-native.so']! != native_dso {
		return error('exact historical native build receipt and DSO required')
	}
	if fresh.files['build.json']! != fresh_native_build || fresh.files['native/libvinix-android-native.so']! != fresh_native_dso
		|| fresh.files['native/android-native.c']! != fresh_native_c
		|| fresh_native_dso == native_dso || fresh_native_seal == native_seal { return error('exact changed fresh native production required') }
	if old_sdk.files['api-impl.jar']! != sdk_jar || old_sdk.files['classes.dex']! != sdk_dex
		|| traffic_sdk.files['api-impl.jar']! != traffic_jar || traffic_sdk.files['classes.dex']! != traffic_dex {
		return error('exact complete original and TrafficStats SDKs required')
	}
	exact_sdk_delta(canonical_classes(old_sdk)!, canonical_classes(traffic_sdk)!, traffic_stats)!
	sdk_profile(traffic_sdk, new_sdk)!
	if delta(canonical_classes(old_sdk)!, canonical_classes(new_sdk)!).keys().sorted() != [process_info, traffic_stats].sorted() {
		return error('only TrafficStats and process info may differ from the original native SDK')
	}
	consumed := object(native, 'framework/consumed-smali.json')!
	proof := consumed_classes(consumed, native.files, old_sdk.files, new_sdk.files)!
	fresh_consumed := object(fresh, 'framework/consumed-smali.json')!
	if fresh_consumed.keys().sorted() != consumed.keys().sorted()
		|| subtree(fresh.files, 'framework/smali/').keys().sorted() != fresh_consumed.keys().map('framework/' + it).sorted() {
		return error('fresh native must copy exactly the original 70 binding classes')
	}
	for path, pin in fresh_consumed {
		if fresh.files['framework/' + path] or { '' } != pin || new_sdk.files[path] or { '' } != pin {
			return error('fresh native consumed copy differs from its exact direct SDK')
		}
	}
	bindings := os.read_file(native.root + '/native/bindings.txt')!
	if binding_classes(bindings)! != consumed.keys().sorted() { return error('native binding classes differ from complete consumed inventory') }
	for path in consumed.keys() {
		canonical := 'new-dex/' + path.all_after('smali/')
		shape := declarations(os.read_file(native.root + '/framework/' + path)!)!
		for source in [old_sdk.root + '/' + path, old_sdk.root + '/' + canonical, traffic_sdk.root + '/' + canonical,
			new_sdk.root + '/' + path, new_sdk.root + '/' + canonical, fresh.root + '/framework/' + path] {
			if declarations(os.read_file(source)!)! != shape { return error('native class metadata, fields or method declarations changed: ' + path) }
		}
	}
	for bundle in [old_sdk, traffic_sdk, new_sdk] {
		for prefix in ['smali/', 'new-dex/'] { no_native_traffic(os.read_file(bundle.root + '/' + prefix + traffic_stats)!)! }
	}
	generated := os.read_file(native.root + '/native/atlframework/ws_generated.v')!
	exports := json2.decode[[]string](os.read_file(native.root + '/native/exports.json')!)!
	if generated.contains('Java_android_net_TrafficStats_') || exports.len != 721
		|| exports.any(it.starts_with('Java_android_net_TrafficStats_')) { return error('exact retained JNI exports excluding TrafficStats required') }
	inputs := native_sources(native)!
	fresh_inputs := native_sources(fresh)!
	if object(native, 'native/source-origins.json')! != object(fresh, 'native/source-origins.json')!
		|| delta(inputs, fresh_inputs) != {repo + 'build-support/android/nativews/importance.v': [importance_before, importance_after]} {
		return error('only the reviewed importance.v origin may change among 91 sources and 92 inputs')
	}
	importance_scope(os.read_file(native.root + '/native/atlframework/importance.v')!,
		os.read_file(fresh.root + '/native/atlframework/importance.v')!)!
	for name in ['baseline', 'baseline_sha256', 'compiler_library_baseline', 'compiler_library_sha256', 'compiler_source_policy'] {
		if native.receipt[name]! != fresh.receipt[name]! { return error('generic native baseline/library policy changed') }
	}
	for name in ['builder-source.v', 'native/bindings.txt', 'native/source-origins.json',
		'native/atlframework/ws_generated.v', 'native/exports.json', 'tools/find-v.sh',
		'native/androidfw_c_api.h', 'native/sqlite3.h', 'native/stb_image.h', 'native/stb_truetype.h',
		'reused-inputs.json', 'crosscompiler-specs.txt', 'compiler-library-sha256.json', 'compiler-library-origins.json'] {
		if native.files[name]! != fresh.files[name]! { return error('retained native ABI/toolchain input changed: ' + name) }
	}
	if binding_classes(os.read_file(fresh.root + '/native/bindings.txt')!)! != consumed.keys().sorted() {
		return error('fresh native binding membership changed')
	}
	generated_c_delta := c_delta(os.read_file(native.root + '/native/android-native.c')!,
		os.read_file(fresh.root + '/native/android-native.c')!, reviewed_running_c)!
	generator := normalized_closure(native, 'native-generator', 340)!
	fresh_generator := normalized_closure(fresh, 'native-generator', 340)!
	builder := normalized_closure(native, 'builder', 660)!
	fresh_builder := normalized_closure(fresh, 'builder', 660)!
	compiler := normalized_compiler(native)!
	fresh_compiler := normalized_compiler(fresh)!
	if generator != fresh_generator || compiler != fresh_compiler { return error('native generator or restored compiler source changed') }
	builder_delta := delta(builder, fresh_builder)
	admitted_builder_delta(builder_delta, permitted_builder_delta())!
	consumed_headers := normalized_headers(native)!
	fresh_headers := normalized_headers(fresh)!
	header_delta := delta(consumed_headers, fresh_headers)
	if header_delta != {'@native/android-native.c': [native.files['native/android-native.c']!, fresh.files['native/android-native.c']!]} {
		return error('only generated C may change among exact 58 normalized C/header inputs')
	}
	old_command, fresh_command := command(native, 'build-native')!, command(fresh, 'build-native')!
	if old_command.map(it.replace(native.root, '@native-root')) != fresh_command.map(it.replace(fresh.root, '@native-root')) {
		return error('strict native cross-link argv changed beyond owned output paths')
	}
	elf := stage.inspect_elf(os.read_bytes(native.root + '/native/libvinix-android-native.so')!)!
	fresh_elf := stage.inspect_elf(os.read_bytes(fresh.root + '/native/libvinix-android-native.so')!)!
	if elf.needed != fresh_elf.needed || elf.soname != fresh_elf.soname || elf.interpreter != fresh_elf.interpreter
		|| elf.runpath != fresh_elf.runpath { return error('fresh native ELF dependency identity changed') }
	for bundle in [native, fresh, old_sdk, traffic_sdk, new_sdk] { stage.recheck(bundle)! }
	if native_sources(native)! != inputs || native_sources(fresh)! != fresh_inputs
		|| normalized_closure(native, 'native-generator', 340)! != generator || normalized_closure(fresh, 'native-generator', 340)! != fresh_generator
		|| normalized_closure(native, 'builder', 660)! != builder || normalized_closure(fresh, 'builder', 660)! != fresh_builder
		|| normalized_compiler(native)! != compiler || normalized_compiler(fresh)! != fresh_compiler
		|| normalized_headers(native)! != consumed_headers || normalized_headers(fresh)! != fresh_headers {
		return error('complete original/fresh native inputs changed during readback')
	}
	os.write_file(output, json2.encode({
		'kind': json2.Any('vinix-process-packages-native-readback-v1'),
		'previous_native_root': json2.Any(native.root), 'previous_native_manifest_sha256': json2.Any(native.seal),
		'previous_native_build_sha256': json2.Any(native_build), 'previous_native_dso_sha256': json2.Any(native_dso),
		'native_root': json2.Any(fresh.root), 'native_manifest_sha256': json2.Any(fresh.seal),
		'native_build_sha256': json2.Any(fresh_native_build), 'native_dso_sha256': json2.Any(fresh_native_dso),
		'original_framework_root': json2.Any(old_sdk.root), 'original_framework_manifest_sha256': json2.Any(old_sdk.seal),
		'parent_framework_root': json2.Any(traffic_sdk.root), 'parent_framework_manifest_sha256': json2.Any(traffic_sdk.seal),
		'framework_root': json2.Any(new_sdk.root), 'framework_manifest_sha256': json2.Any(new_sdk.seal),
		'framework_jar_sha256': json2.Any(successor_jar), 'framework_dex_sha256': json2.Any(successor_dex),
		'consumed_class_pins': json2.decode[json2.Any](json2.encode(proof))!,
		'permitted_raw_formatting_pairs': json2.decode[json2.Any](json2.encode(permitted_pairs()))!,
		'native_source_delta': json2.decode[json2.Any](json2.encode(delta(inputs, fresh_inputs)))!,
		'generated_c_function_delta': json2.decode[json2.Any](json2.encode(generated_c_delta))!,
		'builder_helper_delta': json2.decode[json2.Any](json2.encode(builder_delta))!,
		'consumed_headers_delta': json2.decode[json2.Any](json2.encode(header_delta))!,
		'native_bindings_sha256': json2.Any(fresh.files['native/bindings.txt']!),
		'generated_jni_sha256': json2.Any(fresh.files['native/atlframework/ws_generated.v']!),
		'generated_c_sha256': json2.Any(fresh.files['native/android-native.c']!),
		'exports_sha256': json2.Any(fresh.files['native/exports.json']!),
		'consumed_headers_sha256': json2.Any(fresh.files['native/consumed-headers.json']!),
		'needed': json2.decode[json2.Any](json2.encode(fresh_elf.needed))!,
		'canonical_native_class_count': json2.Any(proof.len), 'unchanged_parent_canonical_class_count': json2.Any(2116),
		'unchanged_original_canonical_class_count': json2.Any(2115),
		'fresh_native_coupled_to_successor_sdk': json2.Any(true), 'complete_inventory_rechecks': json2.Any(true),
	}, prettify: true) + '\n')!
	println('PROCESS-PACKAGES-NATIVE-READBACK-PASS fresh-coupled-DSO origins91 inputs92 one-V-origin one-C-function native70-canonical-unchanged raw-pairs2 exports721 headers58 generator340 exact-builder-delta five-complete-rechecks')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or { eprintln(err); exit(1) }
		inspection_scope_self_test() or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 3 && os.args[1] == '--inspect-fresh' { inspect_fresh(os.args[2]) or { eprintln(err); exit(1) }; return }
	if os.args.len != 2 { eprintln('usage: process-packages-native-readback FRESH_EXTERNAL_JSON | --self-test | --inspect-fresh FRESH_EXTERNAL_DIRECTORY'); exit(2) }
	run(os.args[1]) or { eprintln(err); exit(1) }
}
