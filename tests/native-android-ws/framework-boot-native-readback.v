// SPDX-License-Identifier: GPL-2.0-or-later
// Independently verify the complete framework boot-visibility/native delta.
module main

import crypto.sha256
import json2
import mapsaccountstage as stage
import os

const state = '/Users/alex/.local/state/vinix/android/'
const previous_root = state + 'current-native-build-2026-11-03-webview-package-r2'
const previous_seal = '1434754497efa741ddb2b378cbb693862ee96eb04cb304d9cbeeae5cc98b4dc0'
const previous_sdk = state + 'combined-account-webview-webview-package-framework-2026-11-03-r1'
const previous_sdk_seal = 'c79d421bd385777aefd00b0be85a287af7907b1bb6dd55244d7546eb99ea958a'
const successor_root = state + 'current-native-build-2026-11-03-framework-boot-r1'
const successor_sdk = state + 'combined-account-webview-framework-boot-framework-2026-11-03-r1'
const repo = '/Users/alex/code/vinix/'
const bootstrap_after = 'a716e6820e6581f018fe6bd25ebc6735251d6265c71f4290e8c9224c2dcf5bae'
const runtime_after = 'bba5097f2ebfaad299af46192ec3b672630e9a3db2ca86d8cc73c84a6121440b'

fn object(bundle stage.Bundle, path string) !map[string]string {
	if path !in bundle.files { return error('sealed object missing: ' + path) }
	return json2.decode[map[string]string](os.read_file(bundle.root + '/' + path)!)
}

fn delta(before map[string]string, after map[string]string) map[string][]string {
	mut changed := map[string][]string{}
	for path, old in before {
		new := after[path] or { '' }
		if new != old { changed[path] = [old, new] }
	}
	for path, new in after {
		if path !in before { changed[path] = ['', new] }
	}
	return changed
}

fn closure(bundle stage.Bundle, label string) !map[string]string {
	pins := object(bundle, label + '-closure.json')!
	mut normalized := map[string]string{}
	for path, pin in pins {
		if bundle.files['closure/' + label + '/' + path.trim_left('/')] or { '' } != pin {
			return error('complete frozen helper copy mismatch: ' + path)
		}
		name := if path.starts_with(bundle.root + '/compiler-root/') {
			'@compiler/' + path.all_after(bundle.root + '/compiler-root/')
		} else if path.starts_with(repo) { path } else {
			return error('helper outside exact compiler root or repository: ' + path)
		}
		if name in normalized { return error('normalized helper collision') }
		normalized[name] = pin
	}
	return normalized
}

fn compiler_root(bundle stage.Bundle) !map[string]string {
	mut normalized := map[string]string{}
	for path, pin in object(bundle, 'compiler-root-inputs.json')! {
		if !path.starts_with(bundle.root + '/compiler-root/')
			|| bundle.files[path.all_after(bundle.root + '/')] or { '' } != pin {
			return error('complete compiler input outside owned frozen root')
		}
		normalized[path.all_after(bundle.root + '/compiler-root/')] = pin
	}
	return normalized
}

fn headers(bundle stage.Bundle) !map[string]string {
	pins := object(bundle, 'native/consumed-headers.json')!
	if pins.len != 58 { return error('exactly 58 consumed C/header inputs required') }
	mut normalized := map[string]string{}
	mut owned := []string{}
	for path, pin in pins {
		if path != os.real_path(path) || stage.hash(path)! != pin { return error('consumed C/header bytes differ') }
		name := if path.starts_with(bundle.root + '/native/') {
			relative := path.all_after(bundle.root + '/')
			if bundle.files[relative] or { '' } != pin { return error('owned header not sealed') }
			owned << relative
			'@native/' + path.all_after(bundle.root + '/native/')
		} else { path }
		if name in normalized { return error('normalized header collision') }
		normalized[name] = pin
	}
	if owned.sorted() != ['native/android-native.c', 'native/androidfw_c_api.h', 'native/sqlite3.h',
		'native/stb_image.h', 'native/stb_truetype.h'] { return error('exact five owned native inputs required') }
	return normalized
}

