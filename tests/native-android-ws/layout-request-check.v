// SPDX-License-Identifier: GPL-2.0-or-later
// Host transformation and DEX syntax checks; this does not execute ART.
module main

import androidtools
import crypto.sha256
import json2
import os
import startupfixture
import time

const baseline_seal = '4f526669c32b91db3da92d3508b6aa97297d8a8b48b89fef29f6cd3f1f64559e'
const view_key = 'framework/smali/android/view/View.smali'
const jars = ['antlr-2.7.7.jar', 'antlr-3.5.2.jar', 'antlr-runtime-3.5.2.jar',
	'baksmali-2.5.2.jar', 'dexlib2-2.5.2.jar', 'failureaccess-1.0.1.jar',
	'guava-27.1-android.jar', 'jcommander-1.64.jar', 'smali-2.5.2.jar',
	'stringtemplate-3.2.1.jar', 'util-2.5.2.jar']

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn inventory(root string, prefix string, mut files map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut files)! }
			.regular { files[key] = hash(root + '/' + key)! }
			else { return error('nonregular evidence entry: ' + key) }
		}
	}
}

fn command(out string, name string, argv []string) ! {
	r := os.exec(argv)
	write_json(out + '/commands/' + name + '.json', {
		'argv': json2.Any(argv)
		'exit_code': json2.Any(r.exit_code)
		'output': json2.Any(r.output)
	})!
	if r.exit_code != 0 { return error(name + ' failed: ' + r.output) }
}

fn methods(source string) !map[string]string {
	mut result := map[string]string{}
	for block in source.split('\n.method ')[1..] {
		declaration := '.method ' + block.all_before('\n')
		if declaration in result { return error('duplicate method: ' + declaration) }
		end := block.index('.end method') or { return error('unterminated method') }
		result[declaration] = '.method ' + block[..end + '.end method'.len]
	}
	return result
}

fn delta(before string, after string) ![]string {
	old := methods(before)!
	new := methods(after)!
	if old.len != new.len { return error('method count changed') }
	mut changed := []string{}
	for declaration, body in old {
		if declaration !in new { return error('method removed: ' + declaration) }
		if new[declaration]! != body { changed << declaration }
	}
	changed.sort()
	if changed != ['.method public final vinixPerformLayout(IIII)V', '.method public requestLayout()V'] {
		return error('unexpected method delta: ' + changed.str())
	}
	return changed
}

fn roundtrip(out string, java string, variant string) !string {
	command(out, variant + '-assemble', [java, '-cp', out + '/tools/*', 'org.jf.smali.Main',
		'assemble', '--jobs', '2', out + '/' + variant + '-smali', '-o', out + '/' + variant + '.dex'])!
	command(out, variant + '-disassemble', [java, '-cp', out + '/tools/*', 'org.jf.baksmali.Main',
		'disassemble', '--jobs', '2', out + '/' + variant + '.dex', '-o', out + '/' + variant + '-roundtrip'])!
	return os.read_file(out + '/' + variant + '-roundtrip/android/view/View.smali')!
}

