// SPDX-License-Identifier: GPL-2.0-or-later
// Refuse resealed evidence using disposable hard links, never the native run.
module main

import crypto.sha256
import json2
import normalproof
import os

fn C.link(&char, &char) int

struct Qualification {
	architecture   string
	platform       string
	artifacts      map[string]string
	artifact_paths map[string]string
}

struct Outcome {
	name   string
	code   int
	output string
}

struct Evidence {
	arguments []string
	artifacts map[string]string
	controls  []Outcome
}

fn invoke(program string, args []string) Outcome {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(args)
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	return Outcome{ code: child.code, output: output }
}

fn clone(source string, copy string) ! {
	os.mkdir(copy, mode: 0o700)!
	for name in os.ls(source)! {
		from := source + '/' + name
		to := copy + '/' + name
		if os.is_link(from) {
			os.symlink(os.readlink(from)!, to)!
		} else if os.is_dir(from) {
			clone(from, to)!
		} else if unsafe { C.link(from.str, to.str) } != 0 {
			return error('hard link failed: ' + from)
		}
	}
}

// Unlink first: every original native artifact remains read-only to controls.
fn replace(path string, text string) ! {
	os.rm(path)!
	os.write_file(path, text)!
}

fn maps(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)
}

fn reseal(copy string, name string) ! {
	mut receipt := json2.decode[Qualification](os.read_file(copy + '/qualification.json')!)!
	mut hashes := receipt.artifacts.clone()
	hashes[name] = normalproof.digest(copy + '/' + name)!
	replace(copy + '/qualification.json', json2.encode(Qualification{
		architecture:   receipt.architecture
		platform:       receipt.platform
		artifacts:      hashes
		artifact_paths: receipt.artifact_paths
	}))!
}

fn generated_hash(copy string, name string) ! {
	for file in ['generated-inputs.json', 'verified-generated-inputs.json'] {
		mut hashes := maps(copy + '/' + file)!
		hashes[name] = normalproof.digest(copy + '/' + name)!
		replace(copy + '/' + file, json2.encode(hashes))!
	}
}

fn omit_generated(copy string, name string) ! {
	os.rm(copy + '/' + name)!
	for file in ['generated-inputs.json', 'verified-generated-inputs.json', 'generated-paths.json'] {
		mut values := maps(copy + '/' + file)!
		values.delete(name)
		replace(copy + '/' + file, json2.encode(values))!
	}
	mut receipt := json2.decode[Qualification](os.read_file(copy + '/qualification.json')!)!
	mut hashes := receipt.artifacts.clone()
	mut paths := receipt.artifact_paths.clone()
	hashes.delete(name)
	paths.delete(name)
	replace(copy + '/qualification.json', json2.encode(Qualification{
		architecture:   receipt.architecture
		platform:       receipt.platform
		artifacts:      hashes
		artifact_paths: paths
	}))!
}

