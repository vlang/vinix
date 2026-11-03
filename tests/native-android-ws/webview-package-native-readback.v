// SPDX-License-Identifier: GPL-2.0-or-later
// Independently measure the complete newly coupled native producer inputs.
module main

import json2
import mapsaccountstage as stage
import os

const state = '/Users/alex/.local/state/vinix/android/'
const previous_root = state + 'current-native-build-2026-11-02-broadcast-permission-r1'
const previous_seal = 'e371c8d365b78493f9f9d660ceceb1cb2b1382eaa60cae06bcbe4aad0c6c233b'
const previous_sdk = state + 'combined-account-webview-broadcast-permission-framework-2026-11-02-r1'
const previous_sdk_seal = '49daffbfa9dc1dcc598e453eaae3611df7702963aa5b659022545149af7132d5'
const successor_root = state + 'current-native-build-2026-11-03-webview-package-r2'
const successor_sdk = state + 'combined-account-webview-webview-package-framework-2026-11-03-r1'
const repo = '/Users/alex/code/vinix/'

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

fn run(native_seal string, sdk_seal string, output string) ! {
	if !stage.valid_pin(native_seal) || !stage.valid_pin(sdk_seal)
		|| os.exists(output) || os.is_link(output) || !output.starts_with(state)
		|| os.real_path(os.dir(output)) != os.dir(output) { return error('exact pins and fresh external output required') }
	old := stage.load_bundle(previous_root, previous_seal)!
	new := stage.load_bundle(successor_root, native_seal)!
	old_sdk := stage.load_bundle(previous_sdk, previous_sdk_seal)!
	new_sdk := stage.load_bundle(successor_sdk, sdk_seal)!
	stage.verify_native(old, old_sdk)!
	stage.verify_native(new, new_sdk)!
	if stage.text_field(new.receipt, 'framework')! != new_sdk.root
		|| stage.text_field(new.receipt, 'framework_sha256')! != new_sdk.seal
		|| new.files['framework-sha256.json']! != new_sdk.seal { return error('new native producer must couple directly to new SDK') }
	for name in ['baseline', 'baseline_sha256', 'compiler_library_baseline', 'compiler_library_sha256', 'compiler_source_policy'] {
		if new.receipt[name]! != old.receipt[name]! { return error('native producer baseline/library policy changed') }
	}
	for name in ['builder-source.v', 'native/bindings.txt', 'native/source-origins.json', 'native/current-inputs.json',
		'native/atlframework/ws_generated.v', 'native/android-native.c', 'native/exports.json', 'tools/find-v.sh',
		'native/androidfw_c_api.h', 'native/sqlite3.h', 'native/stb_image.h', 'native/stb_truetype.h',
		'reused-inputs.json', 'crosscompiler-specs.txt', 'compiler-library-sha256.json', 'compiler-library-origins.json'] {
		if old.files[name]! != new.files[name]! { return error('native implementation/toolchain input changed: ' + name) }
	}
	origins := object(new, 'native/source-origins.json')!
	inputs := object(new, 'native/current-inputs.json')!
	if origins.len != 91 || inputs.len != 92 { return error('exact 91 native origins and 92 inputs required') }
	for name, origin in origins {
		if os.file_name(origin) != name || origin !in inputs
			|| old.files['native/atlframework/' + name]! != new.files['native/atlframework/' + name]!
			|| new.files['native/atlframework/' + name]! != inputs[origin]! { return error('native source membership or value differs') }
	}
	if old.files.keys().filter(it.starts_with('native/atlframework/')).sorted()
		!= new.files.keys().filter(it.starts_with('native/atlframework/')).sorted() { return error('native source membership changed') }
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
		'smali/android/content/Context.smali': ['3819dd399a1ac9e8fba32ada045cc250f670f4fa012d765126ded7d1acbba0e8', '60fdbab8aef10711d65afa9a0ddf5e64369ae21e0f9010291288109ebc305ab5'],
		'smali/android/atl/ATLLoadedApp.smali': ['3e133e9cf9a3a2271bfef87917f2060c14b40a550dfb6f760c5b4278580b729f', '6e8d9800711ae17e8b8a86de267590c2bb702d7d6fe8db870c57e6a599e5b0bd'],
		'smali/android/webkit/WebView.smali': ['c166edde745619d979459f2f1b796e862b293fdb1c5052731982a8d92782c40b', new_sdk.files['smali/android/webkit/WebView.smali']!],
	} || canonical_delta.keys() != ['smali/android/webkit/WebView.smali'] { return error('exact three raw and one canonical consumed deltas required') }
	if compiler_root(old)! != compiler_root(new)! || headers(old)! != headers(new)! {
		return error('complete compiler-root or normalized consumed-header input changed')
	}
	old_generator, new_generator := closure(old, 'native-generator')!, closure(new, 'native-generator')!
	if old_generator.len != 340 || old_generator != new_generator { return error('complete 340-input native generator must stay equal') }
	old_builder, new_builder := closure(old, 'builder')!, closure(new, 'builder')!
	builder_delta := delta(old_builder, new_builder)
	for path, pins in builder_delta {
		if !path.starts_with(repo) || pins[1] == '' { return error('builder compiler changes or removed source require separate review') }
	}
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
		'kind': json2.Any('vinix-webview-package-native-readback-v1'),
		'previous_manifest_sha256': json2.Any(old.seal), 'native_manifest_sha256': json2.Any(new.seal),
		'framework_manifest_sha256': json2.Any(new_sdk.seal), 'native_build_sha256': json2.Any(new.files['build.json']!),
		'native_dso_sha256': json2.Any(new.files['native/libvinix-android-native.so']!),
		'consumed_headers_sha256': json2.Any(new.files['native/consumed-headers.json']!),
		'builder_count_before': json2.Any(old_builder.len), 'builder_count_after': json2.Any(new_builder.len),
		'builder_delta': json2.decode[json2.Any](json2.encode(builder_delta))!,
		'builder_after_delta': json2.decode[json2.Any](json2.encode(after_helpers))!,
		'consumed_raw_delta': json2.decode[json2.Any](json2.encode(raw_delta))!,
		'consumed_canonical_delta': json2.decode[json2.Any](json2.encode(canonical_delta))!,
		'needed': json2.decode[json2.Any](json2.encode(new_elf.needed))!,
	}
	for bundle in [old, new, old_sdk, new_sdk] { stage.recheck(bundle)! }
	os.write_file(output, json2.encode(result, prettify: true) + '\n')!
	println('WEBVIEW-PACKAGE-NATIVE-READBACK-PASS origins=91 inputs=92 consumed=70 exports=721 headers=58 generator=340 builder-before=' + old_builder.len.str() + ' builder-after=' + new_builder.len.str() + ' builder-delta=' + builder_delta.len.str())
}

fn main() {
	if os.args.len != 4 { eprintln('usage: webview-package-native-readback NATIVE_MANIFEST_SHA256 SDK_MANIFEST_SHA256 FRESH_EXTERNAL_JSON'); exit(2) }
	run(os.args[1], os.args[2], os.args[3]) or { eprintln(err); exit(1) }
}
