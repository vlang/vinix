// SPDX-License-Identifier: GPL-2.0-or-later
// Collect already independently admitted native evidence and host regressions.
module main

import json2
import os
import proof

struct Control { name string code int output string }
struct Controls { arguments []string artifacts map[string]string controls []Control }
struct HostCheck { name string executable string sha256 string exit_code int output string }

fn host_check(name string, path string) !HostCheck {
	mut child := os.new_process(path)
	defer { child.close() }
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	child.wait()
	if child.code != 0 { return error('host regression failed: ' + name + ': ' + output) }
	return HostCheck{name, path, proof.digest(path)!, child.code, output}
}

fn collect() ! {
	if os.args.len != 5 { return error('use ARM_CONTROL_DIRECTORY X86_CONTROL_DIRECTORY POINTER_HOST_TEST_DIRECTORY NEW_OUTPUT_DIRECTORY') }
	out := os.abs_path(os.args[4])
	if os.exists(out) { return error('collection output already exists') }
	mut files := map[string]string{}
	for index, arch in ['aarch64', 'x86_64'] {
		controls := os.abs_path(os.args[index + 1])
		baseline := controls + '/native-baseline'
		report := json2.decode[Controls](os.read_file(controls + '/controls.json')!)!
		if report.controls.len != 42 || report.controls[0].name != 'native-baseline' || report.controls[1].name != 'private-baseline' {
			return error('expected two baselines and forty refusals: ' + arch)
		}
		mut names := map[string]bool{}
		for number, control in report.controls {
			if control.name in names || (number < 2 && control.code != 0) || (number >= 2 && control.code == 0) {
				return error('control result differs: ' + arch + '/' + control.name)
			}
			names[control.name] = true
		}
		retained := json2.decode[map[string]string](os.read_file(baseline + '/retention.json')!)!
		if retained['architecture'] or { '' } != arch ||
			retained['qualification'] or { '' } != proof.digest(baseline + '/qualification.json')! ||
			report.artifacts['native-receipt'] or { '' } != retained['qualification']! ||
			report.artifacts['retainer'] or { '' } != retained['retainer']! {
			return error('independent control and retained receipt binding differs: ' + arch)
		}
		for name in ['qualification.json', 'retention.json', 'serial.log', 'shutdown-1.jsonl', 'qemu-exit.json',
			'01-catalog.png', '02-painted.png', '03-pointer.png', '04-closed.png'] {
			files[arch + '/' + name] = baseline + '/' + name
		}
		files[arch + '/controls.json'] = controls + '/controls.json'
	}
	root := os.real_path('.')
	mut sources := map[string]string{}
	for name in ['check.v', 'guest/main.v', 'retain.v', 'evidence-check.v', 'collect.v', 'proof/admit.v', 'proof/admit_test.v'] {
		sources['tests/software-hosted-x11/' + name] = proof.digest(root + '/tests/software-hosted-x11/' + name)!
	}
	for name in ['desktop/app.v', 'desktop/tools/tests/software_pointer_test.v', 'desktop/tools/test-app-selection.v'] {
		sources[name] = proof.digest(root + '/' + name)!
	}
	// Assertions remain enabled in these prebuilt host tests. The pointer test's
	// generated C is retained by the documented setup runner; it contains both
	// test entry points and their actual assertion failure branches.
	pointer := os.abs_path(os.args[3])
	generated := pointer + '/test.c'
	c := os.read_file(generated)!
	if !c.contains('test_software_factory_enables_remote_hosted_pointer_transport') ||
		!c.contains('test_software_pointer_delegates_scaled_motion_press_and_release_only_when_ready') ||
		!c.contains('software_pointer_test.v:32: fn test_software_pointer') {
		return error('host pointer assertion branches absent')
	}
	checks := [host_check('software-pointer-normal-2-tests', pointer + '/test')!,
		host_check('software-pointer-asan-ubsan-2-tests', root + '/build/software-hosted-x11-tools/software-pointer-asan')!,
		host_check('proof-inventory-archive-3-tests', root + '/build/software-hosted-x11-tools/proof-test')!]
	os.mkdir_all(out)!
	mut pins := map[string]string{}
	for relative, path in files {
		os.mkdir_all(os.dir(out + '/' + relative))!
		os.cp(path, out + '/' + relative)!
		if proof.digest(path)! != proof.digest(out + '/' + relative)! { return error('copied evidence differs') }
		pins[relative] = proof.digest(out + '/' + relative)!
	}
	os.write_file(out + '/host-checks.json', json2.encode(checks))!
	os.write_file(out + '/source-inputs.json', json2.encode(sources))!
	os.write_file(out + '/collector.json', json2.encode({'arguments': json2.Any(os.args.map(json2.Any(it))),
		'compiler': json2.Any(proof.digest(@VEXE)!), 'source': json2.Any(proof.digest(@FILE)!),
		'binary': json2.Any(proof.digest(os.executable())!), 'pointer_generated_c': json2.Any(proof.digest(generated)!)}))!
	for name in ['host-checks.json', 'source-inputs.json', 'collector.json'] { pins[name] = proof.digest(out + '/' + name)! }
	os.write_file(out + '/evidence-pins.json', json2.encode(pins))!
	println('PASS hosted X11 evidence collection; two architectures, forty refusals each, seven host test executions')
}

fn main() { collect() or { eprintln(err); exit(1) } }
