// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import guesthost
import hosttest
import json2
import os

struct Receipt {
	architecture string
	case_name string
	context string = 'native Vinix QEMU guest; private tmpfs mounts; root and UID/GID 1000 checks; networking disabled'
	inputs map[string]string
	exit_code int
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--case', value: true, choices: ['flags', 'move', 'identities', 'id-0', 'id-1', 'id-2', 'id-3', 'id-4', 'id-5', 'id-6', 'admission', 'ad-0', 'ad-1', 'ad-2', 'ad-3', 'ad-4', 'ad-5', 'ad-6', 'ad-7', 'propagation', 'pr-0', 'pr-1', 'pr-2', 'pr-3', 'pr-4', 'pivot', 'pv-0', 'pv-1', 'pv-2', 'pv-3', 'pv-4', 'pv-5', 'pv-6', 'pivot-life', 'pl-0', 'pl-1', 'pl-2', 'pl-3', 'all'] },
		hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--probe-state', value: true },
	], [], 'Usage: run.v --arch ARCH --kernel-dir DIR --state-dir FRESH-DIR [--case flags|move|identities|id-0..id-6|admission|ad-0..ad-7|propagation|pr-0..pr-4|pivot|pv-0..pv-6|pivot-life|pl-0..pl-3|all] [--timeout SECONDS] [--probe-state RECEIPT-DIR]')!
	for key in ['--arch', '--kernel-dir', '--state-dir'] {
		if !options.has(key) { eprintln('missing ' + key); exit(2) }
	}
	arch := options.value('--arch', '')
	selected := options.value('--case', 'all')
	probe_state := options.value('--probe-state', '')
	state := os.abs_path(options.value('--state-dir', ''))
	timeout := options.integer('--timeout', 180)!
	if os.exists(state) || timeout <= 0 { eprintln('state must be fresh and timeout positive'); exit(2) }
	kernel := os.read_bytes(options.value('--kernel-dir', '') + '/bin/vinix')!
	machine := if arch == 'aarch64' { 183 } else { 62 }
	if kernel.len < 20 || kernel[..6] != [u8(127), `E`, `L`, `F`, 2, 1]
		|| int(kernel[18]) + (int(kernel[19]) << 8) != machine {
		eprintln('kernel must be matching little-endian ELF64'); exit(2)
	}
	os.mkdir_all(state + '/kernel/bin')!
	os.write_file_array(state + '/kernel/bin/vinix', kernel)!
	os.mkdir_all(state + '/sources')!
	hosttest.module_copy_tree(@DIR + '/mountfixture', state + '/sources/mountfixture')!
	mut inputs := {
		'kernel': sha256.sum(kernel).hex()
		'fixture': digest(state + '/sources/mountfixture/core.v')!
		'identities_fixture': digest(state + '/sources/mountfixture/identities.v')!
		'admission_fixture': digest(state + '/sources/mountfixture/admission.v')!
		'propagation_fixture': digest(state + '/sources/mountfixture/propagation.v')!
		'pivot_fixture': digest(state + '/sources/mountfixture/pivot.v')!
		'pivot_lifecycle_fixture': digest(state + '/sources/mountfixture/pivot_lifecycle.v')!
		'controller': digest(@FILE)!
	}
	if probe_state != '' { inputs['probe_receipt'] = digest(os.abs_path(probe_state) + '/receipt.json')! }
	code := run_guest(state, arch, selected, timeout, probe_state) or { eprintln(err.msg()); 1 }
	for name, path in {'init': state + '/init', 'iso': state + '/test.iso', 'fixture_c': state + '/fixture.c'} {
		inputs[name] = digest(path) or { '' }
	}
	os.write_file(state + '/receipt.json', json2.encode(Receipt{
		architecture: arch, case_name: selected, inputs: inputs, exit_code: code
	}, prettify: true) + '\n')!
	exit(code)
}