fn check() ! {
	if os.args.len != 5 { return error('usage: layout-request-check FRAMEWORK329 JAVA FRESH_EXTERNAL_OUT SOURCE_ROOT') }
	baseline := os.real_path(os.args[1])
	java := os.real_path(os.args[2])
	out := os.abs_path(os.args[3])
	source_root := os.real_path(os.args[4])
	if os.exists(out) || os.is_link(out) { return error('fresh output required') }
	for root in [baseline, source_root] {
		if out == root || out.starts_with(root + '/') { return error('external output required') }
	}
	if hash(baseline + '/sha256.json')! != baseline_seal { return error('baseline seal mismatch') }
	manifest := json2.decode[map[string]string](os.read_file(baseline + '/sha256.json')!)!
	if hash(baseline + '/' + view_key)! != manifest[view_key]! { return error('baseline View changed') }
	os.mkdir_all(out + '/tools')!
	os.mkdir_all(out + '/commands')!
	os.mkdir_all(out + '/negative')!
	os.cp(baseline + '/sha256.json', out + '/baseline-sha256.json')!
	os.cp(os.executable(), out + '/checker')!
	mut inputs := {baseline + '/sha256.json': baseline_seal, java: hash(java)!,
		baseline + '/' + view_key: manifest[view_key]!}
	for name in jars {
		key := 'tools/framework/' + name
		if hash(baseline + '/' + key)! != manifest[key]! { return error('tool pin mismatch: ' + key) }
		os.cp(baseline + '/' + key, out + '/tools/' + name)!
		inputs[baseline + '/' + key] = manifest[key]!
	}
	for relative in ['tests/native-android-ws/layout-request-check.v',
		'tests/native-android-tools/androidtools/framework_layout_requests.v',
		'tests/native-android-tools/androidtools/framework_layout_listeners.v',
		'tests/native-android-tools/androidtools/framework.v',
		'tests/native-android-ws/startupfixture/layout_requests.v',
		'tests/native-android-ws/startupfixture/startup.v'] {
		path := source_root + '/' + relative
		inputs[path] = hash(path)!
		os.mkdir_all(os.dir(out + '/sources/' + relative))!
		os.cp(path, out + '/sources/' + relative)!
	}
	write_json(out + '/inputs-before.json', inputs)!
	original := os.read_file(baseline + '/' + view_key)!
	changed := androidtools.framework_layout_requests(original)!
	source_delta := delta(original, changed)!
	old_methods := methods(original)!
	new_methods := methods(changed)!
	layout := '.method public final vinixPerformLayout(IIII)V'
	request := '.method public requestLayout()V'
	clear := 'const/4 v0, 0\niput-boolean v0, p0, Landroid/view/View;->layoutRequested:Z\n'
	if new_methods[layout]! != old_methods[layout]!.replace(clear, '') { return error('unexpected layout body change') }
	if new_methods[request]!.contains('iget-boolean') { return error('request still stops at a pending child') }
	measure := old_methods['.method public final measure(II)V']!
	consume := measure.index('iput-boolean v0, p0, Landroid/view/View;->layoutRequested:Z') or { return error('missing provider measurement reset') }
	callback := measure.index('->onMeasure(II)V') or { return error('missing provider measurement callback') }
	if consume >= callback {
		return error('provider measurement no longer consumes before callback')
	}
	mut negatives := {
		'missing-layout': original.replace('.method public final vinixPerformLayout(IIII)V', '.method public final otherLayout(IIII)V')
		'duplicate-layout': original + '\n' + old_methods[layout]!
		'unterminated-layout': original.replace(old_methods[layout]!, old_methods[layout]!.replace('.end method', ''))
		'missing-reset': original.replace(':done\n' + clear, ':done\n')
		'duplicate-reset': original.replace(':done\n' + clear, ':done\n' + clear + clear)
		'relocated-reset': original.replace(':done\n' + clear, clear + ':done\n')
		'wrong-reset-field': original.replace(':done\n' + clear, ':done\n' + clear.replace('layoutRequested', 'vinixLayoutRequired'))
		'duplicate-request': original + '\n' + old_methods[request]!
		'missing-request': original.replace(old_methods[request]!, '')
		'nonpublic-request': original.replace('.method public requestLayout()V', '.method protected requestLayout()V')
		'already-patched': changed
	}
	mut rejected := []string{}
	for name, malformed in negatives {
		os.write_file(out + '/negative/' + name + '.smali', malformed)!
		if _ := androidtools.framework_layout_requests(malformed) { return error('accepted malformed input: ' + name) }
		else { rejected << name }
	}
	rejected.sort()
	for variant, body in {'old': original, 'new': changed} {
		os.mkdir_all(out + '/' + variant + '-smali/android/view')!
		os.write_file(out + '/' + variant + '-smali/android/view/View.smali', body)!
	}
	old_roundtrip := roundtrip(out, java, 'old')!
	new_roundtrip := roundtrip(out, java, 'new')!
	dex_delta := delta(old_roundtrip, new_roundtrip)!
	probe_dir := out + '/probe-smali/org/vinix/bootstrap'
	os.mkdir_all(probe_dir)!
	startupfixture.install_layout_request_probe(probe_dir)!
	command(out, 'probe-assemble', [java, '-cp', out + '/tools/*', 'org.jf.smali.Main',
		'assemble', '--jobs', '2', out + '/probe-smali', '-o', out + '/probe.dex'])!
	command(out, 'probe-disassemble', [java, '-cp', out + '/tools/*', 'org.jf.baksmali.Main',
		'disassemble', '--jobs', '2', out + '/probe.dex', '-o', out + '/probe-roundtrip'])!
	probe_classes := os.walk_ext(out + '/probe-roundtrip', '.smali')
	if probe_classes.len != 3 { return error('unexpected probe class count') }
	for path, pin in inputs {
		if hash(path)! != pin { return error('input changed during check: ' + path) }
	}
	write_json(out + '/inputs-after.json', inputs)!
	write_json(out + '/result.json', {
		'scope': json2.Any('HOST transformation and actual DEX roundtrip only; probe assembled but not executed in ART')
		'completed_utc': json2.Any(time.utc().str())
		'baseline_manifest_sha256': json2.Any(baseline_seal)
		'view_methods': json2.Any(old_methods.len)
		'unchanged_methods': json2.Any(old_methods.len - 2)
		'source_method_delta': json2.Any(source_delta)
		'dex_method_delta': json2.Any(dex_delta)
		'rejected_malformed_inputs': json2.Any(rejected)
		'probe_classes': json2.Any(probe_classes.len)
		'checker_sha256': json2.Any(hash(os.executable())!)
		'exit_code': json2.Any(0)
	})!
	mut files := map[string]string{}
	inventory(out, '', mut files)!
	write_json(out + '/sha256.json', files)!
	println('LAYOUT-REQUEST-HOST-CHECK-PASS methods=${old_methods.len} negative=${rejected.len} probe=3 manifest=${hash(out + '/sha256.json')!}')
}

fn main() {
	$if prod { eprintln('assertions required; compile without -prod'); exit(2) }
	check() or { eprintln(err); exit(1) }
}