fn command(bundle stage.Bundle, name string) ![]string {
	path := 'commands/' + name + '.json'
	if path !in bundle.files { return error('sealed command missing') }
	value := json2.decode[map[string]json2.Any](os.read_file(bundle.root + '/' + path)!)!
	if json2.encode(value['exit_code']!) != '0' { return error('sealed command failed: ' + name) }
	return json2.decode[[]string](json2.encode(value['argv']!))!
}

struct CFunction {
	text string
}

// Only exact generated signatures identify a function. Brace matching ignores
// strings, characters and both comment forms; an embedded brace cannot widen
// the admitted function range into an unrelated declaration or definition.
fn c_function(source string, signature string) !CFunction {
	anchor := signature + ' {'
	if source.count(anchor) != 1 { return error('one exact generated function required: ' + signature) }
	start := source.index(anchor) or { return error('generated function anchor missing') }
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
		} else if ch == `/` && next == `/` {
			line_comment = true
			offset++
		} else if ch == `/` && next == `*` {
			block_comment = true
			offset++
		} else if ch == `"` || ch == `'` {
			quote = ch
		} else if ch == `{` {
			depth++
		} else if ch == `}` {
			depth--
			if depth == 0 {
				mut end := offset + 1
				if end >= source.len || source[end] != `\n` { return error('generated function newline required') }
				end++
				if end < source.len && source[end] == `\n` { end++ }
				return CFunction{source[start..end]}
			}
			if depth < 0 { return error('unbalanced generated function') }
		}
		offset++
	}
	return error('unterminated generated function')
}

fn c_delta(before string, after string) !map[string][]string {
	bootstrap := 'void* atlframework__ws_bootstrap(char* root, char* apk, bool display)'
	load := 'bool atlframework__ws_load_jni(void* e, char* path)'
	helper := 'bool atlframework__ws_boot_classpath(char* root, char* buffer, size_t capacity)'
	prototype := helper + ';\n'
	if before.contains('atlframework__ws_boot_classpath(') || after.count('atlframework__ws_boot_classpath(') != 3
		|| after.count(prototype) != 1 { return error('one added boot helper declaration, definition and startup call required') }
	old_boot, new_boot := c_function(before, bootstrap)!, c_function(after, bootstrap)!
	old_load, new_load := c_function(before, load)!, c_function(after, load)!
	new_helper := c_function(after, helper)!
	if old_boot.text == new_boot.text || old_load.text == new_load.text
		|| !new_boot.text.contains('atlframework__ws_boot_classpath(') {
		return error('both boot startup and JNI loading must change')
	}
	if old_load.text.count('atlframework__ws_string(e, "vinix-android-native")') != 1
		|| old_load.text.count('runtime, "java/lang/Runtime", "loadLibrary"') != 1 {
		return error('exact old JNI name-loading function required')
	}
	expected_load := old_load.text.replace('atlframework__ws_string(e, "vinix-android-native")',
		'atlframework__ws_string(e, path)').replace('runtime, "java/lang/Runtime", "loadLibrary"',
		'runtime, "java/lang/Runtime", "load"')
	if new_load.text != expected_load { return error('JNI C delta must only use the existing absolute path and load overload') }
	old_rest := before.replace(old_boot.text, '@@BOOT-STARTUP@@\n\n').replace(old_load.text, '@@JNI-LOAD@@\n\n')
	new_rest := after.replace(new_boot.text, '@@BOOT-STARTUP@@\n\n').replace(new_load.text, '@@JNI-LOAD@@\n\n')
		.replace(new_helper.text, '').replace(prototype, '')
	if old_rest != new_rest { return error('generated C changed outside the two functions and added helper/prototype') }
	return {
		'ws_bootstrap': [sha256.sum(old_boot.text.bytes()).hex(), sha256.sum(new_boot.text.bytes()).hex()]
		'ws_load_jni': [sha256.sum(old_load.text.bytes()).hex(), sha256.sum(new_load.text.bytes()).hex()]
		'ws_boot_classpath': ['', sha256.sum(new_helper.text.bytes()).hex()]
	}
}

