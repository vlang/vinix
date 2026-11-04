// SPDX-License-Identifier: GPL-2.0-or-later
// Source-only qualification of the class-based framework JNI bootstrap load.
module main

import crypto.sha256
import json2
import os

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const baseline = state + 'current-native-build-2026-11-03-framework-boot-r1'
const baseline_manifest = '0a6d8126bd0842985123578550fc3fa60c0eb12543e8fcf680d1644f6b49f81f'
const baseline_runtime_pin = 'bba5097f2ebfaad299af46192ec3b672630e9a3db2ca86d8cc73c84a6121440b'
const old_primary = state + 'boot-classpath-core-audit-2026-11-03-r1'
const new_primary = state + 'framework-jni-load-primary-2026-11-04-r1'
const runtime_java_pin = 'c89a29fa924bdb1fd0f19dd945644b733c607e1d948f2bca7cd567fca609f1bb'
const vmruntime_java_pin = 'e10c961a622b8448856965df5aafcf0161a2e8c1f670ff9736c7caf5abd04738'
const java_vm_ext_pin = '6686f11da2330225877a840cc3be6c77258fef1e04535d042e74ee2625738e16'
const runtime_origin = repo + '/build-support/android/nativews/runtime.v'

struct NativeSource {
	before map[string]string
	after map[string]string
	owned_names []string
}

struct Mutation {
	name string
	text string
}

fn digest(path string) !string {
	if os.real_path(path) != path { return error('canonical input required: ' + path) }
	info := os.lstat(path)!
	if info.get_filetype() != .regular || info.nlink != 1 || info.size > 16 * 1024 * 1024 {
		return error('bounded single-linked regular input required: ' + path)
	}
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn capture(mut pins map[string]string, path string, expected string) !string {
	pin := digest(path)!
	if expected != '' && pin != expected { return error('pinned input differs: ' + path) }
	if path in pins && pins[path] != pin { return error('input changed during capture: ' + path) }
	pins[path] = pin
	return os.read_file(path)
}

fn owned_names() ![]string {
	return os.ls(repo + '/build-support/android/nativews')!.filter(it.ends_with('.v')).sorted()
}

fn require_membership(expected []string, actual []string) ! {
	if actual != expected { return error('native provider source membership changed') }
}

fn sources(mut pins map[string]string) !NativeSource {
	manifest := capture(mut pins, baseline + '/sha256.json', baseline_manifest)!
	files := json2.decode[map[string]string](manifest)!
	origins := json2.decode[map[string]string](capture(mut pins,
		baseline + '/native/source-origins.json', files['native/source-origins.json']!)!)!
	inputs := json2.decode[map[string]string](capture(mut pins,
		baseline + '/native/current-inputs.json', files['native/current-inputs.json']!)!)!
	if origins.len != 91 || inputs.len != 92 { return error('exact 91 native origins and 92 inputs required') }
	mut before := map[string]string{}
	mut after := map[string]string{}
	mut names := []string{}
	for name, origin in origins {
		if os.file_name(origin) != name || origin !in inputs
			|| !origin.starts_with(repo + '/build-support/android/') {
			return error('exact complete native origin map required')
		}
		path := 'native/atlframework/' + name
		if files[path]! != inputs[origin]! { return error('frozen source/input pin mismatch') }
		before[origin] = capture(mut pins, baseline + '/' + path, files[path]!)!
		after[origin] = capture(mut pins, origin, if origin == runtime_origin { '' } else { inputs[origin]! })!
		if origin.starts_with(repo + '/build-support/android/nativews/') { names << name }
	}
	bindings := repo + '/build-support/android/nativews/bindings.txt'
	if inputs.keys().sorted() != [...origins.values(), bindings].sorted()
		|| files['native/bindings.txt']! != inputs[bindings]! {
		return error('native inputs must be exactly origins plus unchanged bindings')
	}
	before[bindings] = capture(mut pins, baseline + '/native/bindings.txt', inputs[bindings]!)!
	after[bindings] = capture(mut pins, bindings, inputs[bindings]!)!
	names.sort()
	require_membership(names, owned_names()!)!
	return NativeSource{before, after, names}
}

// The pinned predecessor supplies the unique complete function boundaries.
// No parser can enlarge the permitted edit into an adjacent function.
fn load_function(text string) !(string, string, string) {
	anchor := 'fn ws_load_jni(e voidptr, path &char) bool {\n'
	boundary := '\nfn ws_open_surface() bool {'
	if text.count(anchor) != 1 || text.count(boundary) != 1 {
		return error('one exact JNI-load function and next-function boundary required')
	}
	start := text.index(anchor) or { return error('JNI-load function missing') }
	end := text.index(boundary) or { return error('JNI-load end missing') }
	if start >= end { return error('JNI-load boundaries reversed') }
	return text[..start], text[start..end], text[end..]
}

fn code_lines(text string) string {
	return text.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('//')).join('\n')
}

