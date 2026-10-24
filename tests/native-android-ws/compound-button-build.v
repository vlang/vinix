// SPDX-License-Identifier: GPL-2.0-or-later
// Compiled with the selected attempt's frozen framework sources first in the V module path.
module main

import androidtools
import crypto.sha256
import json2
import os

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	attempt := os.getenv_opt('VINIX_COMPOUND_ATTEMPT') or { '258' }
	assert attempt.len == 3 && attempt.bytes().all(it >= `0` && it <= `9`)
	base := 'build/android-maps/compound' + attempt
	input := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
	assert hash(input)! == '4acb4a9356b7c0ed53498923e46fbe55acfabfe362f899a0a0a45bfd58f12357'
	pins := json2.decode[map[string]string](os.read_file(base + '/frozen-inputs.json')!)!
	for path, expected in pins { assert hash(path)! == expected, path }
	for path, expected in json2.decode[map[string]string](os.read_file(base + '/framework/sources.json')!)! {
		assert hash(base + '/framework/sources/' + path)! == expected, path
	}
	out := os.abs_path(base + '/framework')
	androidtools.extend_framework(input, out + '/api-impl.jar', out, os.abs_path('build/android-framework/tools'), '/opt/homebrew/opt/openjdk@25/bin/java')!
	for path, expected in pins { assert hash(path)! == expected, path }
	os.cp(out + '/framework-manifest.json', out + '/framework-manifest-live-checkout.json')!
	mut manifest := json2.decode[map[string]json2.Any](os.read_file(out + '/framework-manifest.json')!)!
	mut sources := manifest['sources']!.as_map()
	for key in sources.keys() { if key.starts_with('tests/native-android-tools/androidtools/') { sources.delete(key) } }
	for file in os.ls(out + '/sources/androidtools')! {
		if file.starts_with('framework') && file.ends_with('.v') { sources['tests/native-android-tools/androidtools/' + file] = hash(out + '/sources/androidtools/' + file)! }
	}
	manifest['sources'] = json2.Any(sources)
	manifest['source_scope'] = if attempt in ['264', '266'] { 'Frozen compound262 generators; only framework_view_geometry, framework_view_canvas and framework_text_widgets changed. Live ATL registration sources match262 baseline before and after build.' } else { 'Frozen compound247 generators; only framework_check_widgets changed. Live ATL registration sources match247 baseline before and after build.' }
	os.write_file(out + '/framework-manifest.json', json2.encode(manifest, prettify: true) + '\n')!
	println('COMPOUND' + attempt + ' FRAMEWORK ' + hash(out + '/api-impl.jar')!)
}