fn c_delta_self_test() ! {
	boot := 'void* atlframework__ws_bootstrap(char* root, char* apk, bool display) {\nreturn NULL;\n}\n\n'
	load := 'bool atlframework__ws_load_jni(void* e, char* path) {\n'
		+ 'atlframework__ws_string(e, "vinix-android-native");\n'
		+ 'atlframework__call(e, runtime, "java/lang/Runtime", "loadLibrary", "(Ljava/lang/String;Ljava/lang/ClassLoader;)V", NULL);\nreturn true;\n}\n\n'
	helper := 'bool atlframework__ws_boot_classpath(char* root, char* buffer, size_t capacity)'
	added := helper + ';\n'
		+ helper + ' {\n// } ignored\n/* { ignored */\nconst char* text = "\\\"}\\\\";\nchar bracket = \'}\';\nreturn true;\n}\n\n'
	changed_boot := boot.replace('return NULL;', 'atlframework__ws_boot_classpath(root, NULL, 0);\nreturn NULL;')
	changed_load := load.replace('atlframework__ws_string(e, "vinix-android-native")', 'atlframework__ws_string(e, path)')
		.replace('runtime, "java/lang/Runtime", "loadLibrary"', 'runtime, "java/lang/Runtime", "load"')
	before := 'int unrelated = 7;\n' + boot + load + 'void other() { return; }\n'
	after := 'int unrelated = 7;\n' + added + changed_boot + changed_load + 'void other() { return; }\n'
	if c_delta(before, after)!.len != 3 { return error('complete C preservation positive refused') }
	for bad in [after.replace('unrelated = 7', 'unrelated = 8'), after.replace('other() { return;', 'other() { abort();'),
		after + 'void added_unrelated() {}\n', after.replace(helper + ';\n', ''), after.replace(helper + ';\n', helper + ';\n' + helper + ';\n'),
		after.replace(changed_boot, boot), after.replace('char* apk, bool display) {', 'char* apk, int display) {'),
		after.replace('atlframework__ws_string(e, path)', 'atlframework__ws_string(e, root)'),
		after.replace('return true;\n}\n\nvoid other', 'return false;\n}\n\nvoid other'),
		after.replace(helper + ' {', helper + ' {\n') + helper + ' { return true; }\n\n'] {
		c_delta(before, bad) or { continue }
		return error('generated C preservation or JNI scope mutation accepted')
	}
	for bad in [helper + ' {\n"unterminated }\n', helper + ' {\n/* unterminated }\n', helper + ' {\nreturn true;\n'] {
		c_function(bad, helper) or { continue }
		return error('unterminated C lexical state accepted')
	}
}

fn smali_method(text string, signature string) !string {
	header := '.method public static ' + signature + '\n'
	if text.count(header) != 1 { return error('one exact existing public static method required') }
	start := text.index(header) or { return error('SDK method header missing') }
	end := text[start..].index('.end method') or { return error('SDK method footer missing') }
	return text[start..start + end + '.end method'.len]
}

fn smali_labels(text string) !string {
	mut labels := map[string]string{}
	for line in text.split_into_lines() {
		value := line.trim_space()
		if value.starts_with(':') {
			name := value.all_before(' ').all_before('\t')
			if name in labels { return error('duplicate Smali label') }
			labels[name] = '@LABEL' + labels.len.str() + '@'
		}
	}
	mut result := []u8{cap: text.len}
	mut quote := false
	mut escape := false
	mut comment := false
	mut offset := 0
	for offset < text.len {
		ch := text[offset]
		if comment {
			if ch == `\n` { comment = false }
		} else if quote {
			if escape { escape = false } else if ch == `\\` { escape = true } else if ch == `"` { quote = false }
		} else if ch == `#` {
			comment = true
		} else if ch == `"` {
			quote = true
		} else if ch == `:` {
			mut end := offset + 1
			for end < text.len && ((text[end] >= `a` && text[end] <= `z`) || (text[end] >= `A` && text[end] <= `Z`)
				|| (text[end] >= `0` && text[end] <= `9`) || text[end] == `_` || text[end] == `$`) { end++ }
			name := text[offset..end]
			if name in labels {
				result << labels[name]!.bytes()
				offset = end
				continue
			}
		}
		result << ch
		offset++
	}
	if quote { return error('unterminated Smali string') }
	return result.bytestr()
}

