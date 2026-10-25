// SPDX-License-Identifier: GPL-2.0-or-later
// Compile with the isolated312 framework sources first in the V module path.
module main

import androidtools
import crypto.sha256
import json2
import os

const base = 'build/android-maps/paint-text-widths312-framework'
const java = '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn verify_inputs() ! {
	for path, pin in json2.decode[map[string]string](os.read_file(base + '/frozen-inputs.json')!)! {
		selected := if path == '/opt/homebrew/opt/openjdk@25/bin/java' { java } else { path }
		assert hash(selected)! == pin, path
		assert hash(base + '/inputs/' + path.trim_left('/'))! == pin, path
	}
	for path, pin in json2.decode[map[string]string](os.read_file(base + '/framework/sources.json')!)! {
		assert hash(base + '/framework/sources/' + path)! == pin, path
	}
}

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	verify_inputs()!
	input := os.abs_path(base + '/input/api-impl.jar')
	assert hash(input)! == '4acb4a9356b7c0ed53498923e46fbe55acfabfe362f899a0a0a45bfd58f12357'
	out := os.abs_path(base + '/framework')
	androidtools.extend_framework(input, out + '/api-impl.jar', out, os.abs_path(base + '/tools/framework'), java)!
	verify_inputs()!
	os.cp(out + '/framework-manifest.json', out + '/framework-manifest-live-checkout.json')!
	mut manifest := json2.decode[map[string]json2.Any](os.read_file(out + '/framework-manifest.json')!)!
	mut sources := manifest['sources']!.as_map()
	for key in sources.keys() {
		if key.starts_with('tests/native-android-tools/androidtools/') { sources.delete(key) }
	}
	for file in os.ls(out + '/sources/androidtools')! {
		if file.starts_with('framework') && file.ends_with('.v') {
			sources['tests/native-android-tools/androidtools/' + file] = hash(out + '/sources/androidtools/' + file)!
		}
	}
	manifest['sources'] = json2.Any(sources)
	manifest['source_scope'] = 'Exact sealed309 framework generators plus framework_classes registration and new framework_paint_text_widths. NinePatchDrawable dimensions, optical insets, hints, RippleDrawable and PathOps generators remain identical. ATL registration inputs match309 before and after generation; actual consumed frozen generator closure retained separately. Native309 is retained as a baseline reference; runtime pairing is supplied by a separate native312 build.'
	os.write_file(out + '/framework-manifest.json', json2.encode(manifest, prettify: true) + '\n')!
	println('FRAMEWORK312 BUILT jar=' + hash(out + '/api-impl.jar')!)
}
