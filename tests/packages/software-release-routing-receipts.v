// SPDX-License-Identifier: GPL-2.0-or-later
// Summarize completed routing evidence; the original strict auditors remain required.
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn git_output(arguments []string, work string) !string {
	mut child := os.new_process('git')
	defer { child.close() }
	child.set_args(arguments)
	child.set_work_folder(work)
	child.set_redirect_stdio()
	child.run()
	result := child.stdout_slurp() + child.stderr_slurp()
	child.wait()
	if child.code != 0 { return error('git receipt failed') }
	return result
}

fn admit_controls(controls []json2.Any) ! {
	if controls.len != 107 { return error('expected baseline plus 106 corruptions') }
	mut seen := map[string]bool{}
	for index, entry in controls {
		control := entry.as_map()
		name := control['name']!.str()
		code := control['code']!
		if name == '' || name in seen || code !is f64 || code.f64() != f64(code.int()) ||
			(index == 0 && (name != 'baseline' || code.int() != 0)) ||
			(index > 0 && code.int() == 0) || control['output']!.str() == '' {
			return error('invalid completed control result')
		}
		seen[name] = true
	}
}

fn equal_maps(root string, before string, after string, mut pins map[string]string) ! {
	if json2.decode[map[string]string](os.read_file(root + '/' + before)!)! !=
		json2.decode[map[string]string](os.read_file(root + '/' + after)!)! {
		return error('before/after differs: ' + before)
	}
	pins[before] = digest(root + '/' + before)!
	pins[after] = digest(root + '/' + after)!
}

fn retain(root string, work string, out string) ! {
	if os.exists(out) || os.is_link(out) { return error('output already exists') }
	mut qualification := map[string]json2.Any{}
	mut before_after := map[string]string{}
	for arch in ['aarch64', 'x86_64'] {
		run := root + '/run-' + arch + '-06'
		proof := root + '/proof-' + arch + '-06-02'
		matrix := json2.decode[json2.Any](os.read_file(proof + '/controls.json')!)!.as_map()
		controls := matrix['controls']!.as_array()
		admit_controls(controls)!
		receipt := json2.decode[json2.Any](os.read_file(run + '/qualification.json')!)!.as_map()
		artifacts := receipt['artifacts']!.as_map()
		paths := receipt['artifact_paths']!.as_map()
		if receipt['architecture']!.str() != arch || receipt['platform']!.str() !=
			'qemu-framebuffer-ordinary-seat-release-routing-installed-root-two-boots' ||
			paths.len != artifacts.len { return error('native receipt scope differs') }
		mut screenshots := 0
		for name, path in paths {
			if name !in artifacts { return error('artifact coverage differs') }
			if path.str().ends_with('.png') { screenshots++ }
		}
		if screenshots != 23 { return error('native screenshot inventory differs') }
		baseline_output := controls[0].as_map()['output']!.str()
		if baseline_output != 'SOFTWARE GRAPHICAL RETAIN PASS ' + arch + ': ' +
			artifacts.len.str() + ' artifact digests and 20 current desktop identity/seat/runtime/release sources match\n' {
			return error('strict baseline result differs')
		}
		qualification[arch] = json2.Any({
			'baseline_accepted': json2.Any(true)
			'negative_controls': json2.Any(106)
			'historical_controls': json2.Any(43)
			'routing_controls': json2.Any(63)
			'screenshots': json2.Any(screenshots)
			'artifacts': json2.Any(artifacts.len)
			'current_desktop_sources': json2.Any(20)
			'qualification_sha256': json2.Any(digest(run + '/qualification.json')!)
			'controls_sha256': json2.Any(digest(proof + '/controls.json')!)
			'baseline_output': controls[0].as_map()['output']!
		})
		equal_maps(root, 'prepared-' + arch + '-04/inputs-before.json',
			'prepared-' + arch + '-04/inputs-after.json', mut before_after)!
	}
	for name in ['source', 'production', 'tools', 'aarch64/generated', 'x86_64/generated'] {
		prefix := 'inputs/compositor-build-original/' + name
		equal_maps(root, prefix + '-before.json', prefix + '-after.json', mut before_after)!
	}
	mut pins := map[string]string{}
	mut contents := map[string]string{}
	for name in ['tests/packages/software-graphical-check.v',
		'tests/packages/software-graphical-evidence-check.v',
		'tests/packages/software-graphical-retain.v',
		'tests/packages/software-graphical-guest/main.v',
		'tests/packages/software-graphical-guest/first_run.v',
		'tests/packages/software-graphical-guest/release_routing.v',
		'tests/packages/software-release-routing-prepare.v',
		'tests/packages/software-release-routing-import.v',
		'tests/packages/software-release-routing-bundle.v',
		'tests/packages/software-release-routing-receipts.v',
		'tests/packages/software-release-routing-native-check.md'] {
		contents[name] = os.read_file(work + '/' + name)!
		pins[name] = sha256.sum(contents[name].bytes()).hex()
	}
	revision := git_output(['rev-parse', 'HEAD'], work)!
	status := git_output(['status', '--short'], work)!
	invocation := {'arguments': json2.Any(os.args.map(json2.Any(it))),
		'producer_sha256': json2.Any(digest(os.executable())!),
		'source_sha256': json2.Any(digest(@FILE)!),
		'compiler_sha256': json2.Any(digest(@VEXE)!)}
	os.mkdir_all(out)!
	for name, content in contents {
		path := out + '/source/' + name
		os.mkdir_all(os.dir(path))!
		os.write_file(path, content)!
	}
	os.write_file(out + '/accepted-results.json', json2.encode(qualification) + '\n')!
	os.write_file(out + '/accepted-before-after.json', json2.encode(before_after) + '\n')!
	os.write_file(out + '/maintained-source.json', json2.encode(pins) + '\n')!
	os.write_file(out + '/maintained-source-revision.txt', revision)!
	os.write_file(out + '/status.txt', status)!
	os.write_file(out + '/invocation.json', json2.encode(invocation) + '\n')!
	println('SOFTWARE RELEASE ROUTING RECEIPTS PASS')
}