fn sdk_method_scope(before string, after string, path string) ! {
	names := match path {
		'new-dex/android/content/res/Resources.smali' { ['getSystem()Landroid/content/res/Resources;', 'v3', 'android/content/res/Resources'] }
		'new-dex/android/atl/ATLLoadedApp.smali' { ['loadFromPath(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;', 'v1', 'android/atl/ATLLoadedApp'] }
		else { return error('unknown SDK method-scope class') }
	}
	signature, register, owner := names[0], names[1], names[2]
	old_method, new_method := smali_method(before, signature)!, smali_method(after, signature)!
	anchor := '    const-class ' + register + ', L' + owner + ';\n\n'
		+ '    invoke-virtual {' + register + '}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;'
	replacement := '    invoke-static {}, Ljava/lang/ClassLoader;->getSystemClassLoader()Ljava/lang/ClassLoader;'
	if old_method.count(anchor) != 1 { return error('exact old defining-class loader pair required') }
	expected := old_method.replace(anchor, replacement)
	if smali_labels(expected)! != smali_labels(new_method)!
		|| before.replace(old_method, '@@ONE-METHOD@@') != after.replace(new_method, '@@ONE-METHOD@@') {
		return error('SDK method, metadata, fields or unrelated code changed beyond exact system-loader source')
	}
}

fn sdk_scope_self_test() ! {
	for row in [
		['new-dex/android/content/res/Resources.smali', 'getSystem()Landroid/content/res/Resources;', 'v3', 'android/content/res/Resources'],
		['new-dex/android/atl/ATLLoadedApp.smali', 'loadFromPath(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;', 'v1', 'android/atl/ATLLoadedApp'],
	] {
		path, signature, register, owner := row[0], row[1], row[2], row[3]
		anchor := '    const-class ' + register + ', L' + owner + ';\n\n'
			+ '    invoke-virtual {' + register + '}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;'
		before := '.class public L' + owner + ';\n.super Ljava/lang/Object;\n.field keep:I\n'
			+ '.method public static ' + signature + '\n    .registers 5\n    :start\n'
			+ anchor + '\n\n    move-result-object ' + register + '\n'
			+ '    const-string v0, "literal :done"\n    if-eqz ' + register + ', :done\n    :done\n    return-object ' + register + '\n.end method\n'
			+ '.method public keep()V\n.registers 1\nreturn-void\n.end method\n'
		after := before.replace(anchor, '    invoke-static {}, Ljava/lang/ClassLoader;->getSystemClassLoader()Ljava/lang/ClassLoader;')
			.replace('    :start\n', '    :begin\n').replace(', :done\n', ', :finish\n').replace('    :done\n', '    :finish\n')
		sdk_method_scope(before, after, path)!
		for bad in [after.replace('.field keep:I', '.field keep:J'), after.replace('return-void', 'nop\nreturn-void'),
			after.replace('public static ' + signature, 'private static ' + signature),
			after.replace('    .registers 5', '    .registers 6'), after.replace('literal :done', 'literal :finish'),
			after.replace('    move-result-object ' + register, '    move-result-object v4'),
			after.replace(', :finish\n', ', :begin\n'), after + '.field added:I\n'] {
			sdk_method_scope(before, bad, path) or { continue }
			return error('SDK class/member/register/instruction/label/string mutation accepted')
		}
	}
}

