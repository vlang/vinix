// SPDX-License-Identifier: GPL-2.0-or-later
// Minimal host proof. Copy this source and the two providers beneath a frozen
// V root before compiling; full framework and ART qualification are separate.
module main

import androidtools
import crypto.sha256
import json2
import os
import startupfixture

fn hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular source proof input: ' + key) }
		}
	}
}

fn command(root string, label string, argv []string) ! {
	r := os.exec(argv)
	os.write_file(root + '/' + label + '.log', r.output)!
	os.write_file(root + '/' + label + '.json', json2.encode({
		'argv': json2.Any(argv), 'exit_code': json2.Any(r.exit_code)
	}, prettify: true) + '\n')!
	assert r.exit_code == 0, label + ': ' + r.output
	assert r.output.trim_space() == '', label + ': unexpected assembler diagnostics'
}

fn rejected_unchanged(dir string) ! {
	mut before := map[string]string{}
	inventory(dir, '', mut before)!
	mut rejected := false
	androidtools.framework_service_stop(dir) or { rejected = true }
	assert rejected, 'invalid service stop provider input accepted'
	mut after := map[string]string{}
	inventory(dir, '', mut after)!
	assert before == after, 'rejected provider application mutated files'
}

fn extract(text string, signature string) !string {
	start := text.index(signature) or { return error('method missing: ' + signature) }
	tail := text[start..]
	end := tail.index('.end method') or { return error('method end missing') }
	return tail[..end + '.end method'.len]
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 5, 'WORK_ROOT BASELINE_ATL_SMALI JAVA JARS'
	root := os.abs_path(os.args[1])
	baseline := os.abs_path(os.args[2])
	java := os.abs_path(os.args[3])
	jars := os.abs_path(os.args[4])
	assert !os.exists(root + '/smali') && !os.exists(root + '/classes.dex')
	mut inputs := map[string]string{}
	inputs[baseline] = hash(baseline)!
	inputs[java] = hash(java)!
	for name in os.ls(jars)! { inputs[jars + '/' + name] = hash(jars + '/' + name)! }
	old := os.read_file(baseline)!
	app := '/android/atl/ATLLoadedApp.smali'
	request := '/android/atl/VinixServiceStop.smali'
	signature := '.method public stopService(Landroid/content/Intent;)Z\n'
	original := extract(old, signature)!
	for n in 0 .. 4 {
		dir := root + '/rejected-' + n.str()
		os.mkdir_all(dir + '/android/atl')!
		mut malformed := old
		match n {
			0 { malformed = old.replace(signature, signature.replace('public', 'private')) }
			1 { malformed = old.replace('Landroid/atl/VinixServiceBinding;->maybeDestroy(', 'Landroid/atl/VinixServiceBinding;->missingDestroy(') }
			2 { malformed = old.replace('Landroid/app/Service;->vinixStarted:Z', 'Landroid/app/Service;->missingStarted:Z') }
			3 { os.write_file(dir + request, 'destination already occupied\n')! }
			else {}
		}
		os.write_file(dir + app, malformed)!
		rejected_unchanged(dir)!
	}
	dir := root + '/smali'
	os.mkdir_all(dir + '/android/atl')!
	os.write_file(dir + app, old)!
	androidtools.framework_service_stop(dir)!
	rejected_unchanged(dir)!
	text := os.read_file(dir + app)!
	helper_signature := '.method final vinixStopServiceMain(Landroid/content/Intent;)Z\n'
	assert extract(text, helper_signature)! == original.replace(signature, helper_signature), 'original main-looper stop semantics changed'
	assert text.replace(extract(text, signature)! + '\n\n' + extract(text, helper_signature)!, original) == old, 'unrelated ATLLoadedApp source changed'
	fixture := dir + '/org/vinix/bootstrap'
	os.mkdir_all(fixture)!
	startupfixture.install_service_stop_probe(fixture)!
	assert os.ls(fixture)!.len == 4
	command(root, 'assemble', [java, '-cp', jars + '/*', 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', dir, '-o', root + '/classes.dex'])!
	assert os.file_size(root + '/classes.dex') > 0, 'assembler did not create DEX'
	command(root, 'disassemble', [java, '-cp', jars + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2', root + '/classes.dex', '-o', root + '/disassembled'])!
	mut classes := map[string]string{}
	inventory(root + '/disassembled', '', mut classes)!
	assert classes.len == 6, 'expected two provider and four fixture classes'
	assert 'android/atl/ATLLoadedApp.smali' in classes && 'android/atl/VinixServiceStop.smali' in classes
	for name in ['ServiceStopProbe', 'ServiceStopService', 'ServiceStopWorker', 'ServiceStopConnection'] {
		assert 'org/vinix/bootstrap/' + name + '.smali' in classes
	}
	for path, pin in inputs { assert hash(path)! == pin, 'input changed during source proof: ' + path }
	os.write_file(root + '/inputs.json', json2.encode(inputs, prettify: true) + '\n')!
	os.write_file(root + '/validation.json', json2.encode({
		'scope': 'Host source generation, four malformed/destination guard cases, duplicate guard, unchanged main helper, six-class API28 assemble/disassemble; no ART or framework runtime claim.',
		'malformed_cases': '4', 'duplicate_unchanged': 'true', 'original_main_helper_unchanged': 'true',
		'assembled_classes': '6', 'dex_sha256': hash(root + '/classes.dex')!
	}, prettify: true) + '\n')!
	println('SERVICE-STOP-SOURCE-CHECK-PASS guards=5 classes=6 dex=' + hash(root + '/classes.dex')!)
}
