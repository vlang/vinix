// SPDX-License-Identifier: GPL-2.0-or-later
// Validator controls never execute or alter the retained native guests.
module main

import crypto.sha256
import json2
import os

struct Pin { path string sha256 string }
struct Check { name string argv []string seconds f64 artifacts []Pin }
struct Host { format int baseline_commit string inputs []Pin checks []Check }
struct Artifact { role string path string sha256 string }
struct Native { format int architecture string seconds f64 artifacts []Artifact }
struct Ledger { format int = 1 baseline_commit string inputs []Pin evidence []Pin }
struct Report {
	baseline bool
	ledger_baseline bool
	refused []string
	retainer Pin
	retainer_source Pin
	source Pin
	executable Pin
	compiler Pin
	original_ledger Pin
	original_ledger_refused bool
	legacy_source Pin
	legacy_prod Pin
	legacy_normal Pin
	legacy_prod_accepted_invalid bool
	legacy_normal_refused_invalid bool
	original_receipts []Pin
	relocated_inputs []Pin
	unavailable_inputs []Pin
	replay_commit string
}

fn pin(path string) !Pin { return Pin{path: path, sha256: sha256.sum(os.read_bytes(path)!).hex()} }

fn invoke(program string, args []string, log string, accepted bool, reason string) ! {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(args); child.set_redirect_stdio_merged(); child.run()
	output := child.stdout_slurp(); child.wait()
	os.write_file(log, output)!
	if (child.code == 0) != accepted || !output.contains(reason) { return error('unexpected validation result: ' + log + '\n' + output) }
}

fn copy_host(original string, copy string) ! {
	os.mkdir_all(copy)!
	host := json2.decode[Host](os.read_file(original + '/qualification.json')!)!
	for check in host.checks { os.symlink(original + '/' + check.name + '.txt', copy + '/' + check.name + '.txt')! }
	for name in ['stage', 'baseline-stage.v'] { os.symlink(original + '/' + name, copy + '/' + name)! }
	os.cp(original + '/qualification.json', copy + '/qualification.json')!
}

fn copy_native(original string, copy string) ! {
	os.mkdir_all(copy + '/packages-image-integration')!
	os.cp(original + '/qualification.json', copy + '/qualification.json')!
	os.cp(original + '/packages-image-integration/serial.log', copy + '/packages-image-integration/serial.log')!
	os.symlink(original + '/stage.log', copy + '/stage.log')!
}

fn seal_serial(work string) ! {
	native := json2.decode[Native](os.read_file(work + '/qualification.json')!)!
	mut artifacts := native.artifacts.clone()
	for i, artifact in artifacts {
		if artifact.role == 'serial-log' { p := pin(work + '/packages-image-integration/serial.log')!; artifacts[i] = Artifact{role: artifact.role, path: p.path, sha256: p.sha256} }
	}
	os.write_file(work + '/qualification.json', json2.encode(Native{...native, artifacts: artifacts}))!
}

fn historical_mode_reproduction(root string, commit string, proof string, fixed string) ![]Pin {
	mut git := os.new_process('git')
	git.set_args(['-C', root, 'show', commit + ':tests/packages/image-integration-retain.v'])
	git.set_redirect_stdio_merged(); git.run()
	contents := git.stdout_slurp(); git.wait(); code := git.code; git.close()
	if code != 0 || !contents.contains('assert ledger.format == 1') { return error('historical assertion-based retainer unavailable') }
	legacy := proof + '/legacy'
	source := legacy + '/tests/packages/image-integration-retain.v'
	results := legacy + '/tests/packages/results/2026-10-18'
	os.mkdir_all(results)!; os.write_file(source, contents)!
	ledger := results + '/image-integration-ledger.json'
	os.write_file(ledger, json2.encode(Ledger{format: 99, baseline_commit: 'invalid',
		inputs: [Pin{path: source, sha256: '00'.repeat(32)}]}))!
	prod := legacy + '/retainer-prod'; normal := legacy + '/retainer-normal'
	invoke(@VEXE, ['-nocache', '-prod', '-o', prod, source], legacy + '/compile-prod.log', true, '')!
	invoke(@VEXE, ['-nocache', '-o', normal, source], legacy + '/compile-normal.log', true, '')!
	invoke(prod, ['--verify'], legacy + '/prod-accepted-invalid.log', true, 'evidence hashes PASS')!
	invoke(normal, ['--verify'], legacy + '/normal-refused-invalid.log', false, '')!
	invoke(fixed, ['--verify', ledger], legacy + '/fixed-refused-invalid.log', false, 'unsupported image integration ledger')!
	return [pin(source)!, pin(prod)!, pin(normal)!]
}

