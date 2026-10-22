// SPDX-License-Identifier: GPL-2.0-or-later
// Meaningful evidence refusals use private copies and resealed JSON digests.
module main

import crypto.sha256
import json2
import os

struct Controls {
	baseline bool
	refused []string
	source string
	executable string
}

fn hash_file(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn validate(retainer string, run string, tail []string, output string, log string) !int {
	mut child := os.new_process(retainer)
	defer { child.close() }
	child.set_args([run, ...tail, output]); child.set_redirect_stdio_merged(); child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	child.wait()
	os.write_file(log, text)!
	return child.code
}

fn clone_evidence(run string, destination string, outputs map[string]string) ! {
	os.mkdir_all(destination)!
	for name, _ in outputs {
		os.mkdir_all(os.dir(destination + '/' + name))!
		if name in ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json', 'result.json',
			'boot/serial.log', 'source/tests/wine-host/native/main.v', 'build-guest/guest'] {
			os.cp(run + '/' + name, destination + '/' + name)!
		} else { os.symlink(run + '/' + name, destination + '/' + name)! }
	}
	os.cp(run + '/outputs.json', destination + '/outputs.json')!
}

fn reseal(directory string, changed []string) ! {
	mut outputs := json2.decode[map[string]string](os.read_file(directory + '/outputs.json')!)!
	for name in changed { outputs[name] = hash_file(directory + '/' + name)! }
	os.write_file(directory + '/outputs.json', json2.encode(outputs))!
}

fn checks() ! {
	$if prod {} $else { return error('compile the evidence controls with -prod') }
	if os.args.len != 8 { return error('use RETAINER RUN ARCH KERNEL CONTROLLER HOST_TOOL NEW_PROOF_DIRECTORY') }
	source := @FILE
	if hash_file(source)! != sha256.sum($embed_file('evidence-check.v').to_string().bytes()).hex() {
		return error('control source changed after compilation')
	}
	retainer := os.abs_path(os.args[1])
	run := os.abs_path(os.args[2])
	tail := [os.args[3], os.abs_path(os.args[4]), os.abs_path(os.args[5]), os.abs_path(os.args[6])]
	proof := os.abs_path(os.args[7])
	if os.exists(proof) { return error('proof directory must be new') }
	os.mkdir_all(proof)!
	if validate(retainer, run, tail, proof + '/baseline', proof + '/baseline.log')! != 0 {
		return error('real native evidence baseline was refused')
	}
	outputs := json2.decode[map[string]string](os.read_file(run + '/outputs.json')!)!
	marker := 'HWTEST INFO signed-X11 framebuffer colored-window damage-observed PASS'
	mut refused := []string{}
	for name in ['failed', 'interrupted', 'reason', 'missing-marker', 'duplicate-marker', 'forbidden',
		'input-mismatch', 'missing-source-input', 'frozen-source', 'missing-archive', 'missing-build-command', 'changed-elf'] {
		copy := proof + '/' + name
		clone_evidence(run, copy, outputs)!
		if name in ['failed', 'interrupted', 'reason'] {
			mut result := json2.decode[map[string]json2.Any](os.read_file(copy + '/result.json')!)!
			if name == 'failed' { result['passed'] = false }
			else if name == 'interrupted' { result['interrupted'] = true }
			else { result['reason'] = 'control failure' }
			os.write_file(copy + '/result.json', json2.encode(result))!
			reseal(copy, ['result.json'])!
		} else if name in ['missing-marker', 'duplicate-marker', 'forbidden'] {
			serial := os.read_file(copy + '/boot/serial.log')!
			changed := if name == 'missing-marker' { serial.replace(marker, 'removed marker') }
				else if name == 'duplicate-marker' { serial + '\n' + marker + '\n' }
				else { serial + '\nHWTEST FAIL injected control\n' }
			os.write_file(copy + '/boot/serial.log', changed)!
			reseal(copy, ['boot/serial.log'])!
		} else if name == 'input-mismatch' {
			mut inputs := json2.decode[map[string]string](os.read_file(copy + '/inputs-verified.json')!)!
			inputs['control'] = 'changed'
			os.write_file(copy + '/inputs-verified.json', json2.encode(inputs))!
			reseal(copy, ['inputs-verified.json'])!
		} else if name == 'missing-source-input' {
			for file in ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json'] {
				mut inputs := json2.decode[map[string]string](os.read_file(copy + '/' + file)!)!
				for path in inputs.keys() { if path.ends_with('/tests/wine-host/native/main.v') && !path.contains('/source/') { inputs.delete(path) } }
				os.write_file(copy + '/' + file, json2.encode(inputs))!
			}
			reseal(copy, ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json'])!
		} else if name == 'frozen-source' {
			os.write_file(copy + '/source/tests/wine-host/native/main.v', '// changed fixture\n')!
			reseal(copy, ['source/tests/wine-host/native/main.v'])!
		} else if name == 'changed-elf' {
			os.write_file(copy + '/build-guest/guest', 'changed executable\n')!
			reseal(copy, ['build-guest/guest'])!
		} else {
			mut listing := json2.decode[map[string]string](os.read_file(copy + '/outputs.json')!)!
			listing.delete(if name == 'missing-archive' { 'boot/initramfs.tar' } else { 'build-guest/cc.log.argv.json' })
			os.write_file(copy + '/outputs.json', json2.encode(listing))!
		}
		output := copy + '/retained'
		if validate(retainer, copy, tail, output, proof + '/' + name + '.log')! == 0 || os.exists(output) {
			return error('corrupted evidence accepted or created output: ' + name)
		}
		refused << name
	}
	os.write_file(proof + '/controls.json', json2.encode(Controls{ baseline: true, refused: refused,
		source: hash_file(source)!, executable: hash_file(os.executable())! }) + '\n')!
	println('HOSTED X11 EVIDENCE CONTROLS PASS: real baseline plus ' + refused.len.str() + ' resealed corruptions refused')
}

fn main() { checks() or { eprintln(err); exit(1) } }
