// SPDX-License-Identifier: GPL-2.0-or-later
// Reseal disposable evidence copies; every refusal must precede output creation.
module main

import json2
import loginproof
import os

struct Control {
	name string
	expected string
}

struct Result {
	name string
	passed bool
	diagnostic string
}

struct Report {
	architecture string
	passed bool
	baseline string
	controls []Result
	arguments []string
	inputs map[string]string
	input_paths map[string]string
}

fn links(source string, output string) ! {
	os.mkdir(output, mode: 0o700)!
	for name in os.ls(source)! { os.symlink(source + '/' + name, output + '/' + name)! }
}

fn directory(source string, output string) ! {
	if os.is_link(output) { os.rm(output)! }
	links(source, output)!
}

fn write(path string, text string) ! {
	if os.is_link(path) { os.rm(path)! }
	os.write_file(path, text)!
}

fn encode(path string, values map[string]string) ! { write(path, json2.encode(values))! }

fn invoke(program string, arguments []string) !(int, string) {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(arguments)
	child.set_redirect_stdio()
	child.wait()
	return child.code, child.stdout_slurp() + child.stderr_slurp()
}

fn omit(path_file string, hash_file string, prefix string) !string {
	mut paths := loginproof.strings(path_file)!
	mut hashes := loginproof.strings(hash_file)!
	mut names := paths.keys().filter(it.starts_with(prefix))
	names.sort()
	if names.len == 0 { return error('control has no matching inventory entry: ' + prefix) }
	name := names[0]
	paths.delete(name)
	hashes.delete(name)
	encode(path_file, paths)!
	encode(hash_file, hashes)!
	return name
}

fn controls() []Control {
	return [
		Control{'missing-marker', 'missing or duplicated exact marker'},
		Control{'duplicate-marker', 'missing or duplicated exact marker'},
		Control{'reordered-markers', 'graphical login markers are out of order'},
		Control{'panic', 'forbidden serial marker'},
		Control{'failed-result', 'requires a passing direct-manager graphical result'},
		Control{'missing-screenshot', 'graphical output inventory differs'},
		Control{'extra-screenshot', 'required screenshot inventory differs'},
		Control{'artifact-pin-mismatch', 'output digest differs'},
		Control{'controller-argv', 'controller arguments differ'},
		Control{'qemu-argv', 'QEMU arguments do not bind'},
		Control{'guest-v-argv', 'guest build arguments do not bind'},
		Control{'guest-c-argv', 'guest build arguments do not bind'},
		Control{'frozen-source', 'qualified graphical fixture differs from embedded source'},
		Control{'desktop-source-omission', 'desktop input inventory differs'},
		Control{'desktop-library-omission', 'desktop input inventory differs'},
		Control{'desktop-sysroot-omission', 'desktop input inventory differs'},
		Control{'frozen-desktop-omission', 'desktop output inventory differs'},
		Control{'desktop-v-argv', 'desktop build argument compiler binding differs'},
		Control{'desktop-c-argv', 'desktop build argument compiler binding differs'},
		Control{'account-source-omission', 'account input inventory differs'},
		Control{'account-library-omission', 'account input inventory differs'},
		Control{'account-action-omission', 'account input inventory differs'},
		Control{'account-v-argv', 'account build argument compiler binding differs'},
		Control{'account-c-argv', 'account build argument compiler binding differs'},
	]
}