fn sdk_delta(old stage.Bundle, new stage.Bundle) !map[string][]string {
	mut before := map[string]string{}
	mut after := map[string]string{}
	for path, pin in old.files { if path.starts_with('new-dex/') && path.ends_with('.smali') { before[path] = pin } }
	for path, pin in new.files { if path.starts_with('new-dex/') && path.ends_with('.smali') { after[path] = pin } }
	if before.len != 2117 || before.keys().sorted() != after.keys().sorted() {
		return error('exact 2117 SDK classes with preserved membership required')
	}
	changed := delta(before, after)
	if changed.keys().sorted() != ['new-dex/android/atl/ATLLoadedApp.smali', 'new-dex/android/content/res/Resources.smali'] {
		return error('only the two resource-loader SDK classes may change canonically')
	}
	for path in changed.keys() { sdk_method_scope(os.read_file(old.root + '/' + path)!, os.read_file(new.root + '/' + path)!, path)! }
	if json2.decode[map[string]int](json2.encode(new.receipt['changed_method_counts']!))! != {
		'android/atl/ATLLoadedApp.smali': 1, 'android/content/res/Resources.smali': 1,
	} || json2.decode[map[string]int](json2.encode(new.receipt['added_method_counts']!))! != {
		'android/atl/ATLLoadedApp.smali': 0, 'android/content/res/Resources.smali': 0,
	} || json2.decode[[]string](json2.encode(new.receipt['added_classes']!))!.len != 0
		|| json2.decode[map[string][]string](json2.encode(new.receipt['added_fields']!))!.len != 0 {
		return error('exact two changed existing SDK methods and no additions required')
	}
	return changed
}

