// SPDX-License-Identifier: GPL-2.0-or-later
// Record preparation of a generated replay helper; never launch QEMU.
module main

import crypto.sha256
import json2
import os
import time

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}
fn record(root string, label string, argv []string, inputs []string) ! {
	mut pins := map[string]string{}
	for path in [argv[0], ...inputs] { pins[path] = hash(path)! }
	mut receipt := {'argv': json2.Any(argv), 'recorded_before_command_utc': json2.Any(time.utc().str()),
		'input_sha256': json2.decode[json2.Any](json2.encode(pins))!}
	os.write_file(root + '/' + label + '-before.json', json2.encode(receipt, prettify: true) + '\n')!
	result := os.exec(argv)
	os.write_file(root + '/' + label + '.log', result.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(result.exit_code)
	receipt['log_sha256'] = hash(root + '/' + label + '.log')!
	for path, pin in pins { if hash(path)! != pin { return error('command input changed: ' + path) } }
	os.write_file(root + '/' + label + '-receipt.json', json2.encode(receipt, prettify: true) + '\n')!
	if result.exit_code != 0 { return error(label + ': ' + result.output) }
}
fn prepare() ! {
	if os.args.len != 5 { return error('usage: maps-replay-prepare GENERATED_HELPER.v FROZEN256 STOPPED_MEDIA EXTERNAL_PREFIX') }
	source, frozen, media, prefix := os.args[1], os.args[2], os.args[3], os.args[4]
	if !os.is_abs_path(prefix) || !os.is_dir(os.dir(prefix)) { return error('absolute external prefix with existing parent required') }
	resolved := os.real_path(os.dir(prefix)) + '/' + os.file_name(prefix)
	if resolved == os.real_path(os.getwd()) || resolved.starts_with(os.real_path(os.getwd()) + '/') { return error('evidence must be outside checkout') }
	root, prelaunch, helper := prefix + '-preparation', prefix + '-prelaunch', source + '.prepare'
	for path in [root, prelaunch, helper] { if os.exists(path) || os.is_link(path) { return error('fresh preparation path required: ' + path) } }
	os.mkdir_all(root)!
	os.cp(@FILE, root + '/record.v')!
	os.cp(os.executable(), root + '/record')!
	compiler := '/Users/alex/code/v/v_old'
	record(root, 'compile', [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', helper, source], [source])!
	record(root, 'self-test', [helper, '--self-test', frozen + '/inputs/build/android-maps/suite256-resume.v'], [source])!
	record(root, 'prepare', [helper, 'prepare', frozen, media, prelaunch], [source])!
	pin := hash(prelaunch + '/prelaunch-sha256.json')!
	record(root, 'full-check', [helper, 'check', prelaunch, pin], [source])!
	mut manifest := map[string]string{}
	for name in os.ls(root)! { manifest[name] = hash(root + '/' + name)! }
	os.write_file(root + '/sha256.json', json2.encode(manifest, prettify: true) + '\n')!
	println('MAPS PRELAUNCH READY root=' + prelaunch + ' pin=' + pin)
	println('MAPS PREPARATION CHECK PASS root=' + root + ' pin=' + hash(root + '/sha256.json')!)
}
fn main() {
	$if prod { eprintln('preparation requires assertions; compile without -prod'); exit(2) }
	prepare() or { eprintln(err); exit(1) }
}
