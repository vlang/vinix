// SPDX-License-Identifier: GPL-2.0-or-later
// Bounded admission controls against private copies of real native evidence.
module main

import crypto.sha256
import json2
import os

struct Outcome {
	scenario    string
	passed      bool
	interrupted bool
	reason      string
}

struct Control {
	name   string
	code   int
	output string
}

struct Evidence {
	arguments []string
	artifacts map[string]string
	controls  []Control
}

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn call(program string, args []string) Control {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(args)
	child.set_redirect_stdio()
	child.run()
	output := child.stdout_slurp() + child.stderr_slurp()
	child.wait()
	return Control{ code: child.code, output: output }
}

fn private_copy(original string, copy string) ! {
	os.rm(copy)!
	os.cp(original, copy)!
}

fn seal(work string, name string) ! {
	mut outputs := json2.decode[map[string]string](os.read_file(work + '/outputs.json')!)!
	outputs[name] = digest(work + '/' + name)!
	os.write_file(work + '/outputs.json', json2.encode(outputs))!
}

fn clone_run(original string, work string) ! {
	os.mkdir_all(work)!
	outputs := json2.decode[map[string]string](os.read_file(original + '/outputs.json')!)!
	for name, _ in outputs {
		if name.starts_with('/') || '..' in name.split('/') { return error('unsafe output path') }
		target := work + '/' + name
		os.mkdir_all(os.dir(target))!
		os.symlink(original + '/' + name, target)!
	}
	os.cp(original + '/outputs.json', work + '/outputs.json')!
	for name in ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json', 'result.json',
		'boot/serial.log', 'source/check.v'] {
		private_copy(original + '/' + name, work + '/' + name)!
	}
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}

fn check() ! {
	$if prod {
	} $else {
		return error('compile the evidence controls with -prod')
	}
	if sha256.sum($embed_file('evidence-check.v').to_string().bytes()).hex() != digest(@FILE)! {
		return error('evidence control source changed after compilation')
	}
	if os.args.len != 9 {
		return error('use RETAINER RUN DESKTOP KERNEL CONTROLLER PROOF_DIRECTORY ARCH CROSS_DRIVER')
	}
	program := os.abs_path(os.args[1])
	original := os.abs_path(os.args[2])
	proof := os.abs_path(os.args[6])
	if os.exists(proof) { return error('proof directory exists') }
	os.mkdir_all(proof)!
	base := [original, os.abs_path(os.args[3]), os.abs_path(os.args[4]), os.abs_path(os.args[5]),
		proof + '/baseline', os.args[7], os.abs_path(os.args[8])]
	baseline := call(program, base)
	if baseline.code != 0 { return error('baseline rejected: ' + baseline.output) }
	mut controls := [Control{ name: 'baseline', code: baseline.code, output: baseline.output }]
	marker := 'HWTEST INFO external-broker uid=1000 ping=ok PASS'
	names := ['missing-marker', 'duplicate-marker', 'forbidden-marker', 'failed-result',
		'interrupted-result', 'reason-result', 'unsealed-serial', 'missing-archive-admission',
		'missing-build-command-admission', 'verified-input-mismatch', 'frozen-source-mismatch']
	reasons := ['missing or duplicated exact marker', 'missing or duplicated exact marker',
		'forbidden serial marker', 'requires an uninterrupted, passing',
		'requires an uninterrupted, passing', 'requires an uninterrupted, passing',
		'output digest mismatch', 'output receipt lacks', 'missing build command/log receipt',
		'completed input verification differs', 'frozen fixture source']
	for index, name in names {
		work := proof + '/' + name
		clone_run(original, work)!
		match name {
			'missing-marker' {
				serial := os.read_file(work + '/boot/serial.log')!
				os.write_file(work + '/boot/serial.log', serial.split_into_lines().filter(it.trim_space() != marker).join('\n') + '\n')!
				seal(work, 'boot/serial.log')!
			}
			'duplicate-marker', 'forbidden-marker', 'unsealed-serial' {
				extra := if name == 'duplicate-marker' { marker } else { 'HWTEST FAIL control' }
				serial := os.read_file(work + '/boot/serial.log')!
				os.write_file(work + '/boot/serial.log', serial + '\n' + extra + '\n')!
				if name != 'unsealed-serial' { seal(work, 'boot/serial.log')! }
			}
			'failed-result', 'interrupted-result', 'reason-result' {
				result := Outcome{
					scenario:    'session-runtime'
					passed:      name != 'failed-result'
					interrupted: name == 'interrupted-result'
					reason:      if name == 'reason-result' { 'control' } else { '' }
				}
				os.write_file(work + '/result.json', json2.encode(result))!
				seal(work, 'result.json')!
			}
			'missing-archive-admission', 'missing-build-command-admission' {
				mut outputs := json2.decode[map[string]string](os.read_file(work + '/outputs.json')!)!
				outputs.delete(if name == 'missing-archive-admission' {
					'boot/initramfs.tar'
				} else {
					'build-guest/commands.json'
				})
				os.write_file(work + '/outputs.json', json2.encode(outputs))!
			}
			'verified-input-mismatch' {
				mut verified := json2.decode[map[string]string](os.read_file(work + '/inputs-verified.json')!)!
				verified['compiler'] = '0'.repeat(64)
				os.write_file(work + '/inputs-verified.json', json2.encode(verified))!
				seal(work, 'inputs-verified.json')!
			}
			'frozen-source-mismatch' {
				source := os.read_file(work + '/source/check.v')!
				os.write_file(work + '/source/check.v', source + '\n// bounded negative control\n')!
				seal(work, 'source/check.v')!
			}
			else { return error('unknown control') }
		}
		mut args := base.clone()
		args[0] = work
		args[4] = work + '/retained'
		result := call(program, args)
		if result.code == 0 || !result.output.contains(reasons[index]) {
			return error('control did not refuse for intended reason: ' + name + ': ' + result.output)
		}
		if os.exists(work + '/retained') {
			return error('failed admission wrote retained output: ' + name)
		}
		controls << Control{ name: name, code: result.code, output: result.output }
		println('PASS ' + name)
	}
	artifacts := {
		'control-source':        digest(@FILE)!
		'control-controller':    digest(os.executable())!
		'compiler':              digest(@VEXE)!
		'retention-controller':  digest(program)!
		'native-output-receipt': digest(original + '/outputs.json')!
		'native-inputs':         digest(original + '/inputs-verified.json')!
	}
	os.write_file(proof + '/controls.json', json2.encode(Evidence{
		arguments: os.args[1..]
		artifacts: artifacts
		controls:  controls
	}))!
	println('PASS session-runtime evidence controls: baseline accepted, 11 corruptions rejected')
}
