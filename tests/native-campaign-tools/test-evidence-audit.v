// SPDX-License-Identifier: GPL-2.0-or-later
module main

import campaignhost
import hosttest
import json2
import os

fn qualify(work string) ! {
	os.mkdir(work)!
	root := hosttest.root()
	old := root + '/build/useralloc-core-v6'
	for name in ['final-gates.json'] { os.cp(old + '/' + name, work + '/' + name)! }
	for mode in ['x86_64', 'x86_64-four-level', 'aarch64'] {
		from := old + '/core-' + mode
		to := work + '/core-' + mode
		os.mkdir(to)!
		for name in ['run.json', 'serial.log', 'qemu-observed.json', 'compile.json', 'compile-exact-flags.json', 'test.c', 'pagetable.c', 'compile.log', 'embedded-arm-kernel', 'embedded-arm-loader', 'embedded-arm-runtime.tar', 'embedded-arm-initramfs.tar'] {
			if os.is_file(from + '/' + name) { os.cp(from + '/' + name, to + '/' + name)! }
		}
		if os.is_dir(from + '/vm') { os.symlink(from + '/vm', to + '/vm')! }
	}
	context := campaignhost.Context{root: root, state: work, origin: work + '/origin'}
	assert campaignhost.core_evidence_audit(context)! == 0
	actual := campaignhost.read_json(work + '/evidence-audit.json')!
	expected := campaignhost.read_json(old + '/evidence-audit.json')!
	for mode, row in actual['modes']!.as_map() {
		old_row := expected['modes']!.as_map()[mode]!.as_map()
		for key in ['serial_sha256', 'all_source_core_pass_marker_count', 'pagetable_check_pass_count', 'exact_flags_binary_identical', 'actual_qemu_process_count', 'static_archive_sha256', 'actual_crt_sha256', 'source_sha256', 'actual_run_command'] {
			assert json2.encode(row.as_map()[key]!) == json2.encode(old_row[key]!), mode + ' ' + key
		}
	}
	for mode in ['x86_64', 'x86_64-four-level', 'aarch64'] {
		path := work + '/core-' + mode + '/serial.log'
		original := os.read_bytes(path)!
		os.write_file_array(path, [...original, ...'\nmutated evidence\n'.bytes()])!
		mut refused := false
		campaignhost.core_evidence_audit(context) or { refused = true }
		assert refused, 'changed serial proof accepted'
		os.write_file_array(path, original)!
	}
	os.write_file(work + '/passed', 'PASS\n')!
	println('FULL CORE EVIDENCE AUDIT / all three immutable modes / exact code-generation proof / live QEMU process evidence / independent ARM payload extraction / changed capture rejection: PASS')
	flush_stdout()
}

fn main() {
	if os.args.len != 2 { eprintln('usage: test-evidence-audit NEW_STATE'); exit(2) }
	qualify(os.args[1]) or { eprintln(err); exit(1) }
}