fn fixture_init(state string, arch string, probe_state string) !string {
	if probe_state == '' { return guesthost.compile_init(state + '/sources/mountfixture/core.v', state, arch, false)! }
	prior := os.abs_path(probe_state)
	receipt := json2.decode[Receipt](os.read_file(prior + '/receipt.json')!)!
	if receipt.architecture != arch { return error('cached probe architecture differs') }
	for key, file in {'fixture': 'sources/mountfixture/core.v', 'identities_fixture': 'sources/mountfixture/identities.v', 'admission_fixture': 'sources/mountfixture/admission.v', 'propagation_fixture': 'sources/mountfixture/propagation.v', 'pivot_fixture': 'sources/mountfixture/pivot.v', 'pivot_lifecycle_fixture': 'sources/mountfixture/pivot_lifecycle.v'} {
		if receipt.inputs[key] != digest(prior + '/' + file)! || receipt.inputs[key] != digest(state + '/' + file)! {
			return error('cached probe source differs: ' + file)
		}
	}
	for key, file in {'init': 'init', 'fixture_c': 'fixture.c'} {
		if receipt.inputs[key] != digest(prior + '/' + file)! { return error('cached probe artifact differs: ' + file) }
		os.cp(prior + '/' + file, state + '/' + file)!
	}
	bytes := os.read_bytes(state + '/init')!
	machine := if arch == 'aarch64' { 183 } else { 62 }
	if bytes.len < 20 || bytes[..6] != [u8(127), `E`, `L`, `F`, 2, 1]
		|| int(bytes[18]) + (int(bytes[19]) << 8) != machine { return error('cached probe ELF architecture differs') }
	return state + '/init'
}

fn run_guest(state string, arch string, selected string, timeout int, probe_state string) !int {
	init := fixture_init(state, arch, probe_state)!
	os.mkdir_all(state + '/rootfs')!
	os.write_file(state + '/rootfs/mount-case', selected)!
	archive := guesthost.image(init, state)!
	configured := guesthost.launch(init, archive, state, state + '/kernel', arch, true)!
	mut expected := ['MOUNT LIFECYCLE: PASS']
	if selected in ['flags', 'all'] { expected << 'MOUNT UNMOUNT MODES: PASS' }
	if selected in ['move', 'all'] { expected << ['MOUNT MOVE CYCLES: PASS', 'MOUNT REPARENTED HOLDERS: PASS', 'MOUNT MOVE DEPTH: PASS'] }
	if selected in ['identities', 'all'] {
		expected << 'MOUNT IDENTITIES: PASS'
		for kind in 0 .. 7 { expected << 'MOUNT IDENTITY CASE: ${kind} PASS' }
	} else if selected.starts_with('id-') {
		expected << ['MOUNT IDENTITIES: PASS', 'MOUNT IDENTITY CASE: ' + selected.all_after('id-') + ' PASS']
	}
	if selected in ['admission', 'all'] {
		expected << 'MOUNT ADMISSION: PASS'
		for kind in 0 .. 8 { expected << 'MOUNT ADMISSION CASE: ${kind} PASS' }
	} else if selected.starts_with('ad-') {
		expected << ['MOUNT ADMISSION: PASS', 'MOUNT ADMISSION CASE: ' + selected.all_after('ad-') + ' PASS']
	}
	if selected in ['propagation', 'all'] {
		expected << 'MOUNT PROPAGATION VALIDATION: PASS'
		for kind in 0 .. 5 { expected << 'MOUNT PROPAGATION CASE: ${kind} PASS' }
	} else if selected.starts_with('pr-') {
		expected << ['MOUNT PROPAGATION VALIDATION: PASS', 'MOUNT PROPAGATION CASE: ' + selected.all_after('pr-') + ' PASS']
	}
	if selected in ['pivot', 'all'] {
		expected << 'MOUNT PIVOT ADMISSION: PASS'
		for kind in 0 .. 7 { expected << 'MOUNT PIVOT CASE: ${kind} PASS' }
	} else if selected.starts_with('pv-') {
		expected << ['MOUNT PIVOT ADMISSION: PASS', 'MOUNT PIVOT CASE: ' + selected.all_after('pv-') + ' PASS']
	}
	if selected in ['pivot-life', 'all'] {
		expected << 'MOUNT PIVOT LIFECYCLE: PASS'
		for kind in 0 .. 4 { expected << 'MOUNT PIVOT LIFE CASE: ${kind} PASS' }
	} else if selected.starts_with('pl-') {
		expected << ['MOUNT PIVOT LIFECYCLE: PASS', 'MOUNT PIVOT LIFE CASE: ' + selected.all_after('pl-') + ' PASS']
	}
	positive, negative := guesthost.verdict_policy(expected, ['MOUNT LIFECYCLE FAIL:'], false)
	return guesthost.boot(configured.command, configured.env, state, positive, negative, timeout, true)!
}