fn controls_self_test() ! {
	mut controls := []json2.Any{}
	for index in 0 .. 107 {
		controls << json2.Any({'name': json2.Any(if index == 0 { 'baseline' } else { 'control-' + index.str() }),
			'code': json2.Any(f64(if index == 0 { 0 } else { 1 })), 'output': json2.Any('retained control result')})
	}
	admit_controls(controls)!
	for mutation in ['missing', 'duplicate', 'accepted-corruption', 'failed-baseline', 'fractional-code'] {
		mut changed := controls.clone()
		match mutation {
			'missing' { changed.delete_last() }
			'duplicate' { changed[106] = changed[105] }
			else {
				index := if mutation == 'failed-baseline' { 0 } else { 1 }
				mut control := changed[index].as_map().clone()
				code := if mutation == 'failed-baseline' { f64(1) } else if mutation == 'fractional-code' { f64(1.5) } else { f64(0) }
				control['code'] = json2.Any(code)
				changed[index] = json2.Any(control)
			}
		}
		admit_controls(changed) or { continue }
		return error('self-test accepted invalid control matrix: ' + mutation)
	}
	println('SOFTWARE RELEASE ROUTING RECEIPTS SELF TEST PASS: five corruptions refused')
}

fn execute() ! {
	$if prod {} $else { return error('compile the receipts producer with -prod') }
	if sha256.sum($embed_file('software-release-routing-receipts.v').to_string().bytes()).hex() != digest(@FILE)! {
		return error('receipts source changed after compilation')
	}
	if os.args.len == 2 && os.args[1] == 'self-test' { controls_self_test()!; return }
	if os.args.len != 4 { return error('use EVIDENCE_ROOT WORK_TREE NEW_OUTPUT_DIRECTORY or self-test') }
	retain(os.real_path(os.args[1]), os.real_path(os.args[2]), os.abs_path(os.args[3]))!
}

fn main() {
	execute() or { eprintln(err); exit(1) }
}