fn mutate(copy string, name string) !string {
	match name {
		'omitted-source-input', 'omitted-compiler-input' {
			paths := maps(copy + '/source-paths.json')!
			prefix := if name == 'omitted-source-input' {
				'source/tools/accounts/sessioncore/'
			} else {
				'compiler/vlib/'
			}
			mut selected := ''
			for key, _ in paths {
				if key.starts_with(prefix) {
					selected = key
					break
				}
			}
			if selected == '' { return error('baseline lacks selected source input') }
			for file in ['source-paths.json', 'source-inputs.json', 'verified-source-inputs.json'] {
				mut values := maps(copy + '/' + file)!
				values.delete(selected)
				replace(copy + '/' + file, json2.encode(values))!
			}
			return 'source input inventory differs'
		}
		'omitted-generated-c', 'omitted-build-log', 'omitted-build-argv' {
			file := match name {
				'omitted-generated-c' { 'session-build/session.c' }
				'omitted-build-log' { 'observer-build/c.log' }
				else { 'session-build/v.log.argv.json' }
			}
			omit_generated(copy, file)!
			return 'missing required generated artifact'
		}
		'output-only-c', 'output-only-argv', 'resealed-compiler-argv' {
			file := if name == 'output-only-c' {
				'session-build/session.c'
			} else {
				'session-build/v.log.argv.json'
			}
			if name == 'output-only-c' {
				replace(copy + '/' + file, os.read_file(copy + '/' + file)! + '\n/* changed output */\n')!
			} else {
				mut args := json2.decode[[]string](os.read_file(copy + '/' + file)!)!
				args[0] = '/unadmitted/compiler'
				replace(copy + '/' + file, json2.encode(args))!
			}
			reseal(copy, file)!
			if name == 'resealed-compiler-argv' {
				generated_hash(copy, file)!
				return 'build arguments do not bind admitted compiler'
			}
			return 'build input changed'
		}
		'resealed-frozen-source' {
			file := 'source/check.v'
			replace(copy + '/' + file, os.read_file(copy + '/' + file)! + '\n// changed frozen source\n')!
			generated_hash(copy, file)!
			reseal(copy, file)!
			return 'frozen source does not bind admitted input'
		}
		'resealed-staged-sandbox' {
			file := 'rootfs/usr/bin/vinix-sandbox'
			replace(copy + '/' + file, 'changed sandbox')!
			generated_hash(copy, file)!
			return 'staged program differs from admitted input'
		}
		'resealed-staged-action' {
			file := 'rootfs/usr/share/vinix/actions/packages-change'
			replace(copy + '/' + file, 'changed account action')!
			generated_hash(copy, file)!
			return 'staged account action differs from admitted source'
		}
		'resealed-observer-declaration' {
			file := 'rootfs/usr/share/normal-init-software.json'
			mut declaration := maps(copy + '/' + file)!
			declaration.delete('/usr/sbin/vinix-session')
			replace(copy + '/' + file, json2.encode(declaration))!
			generated_hash(copy, file)!
			return 'boot observer declaration differs'
		}
		'missing-screenshot' {
			os.rm(copy + '/02-greeter.png')!
			return ''
		}
		'artifact-pin-mismatch' {
			replace(copy + '/serial-1.log', os.read_file(copy + '/serial-1.log')! + '\nchanged unsealed output\n')!
			return 'artifact digest differs'
		}
		'missing-qemu-digest' {
			mut receipt := json2.decode[Qualification](os.read_file(copy + '/qualification.json')!)!
			mut hashes := receipt.artifacts.clone()
			mut paths := receipt.artifact_paths.clone()
			hashes.delete('qemu-argv')
			paths.delete('qemu-argv')
			replace(copy + '/qualification.json', json2.encode(Qualification{
				architecture:   receipt.architecture
				platform:       receipt.platform
				artifacts:      hashes
				artifact_paths: paths
			}))!
			return 'selected qualification artifact differs: qemu-argv'
		}
		'resealed-qemu-argv' {
			mut args := json2.decode[[]string](os.read_file(copy + '/qemu-argv.json')!)!
			args << ['-nic', 'user']
			replace(copy + '/qemu-argv.json', json2.encode(args))!
			// This artifact uses a semantic key rather than its filename.
			mut receipt := json2.decode[Qualification](os.read_file(copy + '/qualification.json')!)!
			mut hashes := receipt.artifacts.clone()
			hashes['qemu-argv'] = normalproof.digest(copy + '/qemu-argv.json')!
			replace(copy + '/qualification.json', json2.encode(Qualification{
				architecture:   receipt.architecture
				platform:       receipt.platform
				artifacts:      hashes
				artifact_paths: receipt.artifact_paths
			}))!
			return 'QEMU arguments differ from frozen'
		}
		else {}
	}
	if name in ['missing-success', 'missing-reboot-success', 'duplicate-identity', 'kernel-panic',
		'missing-proposal', 'wrong-proposal-publisher', 'proposal-order'] {
		file := if name == 'missing-reboot-success' { 'serial-2.log' } else { 'serial-1.log' }
		mut lines := os.read_file(copy + '/' + file)!.split_into_lines()
		match name {
			'missing-success', 'missing-reboot-success' {
				lines = lines.filter(!it.starts_with('NORMAL INIT SOFTWARE BOOT ') || !it.contains('ready for UI shutdown PASS'))
			}
			'duplicate-identity' { lines << 'NORMAL INIT SOFTWARE ordinary greeter uid=101 READY' }
			'kernel-panic' { lines << 'KERNEL PANIC controlled refusal' }
			'missing-proposal' {
				lines = lines.filter(!it.starts_with('NORMAL INIT SOFTWARE PROPOSAL '))
			}
			'proposal-order' {
				proposal := lines.filter(it.starts_with('NORMAL INIT SOFTWARE PROPOSAL '))
				if proposal.len != 1 { return error('baseline lacks unique proposal') }
				lines = lines.filter(!it.starts_with('NORMAL INIT SOFTWARE PROPOSAL '))
				lines << proposal[0]
			}
			else {
				mut changed := false
				for i, line in lines {
					if !line.starts_with('NORMAL INIT SOFTWARE PROPOSAL ') { continue }
					mut review := json2.decode[json2.Any](line.all_after('NORMAL INIT SOFTWARE PROPOSAL '))!.as_map()
					mut rows := review['rows']!.as_array()
					mut row := rows[0].as_map()
					row['public_key'] = json2.Any('0'.repeat(64))
					rows[0] = json2.Any(row)
					review['rows'] = json2.Any(rows)
					lines[i] = 'NORMAL INIT SOFTWARE PROPOSAL ' + json2.encode(review)
					changed = true
				}
				if !changed { return error('baseline lacks proposal') }
			}
		}
		replace(copy + '/' + file, lines.join('\n') + '\n')!
		reseal(copy, file)!
		return if name == 'kernel-panic' {
			'forbidden serial marker'
		} else if name == 'missing-proposal' {
			'proposal operation inventory differs'
		} else if name == 'wrong-proposal-publisher' {
			'complete signed proposal row differs'
		} else if name == 'proposal-order' {
			'proposal order differs from read-only review'
		} else {
			'missing or duplicated exact marker'
		}
	}
	if name.starts_with('qmp-') {
		file := if name == 'qmp-missing-reboot-shutdown' {
			'shutdown-2.jsonl'
		} else {
			'shutdown-1.jsonl'
		}
		mut lines := os.read_file(copy + '/' + file)!.split_into_lines()
		mut reason := ''
		match name {
			'qmp-missing-shutdown', 'qmp-missing-reboot-shutdown' {
				lines = lines.filter(!it.contains('"SHUTDOWN"'))
				reason = 'guest SHUTDOWN event'
			}
			'qmp-wrong-boot' {
				lines[0] = '{"graphical_boot":2}'
				reason = 'QMP shutdown boot binding differs'
			}
			'qmp-string-boot' {
				lines[0] = '{"graphical_boot":"1"}'
				reason = 'QMP shutdown boot binding differs'
			}
			'qmp-reset', 'qmp-panic' {
				event := if name == 'qmp-reset' { 'RESET' } else { 'GUEST_PANICKED' }
				lines << '{"event":"' + event + '","data":{}}'
				reason = 'forbidden QMP power event'
			}
			else {
				mut changed := false
				for i, line in lines {
					if !line.contains('"SHUTDOWN"') { continue }
					if name == 'qmp-duplicate-shutdown' {
						lines << line
						changed = true
						break
					}
					mut event := json2.decode[json2.Any](line)!.as_map()
					mut data := event['data']!.as_map()
					if name == 'qmp-host-shutdown' {
						data['guest'] = json2.Any(false)
					} else {
						data['reason'] = json2.Any('host-qmp-quit')
					}
					event['data'] = json2.Any(data)
					lines[i] = json2.encode(event)
					changed = true
				}
				if !changed { return error('baseline lacks shutdown event') }
				reason = if name == 'qmp-duplicate-shutdown' {
					'missing or duplicated exact guest SHUTDOWN event'
				} else {
					'QMP did not report guest-initiated shutdown'
				}
			}
		}
		replace(copy + '/' + file, lines.join('\n') + '\n')!
		reseal(copy, file)!
		return reason
	}
	return error('unknown control: ' + name)
}

