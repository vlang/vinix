// SPDX-License-Identifier: GPL-2.0-or-later
// Full native-only successor audit; the original boot-path audit is unchanged.
module main

import crypto.sha256
import json2
import mapsaccountstage as stage
import os

const state = '/Users/alex/.local/state/vinix/android/'
const previous_root = state + 'current-native-build-2026-11-03-framework-boot-r1'
const previous_seal = '0a6d8126bd0842985123578550fc3fa60c0eb12543e8fcf680d1644f6b49f81f'
const successor_root = state + 'current-native-build-2026-11-04-framework-jni-load-r1'
const sdk_root = state + 'combined-account-webview-framework-boot-framework-2026-11-03-r1'
const sdk_seal = 'af23c13d90f557c4f7f208ae75c39ad8bcf0efd86fc88fddfe399fe2e66a4e91'
const repo = '/Users/alex/code/vinix/'
const runtime_before = 'bba5097f2ebfaad299af46192ec3b672630e9a3db2ca86d8cc73c84a6121440b'
const runtime_after = 'c733da77a56ad5c9c4740de5fc8791921e74089aaf494d749e562a5774cfedc0'

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
	for path, new in after { if path !in before { changed[path] = ['', new] } }
	return changed
}

fn closure(bundle stage.Bundle, label string) !map[string]string {
	mut normalized := map[string]string{}
	for path, pin in object(bundle, label + '-closure.json')! {
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
		name := path.all_after(bundle.root + '/compiler-root/')
		if name in normalized { return error('normalized compiler input collision') }
		normalized[name] = pin
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

// Exact signatures and lexical brace matching prevent a string or comment
// from widening the admitted function range into an unrelated C definition.
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

fn replace_once(text string, old string, new string) !string {
	if text.count(old) != 1 { return error('one exact original C expression required') }
	return text.replace(old, new)
}

fn expected_load(before string) !string {
	old_class := '\tvoid* loader = atlframework__obj(e, atlframework__cls(e, "android/view/View"), "java/lang/Class", "getClassLoader", "()Ljava/lang/ClassLoader;", NULL);\n'
	new_class := '\tvoid* framework = atlframework__cls(e, "android/view/View");\n'
	old_args := '(atlframework__Value){.l = atlframework__ws_string(e, path)}, (atlframework__Value){.l = loader}'
	new_args := '(atlframework__Value){.l = framework}, (atlframework__Value){.l = atlframework__ws_string(e, path)}'
	old_call := 'runtime, "java/lang/Runtime", "load", "(Ljava/lang/String;Ljava/lang/ClassLoader;)V"'
	new_call := 'runtime, "java/lang/Runtime", "load0", "(Ljava/lang/Class;Ljava/lang/String;)V"'
	mut expected := replace_once(before, old_class, new_class)!
	expected = replace_once(expected, old_args, new_args)!
	return replace_once(expected, old_call, new_call)
}

fn c_delta(before string, after string) !map[string][]string {
	signature := 'bool atlframework__ws_load_jni(void* e, char* path)'
	old_load, new_load := c_function(before, signature)!, c_function(after, signature)!
	if new_load.text != expected_load(old_load.text)! || old_load.text == new_load.text {
		return error('exact JNI Class/path argument and load0 descriptor delta required')
	}
	if before.replace(old_load.text, '@@JNI-LOAD@@\n\n') != after.replace(new_load.text, '@@JNI-LOAD@@\n\n') {
		return error('generated C changed outside the single JNI-load function')
	}
	return {'ws_load_jni': [sha256.sum(old_load.text.bytes()).hex(), sha256.sum(new_load.text.bytes()).hex()]}
}

fn c_delta_self_test() ! {
	signature := 'bool atlframework__ws_load_jni(void* e, char* path)'
	load := signature + ' {\n'
		+ '\tvoid* loader = atlframework__obj(e, atlframework__cls(e, "android/view/View"), "java/lang/Class", "getClassLoader", "()Ljava/lang/ClassLoader;", NULL);\n'
		+ '\tvoid* runtime = atlframework__static_obj(e, "java/lang/Runtime", "getRuntime", "()Ljava/lang/Runtime;", NULL);\n'
		+ '\tatlframework__Value args[2];\n'
		+ '\tmemmove(args, (atlframework__Value[]){(atlframework__Value){.l = atlframework__ws_string(e, path)}, (atlframework__Value){.l = loader}}, sizeof(args));\n'
		+ '\tatlframework__call(e, runtime, "java/lang/Runtime", "load", "(Ljava/lang/String;Ljava/lang/ClassLoader;)V", &args[0]);\n'
		+ '\treturn ((!atlframework__ws_failure(e, "ANDROID-WS-FAIL load JNI backend")) != 0);\n}\n\n'
	before := 'int unrelated = 7;\n' + load + 'void other() { return; }\n'
	after := before.replace(load, expected_load(load)!)
	if c_delta(before, after)!.len != 1 { return error('complete C preservation positive refused') }
	mut controls := 0
	for bad in [after.replace('unrelated = 7', 'unrelated = 8'), after.replace('other() { return;', 'other() { abort();'),
		after + 'void added_unrelated() {}\n', after.replace('"android/view/View"', '"java/lang/Object"'),
		after.replace('"load0"', '"load"'), after.replace('"load0"', '"loadLibrary"'),
		after.replace('(Ljava/lang/Class;Ljava/lang/String;)V', '(Ljava/lang/String;Ljava/lang/ClassLoader;)V'),
		after.replace('.l = framework', '.l = NULL'), after.replace('atlframework__ws_string(e, path)', 'atlframework__ws_string(e, root)'),
		after.replace('.l = framework}, (atlframework__Value){.l = atlframework__ws_string(e, path)', '.l = atlframework__ws_string(e, path)}, (atlframework__Value){.l = framework'),
		after.replace('(!atlframework__ws_failure', '(atlframework__ws_failure'),
		after.replace(signature, 'bool atlframework__ws_load_jni(void* e, int path)'),
		after + expected_load(load)!] {
		if bad == after { return error('inactive C mutation control') }
		c_delta(before, bad) or { controls++; continue }
		return error('generated C preservation or JNI scope mutation accepted')
	}
	for bad in [signature + ' {\n"unterminated }\n', signature + ' {\n/* unterminated }\n', signature + ' {\nreturn true;\n'] {
		c_function(bad, signature) or { controls++; continue }
		return error('unterminated C lexical state accepted')
	}
	// Quoted/comment braces inside the admitted function cannot change its range.
	lexical := load.replace(signature + ' {\n', signature + ' {\n'
		+ '\t// } ignored\n\t/* { ignored */\n\tconst char* text = "}";\n\tchar brace = \'}\';\n')
	c_delta('int unrelated = 7;\n' + lexical + 'void other() { return; }\n',
		'int unrelated = 7;\n' + expected_load(lexical)! + 'void other() { return; }\n')!
	println('FRAMEWORK-JNI-LOAD-NATIVE-SELFTEST-PASS controls=' + controls.str() + ' exact-Class-path-order guarded-overload-refused whole-C-preservation lexical-braces')
}

fn run(native_seal string, output string) ! {
	if !stage.valid_pin(native_seal) || os.exists(output) || os.is_link(output)
		|| !output.starts_with(state) || os.real_path(os.dir(output)) != os.dir(output) {
		return error('exact native pin and fresh external output with existing canonical parent required')
	}
	old := stage.load_bundle(previous_root, previous_seal)!
	new := stage.load_bundle(successor_root, native_seal)!
	sdk := stage.load_bundle(sdk_root, sdk_seal)!
	stage.verify_native(old, sdk)!
	stage.verify_native(new, sdk)!
	for bundle in [old, new] {
		if stage.text_field(bundle.receipt, 'framework')! != sdk.root
			|| stage.text_field(bundle.receipt, 'framework_sha256')! != sdk.seal
			|| bundle.files['framework-sha256.json']! != sdk.seal { return error('both native producers must couple to the identical complete SDK') }
	}
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
	if origins.len != 91 || inputs.len != 92 || origins != old_origins
		|| old_inputs.keys().sorted() != inputs.keys().sorted() { return error('exact equal 91 native origins and 92 input membership required') }
	mut source_delta := map[string][]string{}
	for name, origin in origins {
		if os.file_name(origin) != name || origin !in inputs
			|| old.files['native/atlframework/' + name]! != old_inputs[origin]!
			|| new.files['native/atlframework/' + name]! != inputs[origin]! { return error('copied native source differs from its input pin') }
		if old_inputs[origin]! != inputs[origin]! { source_delta[origin] = [old_inputs[origin]!, inputs[origin]!] }
	}
	if source_delta != {repo + 'build-support/android/nativews/runtime.v': [runtime_before, runtime_after]}
		|| delta(old_inputs, inputs) != source_delta { return error('only the exact reviewed runtime.v source may change') }
	if old.files.keys().filter(it.starts_with('native/atlframework/')).sorted()
		!= new.files.keys().filter(it.starts_with('native/atlframework/')).sorted() { return error('native source membership changed') }
	generated_c_delta := c_delta(os.read_file(old.root + '/native/android-native.c')!, os.read_file(new.root + '/native/android-native.c')!)!
	if old.files['native/libvinix-android-native.so']! == new.files['native/libvinix-android-native.so']! {
		return error('JNI loading fix requires a changed native DSO')
	}
	exports := json2.decode[[]string](os.read_file(new.root + '/native/exports.json')!)!
	if exports.len != 721 { return error('exact 721 unchanged exports required') }
	before := object(old, 'framework/consumed-smali.json')!
	after := object(new, 'framework/consumed-smali.json')!
	if before.len != 70 || before != after { return error('all 70 consumed raw SDK classes must remain identical') }
	for path, pin in after {
		if new.files['framework/' + path]! != pin || old.files['framework/' + path]! != pin
			|| sdk.files[path]! != pin { return error('consumed native class differs from the unchanged SDK') }
	}
	if old.files.keys().filter(it.starts_with('framework/')).sorted()
		!= new.files.keys().filter(it.starts_with('framework/')).sorted() { return error('framework copy membership changed') }
	if compiler_root(old)! != compiler_root(new)! { return error('complete restored compiler-root inputs must remain equal') }
	old_headers, new_headers := headers(old)!, headers(new)!
	header_delta := delta(old_headers, new_headers)
	if header_delta != {'@native/android-native.c': [old.files['native/android-native.c']!, new.files['native/android-native.c']!]} {
		return error('only generated C may change among exact 58 normalized consumed inputs')
	}
	for row in [['native-generator', '340'], ['builder', '660']] {
		before_closure, after_closure := closure(old, row[0])!, closure(new, row[0])!
		if before_closure.len != row[1].int() || before_closure != after_closure { return error('complete normalized helper closure changed: ' + row[0]) }
	}
	old_command, new_command := command(old, 'build-native')!, command(new, 'build-native')!
	if old_command.map(it.replace(old.root, '@native-root')) != new_command.map(it.replace(new.root, '@native-root')) {
		return error('native compiler arguments changed beyond exact owned root')
	}
	old_elf := stage.inspect_elf(os.read_bytes(old.root + '/native/libvinix-android-native.so')!)!
	new_elf := stage.inspect_elf(os.read_bytes(new.root + '/native/libvinix-android-native.so')!)!
	if old_elf.needed != new_elf.needed || old_elf.soname != new_elf.soname || old_elf.interpreter != new_elf.interpreter
		|| old_elf.runpath != new_elf.runpath { return error('native ELF dependency identity changed') }
	for bundle in [old, new, sdk] { stage.recheck(bundle)! }
	if headers(old)! != old_headers || headers(new)! != new_headers {
		return error('complete consumed external/header input changed during readback')
	}
	os.write_file(output, json2.encode({
		'kind': json2.Any('vinix-framework-jni-load-native-readback-v1'),
		'previous_manifest_sha256': json2.Any(old.seal), 'native_manifest_sha256': json2.Any(new.seal),
		'framework_manifest_sha256': json2.Any(sdk.seal), 'native_build_sha256': json2.Any(new.files['build.json']!),
		'native_dso_sha256': json2.Any(new.files['native/libvinix-android-native.so']!),
		'native_source_delta': json2.decode[json2.Any](json2.encode(source_delta))!,
		'generated_c_sha256': json2.Any(new.files['native/android-native.c']!),
		'generated_c_function_delta': json2.decode[json2.Any](json2.encode(generated_c_delta))!,
		'consumed_headers_delta': json2.decode[json2.Any](json2.encode(header_delta))!,
		'consumed_raw_delta': json2.decode[json2.Any](json2.encode(delta(before, after)))!,
		'needed': json2.decode[json2.Any](json2.encode(new_elf.needed))!,
	}, prettify: true) + '\n')!
	println('FRAMEWORK-JNI-LOAD-NATIVE-READBACK-PASS origins91 inputs92 source-delta1 generated-C-function-delta1 consumed70-unchanged exports721 headers58 header-delta1 generator340 builder660 same-SDK complete-rechecks')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		c_delta_self_test() or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 3 { eprintln('usage: framework-jni-load-native-readback NATIVE_MANIFEST_SHA256 FRESH_EXTERNAL_JSON | --self-test'); exit(2) }
	run(os.args[1], os.args[2]) or { eprintln(err); exit(1) }
}