fn check() ! {
	if os.args.len != 10 { return error('use RETAIN RUN DESKTOP ACCOUNTS ACCOUNT_PROOF KERNEL CONTROLLER OUTPUT ARCH') }
	retainer := os.abs_path(os.args[1])
	run := os.abs_path(os.args[2])
	desktop := os.abs_path(os.args[3])
	accounts := os.abs_path(os.args[4])
	account_proof := os.abs_path(os.args[5])
	kernel := os.abs_path(os.args[6])
	controller := os.abs_path(os.args[7])
	work := os.abs_path(os.args[8])
	arch := os.args[9]
	if arch !in ['aarch64', 'x86_64'] || os.exists(work) || os.is_link(work) { return error('architecture invalid or output already exists') }
	os.mkdir(work, mode: 0o700)!
	baseline := [run, desktop, accounts, account_proof, kernel, controller, work + '/baseline', arch]
	code, output := invoke(retainer, baseline)!
	write(work + '/baseline.log', output)!
	if code != 0 || !output.contains('independently retained graphical login') { return error('baseline refused: ' + output) }
	mut results := []Result{}
	for control in controls() {
		root := work + '/' + control.name
		os.mkdir(root, mode: 0o700)!
		copy_run := root + '/run'
		copy_desktop := root + '/desktop'
		copy_proof := root + '/accounts'
		links(run, copy_run)!
		directory(run + '/boot', copy_run + '/boot')!
		links(desktop, copy_desktop)!
		links(account_proof, copy_proof)!
		directory(account_proof + '/receipt', copy_proof + '/receipt')!
		for program in ['account', 'auth', 'authd', 'system', 'session'] {
			directory(account_proof + '/' + program, copy_proof + '/' + program)!
		}
		original_paths := loginproof.strings(run + '/input-paths.json')!
		mut paths := original_paths.clone()
		for name, leaf in {'desktop': 'vinix-desktop', 'desktop-build': 'desktop-build.json',
			'desktop-inputs': 'build-inputs.json', 'desktop-input-paths': 'build-input-paths.json', 'desktop-argv': 'build-argv.json'} {
			paths[name] = copy_desktop + '/' + leaf
		}
		for name in ['inputs', 'input-paths', 'outputs', 'arguments', 'result'] { paths['account-proof-' + name] = copy_proof + '/receipt/' + name + '.json' }
		mut args := json2.decode[[]string](os.read_file(run + '/arguments.json')!)!
		args[3], args[5], args[6] = copy_desktop, copy_proof, copy_run
		write(copy_run + '/arguments.json', json2.encode(args))!
		mut outputs := loginproof.strings(run + '/outputs.json')!
		match control.name {
			'missing-marker' { write(copy_run + '/boot/serial.log', os.read_file(run + '/boot/serial.log')!.replace(loginproof.markers[3], 'REMOVED qualification marker'))! }
			'duplicate-marker' { write(copy_run + '/boot/serial.log', os.read_file(run + '/boot/serial.log')! + loginproof.markers[3] + '\n')! }
			'reordered-markers' {
				text := os.read_file(run + '/boot/serial.log')!
				write(copy_run + '/boot/serial.log', text.replace(loginproof.markers[2], '@@swap@@').replace(loginproof.markers[3], loginproof.markers[2]).replace('@@swap@@', loginproof.markers[3]))!
			}
			'panic' { write(copy_run + '/boot/serial.log', os.read_file(run + '/boot/serial.log')! + '\nKERNEL PANIC: refusal control\n')! }
			'failed-result' { encode(copy_run + '/result.json', {'passed': 'false', 'platform': 'direct-graphical-manager-registration-login-switch-logout', 'arch': arch})! }
			'missing-screenshot' { os.rm(copy_run + '/' + loginproof.screenshots[0])!; outputs.delete(loginproof.screenshots[0]) }
			'extra-screenshot' { os.symlink(run + '/' + loginproof.screenshots[0], copy_run + '/unexpected.png')! }
			'artifact-pin-mismatch' { write(copy_run + '/qemu.log', 'changed output without resealing its pin\n')! }
			'controller-argv' { args[2] = '/different/kernel'; write(copy_run + '/arguments.json', json2.encode(args))! }
			'qemu-argv' { write(copy_run + '/qemu-argv.json', json2.encode(['/different/qemu', '-nodefaults']))! }
			'guest-v-argv', 'guest-c-argv' {
				mut values := json2.decode[map[string][]string](os.read_file(run + '/guest-argv.json')!)!
				key := if control.name == 'guest-v-argv' { 'v' } else { 'c' }
				values[key] = ['/different/compiler', '-o', 'guest']
				write(copy_run + '/guest-argv.json', json2.encode(values))!
			}
			'frozen-source' { write(root + '/changed-source.v', '// resealed source substitution\n')!; paths['guest-source'] = root + '/changed-source.v' }
			'desktop-source-omission', 'desktop-library-omission', 'desktop-sysroot-omission' {
				prefix := match control.name { 'desktop-source-omission' { 'source/desktop/' } 'desktop-library-omission' { 'vlib/' } else { 'sysroot/lib/' } }
				name := omit(copy_desktop + '/build-input-paths.json', copy_desktop + '/build-inputs.json', prefix)!
				if name.starts_with('source/') {
					mut manifest := loginproof.strings(copy_desktop + '/desktop-build.json')!
					manifest.delete(name['source/'.len..])
					encode(copy_desktop + '/desktop-build.json', manifest)!
				}
			}
			'frozen-desktop-omission' {
				mut manifest := loginproof.strings(copy_desktop + '/desktop-build.json')!
				name := manifest.keys().filter(it.starts_with('desktop/'))[0]
				manifest.delete(name)
				encode(copy_desktop + '/desktop-build.json', manifest)!
			}
			'desktop-v-argv', 'desktop-c-argv' {
				mut values := json2.decode[map[string][]string](os.read_file(copy_desktop + '/build-argv.json')!)!
				key := if control.name == 'desktop-v-argv' { 'v' } else { 'c' }
				values[key] = ['/different/compiler', '-o', 'desktop']
				write(copy_desktop + '/build-argv.json', json2.encode(values))!
			}
			'account-source-omission', 'account-library-omission', 'account-action-omission' {
				prefix := match control.name { 'account-source-omission' { 'accounts/' } 'account-library-omission' { 'vlib/' } else { 'action/' } }
				omit(copy_proof + '/receipt/input-paths.json', copy_proof + '/receipt/inputs.json', prefix)!
			}
			'account-v-argv', 'account-c-argv' {
				mut values := json2.decode[map[string][]string](os.read_file(copy_proof + '/auth/argv.json')!)!
				key := if control.name == 'account-v-argv' { 'v' } else { 'c' }
				values[key] = ['/different/compiler', '-o', 'auth']
				write(copy_proof + '/auth/argv.json', json2.encode(values))!
				mut account_outputs := loginproof.strings(copy_proof + '/receipt/outputs.json')!
				account_outputs['auth/argv.json'] = loginproof.digest(copy_proof + '/auth/argv.json')!
				encode(copy_proof + '/receipt/outputs.json', account_outputs)!
			}
			else { return error('unimplemented control') }
		}
		mut inputs := loginproof.strings(run + '/inputs.json')!
		for name, path in paths {
			if path != original_paths[name] || name.starts_with('desktop-') || name.starts_with('account-proof-') { inputs[name] = loginproof.digest(path)! }
		}
		encode(copy_run + '/inputs.json', inputs)!
		encode(copy_run + '/inputs-verified.json', inputs)!
		encode(copy_run + '/input-paths.json', paths)!
		for name in ['arguments.json', 'inputs.json', 'inputs-verified.json', 'input-paths.json', 'result.json', 'guest-argv.json', 'qemu-argv.json', 'boot/serial.log'] {
			outputs[name] = loginproof.digest(copy_run + '/' + name)!
		}
		encode(copy_run + '/outputs.json', outputs)!
		refusal_output := root + '/must-not-exist'
		status, diagnostic := invoke(retainer, [copy_run, copy_desktop, accounts, copy_proof, kernel, controller, refusal_output, arch])!
		write(root + '/refusal.log', diagnostic)!
		passed := status != 0 && diagnostic.contains(control.expected) && !os.exists(refusal_output) && !os.is_link(refusal_output)
		results << Result{control.name, passed, diagnostic.trim_space()}
		if !passed { return error('control did not refuse as expected: ' + control.name + '\n' + diagnostic) }
		println('PASS ' + control.name)
	}
	paths := {
		'control-source': @FILE
		'control': os.executable()
		'proof-source': @DIR + '/loginproof/proof.v'
		'retainer': retainer
		'controller': controller
		'native-inputs': run + '/inputs.json'
		'native-outputs': run + '/outputs.json'
		'baseline-receipt': work + '/baseline/receipt.json'
	}
	mut pins := map[string]string{}
	for name, path in paths { pins[name] = loginproof.digest(path)! }
	write(work + '/controls.json', json2.encode(Report{arch, true, 'Independent native baseline admitted before 24 resealed refusal controls; every refusal left its output absent.', results, os.args, pins, paths}) + '\n')!
	println('PASS ' + arch + ' baseline plus ' + results.len.str() + ' graphical login evidence controls')
}

fn main() { check() or { eprintln(err); exit(1) } }
