// SPDX-License-Identifier: GPL-2.0-or-later
// Read back fresh native production coupled to the default-network-active SDK.
// The Java scheduling hint changes one consumed class, never the native ABI.
module main

import json2
import mapsaccountstage as stage
import os

const state = '/Users/alex/.local/state/vinix/android/'
const repo = '/Users/alex/code/vinix/'
const native_root = state + 'current-native-build-2026-11-04-process-packages-r1'
const native_seal = '0b8ad44d408b90824a69fa7d42c9376965eaa34a93dc81b056050ef227bc3d7f'
const native_build = 'b2235db3cebb559f8aef6aea9693beaea4db59022c2cbca89e9cdb7e548e830b'
const native_dso = 'b69c62304448c1aa0fd5f0cc660acf81cfdd8614b280dad691f53a07d8abcc5f'
const native_c = 'e04800dcc13f7dddfa34ee3e135cf7c9df1acba33b2cc6bb7f6983555dcd8aa8'
const sdk_root = state + 'combined-account-webview-process-packages-framework-2026-11-04-r2'
const sdk_seal = '4a354ead173048b39fb26cce709922f8954e27e53e2d3a5d92ecdf427db0645d'
const sdk_build = 'a72f6b55ea908182d7d4fd331a71290c62eb8367cc9cd3250d6eefb65b696335'
const sdk_jar = '875f854ddf662dcaf55ebe05df06f5833eb5ca1e15f94066ffdf0fef18e829a8'
const sdk_dex = '6e7f03d2fe6951d172f04bbd67993f9e8e00f23a4e794994849b3555e8d77837'
const parent_root = state + 'combined-account-webview-global-settings-string-framework-2026-11-05-r1'
const parent_seal = 'cadfaa0105eb24580f1cdcef590f707e52aab334e9d7bf164524a403f1b43cbc'
const parent_build = '29300cf133e8786b1d7e80a101129d6664a0ce6a0af5315e7eee39ab97d57c37'
const parent_jar = '9207dab7a6a37e09fb049bb636ba6ebad3e63e43bfe7fd95821f67fc2aebeeb7'
const parent_dex = 'ac3f264e0dc77918845bb6ab2015e8c37724cbfaa47339f86f55e5750f7ccc32'

// Production remains closed until completed SDK/native output pins are filled
// from saved producer receipts. Self-tests never qualify an unresolved draft.
const successor_root = state + 'combined-account-webview-default-network-active-framework-2026-11-05-r1'
const successor_seal = ''
const successor_build = ''
const successor_jar = ''
const successor_dex = ''
const fresh_native_root = state + 'current-native-build-2026-11-05-default-network-active-r1'
const fresh_native_seal = ''
const fresh_native_build = ''
const fresh_native_dso = ''
const fresh_builder_count = 661

const connectivity = 'android/net/ConnectivityManager.smali'
const global_settings = 'android/provider/Settings$Global.smali'
const query_signature = 'isDefaultNetworkActive()Z'
const query_method = '.method public isDefaultNetworkActive()Z\n.registers 2\nconst/4 v0, 0x1\nreturn v0\n.end method'
const connectivity_before = '1fd6af85766920db5576fec29ced1331db5b20d914a8909819299116e9c30ec3'
const connectivity_raw_after = '0c907eb36f453d628ca1799b64fef3c537dce10f9296ed31540787997439fb0b'
const connectivity_canonical_after = 'a6a2b21fa2bfae7788d0690d47a746eea3f33a51c109b5c544d5eeead930236a'
const global_before = '871ce221551cfe2690de98ff93b68c2464aa7a35bbbb3ec3245be43bfa833456'
const global_after = '9023f901d1188223ccdf83e89016355eb2b41db4d40d9d7585908b3f8c28faf7'

