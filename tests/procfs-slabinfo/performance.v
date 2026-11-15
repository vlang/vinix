// SPDX-License-Identifier: GPL-2.0-or-later
// Rerun a retained fixed six-scenario profile with only a new kernel selection.
module main

import crypto.sha256
import json2
import os

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn execute(args []string, prefix string) ! {
	os.write_file(prefix + '.argv.json', json2.encode(args) + '\n')!
	result := os.exec(args)
	os.write_file(prefix + '.log', result.output)!
	os.write_file(prefix + '.status', result.exit_code.str() + '\n')!
	if result.exit_code != 0 { return error('failed: ' + prefix + '\n' + result.output) }
}

fn run() ! {
	if os.args.len != 5 { return error('usage: performance OWNER PREPARATION-PROFILE KERNEL FRESH-STATE') }
	owner, reference, kernel, state := os.real_path(os.args[1]), os.real_path(os.args[2]),
		os.real_path(os.args[3]), os.abs_path(os.args[4])
	if os.exists(state) || os.is_link(state) { return error('fresh external state required') }
	mut p := json2.decode[map[string]json2.Any](os.read_file(reference)!)!
	if p['arch']!.str() != 'aarch64' { return error('retained fixed ARM profile required') }
	for field, pin in {'base': 'base_manifest_sha256', 'desktop': 'desktop_sha256', 'adapter': 'adapter_sha256'} {
		if hash(p[field]!.str())! != p[pin]!.str() { return error('reference input changed: ' + field) }
	}
	os.mkdir_all(state + '/bin')!
	os.mkdir_all(state + '/kernel/bin')!
	os.cp(owner, state + '/bin/owner')!
	os.cp(p['adapter']!.str(), state + '/bin/adapter')!
	os.cp(kernel, state + '/kernel/bin/vinix')!
	p['adapter'] = json2.Any(state + '/bin/adapter')
	p['kernel'] = json2.Any(state + '/kernel/bin/vinix')
	p['kernel_sha256'] = json2.Any(hash(kernel)!)
	p['prepared_state'] = json2.Any(state + '/prepared')
	p['inputs_sha256'] = json2.Any('')
	p['charged_roots'] = json2.Any([json2.Any(state), p['directory']!, json2.Any(os.dir(p['compiler']!.str()))])
	owner_copy := state + '/bin/owner'
	profile := state + '/preparation-profile.json'
	os.write_file(profile, json2.encode(p, prettify: true) + '\n')!
	execute([owner_copy, 'admit-prepare', state + '/admission', profile], state + '/admit')!
	admission := json2.decode[map[string]string](os.read_file(state + '/admission/admission.json')!)!
	p['inputs_sha256'] = json2.Any(admission['inputs_sha256'])
	os.write_file(profile, json2.encode(p, prettify: true) + '\n')!
	execute([owner_copy, 'prepare', state + '/preparation-owner', profile], state + '/prepare')!
	prepared := json2.decode[map[string]string](os.read_file(state + '/preparation-owner/preparation.json')!)!
	mut runtime := map[string]json2.Any{}
	for field in ['adapter', 'directory', 'prepared_state', 'charged_limit_kib', 'charged_roots'] { runtime[field] = p[field]! }
	runtime['prepared_sha256'] = json2.Any(prepared['prepared_sha256'])
	runtime['timeout_seconds'] = json2.Any(2520)
	runtime['log_limit_bytes'] = json2.Any(8 * 1024 * 1024)
	mut inputs := p['input_roots']!.as_array().clone()
	inputs << json2.Any(os.dir(p['compiler']!.str()))
	inputs << json2.Any(os.dir(p['sampler_compiler']!.str()))
	for folder in ['tests/desktop-perf', 'tests/hardware-platform/hwhost', 'tests/hardware-platform/plainiso',
		'tests/linuxkpi/hosttest', 'tools/hosttest', 'tools/sourcecommand', 'tools/qmpclient'] {
		inputs << json2.Any(p['directory']!.str() + '/' + folder)
	}
	runtime['input_roots'] = json2.Any(inputs)
	os.write_file(state + '/runtime-profile.json', json2.encode(runtime, prettify: true) + '\n')!
	execute([owner_copy, 'run', state + '/runtime-owner', state + '/runtime-profile.json'], state + '/runtime')!
	if hash(kernel)! != p['kernel_sha256']!.str() || hash(owner)! != hash(owner_copy)! {
		return error('selected kernel/owner changed')
	}
	println('SLABINFO fixed six-scenario execution complete; run unchanged strict flatness checks separately')
}

fn main() { run() or { eprintln(err); exit(1) } }