fn expected_load() string {
	return "fn ws_load_jni(e voidptr, path &char) bool {\n" +
		"framework := cls(e, c'android/view/View')\n" +
		"runtime := static_obj(e, c'java/lang/Runtime', c'getRuntime', c'()Ljava/lang/Runtime;', unsafe { nil })\n" +
		"args := [Value{ l: framework }, Value{ l: ws_string(e, path) }]!\n" +
		"call(e, runtime, c'java/lang/Runtime', c'load0', c'(Ljava/lang/Class;Ljava/lang/String;)V', unsafe { &args[0] })\n" +
		"return !ws_failure(e, c'ANDROID-WS-FAIL load JNI backend')\n}"
}

fn mutate_load(source string, before string, after string) !string {
	prefix, body, suffix := load_function(source)!
	if body.count(before) != 1 { return error('one active mutation anchor inside JNI-load function required') }
	return prefix + body.replace(before, after) + suffix
}

fn verify_delta(before map[string]string, after map[string]string) ! {
	if before.len != 92 || before.keys().sorted() != after.keys().sorted() {
		return error('complete native input membership changed')
	}
	for path, old in before {
		current := after[path]!
		if path != runtime_origin {
			if old != current { return error('bystander native input changed: ' + path) }
			continue
		}
		if sha256.sum(old.bytes()).hex() != baseline_runtime_pin { return error('exact predecessor runtime required') }
		old_prefix, _, old_suffix := load_function(old)!
		new_prefix, new_load, new_suffix := load_function(current)!
		if old_prefix != new_prefix || old_suffix != new_suffix {
			return error('runtime changed outside ws_load_jni')
		}
		if code_lines(new_load) != expected_load() {
			return error('exact class-based absolute Runtime.load0 call required')
		}
	}
}

fn java_method(source string, signature string) !string {
	if source.count(signature) != 1 { return error('unique pinned Java method signature required') }
	start := source.index(signature) or { return error('Java signature missing') }
	tail := source[start..]
	end := tail.index('\n    }\n') or { return error('Java method boundary missing') }
	return tail[..end + '\n    }\n'.len]
}

fn primary_contract(runtime_java string, vmruntime_java string, java_vm_ext string) !map[string]string {
	guard := java_method(runtime_java, 'private void checkTargetSdkVersionForLoad(String methodName) {')!
	load := java_method(runtime_java, 'void load(String absolutePath, ClassLoader loader) {')!
	load0 := java_method(runtime_java, 'synchronized void load0(Class<?> fromClass, String filename) {')!
	getter := java_method(vmruntime_java, 'public synchronized int getTargetSdkVersion() {')!
	if !guard.contains('if (targetSdkVersion > 24) {')
		|| !guard.contains('throw new UnsupportedOperationException(')
		|| !load.contains('checkTargetSdkVersionForLoad("java.lang.Runtime#load(String, ClassLoader)");')
		|| load0.contains('checkTargetSdkVersionForLoad')
		|| !load0.contains('if (!(new File(filename).isAbsolute())) {')
		|| !load0.contains('throw new UnsatisfiedLinkError(')
		|| !load0.contains('String error = doLoad(filename, fromClass.getClassLoader());')
		|| !load0.contains('throw new UnsatisfiedLinkError(error);') {
		return error('pinned guarded-load/class-based-load contract differs')
	}
	if !vmruntime_java.contains('public static final int SDK_VERSION_CUR_DEVELOPMENT = 10000;')
		|| !vmruntime_java.contains('private int targetSdkVersion = SDK_VERSION_CUR_DEVELOPMENT;')
		|| code_lines(getter) != 'public synchronized int getTargetSdkVersion() {\nreturn targetSdkVersion;\n}' {
		return error('VMRuntime Java target SDK default/getter contract differs')
	}
	boot := 'if (class_linker->IsBootClassLoader(soa, loader.Ptr())) {\n' +
		'      loader = nullptr;\n      class_loader = nullptr;'
	if java_vm_ext.count(boot) != 1 { return error('ART boot-loader normalization contract differs') }
	mut result := map[string]string{}
	for name, body in {'guard': guard, 'guarded_load': load, 'class_load0': load0, 'vmruntime_getter': getter} {
		result[name] = sha256.sum(body.bytes()).hex()
	}
	return result
}

