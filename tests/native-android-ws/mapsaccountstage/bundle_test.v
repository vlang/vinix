// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

import json2
import os

fn test_receipt_numbers_preserve_exact_numeric_contract() {
	for text in ['7', '7.0', '7e0'] {
		value := json2.decode[json2.Any](text) or { panic(err) }
		assert exact_integer(value, 7)
	}
	for text in ['"7"', 'true', 'null', '7.1', '-7', '4294967303', '[]', '{}'] {
		value := json2.decode[json2.Any](text) or { panic(err) }
		assert !exact_integer(value, 7)
	}
}

fn test_sealed_bundle_rejects_inventory_and_inode_changes() ! {
	root := os.join_path(os.real_path(os.temp_dir()), 'maps-bundle-test-' + os.getpid().str())
	assert !os.exists(root)
	os.mkdir(root, mode: 0o700)!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/build.json', '{}')!
	os.write_file(root + '/output', 'output')!
	pins := {'build.json': digest(root + '/build.json')!, 'output': digest(root + '/output')!}
	os.write_file(root + '/sha256.json', json2.encode(pins))!
	seal := digest(root + '/sha256.json')!
	bundle := load_bundle(root, seal)!
	assert bundle.files == pins
	recheck(bundle)!
	os.write_file(root + '/unexpected', 'extra')!
	if _ := load_bundle(root, seal) { assert false, 'unlisted file accepted' }
	os.rm(root + '/unexpected')!
	os.write_file(root + '/output', 'modified')!
	if _ := recheck(bundle) { assert false, 'modified output accepted' }
	os.rm(root + '/output')!
	os.symlink(root + '/build.json', root + '/output')!
	if _ := load_bundle(root, seal) { assert false, 'symlink accepted' }
	os.rm(root + '/output')!
	os.write_file(root + '/output', 'output')!
	if _ := load_bundle(root, 'a'.repeat(64)) { assert false, 'wrong manifest seal accepted' }
}

fn test_exact_outputs_and_typed_receipt_fields() ! {
	pin := 'a'.repeat(64)
	mut value := Bundle{
		files: {'bin/first': pin, 'bin/second': pin}
		receipt: {'outputs_sha256': json2.Any({'bin/first': json2.Any(pin)})}
	}
	assert output_map(value, 'outputs_sha256', ['bin/first'])! == {'bin/first': pin}
	if _ := output_map(value, 'outputs_sha256', ['bin/first', 'bin/second']) { assert false, 'incomplete output set accepted' }
	value = Bundle{
		files: value.files
		receipt: {'outputs_sha256': json2.Any({'bin/first': json2.Any(pin), 'bin/second': json2.Any(pin)})}
	}
	if _ := output_map(value, 'outputs_sha256', ['bin/first']) { assert false, 'extra output accepted' }
	for input in [json2.Any(7), json2.Any(true), json2.Any([json2.Any('test')])] {
		if _ := text_field({'name': input}, 'name') { assert false, 'non-string field accepted' }
	}
	for path in ['', '/absolute', '../escape', 'a//b', 'a/./b', 'a/../b', 'a\nb', 'a\\b'] {
		assert !relative_file(path), path
	}
}

fn test_native_and_launch_cannot_change_framework_identity() ! {
	framework := Bundle{root: '/framework', seal: 'a'.repeat(64)}
	valid := Bundle{
		files: {'framework-sha256.json': framework.seal}
		receipt: {'framework': json2.Any(framework.root), 'framework_sha256': json2.Any(framework.seal)}
	}
	coupled_framework(valid, framework)!
	for field in ['framework', 'framework_sha256'] {
		mut changed := valid.receipt.clone()
		changed[field] = 'different'
		invalid := Bundle{files: valid.files, receipt: changed}
		if _ := coupled_framework(invalid, framework) { assert false, 'changed framework coupling accepted' }
	}
	invalid := Bundle{files: {'framework-sha256.json': 'b'.repeat(64)}, receipt: valid.receipt}
	if _ := coupled_framework(invalid, framework) { assert false, 'wrong retained framework manifest accepted' }
}

fn test_controller_receipt_requires_selected_static_output_and_build_identity() ! {
	root := os.join_path(os.real_path(os.temp_dir()), 'maps-controller-test-' + os.getpid().str())
	assert !os.exists(root)
	os.mkdir_all(root + '/bin')!
	defer { os.rmdir_all(root) or {} }
	mut bytes := []u8{len: 120}
	for index, value in [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] { bytes[index] = value }
	bytes[16] = 2
	bytes[18] = 183
	bytes[20] = 1
	bytes[32] = 64
	bytes[52] = 64
	bytes[54] = 56
	bytes[56] = 1
	bytes[64] = 1
	bytes[96] = 120
	bytes[104] = 120
	os.write_file_array(root + '/bin/controller', bytes)!
	pin := digest(root + '/bin/controller')!
	valid := Bundle{
		root: root
		files: {'bin/controller': pin}
		receipt: {
			'kind': json2.Any('controller-kind')
			'source_revision': json2.Any('a'.repeat(40))
			'native_base_sha256': json2.Any(baseline_seal)
			'compiler_sha256': json2.Any(compiler_seal)
			'outputs_sha256': json2.Any({'bin/controller': json2.Any(pin)})
		}
	}
	verify_static_controller(valid, 'controller-kind', 'controller')!
	for field in ['kind', 'source_revision', 'native_base_sha256', 'compiler_sha256'] {
		mut receipt := valid.receipt.clone()
		receipt[field] = 'changed'
		if _ := verify_static_controller(Bundle{root: root, files: valid.files, receipt: receipt}, 'controller-kind', 'controller') {
			assert false, 'controller build identity mutation accepted: ' + field
		}
	}
	if _ := verify_static_controller(Bundle{root: root, files: valid.files, receipt: {
		...valid.receipt
		'outputs_sha256': json2.Any({'bin/controller': json2.Any('b'.repeat(64))})
	}}, 'controller-kind', 'controller') { assert false, 'controller output mutation accepted' }
}
