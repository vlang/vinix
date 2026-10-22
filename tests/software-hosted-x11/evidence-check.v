// SPDX-License-Identifier: GPL-2.0-or-later
// Retention refusals use private APFS clones, never mutate native evidence.
module main

import crypto.sha256
import json2
import os
import proof

struct TreeInput { root string selected_sources bool entries map[string]string }
struct Qualification {
	format int
	architecture string
	desktop string
	desktop_receipt string
	inputs map[string]string
	outputs map[string]string
	trees map[string]TreeInput
	passed bool
}
struct Control { name string code int output string }
struct Report { arguments []string artifacts map[string]string controls []Control }

fn call(program string, arguments []string) Control {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(arguments)
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	child.wait()
	return Control{code: child.code, output: output}
}

fn move_path(path string, original string, copy string) string {
	return if path.starts_with(original + '/') { copy + path[original.len..] } else { path }
}

fn clone_path(path string, original string, copy string, desktop string) string {
	return move_path(move_path(path, original, copy), desktop, copy + '-desktop')
}

fn save(work string, receipt Qualification) ! {
	os.write_file(work + '/qualification.json', json2.encode(receipt))!
}

// The native run is immutable. Rebase only run-owned receipt metadata, command
// arguments and the offline repository URL in a private reflink copy. A fresh
// admitted baseline proves this transformation before any corruptions run.
fn clone_run(original string, work string) !Qualification {
	os.mkdir_all(work)!
	copy := call('/bin/cp', ['-cRp', original + '/.', work])
	if copy.code != 0 { return error('private clone failed: ' + copy.output) }
	old := json2.decode[Qualification](os.read_file(work + '/qualification.json')!)!
	desktop := os.dir(old.desktop)
	archived := call('/bin/cp', ['-cRp', desktop, work + '-desktop'])
	if archived.code != 0 { return error('private desktop clone failed: ' + archived.output) }
	for name in ['vinix-account', 'vinix-session', 'vinix-authd', 'vinix-package', 'guest', 'bridge'] {
		for log in ['v.log', 'cc.log'] {
			path := work + '/build-' + name + '/' + log + '.argv.json'
			arguments := json2.decode[[]string](os.read_file(path)!)!.map(it.replace(original + '/', work + '/'))
			os.write_file(path, json2.encode(arguments))!
		}
	}
	config := work + '/extras/etc/vinix-packages/config.json'
	os.write_file(config, os.read_file(config)!.replace('file://' + original + '/', 'file://' + work + '/'))!
	guest_path := work + '/extras/usr/share/software-hosted-x11.json'
	mut guest_proof := json2.decode[map[string]string](os.read_file(guest_path)!)!
	guest_proof['/etc/vinix-packages/config.json'] = proof.digest(config)!
	os.write_file(guest_path, json2.encode(guest_proof))!
	mut inputs := map[string]string{}
	for path, hash in old.inputs {
		next := clone_path(path, original, work, desktop)
		inputs[next] = if next != path { proof.digest(next)! } else { hash }
		// Anchored desktop metadata retains its literal build-input paths. Keep
		// those original immutable inputs as well as the private archive copy.
		if path.starts_with(desktop + '/') { inputs[path] = hash }
	}
	mut trees := map[string]TreeInput{}
	for name, tree in old.trees {
		next := clone_path(tree.root, original, work, desktop)
		trees[name] = TreeInput{next, tree.selected_sources,
			if next != tree.root { proof.tree(next, tree.selected_sources)! } else { tree.entries }}
	}
	before_path := work + '/inputs-before-build.json'
	mut before := map[string]string{}
	for path, hash in json2.decode[map[string]string](os.read_file(before_path)!)! {
		next := clone_path(path, original, work, desktop)
		before[next] = if next != path { proof.digest(next)! } else { hash }
		if path.starts_with(desktop + '/') { before[path] = hash }
	}
	os.write_file(before_path, json2.encode(before))!
	for name in ['inputs.json', 'inputs-verified.json'] { os.write_file(work + '/' + name, json2.encode(inputs))! }
	mut outputs := map[string]string{}
	for name, _ in old.outputs { outputs[name] = proof.digest(work + '/' + name)! }
	receipt := Qualification{old.format, old.architecture,
		clone_path(old.desktop, original, work, desktop), clone_path(old.desktop_receipt, original, work, desktop), inputs, outputs, trees, old.passed}
	save(work, receipt)!
	return receipt
}