fn controls(native NativeSource, runtime_java string, vmruntime_java string, java_vm_ext string) ![]string {
	current := native.after[runtime_origin]!
	mut passed := []string{}
	for mutation in [
		Mutation{'guarded-load', mutate_load(current, "c'load0'", "c'load'")!},
		Mutation{'old-descriptor', mutate_load(current, '(Ljava/lang/Class;Ljava/lang/String;)V', '(Ljava/lang/String;Ljava/lang/ClassLoader;)V')!},
		Mutation{'reversed-arguments', mutate_load(current, '[Value{ l: framework }, Value{ l: ws_string(e, path) }]', '[Value{ l: ws_string(e, path) }, Value{ l: framework }]')!},
		Mutation{'null-framework', mutate_load(current, 'Value{ l: framework }', 'Value{ l: unsafe { nil } }')!},
		Mutation{'wrong-framework-class', mutate_load(current, "c'android/view/View'", "c'java/lang/Object'")!},
		Mutation{'library-name', mutate_load(current, 'ws_string(e, path)', "ws_string(e, c'vinix-android-native')")!},
		Mutation{'skip-failure', mutate_load(current, "return !ws_failure(e, c'ANDROID-WS-FAIL load JNI backend')", 'return true')!},
		Mutation{'target-sdk-mutation', mutate_load(current, 'args := [Value{ l: framework }', "call(e, runtime, c'dalvik/system/VMRuntime', c'setTargetSdkVersion', c'(I)V', unsafe { nil })\n\targs := [Value{ l: framework }")!},
		Mutation{'outside-function', current + '\n// unrelated native edit\n'},
		Mutation{'duplicate-function', current + '\n' + expected_load() + '\n'},
		Mutation{'unchanged-guarded-predecessor', native.before[runtime_origin]!},
	] {
		if mutation.text == current { return error('inactive mutation: ' + mutation.name) }
		mut changed := native.after.clone()
		changed[runtime_origin] = mutation.text
		if _ := verify_delta(native.before, changed) { return error('unsafe source accepted: ' + mutation.name) }
		passed << mutation.name
	}
	for path in [repo + '/build-support/android/nativews/bootstrap.v', repo + '/build-support/android/nativews/bindings.txt'] {
		mut changed := native.after.clone()
		changed[path] = changed[path]! + '\n'
		if _ := verify_delta(native.before, changed) { return error('bystander source accepted') }
		passed << 'bystander:' + os.file_name(path)
	}
	mut missing := native.after.clone()
	missing.delete(runtime_origin)
	if _ := verify_delta(native.before, missing) { return error('missing native input accepted') }
	passed << 'missing-native-input'
	mut added := native.after.clone()
	added['/unexpected.v'] = 'module atlframework\n'
	if _ := verify_delta(native.before, added) { return error('added native input accepted') }
	passed << 'added-native-input'
	mut changed_before := native.before.clone()
	changed_before[runtime_origin] = changed_before[runtime_origin]! + '\n'
	if _ := verify_delta(changed_before, native.after) { return error('changed predecessor accepted') }
	passed << 'changed-predecessor'
	for names in [[...native.owned_names, 'unexpected.v'], native.owned_names[..native.owned_names.len - 1],
		[...native.owned_names, native.owned_names[0]]] {
		if _ := require_membership(native.owned_names, names) { return error('changed native directory membership accepted') }
		passed << 'native-directory-membership'
	}
	for mutation in [
		Mutation{'removed-compatibility-guard', runtime_java.replace('checkTargetSdkVersionForLoad("java.lang.Runtime#load(String, ClassLoader)");', '')},
		Mutation{'wrong-sdk-threshold', runtime_java.replace('if (targetSdkVersion > 24)', 'if (targetSdkVersion > 10000)')},
		Mutation{'missing-absolute-validation', runtime_java.replace('if (!(new File(filename).isAbsolute()))', 'if (false)')},
		Mutation{'null-loader-selection', runtime_java.replace('doLoad(filename, fromClass.getClassLoader())', 'doLoad(filename, null)')},
	] {
		if mutation.text == runtime_java { return error('inactive primary mutation') }
		if _ := primary_contract(mutation.text, vmruntime_java, java_vm_ext) { return error('incorrect primary contract accepted: ' + mutation.name) }
		passed << mutation.name
	}
	for mutation in [
		Mutation{'wrong-default-sdk', vmruntime_java.replace('SDK_VERSION_CUR_DEVELOPMENT = 10000;', 'SDK_VERSION_CUR_DEVELOPMENT = 24;')},
		Mutation{'wrong-field-initializer', vmruntime_java.replace('targetSdkVersion = SDK_VERSION_CUR_DEVELOPMENT;', 'targetSdkVersion = 24;')},
		Mutation{'wrong-sdk-getter', vmruntime_java.replace('return targetSdkVersion;', 'return 24;')},
	] {
		if mutation.text == vmruntime_java { return error('inactive VMRuntime mutation') }
		if _ := primary_contract(runtime_java, mutation.text, java_vm_ext) { return error('incorrect VMRuntime contract accepted: ' + mutation.name) }
		passed << mutation.name
	}
	if _ := primary_contract(runtime_java, vmruntime_java, java_vm_ext.replace('      class_loader = nullptr;', '      class_loader = class_loader;')) {
		return error('missing ART boot-loader normalization accepted')
	}
	passed << 'missing-boot-normalization'
	return passed
}