fn permitted_builder_delta() map[string][]string {
	return {
		repo + 'tests/native-android-tools/androidtools/framework_classes.v': [
			'41058a6edb1dbf080b5839e6a10db9353b47e4fa9d55774af2d7bba9fb7f9a83',
			'23b8cd3a0f0f1b45909be0000c532691bd9ce8243d06495691dd66ee1b1fcbf7']
		repo + 'tests/native-android-tools/androidtools/framework_settings_global.v': [
			'495eba16970af0a89a12d542659f38d40cc20f391ceadf93333ff17776ed50e0',
			'07208bba49f9a283507b8da196aec55ec6277c23388710873606aa6eb83fc340']
		repo + 'tests/native-android-tools/androidtools/framework_default_network_active.v': [
			'', 'fc459a6cba2efacf8183de5945e9d12ea741d2deccc745da97d72a2cfd9bf51e']
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

fn exact_sdk_delta(before map[string]string, after map[string]string, targets []string) ! {
	if before.len != 2117 || before.keys().sorted() != after.keys().sorted()
		|| targets.len == 0 || targets.any(it !in before)
		|| delta(before, after).keys().sorted() != targets.sorted() {
		return error('exact selected class delta among the same 2117 canonical classes required')
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
	old_raw string
	old_canonical string
	new_raw string
	new_canonical string
}

fn connectivity_pins() ClassPins {
	return ClassPins{connectivity_before, connectivity_before, connectivity_raw_after, connectivity_canonical_after}
}

// The sole fixed pair is a Java method addition, not a normalization exception.
// Every other consumed raw/canonical class remains byte-identical in all SDKs.
fn consumed_classes(consumed map[string]string, native_files map[string]string,
	before map[string]string, parent map[string]string, after map[string]string, expected ClassPins) !map[string]ClassPins {
	target := 'smali/' + connectivity
	if consumed.len != 70 || target !in consumed || 'smali/' + global_settings in consumed
		|| ![expected.old_raw, expected.old_canonical, expected.new_raw, expected.new_canonical].all(stage.valid_pin(it))
		|| expected.old_raw != expected.old_canonical || expected.old_raw == expected.new_raw
		|| expected.old_canonical == expected.new_canonical
		|| subtree(native_files, 'framework/smali/').keys().sorted() != consumed.keys().map('framework/' + it).sorted() {
		return error('exact 70 consumed classes with one fixed ConnectivityManager Java addition required')
	}
	mut result := map[string]ClassPins{}
	for path, pin in consumed {
		if !path.starts_with('smali/') || !path.ends_with('.smali') || !stage.relative_file(path)
			|| native_files['framework/' + path] or { '' } != pin || before[path] or { '' } != pin {
			return error('native consumed copy differs from original coupled SDK')
		}
		canonical := 'new-dex/' + path.all_after('smali/')
		old_canonical := before[canonical] or { return error('original consumed canonical class absent') }
		new_raw := after[path] or { return error('successor consumed raw class absent') }
		new_canonical := after[canonical] or { return error('successor consumed canonical class absent') }
		actual := ClassPins{pin, old_canonical, new_raw, new_canonical}
		if ![pin, old_canonical, new_raw, new_canonical].all(stage.valid_pin(it))
			|| parent[path] or { '' } != pin || parent[canonical] or { '' } != old_canonical {
			return error('complete Global parent consumed copies must remain identical to original native SDK')
		}
		if path == target {
			if actual != expected { return error('exact four ConnectivityManager production hashes required') }
		} else if pin != old_canonical || old_canonical != new_canonical || new_raw != new_canonical {
			return error('other 69 native raw/canonical classes must remain exact without formatting exceptions')
		}
		result[path] = actual
	}
	return result
}

struct ClassParts {
	metadata []string
	methods map[string]string
}

fn class_parts(source string) !ClassParts {
	if source.contains('\x00') { return error('textual class source required') }
	mut metadata := []string{}
	mut methods := map[string]string{}
	mut body := []string{}
	mut signature := ''
	for line in source.split_into_lines() {
		parts := line.trim_space().fields()
		if parts.len == 0 || parts[0].starts_with('#') {
			if signature != '' { body << line }
			continue
		}
		text := parts.join(' ')
		if parts[0] == '.method' {
			if signature != '' || parts.len < 3 || !parts.last().contains('(') || !parts.last().contains(')') {
				return error('nested or malformed method declaration')
			}
			signature = parts.last()
			if signature in methods { return error('duplicate method declaration') }
		} else if parts[0].starts_with('.method') { return error('malformed method directive') }
		if signature != '' {
			if parts[0] in ['.class', '.super', '.field', '.implements'] { return error('class metadata inside method') }
			body << line
			if parts[0] == '.end' && parts.len > 1 && parts[1] == 'method' {
				if text != '.end method' { return error('malformed method terminator') }
				methods[signature] = body.join('\n')
				body = []string{}
				signature = ''
			}
		} else {
			if text == '.end method' { return error('stray method terminator') }
			metadata << text
		}
	}
	if signature != '' || methods.len == 0 { return error('complete class methods required') }
	return ClassParts{metadata, methods}
}

fn method_lines(source string) []string {
	return source.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#')).map(it.fields().join(' '))
}

fn native_declarations(parts ClassParts) []string {
	mut result := []string{}
	for _, body in parts.methods {
		first := body.split_into_lines()[0].fields()
		if 'native' in first { result << first.join(' ') }
	}
	return result.sorted()
}

fn method_only(before string, after string) ! {
	old, new := class_parts(before)!, class_parts(after)!
	if old.methods.len != 28 || new.methods.len != 29 || query_signature in old.methods
		|| query_signature !in new.methods || old.metadata != new.metadata
		|| old.metadata.filter(it.starts_with('.class ')) != ['.class public Landroid/net/ConnectivityManager;']
		|| old.metadata.filter(it.starts_with('.super ')) != ['.super Ljava/lang/Object;']
		|| old.metadata.filter(it.starts_with('.field ')).len != 4
		|| native_declarations(old) != ['.method protected native nativeGetNetworkAvailable()Z', '.method protected native nativeGetNetworkState()I']
		|| native_declarations(new) != native_declarations(old)
		|| method_lines(new.methods[query_signature]!) != method_lines(query_method) {
		return error('only one public virtual no-monitor activity hint may be added to exact ConnectivityManager shape')
	}
	for signature, method in old.methods {
		if new.methods[signature] or { '' } != method { return error('every existing method body and native declaration must remain exact') }
	}
}

fn declarations(source string) ![]string {
	parts := class_parts(source)!
	mut result := parts.metadata.filter(it.starts_with('.class ') || it.starts_with('.super ')
		|| it.starts_with('.implements ') || it.starts_with('.field '))
	if result.filter(it.starts_with('.class ')).len != 1 || result.filter(it.starts_with('.super ')).len != 1 {
		return error('complete class metadata required')
	}
	for _, body in parts.methods { result << body.split_into_lines()[0].fields().join(' ') }
	return result.sorted()
}

fn no_native_global(source string) ! {
	parts := class_parts(source)!
	if parts.metadata.filter(it.starts_with('.class ')) != ['.class public final Landroid/provider/Settings$Global;']
		|| native_declarations(parts).len != 0 { return error('Global settings must remain outside native declarations') }
}

fn binding_classes(source string) ![]string {
	mut result := map[string]bool{}
	mut rows := map[string]bool{}
	for line in source.split_into_lines() {
		if line.trim_space() == '' || line.starts_with('#') { continue }
		parts := line.split('|')
		if parts.len != 3 || parts[0] == '' || parts[1] == '' || parts[2] == '' || line in rows
			|| !stage.relative_file(parts[0] + '.smali') || parts[0] == global_settings.all_before_last('.smali') {
			return error('safe original binding rows excluding Global settings required')
		}
		rows[line] = true
		result['smali/' + parts[0] + '.smali'] = true
	}
	if result.len != 70 || 'smali/' + connectivity !in result { return error('exact original 70 bound classes including ConnectivityManager required') }
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
	return pins
}

fn compiler_root(bundle stage.Bundle) !map[string]string {
	pins := object(bundle, 'compiler-root-inputs.json')!
	if pins.len == 0 { return error('complete restored compiler inputs required') }
	for path, pin in pins {
		if !path.starts_with(bundle.root + '/compiler-root/') || bundle.files[path.all_after(bundle.root + '/')] or { '' } != pin {
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
			relative := path.all_after(bundle.root + '/native/')
			if bundle.files['native/' + relative] or { '' } != pin { return error('owned native header is not sealed') }
			owned << 'native/' + relative
		}
	}
	if owned.sorted() != ['native/android-native.c', 'native/androidfw_c_api.h', 'native/sqlite3.h', 'native/stb_image.h', 'native/stb_truetype.h'] {
		return error('exact five owned C/header inputs required')
	}
	return pins
}

fn normalized_closure(bundle stage.Bundle, label string, count int) !map[string]string {
	mut result := map[string]string{}
	for path, pin in frozen_closure(bundle, label, count)! {
		name := if path.starts_with(bundle.root + '/compiler-root/') { '@compiler/' + path.all_after(bundle.root + '/compiler-root/') } else { path }
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

fn admitted_builder_delta(actual map[string][]string, expected map[string][]string) ! {
	added := repo + 'tests/native-android-tools/androidtools/framework_default_network_active.v'
	if expected.len != 3 || expected.keys().sorted() != [added,
		repo + 'tests/native-android-tools/androidtools/framework_classes.v',
		repo + 'tests/native-android-tools/androidtools/framework_settings_global.v'].sorted()
		|| actual != expected { return error('exact three independently reviewed builder helper changes required') }
	for path, pair in expected {
		if pair.len != 2 || !stage.valid_pin(pair[1]) || (if path == added { pair[0] != '' } else {
			!stage.valid_pin(pair[0]) || pair[0] == pair[1]
		}) { return error('only the one named provider may be added; existing helpers require exact distinct pin pairs') }
	}
}

fn sdk_identity(bundle stage.Bundle, root string, seal string, build string, jar string, dex string) ! {
	if bundle.root != root || bundle.seal != seal || bundle.files['build.json']! != build
		|| bundle.files['api-impl.jar']! != jar || bundle.files['classes.dex']! != dex {
		return error('exact completed SDK manifest/build/JAR/DEX pins required')
	}
}

fn sdk_profile(before stage.Bundle, after stage.Bundle, name string, target string) ! {
	for key, expected in {'profile': name + '-2117', 'baseline_path': before.root,
		'baseline_manifest_sha256': before.seal, 'baseline_api_impl_sha256': before.files['api-impl.jar']!,
		'api_impl_sha256': after.files['api-impl.jar']!, 'classes_dex_sha256': after.files['classes.dex']!,
		'compiler_sha256': stage.compiler_seal} {
		if stage.text_field(after.receipt, key)! != expected { return error('exact SDK producer profile differs: ' + key) }
	}
	if json2.encode(after.receipt['class_count']!) != '2117'
		|| json2.decode[[]string](json2.encode(after.receipt['changed_classes']!))! != [target]
		|| json2.decode[[]string](json2.encode(after.receipt['added_classes']!))!.len != 0
		|| json2.decode[map[string]int](json2.encode(after.receipt['changed_method_counts']!))! != {target: 0}
		|| json2.decode[map[string]int](json2.encode(after.receipt['added_method_counts']!))! != {target: 1}
		|| json2.decode[map[string][]string](json2.encode(after.receipt['added_fields']!))!.len != 0 {
		return error('exact single added method with zero old method/field/class changes required')
	}
	exact_sdk_delta(canonical_classes(before)!, canonical_classes(after)!, [target])!
}

fn output_scope(output string, inputs []string) ! {
	if !output.starts_with(state) || !stage.relative_file(output.all_after(state)) || !output.ends_with('.json')
		|| inputs.any(output == it || output.starts_with(it + '/') || it.starts_with(output + '/')) {
		return error('fresh external JSON outside all complete input bundles required')
	}
}

fn production_pins() ! {
	if ![successor_seal, successor_build, successor_jar, successor_dex,
		fresh_native_seal, fresh_native_build, fresh_native_dso].all(stage.valid_pin(it))
		|| successor_root == parent_root || fresh_native_root == native_root || fresh_native_seal == native_seal {
		return error('completed exact fresh SDK/native production pins required')
	}
}

fn run(output string) ! {
	production_pins()!
	roots := [native_root, fresh_native_root, sdk_root, parent_root, successor_root]
	output_scope(output, roots)!
	if os.exists(output) || os.is_link(output) || os.real_path(os.dir(output)) != os.dir(output)
		|| roots.any(os.real_path(it) != it) { return error('canonical inputs and fresh canonical output required') }
	native := stage.load_bundle(native_root, native_seal)!
	fresh := stage.load_bundle(fresh_native_root, fresh_native_seal)!
	original := stage.load_bundle(sdk_root, sdk_seal)!
	parent := stage.load_bundle(parent_root, parent_seal)!
	successor := stage.load_bundle(successor_root, successor_seal)!
	stage.verify_native(native, original)!
	stage.verify_native(fresh, successor)!
	if native.files['build.json']! != native_build || native.files['native/libvinix-android-native.so']! != native_dso
		|| native.files['native/android-native.c']! != native_c || fresh.files['build.json']! != fresh_native_build
		|| fresh.files['native/libvinix-android-native.so']! != fresh_native_dso || fresh.files['native/android-native.c']! != native_c {
		return error('exact old/fresh native receipts and outputs with unchanged complete generated C required')
	}
	sdk_identity(original, sdk_root, sdk_seal, sdk_build, sdk_jar, sdk_dex)!
	sdk_identity(parent, parent_root, parent_seal, parent_build, parent_jar, parent_dex)!
	sdk_identity(successor, successor_root, successor_seal, successor_build, successor_jar, successor_dex)!
	sdk_profile(original, parent, 'global-settings-string', global_settings)!
	sdk_profile(parent, successor, 'default-network-active', connectivity)!
	exact_sdk_delta(canonical_classes(original)!, canonical_classes(successor)!, [global_settings, connectivity])!
	if original.files['new-dex/' + global_settings]! != global_before || parent.files['new-dex/' + global_settings]! != global_after
		|| successor.files['new-dex/' + global_settings]! != global_after { return error('qualified Global writer must remain exact') }
	consumed := object(native, 'framework/consumed-smali.json')!
	proof := consumed_classes(consumed, native.files, original.files, parent.files, successor.files, connectivity_pins())!
	fresh_consumed := object(fresh, 'framework/consumed-smali.json')!
	if fresh_consumed.keys().sorted() != consumed.keys().sorted()
		|| subtree(fresh.files, 'framework/smali/').keys().sorted() != fresh_consumed.keys().map('framework/' + it).sorted() {
		return error('fresh native must copy exactly the same 70 consumed classes')
	}
	for path, pin in fresh_consumed {
		if fresh.files['framework/' + path] or { '' } != pin || successor.files[path] or { '' } != pin {
			return error('fresh native consumed copy differs from direct successor SDK')
		}
	}
	for bundle in [native, fresh] {
		if binding_classes(os.read_file(bundle.root + '/native/bindings.txt')!)! != consumed.keys().sorted() {
			return error('native binding membership changed')
		}
	}
	for path in consumed.keys() {
		canonical := 'new-dex/' + path.all_after('smali/')
		old := os.read_file(native.root + '/framework/' + path)!
		for source in [original.root + '/' + path, original.root + '/' + canonical, parent.root + '/' + path, parent.root + '/' + canonical] {
			if os.read_file(source)! != old { return error('original and Global parent consumed source changed: ' + path) }
		}
		for source in [successor.root + '/' + path, successor.root + '/' + canonical, fresh.root + '/framework/' + path] {
			if path == 'smali/' + connectivity { method_only(old, os.read_file(source)!)! }
			else if os.read_file(source)! != old || declarations(os.read_file(source)!)! != declarations(old)! {
				return error('other consumed class metadata, fields or complete methods changed: ' + path)
			}
		}
	}
	for bundle in [original, parent, successor] {
		for prefix in ['smali/', 'new-dex/'] { no_native_global(os.read_file(bundle.root + '/' + prefix + global_settings)!)! }
	}
	inputs := native_sources(native)!
	fresh_inputs := native_sources(fresh)!
	if inputs != fresh_inputs || object(native, 'native/source-origins.json')! != object(fresh, 'native/source-origins.json')! {
		return error('all 91 native origins and 92 native inputs must remain exact')
	}
	for key in ['baseline', 'baseline_sha256', 'compiler_library_baseline', 'compiler_library_sha256', 'compiler_source_policy'] {
		if native.receipt[key]! != fresh.receipt[key]! { return error('native baseline or compiler policy changed') }
	}
	for path in ['builder-source.v', 'native/bindings.txt', 'native/source-origins.json', 'native/atlframework/ws_generated.v',
		'native/android-native.c', 'native/exports.json', 'tools/find-v.sh', 'native/androidfw_c_api.h', 'native/sqlite3.h',
		'native/stb_image.h', 'native/stb_truetype.h', 'reused-inputs.json', 'crosscompiler-specs.txt',
		'compiler-library-sha256.json', 'compiler-library-origins.json'] {
		if native.files[path]! != fresh.files[path]! { return error('native ABI, generated C or toolchain input changed: ' + path) }
	}
	generated := os.read_file(fresh.root + '/native/atlframework/ws_generated.v')!
	exports := json2.decode[[]string](os.read_file(fresh.root + '/native/exports.json')!)!
	if exports.len != 721 || generated.contains('Java_android_provider_Settings_00024Global_')
		|| generated.contains('Java_android_net_ConnectivityManager_isDefaultNetworkActive')
		|| exports.any(it.starts_with('Java_android_provider_Settings_00024Global_') || it.starts_with('Java_android_net_ConnectivityManager_isDefaultNetworkActive')) {
		return error('exact 721 exports with no new Java-only JNI entry required')
	}
	generator := normalized_closure(native, 'native-generator', 340)!
	fresh_generator := normalized_closure(fresh, 'native-generator', 340)!
	builder := normalized_closure(native, 'builder', 660)!
	fresh_builder := normalized_closure(fresh, 'builder', fresh_builder_count)!
	compiler := normalized_compiler(native)!
	fresh_compiler := normalized_compiler(fresh)!
	if generator != fresh_generator || compiler != fresh_compiler { return error('native generator or restored compiler changed') }
	builder_delta := delta(builder, fresh_builder)
	admitted_builder_delta(builder_delta, permitted_builder_delta())!
	consumed_headers := normalized_headers(native)!
	fresh_headers := normalized_headers(fresh)!
	if consumed_headers != fresh_headers { return error('all 58 consumed C/header inputs including generated C must remain exact') }
	old_command, fresh_command := command(native, 'build-native')!, command(fresh, 'build-native')!
	if old_command.map(it.replace(native.root, '@native-root')) != fresh_command.map(it.replace(fresh.root, '@native-root')) {
		return error('strict native cross-link argv changed beyond owned output paths')
	}
	elf := stage.inspect_elf(os.read_bytes(native.root + '/native/libvinix-android-native.so')!)!
	fresh_elf := stage.inspect_elf(os.read_bytes(fresh.root + '/native/libvinix-android-native.so')!)!
	if elf.needed != fresh_elf.needed || elf.soname != fresh_elf.soname || elf.interpreter != fresh_elf.interpreter || elf.runpath != fresh_elf.runpath {
		return error('native ELF dependency identity changed')
	}
	for bundle in [native, fresh, original, parent, successor] { stage.recheck(bundle)! }
	if native_sources(native)! != inputs || native_sources(fresh)! != fresh_inputs
		|| normalized_closure(native, 'native-generator', 340)! != generator || normalized_closure(fresh, 'native-generator', 340)! != fresh_generator
		|| normalized_closure(native, 'builder', 660)! != builder || normalized_closure(fresh, 'builder', fresh_builder_count)! != fresh_builder
		|| normalized_compiler(native)! != compiler || normalized_compiler(fresh)! != fresh_compiler
		|| normalized_headers(native)! != consumed_headers || normalized_headers(fresh)! != fresh_headers {
		return error('complete original/fresh inputs changed during readback')
	}
	value := {
		'kind': json2.Any('vinix-default-network-active-native-readback-v1')
		'previous_native_root': json2.Any(native.root), 'previous_native_manifest_sha256': json2.Any(native.seal)
		'previous_native_build_sha256': json2.Any(native_build), 'previous_native_dso_sha256': json2.Any(native_dso)
		'native_root': json2.Any(fresh.root), 'native_manifest_sha256': json2.Any(fresh.seal)
		'native_build_sha256': json2.Any(fresh_native_build), 'native_dso_sha256': json2.Any(fresh_native_dso)
		'native_framework_manifest_sha256': json2.Any(successor.seal)
		'original_framework_root': json2.Any(original.root), 'original_framework_manifest_sha256': json2.Any(original.seal)
		'parent_framework_root': json2.Any(parent.root), 'parent_framework_manifest_sha256': json2.Any(parent.seal)
		'framework_root': json2.Any(successor.root), 'framework_manifest_sha256': json2.Any(successor.seal)
		'framework_build_sha256': json2.Any(successor_build), 'framework_jar_sha256': json2.Any(successor_jar), 'framework_dex_sha256': json2.Any(successor_dex)
		'consumed_class_pins': json2.decode[json2.Any](json2.encode(proof))!
		'permitted_raw_formatting_pairs': json2.decode[json2.Any](json2.encode(map[string][]string{}))!
		'native_consumed_raw_delta': json2.decode[json2.Any](json2.encode(delta(consumed, fresh_consumed)))!
		'native_consumed_canonical_delta': json2.decode[json2.Any](json2.encode({connectivity: [connectivity_before, connectivity_canonical_after]}))!
		'native_source_delta': json2.decode[json2.Any](json2.encode(map[string][]string{}))!
		'generated_c_function_delta': json2.decode[json2.Any](json2.encode(map[string][]string{}))!
		'builder_helper_delta': json2.decode[json2.Any](json2.encode(builder_delta))!
		'consumed_headers_delta': json2.decode[json2.Any](json2.encode(map[string][]string{}))!
		'native_bindings_sha256': json2.Any(fresh.files['native/bindings.txt']!), 'generated_jni_sha256': json2.Any(fresh.files['native/atlframework/ws_generated.v']!)
		'generated_c_sha256': json2.Any(native_c), 'exports_sha256': json2.Any(fresh.files['native/exports.json']!)
		'consumed_headers_sha256': json2.Any(fresh.files['native/consumed-headers.json']!), 'needed': json2.decode[json2.Any](json2.encode(fresh_elf.needed))!
		'canonical_native_class_count': json2.Any(70), 'unchanged_native_consumed_class_count': json2.Any(69)
		'unchanged_parent_canonical_class_count': json2.Any(2116), 'unchanged_original_canonical_class_count': json2.Any(2115)
		'fresh_native_coupled_to_successor_sdk': json2.Any(true), 'native_abi_and_generated_c_unchanged': json2.Any(true)
		'complete_inventory_rechecks': json2.Any(true)
	}
	mut file := os.open_file(output, 'wx', 0o600)!
	defer { file.close() }
	file.write_string(json2.encode(value, prettify: true) + '\n')!
	println('DEFAULT-NETWORK-ACTIVE-NATIVE-READBACK-PASS fresh-coupled-DSO native70 one-Java-method native69-exact native-ABI-C-unchanged exports721 headers58 origins91 inputs92 generator340 exact-builder-delta five-complete-rechecks')
}

fn fixture_connectivity() string {
	mut source := '.class public Landroid/net/ConnectivityManager;\n.super Ljava/lang/Object;\n'
	for i in 0 .. 4 { source += '.field private field' + i.str() + ':I\n' }
	for i in 0 .. 26 { source += '.method public old' + i.str() + '()V\n.registers 1\nreturn-void\n.end method\n' }
	source += '.method protected native nativeGetNetworkAvailable()Z\n.end method\n.method protected native nativeGetNetworkState()I\n.end method\n'
	return source
}

fn self_test() ! {
	mut controls := 0
	old := fixture_connectivity()
	good := old + query_method + '\n'
	method_only(old, good)!
	method_only(old, old + query_method.replace('\n', '\n\t') + '\n')!
	for bad in [old, good + query_method + '\n', good + '.method public extra()V\n.registers 1\nreturn-void\n.end method\n',
		good.replace('public isDefaultNetworkActive', 'public static isDefaultNetworkActive'), good.replace('public isDefaultNetworkActive', 'private isDefaultNetworkActive'),
		good.replace('public isDefaultNetworkActive', 'public native isDefaultNetworkActive'), good.replace('public isDefaultNetworkActive', 'public final isDefaultNetworkActive'),
		good.replace('isDefaultNetworkActive()Z', 'isDefaultNetworkActive()I'), good.replace('const/4 v0, 0x1', 'const/4 v0, 0x0'),
		good.replace('const/4 v0, 0x1', 'invoke-virtual {p0}, Landroid/net/ConnectivityManager;->nativeGetNetworkAvailable()Z\nmove-result v0'),
		good.replace('const/4 v0, 0x1', 'nop\nconst/4 v0, 0x1'), good.replace('native nativeGetNetworkState()I', 'native nativeGetNetworkState()J'),
		good.replace('.field private field0:I', '.field public field0:I'), good.replace('old0()V', 'old0()I'),
		good.replace('.super Ljava/lang/Object;', '.super Ljava/lang/Throwable;'), good.replace('return-void', 'nop\nreturn-void'),
		good.replace('.method public old0()', '.method\tprivate old0()'), good + '.method\tpublic native hidden()V\n.end method\n',
		good + '.methodpublic broken()V\n.end method\n', good + '.end method\n', good.replace('.end method\n', ''),
		good.replace('.class public Landroid/net/ConnectivityManager;', '.class public Landroid/net/Other;')] {
		if bad == good { return error('inactive method-only control') }
		method_only(old, bad) or { controls++; continue }
		return error('CM method body/declaration/metadata preservation mutation accepted')
	}
	if _ := method_only(good, good) { return error('preexisting activity query accepted') }
	controls++
	mut consumed := map[string]string{}
	mut native_files := map[string]string{}
	mut before := map[string]string{}
	mut parent := map[string]string{}
	mut after := map[string]string{}
	for i in 0 .. 70 {
		path := if i == 0 { 'smali/' + connectivity } else { 'smali/other/' + i.str() + '.smali' }
		canonical := 'new-dex/' + path.all_after('smali/')
		consumed[path] = 'a'.repeat(64)
		native_files['framework/' + path] = 'a'.repeat(64)
		before[path] = 'a'.repeat(64); before[canonical] = 'a'.repeat(64)
		parent[path] = 'a'.repeat(64); parent[canonical] = 'a'.repeat(64)
		after[path] = if i == 0 { 'b'.repeat(64) } else { 'a'.repeat(64) }
		after[canonical] = if i == 0 { 'c'.repeat(64) } else { 'a'.repeat(64) }
	}
	expected := ClassPins{'a'.repeat(64), 'a'.repeat(64), 'b'.repeat(64), 'c'.repeat(64)}
	if consumed_classes(consumed, native_files, before, parent, after, expected)!.len != 70 { return error('70-class positive failed') }
	for path in consumed.keys() {
		canonical := 'new-dex/' + path.all_after('smali/')
		for case in 0 .. 13 {
			mut bad_consumed := consumed.clone(); mut bad_native := native_files.clone()
			mut bad_before := before.clone(); mut bad_parent := parent.clone(); mut bad_after := after.clone()
			match case {
				0 { bad_consumed.delete(path) }
				1 { bad_native.delete('framework/' + path) }
				2 { bad_before.delete(path) }
				3 { bad_before.delete(canonical) }
				4 { bad_after.delete(path) }
				5 { bad_after.delete(canonical) }
				6 { bad_after[path] = 'f'.repeat(64) }
				7 { bad_after[canonical] = 'f'.repeat(64) }
				8 { bad_before[canonical] = 'f'.repeat(64); bad_after[canonical] = 'f'.repeat(64); bad_after[path] = 'f'.repeat(64) }
				9 { bad_consumed[path] = 'f'.repeat(64); bad_native['framework/' + path] = 'f'.repeat(64); bad_before[path] = 'f'.repeat(64) }
				10 { bad_parent.delete(path) }
				11 { bad_parent.delete(canonical) }
				else { bad_parent[canonical] = 'f'.repeat(64) }
			}
			consumed_classes(bad_consumed, bad_native, bad_before, bad_parent, bad_after, expected) or { controls++; continue }
			return error('consumed class missing/copy/raw/canonical/parent mutation accepted')
		}
	}
	for case in 0 .. 4 {
		mut bad_native := native_files.clone(); mut bad_consumed := consumed.clone()
		match case {
			0 { bad_native['framework/smali/unlisted.smali'] = 'a'.repeat(64) }
			1 { bad_consumed['smali/extra.smali'] = 'a'.repeat(64) }
			2 { bad_consumed.delete('smali/other/1.smali'); bad_consumed['smali/' + global_settings] = 'a'.repeat(64) }
			else { bad_native['framework/smali/other/1.smali'] = 'f'.repeat(64) }
		}
		consumed_classes(bad_consumed, bad_native, before, parent, after, expected) or { controls++; continue }
		return error('extra or substituted consumed class accepted')
	}
	for bad in [ClassPins{'', expected.old_canonical, expected.new_raw, expected.new_canonical},
		ClassPins{expected.old_raw, 'f'.repeat(64), expected.new_raw, expected.new_canonical},
		ClassPins{expected.old_raw, expected.old_canonical, expected.old_raw, expected.new_canonical},
		ClassPins{expected.old_raw, expected.old_canonical, expected.new_raw, expected.old_canonical}] {
		consumed_classes(consumed, native_files, before, parent, after, bad) or { controls++; continue }
		return error('unresolved or unchanged CM pin pair accepted')
	}
	mut classes := {connectivity: 'a'.repeat(64)}
	for i in 0 .. 2116 { classes['other/' + i.str() + '.smali'] = 'a'.repeat(64) }
	mut changed := classes.clone(); changed[connectivity] = 'b'.repeat(64)
	exact_sdk_delta(classes, changed, [connectivity])!
	for case in 0 .. 5 {
		mut bad := changed.clone()
		match case {
			0 { bad[connectivity] = classes[connectivity]! }
			1 { bad['other/0.smali'] = 'b'.repeat(64) }
			2 { bad.delete(connectivity) }
			3 { bad['extra.smali'] = 'a'.repeat(64) }
			else { bad.delete('other/0.smali'); bad['substitution.smali'] = 'a'.repeat(64) }
		}
		exact_sdk_delta(classes, bad, [connectivity]) or { controls++; continue }
		return error('SDK class-set or target mutation accepted')
	}
	mut bindings := ''
	for path in consumed.keys() { bindings += path.all_after('smali/').all_before_last('.smali') + '|method|body\n' }
	if binding_classes(bindings)! != consumed.keys().sorted() { return error('binding positive failed') }
	for bad in [bindings + bindings.split_into_lines()[0] + '\n', bindings + 'android/provider/Settings$Global|method|body\n',
		bindings + 'malformed\n', bindings + 'other/extra|method|body\n', bindings.replace('android/net/ConnectivityManager', 'android/net/Other')] {
		binding_classes(bad) or { controls++; continue }
		return error('duplicate/missing/extra/malformed binding accepted')
	}
	global := '.class public final Landroid/provider/Settings$Global;\n.super Landroid/provider/Settings$NameValueTable;\n' +
		'.field public static final CONTENT_URI:Landroid/net/Uri;\n.method public static putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z\n.registers 3\nconst/4 v0, 0x0\nreturn v0\n.end method\n'
	no_native_global(global)!
	if declarations(global)! != declarations(global.replace('\n', '\n  '))! { return error('declaration indentation positive failed') }
	for bad in [global.replace('public static putString', 'public static native putString'),
		global + '.method\tpublic static native extra()V\n.end method\n',
		global.replace('Landroid/provider/Settings$Global;', 'Landroid/provider/Settings$Secure;'), global + '.end method\n',
		global.replace('.end method', ''), global + '.method public static broken()V\n',
		global.replace('.method public static ', '.method public static duplicate()V\n.method public static ')] {
		if bad == global { return error('inactive Global declaration control') }
		no_native_global(bad) or { controls++; continue }
		return error('native or malformed Global declaration accepted')
	}
	admitted_builder_delta(permitted_builder_delta(), permitted_builder_delta())!
	for case in 0 .. 7 {
		mut bad := permitted_builder_delta()
		added := repo + 'tests/native-android-tools/androidtools/framework_default_network_active.v'
		classes_path := repo + 'tests/native-android-tools/androidtools/framework_classes.v'
		match case {
			0 { bad.delete(added) }
			1 { bad[added] = ['a'.repeat(64), bad[added]![1]] }
			2 { bad[classes_path] = ['', bad[classes_path]![1]] }
			3 { bad[classes_path] = [bad[classes_path]![0], bad[classes_path]![0]] }
			4 { bad[added] = ['', 'invalid'] }
			5 { bad[repo + 'tests/native-android-tools/androidtools/unreviewed.v'] = ['', 'a'.repeat(64)] }
			else { bad.delete(added); bad[repo + 'tests/native-android-tools/androidtools/other.v'] = ['', 'a'.repeat(64)] }
		}
		admitted_builder_delta(bad, permitted_builder_delta()) or { controls++; continue }
		return error('unreviewed builder change accepted')
	}
	// A draft's expected map must itself fail closed. These controls reach
	// structural validation instead of failing only actual/expected equality.
	for case in 0 .. 7 {
		mut bad := permitted_builder_delta()
		added := repo + 'tests/native-android-tools/androidtools/framework_default_network_active.v'
		classes_path := repo + 'tests/native-android-tools/androidtools/framework_classes.v'
		match case {
			0 { bad.delete(added) }
			1 { bad[added] = ['a'.repeat(64), bad[added]![1]] }
			2 { bad[classes_path] = ['', bad[classes_path]![1]] }
			3 { bad[classes_path] = [bad[classes_path]![0], bad[classes_path]![0]] }
			4 { bad[added] = ['', 'invalid'] }
			5 { bad[repo + 'tests/native-android-tools/androidtools/unreviewed.v'] = ['', 'a'.repeat(64)] }
			else { bad.delete(added); bad[repo + 'tests/native-android-tools/androidtools/other.v'] = ['', 'a'.repeat(64)] }
		}
		admitted_builder_delta(bad, bad) or { controls++; continue }
		return error('unresolved or malformed independently reviewed builder map accepted')
	}
	for pair in [ []string{}, ['a'.repeat(64)], ['a'.repeat(64), 'b'.repeat(64), 'c'.repeat(64)] ] {
		mut bad := permitted_builder_delta()
		bad[repo + 'tests/native-android-tools/androidtools/framework_classes.v'] = pair
		admitted_builder_delta(bad, bad) or { controls++; continue }
		return error('builder helper pin pair with wrong cardinality accepted')
	}
	output_scope(state + 'proof/readback.json', [native_root, sdk_root])!
	output_scope(native_root + '-proof.json', [native_root, sdk_root])!
	for bad in [native_root, native_root + '/readback.json', sdk_root + '/nested/readback.json', repo + 'readback.json',
		state + '../readback.json', state + 'readback', state + 'line\nfeed.json'] {
		output_scope(bad, [native_root, sdk_root]) or { controls++; continue }
		return error('overlapping or unsafe output accepted')
	}
	println('DEFAULT-NETWORK-ACTIVE-NATIVE-SELFTEST-PASS controls=' + controls.str() + ' native70 one-fixed-CM-pair native69-exact public-Java-method-only no-native-ABI-change exact-builder-addition-and-pairs')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len != 2 { eprintln('usage: default-network-active-native-readback FRESH_EXTERNAL_JSON | --self-test'); exit(2) }
	run(os.args[1]) or { eprintln(err); exit(1) }
}
