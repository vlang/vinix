module recoverycli

import encoding.hex
import hosttest
import imageextract
import os
import traceanalysis as j

#include <sys/stat.h>

fn C.mkfifo(&char, u32) int

fn test_path_options_defaults_exact_names_and_prefixes() {
	for mode in ['recover_g17_abi', 'recover_t6050_power'] {
		assert parse_options(mode, []string{})! == defaults(mode)
		for key in defaults(mode).keys() {
			assert parse_options(mode, [key, './a//../界'])![key] == 'a/../界'
			assert parse_options(mode, [key + '='])![key] == '.'
		}
	}
	assert parse_options('recover_t6050_power', ['--pmp=x', '--pmp-firmware=y'])!['--pmp'] == 'x'
	assert parse_options('recover_g17_abi', ['--firm=//a//./b', '--firmware=/last'])!['--firmware'] == '/last'
	for args in [['--p=x'], ['--output', '--kernel=x'], ['--unknown'], ['--'], ['position']] {
		parse_options('recover_t6050_power', args) or {
			assert err.msg() != ''
			continue
		}
		assert false
	}
}

fn test_preboot_discovery_fixed_depth_regular_files_and_ambiguity() {
	work := hosttest.work_dir('', 'vinix-recovery-glob-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	find_device_tree(work) or { assert err.msg() == 'expected one boot DeviceTree, found: none' }
	first := os.join_path(work, 'a/boot/b/usr/standalone/firmware/devicetree.img4')
	second := os.join_path(work, 'z/boot/b/usr/standalone/firmware/devicetree.img4')
	extra := os.join_path(work, 'a/boot/b/extra/usr/standalone/firmware/devicetree.img4')
	os.mkdir_all(os.dir(first))!
	os.write_file(first, 'fixture')!
	os.mkdir_all(os.dir(extra))!
	os.write_file(extra, 'wrong depth')!
	assert find_device_tree(work)! == first
	os.mkdir_all(second)!
	assert find_device_tree(work)! == first
	os.rmdir(second)!
	assert C.mkfifo(second.str, 0o600) == 0
	assert find_device_tree(work)! == first
	os.rm(second)!
	os.symlink(first, second)!
	find_device_tree(work) or {
		assert err.msg() == 'expected one boot DeviceTree, found: ${first}, ${second}'
		return
	}
	assert false
}

fn original_frontend() !map[string]j.Value {
	return j.decode(os.read_file(os.join_path(os.dir(@FILE), '../t6050power/testdata/frontend.json'))!)!.as_map()
}

fn wrap_adt(data []u8, kind string) []u8 {
	mut fields := imageextract.der_encode(0x16, 'IM4P'.bytes())
	fields << imageextract.der_encode(0x16, kind.bytes())
	fields << imageextract.der_encode(0x16, 'independent native fixture'.bytes())
	fields << imageextract.der_encode(0x04, data)
	return imageextract.der_encode(0x30, fields)
}

fn test_owned_device_tree_and_der_type_exact_consumption() {
	fixture := original_frontend()!
	adt := hex.decode(j.string_value(j.value(fixture, 'adt')))!
	mut image := wrap_adt(adt, 'dtre')
	root := device_tree(image)!
	for i in 0 .. image.len { image[i] = 0 }
	assert root.property('flagged')! == 'abc'.bytes()
	for malformed in [wrap_adt(adt, 'krnl'), wrap_adt([...adt, u8(`x`)], 'dtre'), []u8{},
		wrap_adt(adt, 'dtre')[..8]] {
		device_tree(malformed) or {
			assert err.msg() != ''
			continue
		}
		assert false
	}
}

fn test_g17_reads_all_six_inputs_before_attempting_validation() {
	work := hosttest.work_dir('', 'vinix-recovery-order-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	mut options := defaults('recover_g17_abi')
	keys := ['--driver', '--kernel', '--firmware', '--iogpu', '--iosurface', '--rtbuddy']
	for key in keys { options[key] = os.join_path(work, key[2..]) }
	for key in keys {
		recover_g17(options) or {
			assert err.msg() == '[Errno 2] No such file or directory: ${j.quoted(options[key])}'
			os.write_file(options[key], 'malformed')!
			continue
		}
		assert false
	}
	recover_g17(options) or {
		assert !err.msg().contains('No such file')
		return
	}
	assert false
}

fn test_native_cli_validation_and_failed_recovery_do_not_publish() {
	g17 := os.getenv('VINIX_RECOVER_G17_TOOL')
	power := os.getenv('VINIX_RECOVER_T6050_TOOL')
	if g17 == '' || power == '' { return }
	work := hosttest.work_dir('', 'vinix-recovery-cli-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	for tool in [g17, power] {
		for args in [['--help'], ['--unknown', '-h']] {
			help := hosttest.capture_in([tool, ...args], '', 30, os.environ(), work)!
			assert help.code == 0 && help.stderr == '' && help.stdout.starts_with('usage:')
		}
		for args in [['--unknown'], ['--'], ['--kernel'], ['--kernel', '--help']] {
			failed := hosttest.capture_in([tool, ...args], '', 30, os.environ(), work)!
			assert failed.code == 2 && failed.stdout == '' && failed.stderr.starts_with('usage:')
		}
	}
	assert os.ls(work)!.len == 0
	output := os.join_path(work, 'never/create/report.json')
	failed := hosttest.capture_in([power, '--preboot', work, '--output', output], '', 30, os.environ(), work)!
	assert failed.code == 2 && failed.stdout == ''
	assert failed.stderr.contains('expected one boot DeviceTree, found: none')
	assert !os.exists(os.join_path(work, 'never'))
	fifo := os.join_path(work, 'a/boot/b/usr/standalone/firmware/devicetree.img4')
	os.mkdir_all(os.dir(fifo))!
	assert C.mkfifo(fifo.str, 0o600) == 0
	fifo_failed := hosttest.capture_in([power, '--preboot', work, '--output', output], '',
		5, os.environ(), work)!
	assert fifo_failed.code == 2 && fifo_failed.stdout == ''
	assert fifo_failed.stderr.contains('expected one boot DeviceTree, found: none')
	assert !os.exists(os.join_path(work, 'never'))
	image := os.join_path(work, 'tree.img4')
	adt := hex.decode(j.string_value(j.value(original_frontend()!, 'adt')))!
	os.write_file_array(image, wrap_adt(adt, 'dtre'))!
	existing := os.join_path(work, 'existing.json')
	os.write_file(existing, 'original report')!
	topology_failed := hosttest.capture_in([power, '--device-tree', image, '--output', existing], '', 30, os.environ(), work)!
	assert topology_failed.code == 2 && topology_failed.stdout == ''
	assert !topology_failed.stderr.contains('No such file')
	assert os.read_file(existing)! == 'original report'
	assert os.read_bytes(image)! == wrap_adt(adt, 'dtre')
}