fn main() {
	$if prod { panic('live assertions required') }
	if os.args.len != 2 { eprintln('usage: framework-jni-load-source-check FRESH_EXTERNAL_OUTPUT'); exit(2) }
	work := os.abs_path(os.args[1])
	if !work.starts_with(state) || os.exists(work) || os.is_link(work)
		|| os.real_path(os.dir(work)) != os.dir(work) { panic('fresh canonical external output required') }
	mut pins := map[string]string{}
	native := sources(mut pins)!
	verify_delta(native.before, native.after)!
	runtime_java := capture(mut pins, old_primary + '/primary/Runtime.java', runtime_java_pin)!
	java_vm_ext := capture(mut pins, old_primary + '/primary/java_vm_ext.cc', java_vm_ext_pin)!
	vmruntime_java := capture(mut pins, new_primary + '/VMRuntime.java', vmruntime_java_pin)!
	capture(mut pins, old_primary + '/SHA256SUMS', 'e5bc6618969dec60719fa91a49ae4faaee1aacb84c5e740cafb1a142f3592163')!
	for path in [os.real_path(@FILE), repo + '/tests/native-android-ws/framework-jni-load-source-check.v',
		new_primary + '/SHA256SUMS', new_primary + '/source.md', new_primary + '/fetch-result.txt', new_primary + '/fetch.log'] {
		capture(mut pins, path, '')!
	}
	methods := primary_contract(runtime_java, vmruntime_java, java_vm_ext)!
	passed := controls(native, runtime_java, vmruntime_java, java_vm_ext)!
	mut after_pins := map[string]string{}
	for path, pin in pins {
		after_pins[path] = digest(path)!
		if after_pins[path] != pin { panic('source input changed during qualification: ' + path) }
	}
	require_membership(native.owned_names, owned_names()!)!
	os.mkdir(work, mode: 0o700)!
	os.mkdir(work + '/current-inputs', mode: 0o700)!
	for path, body in native.after { os.write_file(work + '/current-inputs/' + os.file_name(path), body)! }
	for name, body in {'runtime-before.v': native.before[runtime_origin]!, 'runtime-after.v': native.after[runtime_origin]!,
		'Runtime.java': runtime_java, 'VMRuntime.java': vmruntime_java, 'java_vm_ext.cc': java_vm_ext} {
		os.write_file(work + '/' + name, body)!
	}
	os.write_file(work + '/inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
	os.write_file(work + '/inputs-after.json', json2.encode(after_pins, prettify: true) + '\n')!
	os.write_file(work + '/result.json', json2.encode({
		'baseline_manifest': json2.Any(baseline_manifest)
		'native_origins': json2.Any(91)
		'native_inputs': json2.Any(92)
		'changed_origins': json2.Any([runtime_origin])
		'changed_function': json2.Any('ws_load_jni')
		'primary_method_sha256': json2.decode[json2.Any](json2.encode(methods))!
		'refused_controls': json2.Any(passed)
		'scope': json2.Any('Source-only exact JNI-load delta and pinned ART contracts; no compiler, native binary or ARM execution result. Historical complete audits remain required.')
	}, prettify: true) + '\n')!
	println('FRAMEWORK-JNI-LOAD-SOURCE PASS origins=91 unchanged=90 inputs=92 changed-functions=1 refusals=' + passed.len.str() + ' pinned-primary input-recheck')
}