fn check() ! {
	$if prod {
	} $else {
		return error('compile controls with -prod to freeze their source')
	}
	if normalproof.digest(@FILE)! != sha256.hexhash($embed_file('evidence-check.v').to_string()) {
		return error('control source differs from executable')
	}
	if os.args.len != 11 {
		return error('use RETAINER RUN INPUT_ROOTFS STAGE DESKTOP KERNEL PUBLISHER CONTROLLER PROOF ARCH')
	}
	program := os.abs_path(os.args[1])
	original := os.abs_path(os.args[2])
	proof := os.abs_path(os.args[9])
	if os.exists(proof) || os.is_link(proof) { return error('proof output must be new') }
	os.mkdir(proof, mode: 0o700)!
	mut base := [original, ...os.args[3..9].map(os.abs_path(it)), proof + '/baseline', os.args[10]]
	// There are six selected paths between RUN and OUTPUT.
	if base.len != 9 { return error('invalid retainer argument count') }
	baseline := invoke(program, base)
	if baseline.code != 0 { return error('baseline rejected: ' + baseline.output) }
	mut outcomes := [Outcome{ name: 'baseline', code: baseline.code, output: baseline.output }]
	names := ['omitted-source-input', 'omitted-compiler-input', 'omitted-generated-c',
		'omitted-build-log', 'omitted-build-argv', 'output-only-c', 'output-only-argv',
		'resealed-compiler-argv', 'resealed-frozen-source', 'resealed-staged-sandbox',
		'resealed-staged-action', 'resealed-observer-declaration', 'missing-screenshot',
		'artifact-pin-mismatch', 'missing-qemu-digest', 'resealed-qemu-argv', 'missing-success',
		'missing-reboot-success', 'duplicate-identity', 'kernel-panic', 'missing-proposal',
		'wrong-proposal-publisher', 'proposal-order', 'qmp-missing-shutdown',
		'qmp-missing-reboot-shutdown', 'qmp-host-shutdown', 'qmp-wrong-reason', 'qmp-reset', 'qmp-panic',
		'qmp-wrong-boot', 'qmp-string-boot', 'qmp-duplicate-shutdown']
	for name in names {
		copy := proof + '/' + name
		clone(original, copy)!
		reason := mutate(copy, name)!
		base[0] = copy
		base[7] = copy + '/refused-output'
		outcome := invoke(program, base)
		if outcome.code == 0 || (reason != '' && !outcome.output.contains(reason)) || os.exists(base[7]) {
			return error('control was not refused before copying: ' + name + ' / ' + outcome.output)
		}
		outcomes << Outcome{ name: name, code: outcome.code, output: outcome.output }
		// Remove only disposable hard links. Original run and baseline stay intact.
		os.rmdir_all(copy)!
		println('PASS refusal ' + name)
	}
	mut artifacts := map[string]string{}
	for name, path in {
		'controls-source':  @FILE
		'controls':         os.executable()
		'retainer':         program
		'qualification':    original + '/qualification.json'
		'source-inputs':    original + '/source-inputs.json'
		'generated-inputs': original + '/generated-inputs.json'
		'retainer-source':  os.dir(@FILE) + '/retain.v'
	} {
		artifacts[name] = normalproof.digest(path)!
	}
	os.write_file(proof + '/controls.json', json2.encode(Evidence{ arguments: os.args, artifacts: artifacts, controls: outcomes }))!
	println('PASS baseline plus ' + names.len.str() + ' independent admission refusals')
}

fn main() {
	check() or {
		eprintln(err.msg())
		exit(1)
	}
}