fn run(native_seal string, sdk_seal string, output string) ! {
	if !stage.valid_pin(native_seal) || !stage.valid_pin(sdk_seal)
		|| os.exists(output) || os.is_link(output) || !output.starts_with(state)
		|| os.real_path(os.dir(output)) != os.dir(output) { return error('exact pins and fresh external output required') }
	old := stage.load_bundle(previous_root, previous_seal)!
	new := stage.load_bundle(successor_root, native_seal)!
	old_sdk := stage.load_bundle(previous_sdk, previous_sdk_seal)!
	new_sdk := stage.load_bundle(successor_sdk, sdk_seal)!
	framework_delta := sdk_delta(old_sdk, new_sdk)!
	stage.verify_native(old, old_sdk)!
	stage.verify_native(new, new_sdk)!
	if stage.text_field(new.receipt, 'framework')! != new_sdk.root
		|| stage.text_field(new.receipt, 'framework_sha256')! != new_sdk.seal
		|| new.files['framework-sha256.json']! != new_sdk.seal { return error('new native producer must couple directly to new SDK') }
	for name in ['baseline', 'baseline_sha256', 'compiler_library_baseline', 'compiler_library_sha256', 'compiler_source_policy'] {
		if new.receipt[name]! != old.receipt[name]! { return error('native producer baseline/library policy changed') }
	}
	for name in ['builder-source.v', 'native/bindings.txt', 'native/source-origins.json',
		'native/atlframework/ws_generated.v', 'native/exports.json', 'tools/find-v.sh',
		'native/androidfw_c_api.h', 'native/sqlite3.h', 'native/stb_image.h', 'native/stb_truetype.h',
		'reused-inputs.json', 'crosscompiler-specs.txt', 'compiler-library-sha256.json', 'compiler-library-origins.json'] {
		if old.files[name]! != new.files[name]! { return error('native implementation/toolchain input changed: ' + name) }
	}
	origins := object(new, 'native/source-origins.json')!
	old_origins := object(old, 'native/source-origins.json')!
	inputs := object(new, 'native/current-inputs.json')!
	old_inputs := object(old, 'native/current-inputs.json')!
	if origins.len != 91 || inputs.len != 92 { return error('exact 91 native origins and 92 inputs required') }
	if origins != old_origins || old_inputs.keys().sorted() != inputs.keys().sorted() {
		return error('complete native origin and input membership must remain equal')
	}
	mut source_delta := map[string][]string{}
	for name, origin in origins {
		if os.file_name(origin) != name || origin !in inputs
			|| old.files['native/atlframework/' + name]! != old_inputs[origin]!
			|| new.files['native/atlframework/' + name]! != inputs[origin]! { return error('complete copied native source must match its original input pin') }
		if old_inputs[origin]! != inputs[origin]! { source_delta[origin] = [old_inputs[origin]!, inputs[origin]!] }
	}
	if source_delta != {
		repo + 'build-support/android/nativews/bootstrap.v': [old.files['native/atlframework/bootstrap.v']!, bootstrap_after],
		repo + 'build-support/android/nativews/runtime.v': [old.files['native/atlframework/runtime.v']!, runtime_after],
	} { return error('only the exact two reviewed native source files may change') }
	if delta(old_inputs, inputs) != source_delta { return error('no generated JNI or extra native input delta allowed') }
	if old.files.keys().filter(it.starts_with('native/atlframework/')).sorted()
		!= new.files.keys().filter(it.starts_with('native/atlframework/')).sorted() { return error('native source membership changed') }
	generated_c_delta := c_delta(os.read_file(old.root + '/native/android-native.c')!, os.read_file(new.root + '/native/android-native.c')!)!
	if old.files['native/android-native.c']! == new.files['native/android-native.c']! { return error('boot visibility requires the measured generated C delta') }
	exports := json2.decode[[]string](os.read_file(new.root + '/native/exports.json')!)!
	if exports.len != 721 { return error('exact 721 unchanged exports required') }
	before := object(old, 'framework/consumed-smali.json')!
	after := object(new, 'framework/consumed-smali.json')!
	if before.len != 70 || before.keys().sorted() != after.keys().sorted() { return error('exact 70 consumed classes required') }
	mut canonical_delta := map[string][]string{}
	for path, pin in after {
		if new.files['framework/' + path]! != pin || new_sdk.files[path]! != pin {
			return error('new native copy differs from exact SDK consumed class: ' + path)
		}
		if old.files['framework/' + path]! != before[path]! || old_sdk.files[path]! != before[path]! {
			return error('previous native copy differs from its original SDK: ' + path)
		}
		name := 'new-dex/' + path.all_after('smali/')
		if old_sdk.files[name]! != new_sdk.files[name]! {
			canonical_delta[path] = [old_sdk.files[name]!, new_sdk.files[name]!]
		}
	}
	raw_delta := delta(before, after)
	if raw_delta != {
		'smali/android/atl/ATLLoadedApp.smali': [old_sdk.files['smali/android/atl/ATLLoadedApp.smali']!, new_sdk.files['smali/android/atl/ATLLoadedApp.smali']!],
		'smali/android/content/res/Resources.smali': [old_sdk.files['smali/android/content/res/Resources.smali']!, new_sdk.files['smali/android/content/res/Resources.smali']!],
		'smali/android/webkit/WebView.smali': ['3cd08baf04f82e1f0d7587219f4f6e5c3310d439086ba6ad6c016b20e543ba1d', 'dd38134f402fbcb5297a50cea97eb7f903963e526026be3a49301ba67e69434e'],
	} || canonical_delta.keys().sorted() != ['smali/android/atl/ATLLoadedApp.smali', 'smali/android/content/res/Resources.smali'] {
		return error('exact three raw and two canonical consumed deltas required')
	}
	if compiler_root(old)! != compiler_root(new)! { return error('complete restored compiler-root inputs must remain equal') }
	old_headers, new_headers := headers(old)!, headers(new)!
	header_delta := delta(old_headers, new_headers)
	if header_delta != {'@native/android-native.c': [old.files['native/android-native.c']!, new.files['native/android-native.c']!]} {
		return error('only generated C may change among the exact 58 normalized consumed inputs')
	}
	old_generator, new_generator := closure(old, 'native-generator')!, closure(new, 'native-generator')!
	if old_generator.len != 340 || old_generator != new_generator { return error('complete 340-input native generator must stay equal') }
	old_builder, new_builder := closure(old, 'builder')!, closure(new, 'builder')!
	builder_delta := delta(old_builder, new_builder)
	registry := repo + 'tests/native-android-tools/androidtools/framework.v'
	provider := repo + 'tests/native-android-tools/androidtools/framework_boot_classpath.v'
	if old_builder.len != 659 || new_builder.len != 660 || builder_delta != {
		registry: [old_builder[registry]!, new_sdk.files['provider-helper-inputs/framework.v']!],
		provider: ['', new_sdk.files['provider-source/androidtools/framework_boot_classpath.v']!],
	} { return error('complete builder closure must have exactly one registry change and one provider addition') }
	old_command, new_command := command(old, 'build-native')!, command(new, 'build-native')!
	if old_command.map(it.replace(old.root, '@native-root')) != new_command.map(it.replace(new.root, '@native-root')) {
		return error('native compiler arguments changed beyond exact owned root')
	}
	old_elf := stage.inspect_elf(os.read_bytes(old.root + '/native/libvinix-android-native.so')!)!
	new_elf := stage.inspect_elf(os.read_bytes(new.root + '/native/libvinix-android-native.so')!)!
	if old_elf.needed != new_elf.needed || old_elf.soname != new_elf.soname || old_elf.interpreter != new_elf.interpreter
		|| old_elf.runpath != new_elf.runpath { return error('native ELF dependency identity changed') }
	mut after_helpers := map[string]string{}
	for path, pins in builder_delta { after_helpers[path] = pins[1] }
	result := {
		'kind': json2.Any('vinix-framework-boot-native-readback-v1'),
		'previous_manifest_sha256': json2.Any(old.seal), 'native_manifest_sha256': json2.Any(new.seal),
		'framework_manifest_sha256': json2.Any(new_sdk.seal), 'native_build_sha256': json2.Any(new.files['build.json']!),
		'native_dso_sha256': json2.Any(new.files['native/libvinix-android-native.so']!),
		'consumed_headers_sha256': json2.Any(new.files['native/consumed-headers.json']!),
		'builder_count_before': json2.Any(old_builder.len), 'builder_count_after': json2.Any(new_builder.len),
		'builder_delta': json2.decode[json2.Any](json2.encode(builder_delta))!,
		'builder_after_delta': json2.decode[json2.Any](json2.encode(after_helpers))!,
		'native_source_delta': json2.decode[json2.Any](json2.encode(source_delta))!,
		'generated_c_sha256': json2.Any(new.files['native/android-native.c']!),
		'generated_c_function_delta': json2.decode[json2.Any](json2.encode(generated_c_delta))!,
		'consumed_headers_delta': json2.decode[json2.Any](json2.encode(header_delta))!,
		'framework_canonical_delta': json2.decode[json2.Any](json2.encode(framework_delta))!,
		'consumed_raw_delta': json2.decode[json2.Any](json2.encode(raw_delta))!,
		'consumed_canonical_delta': json2.decode[json2.Any](json2.encode(canonical_delta))!,
		'needed': json2.decode[json2.Any](json2.encode(new_elf.needed))!,
	}
	for bundle in [old, new, old_sdk, new_sdk] { stage.recheck(bundle)! }
	os.write_file(output, json2.encode(result, prettify: true) + '\n')!
	println('FRAMEWORK-BOOT-NATIVE-READBACK-PASS origins=91 source-delta=2 inputs=92 consumed=70 raw=3 canonical=2 exports=721 headers=58 header-delta=1 generated-C-function-delta=3 generator=340 builder-before=' + old_builder.len.str() + ' builder-after=' + new_builder.len.str() + ' builder-delta=' + builder_delta.len.str())
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		c_delta_self_test() or { eprintln(err); exit(1) }
		sdk_scope_self_test() or { eprintln(err); exit(1) }
		println('FRAMEWORK-BOOT-NATIVE-SCOPE-SELFTEST-PASS whole-C-preservation exact-JNI-delta quoted-comment-braces missing-duplicate-malformed refusals exact-two-SDK-methods label-only-normalization metadata-register-string-controls')
		return
	}
	if os.args.len != 4 { eprintln('usage: framework-boot-native-readback NATIVE_MANIFEST_SHA256 SDK_MANIFEST_SHA256 FRESH_EXTERNAL_JSON | --self-test'); exit(2) }
	run(os.args[1], os.args[2], os.args[3]) or { eprintln(err); exit(1) }
}