fn controls() ! {
	if os.args.len !in [6, 9] || (os.args.len == 9 && os.args[6] != '--replay') {
		return error('use RETAINER HOST ARM X86 NEW_PROOF_DIRECTORY [--replay ORIGINAL_REPOSITORY HISTORICAL_COMMIT]')
	}
	program := os.abs_path(os.args[1]); original_host := os.abs_path(os.args[2])
	proof := os.abs_path(os.args[5])
	if os.exists(proof) || os.is_link(proof) { return error('proof directory must be new') }
	os.mkdir_all(proof)!
	host := proof + '/host'; copy_host(original_host, host)!
	mut relocated := []Pin{}; mut unavailable := []Pin{}
	mut original_ledger := Pin{}
	mut legacy := []Pin{}
	if os.args.len == 9 {
		root := os.abs_path(os.args[7]); commit := os.args[8]
		legacy = historical_mode_reproduction(root, commit, proof, program)!
		original_ledger = pin(root + '/tests/packages/results/2026-10-18/image-integration-ledger.json')!
		invoke(program, ['--verify', original_ledger.path], proof + '/original-ledger-refused.log', false, '')!
		receipt := json2.decode[Host](os.read_file(host + '/qualification.json')!)!
		mut inputs := []Pin{}
		for entry in receipt.inputs {
			actual := pin(entry.path) or { Pin{} }
			if actual == entry { inputs << entry; continue }
			if entry.path == receipt.checks[0].argv[0] && !os.exists(entry.path) {
				// Explicit validator-only replay: never manufacture a missing compiler.
				unavailable << entry; continue
			}
			if !entry.path.starts_with(root + '/') || !entry.path.ends_with('.v') { return error('cannot recover historical input: ' + entry.path) }
			relative := entry.path[root.len + 1..]
			mut git := os.new_process('git'); git.set_args(['-C', root, 'show', commit + ':' + relative]); git.set_redirect_stdio_merged(); git.run()
			contents := git.stdout_slurp(); git.wait(); code := git.code; git.close()
			if code != 0 || sha256.sum(contents.bytes()).hex() != entry.sha256 { return error('historical blob differs: ' + relative) }
			path := proof + '/source/' + relative
			os.mkdir_all(os.dir(path))!; os.write_file(path, contents)!
			p := pin(path)!; inputs << p; relocated << p
		}
		os.write_file(host + '/qualification.json', json2.encode(Host{...receipt, inputs: inputs}))!
	}
	base := [host, os.abs_path(os.args[3]), os.abs_path(os.args[4])]
	invoke(program, [...base, '--output', proof + '/baseline'], proof + '/baseline.log', true, 'evidence pins PASS')!
	ledger_path := proof + '/baseline/image-integration-ledger.json'
	invoke(program, ['--verify', ledger_path], proof + '/verify-baseline.log', true, 'evidence hashes PASS')!
	mut refused := []string{}
	for name in ['host-format', 'host-check-count', 'host-duplicate-check', 'host-digest', 'native-format', 'native-architecture',
		'native-artifact-count', 'native-digest', 'missing-stager', 'different-stager', 'missing-success', 'duplicate-success',
		'missing-core', 'missing-staging', 'missing-tools', 'guest-fail', 'panic', 'out-of-memory', 'nonzero-denial',
		'missing-denial', 'x86-missing-success'] {
		case_work := proof + '/' + name; os.mkdir_all(case_work)!
		mut args := base.clone()
		mut reason := ''
		if name.starts_with('host-') {
			copy_host(host, case_work + '/host')!; args[0] = case_work + '/host'
			r := json2.decode[Host](os.read_file(args[0] + '/qualification.json')!)!
			mut checks := r.checks.clone(); mut inputs := r.inputs.clone()
			if name == 'host-duplicate-check' { checks[1] = checks[0] }
			if name == 'host-check-count' { checks.delete_last() }
			if name == 'host-digest' { inputs[0] = Pin{path: inputs[0].path, sha256: '00'.repeat(32)} }
			os.write_file(args[0] + '/qualification.json', json2.encode(Host{...r, format: if name == 'host-format' { 2 } else { r.format }, checks: checks, inputs: inputs}))!
			reason = if name == 'host-duplicate-check' { 'duplicated host check' } else if name == 'host-digest' { 'digest mismatch' } else { 'host qualification' }
		} else {
			index := if name == 'x86-missing-success' { 2 } else { 1 }
			copy_native(args[index], case_work + '/native')!; args[index] = case_work + '/native'
			r := json2.decode[Native](os.read_file(args[index] + '/qualification.json')!)!
			mut artifacts := r.artifacts.clone()
			if name in ['native-format', 'native-architecture', 'native-artifact-count', 'native-digest', 'missing-stager', 'different-stager'] {
				if name == 'native-artifact-count' { artifacts.delete_last() }
				if name == 'native-digest' { artifacts[0] = Artifact{...artifacts[0], sha256: '00'.repeat(32)} }
				for i, a in artifacts {
					if a.role == 'host-stage' && name == 'missing-stager' { artifacts[i] = Artifact{...a, role: 'changed-role'} }
					if a.role == 'host-stage' && name == 'different-stager' { artifacts[i] = Artifact{...a, path: artifacts[0].path, sha256: artifacts[0].sha256} }
				}
				os.write_file(args[index] + '/qualification.json', json2.encode(Native{...r, format: if name == 'native-format' { 2 } else { r.format }, architecture: if name == 'native-architecture' { 'wrong' } else { r.architecture }, artifacts: artifacts}))!
				reason = if name == 'native-digest' { 'digest mismatch' } else if name in ['missing-stager', 'different-stager'] { 'host stager differs' } else { 'native qualification' }
			} else {
				path := args[index] + '/packages-image-integration/serial.log'
				mut serial := os.read_file(path)!
				marker := if name == 'missing-core' { 'IMAGE INTEGRATION 82 source/capture/publication/refusal cases preserve overrides and outside data; stable descriptors PASS' }
					else if name == 'missing-staging' { 'IMAGE INTEGRATION native staged licenses/actions/launcher/registration and empty consumer state PASS' }
					else if name == 'missing-tools' { 'IMAGE INTEGRATION native production-staged package/session/Linux-runner execution PASS' }
					else { 'HWTEST PASS packages-image-integration' }
				if (name.starts_with('missing-') && name != 'missing-denial') || name == 'x86-missing-success' { serial = serial.replace(marker, 'removed marker') }
				else if name == 'duplicate-success' { serial += '\n' + marker + '\n' }
				else if name in ['guest-fail', 'panic', 'out-of-memory'] { serial += '\n' + if name == 'guest-fail' { 'HWTEST FAIL injected\n' } else if name == 'panic' { 'V panic: injected\n' } else { 'Out of memory\n' } }
				else { lines := serial.split_into_lines(); mut changed := false; mut out := []string{}; for line in lines { if !changed && line.starts_with('Denied') { changed = true; if name == 'nonzero-denial' { out << line.replace(': 0', ': 1') }; continue }; out << line }; if !changed { return error('baseline has no denial counter') }; serial = out.join('\n') }
				os.write_file(path, serial)!; seal_serial(args[index])!
				reason = if name in ['guest-fail', 'panic', 'out-of-memory'] { 'forbidden serial marker' } else if name == 'nonzero-denial' { 'nonzero denial counter' } else if name == 'missing-denial' { 'incomplete denial counters' } else { 'missing or duplicated exact serial marker' }
			}
		}
		output := case_work + '/retained'
		invoke(program, [...args, '--output', output], case_work + '/control.log', false, reason)!
		if os.exists(output) || os.is_link(output) { return error('refusal created retained output: ' + name) }
		refused << name
	}
	ledger := json2.decode[Ledger](os.read_file(ledger_path)!)!
	for name in ['ledger-format', 'ledger-baseline', 'ledger-input-digest', 'ledger-evidence-digest'] {
		mut inputs := ledger.inputs.clone(); mut evidence := ledger.evidence.clone()
		if name == 'ledger-input-digest' { inputs[0] = Pin{...inputs[0], sha256: '00'.repeat(32)} }
		if name == 'ledger-evidence-digest' { evidence[0] = Pin{...evidence[0], sha256: '00'.repeat(32)} }
		path := proof + '/' + name + '.json'
		os.write_file(path, json2.encode(Ledger{...ledger, format: if name == 'ledger-format' { 2 } else { ledger.format }, baseline_commit: if name == 'ledger-baseline' { 'wrong' } else { ledger.baseline_commit }, inputs: inputs, evidence: evidence}))!
		invoke(program, ['--verify', path], proof + '/' + name + '.log', false, if name in ['ledger-format', 'ledger-baseline'] { 'unsupported image integration ledger' } else { 'digest mismatch' })!
		refused << name
	}
	os.write_file(proof + '/controls.json', json2.encode(Report{baseline: true, ledger_baseline: true, refused: refused,
		retainer: pin(program)!, retainer_source: pin(os.dir(@FILE) + '/image-integration-retain.v')!,
		source: pin(@FILE)!, executable: pin(os.executable())!, compiler: pin(@VEXE)!,
		original_ledger: original_ledger, original_ledger_refused: os.args.len == 9,
		legacy_source: if legacy.len > 0 { legacy[0] } else { Pin{} },
		legacy_prod: if legacy.len > 0 { legacy[1] } else { Pin{} },
		legacy_normal: if legacy.len > 0 { legacy[2] } else { Pin{} },
		legacy_prod_accepted_invalid: legacy.len > 0, legacy_normal_refused_invalid: legacy.len > 0,
		original_receipts: [pin(original_host + '/qualification.json')!, pin(base[1] + '/qualification.json')!, pin(base[2] + '/qualification.json')!],
		relocated_inputs: relocated, unavailable_inputs: unavailable, replay_commit: if os.args.len == 9 { os.args[8] } else { '' }}) + '\n')!
	println('IMAGE INTEGRATION evidence controls PASS: baseline, ledger and ' + refused.len.str() + ' corruptions refused')
}

fn main() { controls() or { eprintln(err); exit(1) } }