fn reseal(work string, receipt Qualification, name string, content string) !Qualification {
	os.write_file(work + '/' + name, content)!
	mut outputs := receipt.outputs.clone()
	outputs[name] = proof.digest(work + '/' + name)!
	next := Qualification{...receipt, outputs: outputs}
	save(work, next)!
	return next
}

fn check() ! {
	$if prod {} $else { return error('compile control runner with -prod for source capture') }
	if proof.digest(@FILE)! != sha256.hexhash($embed_file('evidence-check.v').to_string()) { return error('control source changed after compilation') }
	if os.args.len != 4 { return error('use RETAINER NATIVE_RUN PROOF_DIRECTORY') }
	program := os.abs_path(os.args[1])
	original := os.abs_path(os.args[2])
	work := os.abs_path(os.args[3])
	if os.exists(work) { return error('proof directory exists') }
	os.mkdir_all(work)!
	baseline := call(program, ['--work=' + original, '--out=' + work + '/native-baseline'])
	if baseline.code != 0 { return error('native baseline refused: ' + baseline.output) }
	mut controls := [Control{name: 'native-baseline', code: baseline.code, output: baseline.output}]
	copy := work + '/private-run'
	mut receipt := clone_run(original, copy)!
	cloned := call(program, ['--work=' + copy, '--out=' + work + '/private-baseline'])
	if cloned.code != 0 { return error('private baseline refused: ' + cloned.output) }
	controls << Control{name: 'private-baseline', code: cloned.code, output: cloned.output}
	serial_path := copy + '/serial.log'
	serial := os.read_file(serial_path)!
	qmp := os.read_file(copy + '/shutdown-1.jsonl')!
	before_snapshot := os.read_file(copy + '/inputs-before-build.json')!
	archive_source := os.dir(receipt.desktop) + '/source/tools/accounts/session.v'
	archive_source_text := os.read_file(archive_source)!
	markers := [
		'SOFTWARE X11 START',
		'SOFTWARE X11 installed disk-root tools trust signed-state digests PASS',
		'SOFTWARE X11 ordinary-compositor uid=1000 home=/home/alex PASS',
		'SOFTWARE X11 signed-client uid=1000 groups=0 generation=1 private-authority exact-socket lease-held PASS',
		'SOFTWARE X11 painted-client ready PASS',
		'SOFTWARE X11 actual-pointer ButtonPress repainted lease-held PASS',
		'SOFTWARE X11 UI-close bridge+Xvfb reaped authority+socket removed live-child-lease-held PASS',
		'SOFTWARE X11 natural-child-exit actual-reap lease-released PASS',
		'SOFTWARE X11 INSTALLED signed-launch painted pointer close-reap lease-lifecycle PASS',
		'SOFTWARE X11 requesting guest poweroff uid=0',
	]
	mut cases := []string{}
	for i in 0 .. markers.len { cases << 'missing-marker-' + i.str() }
	cases << ['duplicate-identity', 'marker-order', 'panic', 'missing-shutdown', 'host-shutdown', 'wrong-shutdown-reason',
		'duplicate-shutdown', 'reset', 'qmp-panic', 'string-boot', 'wrong-boot', 'missing-screenshot', 'unsealed-serial',
		'failed-exit', 'unreaped-exit', 'not-guest-exit', 'generated-c-output-only', 'argv-output-only', 'missing-generated-input',
		'missing-required-build-output', 'unsealed-inputs-verified', 'missing-archive-tree', 'wrong-desktop-anchor',
		'reduced-full-input-tree', 'unselected-source-tree',
		'resealed-desktop-build-metadata', 'missing-archived-source', 'mismatched-archived-source',
		'painted-phase-order', 'close-retains-surface']
	for name in cases {
		mut reason := ''
		mut changed := ''
		mut previous := ''
		mut next := receipt
		if name.starts_with('missing-marker-') {
			index := name.all_after_last('-').int()
			next = reseal(copy, receipt, 'serial.log', serial.replace(markers[index], ''))!
			reason = 'missing or duplicated exact marker'
		} else {
			match name {
				'duplicate-identity', 'marker-order', 'panic', 'unsealed-serial' {
					text := if name == 'duplicate-identity' { serial + '\n' + markers[2] + '\n' }
						else if name == 'marker-order' { serial.replace(markers[2], '') + '\n' + markers[2] + '\n' }
						else { serial + '\nKERNEL PANIC control\n' }
					if name == 'unsealed-serial' { os.write_file(serial_path, text)! }
					else { next = reseal(copy, receipt, 'serial.log', text)! }
					reason = match name { 'duplicate-identity' { 'missing or duplicated exact marker' }
						'marker-order' { 'serial lifecycle marker order differs' } 'unsealed-serial' { 'output pin differs: serial.log' }
						else { 'forbidden serial marker' } }
				}
				'missing-shutdown', 'host-shutdown', 'wrong-shutdown-reason', 'duplicate-shutdown', 'reset', 'qmp-panic', 'string-boot', 'wrong-boot' {
					mut lines := []string{}
					for line in qmp.split_into_lines() {
						if line == '' { continue }
						mut record := json2.decode[json2.Any](line)!.as_map()
						if 'graphical_boot' in record {
							if name == 'string-boot' { record['graphical_boot'] = json2.Any('1') }
							if name == 'wrong-boot' { record['graphical_boot'] = json2.Any(2) }
						}
						if record['event'] or { json2.Any('') } == json2.Any('SHUTDOWN') {
							if name == 'missing-shutdown' { continue }
							mut data := record['data']!.as_map()
							if name == 'host-shutdown' { data['guest'] = json2.Any(false) }
							if name == 'wrong-shutdown-reason' { data['reason'] = json2.Any('host-qmp-quit') }
							record['data'] = json2.Any(data)
							if name == 'duplicate-shutdown' { lines << json2.encode(record) }
						}
						lines << json2.encode(record)
					}
					if name in ['reset', 'qmp-panic'] { lines << json2.encode({'event': if name == 'reset' { 'RESET' } else { 'GUEST_PANICKED' }}) }
					next = reseal(copy, receipt, 'shutdown-1.jsonl', lines.join('\n') + '\n')!
					reason = if name in ['host-shutdown', 'wrong-shutdown-reason'] { 'shutdown was not the guest shutdown event' }
						else if name in ['reset', 'qmp-panic'] { 'forbidden QMP shutdown event' }
						else if name in ['string-boot', 'wrong-boot'] { 'shutdown boot binding differs' }
						else { 'shutdown handshake or exact guest event missing/duplicated' }
				}
				'failed-exit', 'unreaped-exit', 'not-guest-exit' {
					status := {'exit_code': json2.Any(if name == 'failed-exit' { 1 } else { 0 }),
						'reaped': json2.Any(name != 'unreaped-exit'), 'guest_shutdown': json2.Any(name != 'not-guest-exit')}
					next = reseal(copy, receipt, 'qemu-exit.json', json2.encode(status))!
					reason = 'actual QEMU exit0/reap record differs'
				}
				'generated-c-output-only', 'argv-output-only' {
					changed = if name == 'generated-c-output-only' { 'build-guest/guest.c' } else { 'build-guest/cc.log.argv.json' }
					previous = os.read_file(copy + '/' + changed)!
					next = reseal(copy, receipt, changed, previous + '\n')!
					reason = 'fresh build preboot pin differs'
				}
				'missing-generated-input' {
					mut inputs := receipt.inputs.clone(); inputs.delete(copy + '/build-guest/guest.c')
					next = Qualification{...receipt, inputs: inputs}
					for file in ['inputs.json', 'inputs-verified.json'] { os.write_file(copy + '/' + file, json2.encode(inputs))! }
					mut outputs := receipt.outputs.clone()
					for file in ['inputs.json', 'inputs-verified.json'] { outputs[file] = proof.digest(copy + '/' + file)! }
					next = Qualification{...next, outputs: outputs}; save(copy, next)!
					reason = 'fresh build preboot pin differs'
				}
				'missing-required-build-output', 'missing-screenshot' {
					mut outputs := receipt.outputs.clone()
					outputs.delete(if name == 'missing-screenshot' { '02-painted.png' } else { 'build-guest/guest.c' })
					next = Qualification{...receipt, outputs: outputs}; save(copy, next)!
					reason = if name == 'missing-screenshot' { 'output pin differs: 02-painted.png' } else { 'required fresh build artifact missing' }
				}
				'unsealed-inputs-verified' {
					changed = 'inputs-verified.json'; previous = os.read_file(copy + '/' + changed)!
					next = reseal(copy, receipt, changed, '{}')!; reason = 'verified input snapshot differs'
				}
				'missing-archive-tree' {
					mut trees := receipt.trees.clone(); trees.delete('archived-desktop-source')
					next = Qualification{...receipt, trees: trees}; save(copy, next)!; reason = 'required complete input tree missing'
				}
				'reduced-full-input-tree', 'unselected-source-tree' {
					group := if name == 'reduced-full-input-tree' { 'compiler-vlib' } else { 'source:tools/accounts' }
					mut trees := receipt.trees.clone()
					tree := trees[group]!
					selected := name == 'reduced-full-input-tree'
					entries := proof.tree(tree.root, selected)!
					trees[group] = TreeInput{tree.root, selected, entries}
					mut inputs := receipt.inputs.clone()
					mut before := json2.decode[map[string]string](before_snapshot)!
					for relative, _ in tree.entries {
						if relative !in entries { inputs.delete(tree.root + '/' + relative); before.delete(tree.root + '/' + relative) }
					}
					for relative, value in entries {
						hash := if value.len == 64 { value } else if value.contains('\nsha256:') { value.all_after('\nsha256:') } else { continue }
						inputs[tree.root + '/' + relative] = hash; before[tree.root + '/' + relative] = hash
					}
					os.write_file(copy + '/inputs-before-build.json', json2.encode(before))!
					for file in ['inputs.json', 'inputs-verified.json'] { os.write_file(copy + '/' + file, json2.encode(inputs))! }
					mut outputs := receipt.outputs.clone()
					for file in ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json'] { outputs[file] = proof.digest(copy + '/' + file)! }
					next = Qualification{...receipt, trees: trees, inputs: inputs, outputs: outputs}; save(copy, next)!
					reason = 'required input tree selection mode differs'
				}
				'wrong-desktop-anchor' {
					next = Qualification{...receipt, desktop_receipt: receipt.desktop_receipt + '.other'}; save(copy, next)!
					reason = 'desktop receipt path differs'
				}
				'resealed-desktop-build-metadata' {
					metadata := os.dir(receipt.desktop) + '/build-inputs.json'
					previous = os.read_file(metadata)!
					os.write_file(metadata, previous + '\n')!
					mut inputs := receipt.inputs.clone(); inputs[metadata] = proof.digest(metadata)!
					mut before := json2.decode[map[string]string](os.read_file(copy + '/inputs-before-build.json')!)!
					before[metadata] = inputs[metadata]
					os.write_file(copy + '/inputs-before-build.json', json2.encode(before))!
					for file in ['inputs.json', 'inputs-verified.json'] { os.write_file(copy + '/' + file, json2.encode(inputs))! }
					mut outputs := receipt.outputs.clone()
					for file in ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json'] { outputs[file] = proof.digest(copy + '/' + file)! }
					next = Qualification{...receipt, inputs: inputs, outputs: outputs}; save(copy, next)!
					reason = 'assembled input digest differs: desktop/build-inputs.json'
				}
				'missing-archived-source', 'mismatched-archived-source' {
					if name == 'missing-archived-source' { os.rm(archive_source)! }
					else { os.write_file(archive_source, archive_source_text + '\n')! }
					mut inputs := receipt.inputs.clone()
					mut before := json2.decode[map[string]string](before_snapshot)!
					if name == 'missing-archived-source' { inputs.delete(archive_source); before.delete(archive_source) }
					else { inputs[archive_source] = proof.digest(archive_source)!; before[archive_source] = inputs[archive_source] }
					mut trees := receipt.trees.clone()
					archive_tree := trees['archived-desktop-source']!
					trees['archived-desktop-source'] = TreeInput{...archive_tree, entries: proof.tree(archive_tree.root, archive_tree.selected_sources)!}
					os.write_file(copy + '/inputs-before-build.json', json2.encode(before))!
					for file in ['inputs.json', 'inputs-verified.json'] { os.write_file(copy + '/' + file, json2.encode(inputs))! }
					mut outputs := receipt.outputs.clone()
					for file in ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json'] { outputs[file] = proof.digest(copy + '/' + file)! }
					next = Qualification{...receipt, inputs: inputs, outputs: outputs, trees: trees}; save(copy, next)!
					reason = if name == 'missing-archived-source' { 'source/tools/accounts/session.v' }
						else { 'desktop source/build pin differs: tools/accounts/session.v' }
				}
				'painted-phase-order', 'close-retains-surface' {
					changed = if name == 'painted-phase-order' { '02-painted.png' } else { '04-closed.png' }
					os.cp(copy + '/' + changed, work + '/saved.png')!
					os.cp(copy + '/03-pointer.png', copy + '/' + changed)!
					mut outputs := receipt.outputs.clone(); outputs[changed] = proof.digest(copy + '/' + changed)!
					next = Qualification{...receipt, outputs: outputs}; save(copy, next)!; reason = 'painted X11 framebuffer phase differs'
				}
				else { return error('unknown control: ' + name) }
			}
		}
		result := call(program, ['--work=' + copy, '--out=' + work + '/refused'])
		if result.code == 0 || !result.output.contains(reason) || os.exists(work + '/refused') {
			return error('control did not refuse before retention for expected reason: ' + name + ': ' + result.output)
		}
		controls << Control{name: name, code: result.code, output: result.output}
		println('PASS ' + name)
		if changed.ends_with('.png') { os.cp(work + '/saved.png', copy + '/' + changed)!; os.rm(work + '/saved.png')! }
		else if changed != '' { os.write_file(copy + '/' + changed, previous)! }
		if name == 'resealed-desktop-build-metadata' {
			os.write_file(os.dir(receipt.desktop) + '/build-inputs.json', previous)!
			os.write_file(copy + '/inputs-before-build.json', before_snapshot)!
		}
		if name in ['missing-archived-source', 'mismatched-archived-source'] {
			os.write_file(archive_source, archive_source_text)!
			os.write_file(copy + '/inputs-before-build.json', before_snapshot)!
		}
		if name in ['reduced-full-input-tree', 'unselected-source-tree'] { os.write_file(copy + '/inputs-before-build.json', before_snapshot)! }
		os.write_file(serial_path, serial)!
		os.write_file(copy + '/shutdown-1.jsonl', qmp)!
		os.cp(original + '/qemu-exit.json', copy + '/qemu-exit.json')!
		for file in ['inputs.json', 'inputs-verified.json'] { os.write_file(copy + '/' + file, json2.encode(receipt.inputs))! }
		save(copy, receipt)!
	}
	artifacts := {'control-source': proof.digest(@FILE)!, 'control-binary': proof.digest(os.executable())!,
		'compiler': proof.digest(@VEXE)!, 'retainer': proof.digest(program)!, 'native-receipt': proof.digest(original + '/qualification.json')!}
	os.write_file(work + '/controls.json', json2.encode(Report{os.args.clone(), artifacts, controls}))!
	// Only the private clone is disposable; original evidence and accepted copy
	// receipts/screenshots remain untouched.
	os.rmdir_all(copy)!
	os.rmdir_all(copy + '-desktop')!
	println('PASS hosted X11 baseline + private baseline + ' + cases.len.str() + ' refusals')
}

fn main() { check() or { eprintln(err); exit(1) } }
