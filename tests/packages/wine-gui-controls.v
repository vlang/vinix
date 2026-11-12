// SPDX-License-Identifier: GPL-2.0-or-later
// Actual passing GUI baseline and APFS-cloned corruption/refusal controls.
module main

import crypto.sha256
import json2
import os
import tests.packages.winesource

struct Report { baseline string; refused []string; inputs map[string]string }

fn digest(path string) !string { return winesource.file_digest(path) }
fn hashes(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }

fn invoke(args []string, log string) !int {
	os.write_file(log + '.argv.json', json2.encode(args))!
	result := os.exec(args)
	os.write_file(log, result.output)!
	return result.exit_code
}

fn replace(path string, text string) ! { os.rm(path)!; os.write_file(path, text)! }

fn run() ! {
	$if prod {} $else { return error('compile GUI controls with -prod') }
	if os.args.len != 5 { return error('usage: wine-gui-controls GUI_RETAINER RUN BASELINE_RETAINER FRESH_OUTPUT') }
	if digest(@FILE)! != sha256.hexhash($embed_file('wine-gui-controls.v').to_string()) { return error('compiled GUI controls source differs') }
	retainer := os.real_path(os.args[1]); baseline := os.real_path(os.args[3])
	original := os.real_path(os.args[2]); out := os.abs_path(os.args[4])
	if os.exists(out) || os.is_link(out) { return error('GUI control output must be fresh') }
	os.mkdir_all(out)!
	inputs := { @FILE: digest(@FILE)!, os.executable(): digest(os.executable())!,
		retainer: digest(retainer)!, baseline: digest(baseline)!, original + '/result.json': digest(original + '/result.json')!,
		original + '/inputs-verified.json': digest(original + '/inputs-verified.json')!, '/bin/cp': digest('/bin/cp')! }
	os.write_file(out + '/inputs.json', json2.encode(inputs))!
	if invoke([retainer, original, baseline, out + '/baseline'], out + '/baseline.log')! != 0 { return error('real GUI baseline refused') }
	mut refused := []string{}
	for name in ['copied-baseline', 'failed-outcome', 'diagnostic-outcome', 'missing-auth-marker',
		'duplicate-result', 'changed-frame-hash', 'changed-png', 'missing-generated-guest',
		'missing-shell-input', 'resealed-pe', 'resealed-runtime', 'changed-publisher-signature'] {
		copy := out + '/' + name
		if invoke(['/bin/cp', '-cRp', original, copy], out + '/' + name + '-copy.log')! != 0 { return error('GUI control clone failed') }
		// The unchanged boot image/staging evidence belongs to the retained
		// original run. Borrow it explicitly; keep generated payloads private
		// so resealing controls never alter the original signed baseline.
		for entry in os.ls(copy + '/boot')! {
			path := copy + '/boot/' + entry
			if os.is_dir(path) && !os.is_link(path) { os.rmdir_all(path)! } else { os.rm(path)! }
			os.symlink(original + '/boot/' + entry, path)!
		}
		mut expected := ''
		if name == 'failed-outcome' {
			mut result := json2.decode[map[string]json2.Any](os.read_file(copy + '/result.json')!)!
			result['passed'] = false; replace(copy + '/result.json', json2.encode(result))!
			expected = 'requires uninterrupted passing GUI outcome'
		} else if name == 'diagnostic-outcome' {
			mut declaration := hashes(copy + '/declaration.json')!; declaration['diagnostic'] = 'numeric-hostname'
			replace(copy + '/declaration.json', json2.encode(declaration))!
			expected = 'diagnostic GUI run is not ordinary-host qualification'
		} else if name in ['missing-auth-marker', 'duplicate-result', 'changed-frame-hash'] {
			serial := os.read_file(copy + '/boot/serial.log')!
			if name == 'missing-auth-marker' {
				replace(copy + '/boot/serial.log', serial.replace('WINE GUI authenticated ordinary display PASS', 'removed authenticated display'))!
				expected = 'missing or duplicated GUI marker:'
			} else if name == 'duplicate-result' {
				replace(copy + '/boot/serial.log', serial + '\nVINIX WIN64 CALCULATOR RESULT 42\n')!
				expected = 'missing or duplicated GUI marker:'
			} else {
				mut changed := serial
				for line in serial.split_into_lines() {
					if line.starts_with('WINE GUI FRAME before ') {
						mut fields := line.trim_space().split(' '); fields[6] = '0'.repeat(64)
						changed = serial.replace(line, fields.join(' ')); break
					}
				}
				if changed == serial { return error('GUI frame control missing original frame') }
				replace(copy + '/boot/serial.log', changed)!
				expected = 'GUI frame bytes differ'
			}
		} else if name == 'changed-png' {
			os.rm(copy + '/before.png')!; os.cp(copy + '/after.png', copy + '/before.png')!
			expected = 'GUI PNG pixels differ from captured frame'
		} else if name == 'missing-generated-guest' {
			mut generated := hashes(copy + '/generated-before-boot.json')!; generated.delete('build-guest/guest')
			replace(copy + '/generated-before-boot.json', json2.encode(generated))!
			expected = 'missing or changed GUI generated artifact:'
		} else if name == 'missing-shell-input' {
			declaration := hashes(copy + '/declaration.json')!
			for file in ['inputs.json', 'inputs-verified.json', 'inputs-before-build.json'] {
				mut changed := hashes(copy + '/' + file)!; changed.delete(declaration['shell'])
				replace(copy + '/' + file, json2.encode(changed))!
			}
			expected = 'missing or changed GUI critical input:'
		} else if name == 'changed-publisher-signature' {
			replace(copy + '/publisher/index.sig', '0'.repeat(128))!
			expected = 'GUI publisher signature differs'
		} else if name in ['resealed-pe', 'resealed-runtime'] {
			file := 'extras/var/lib/vinix-packages/generations/1/apps/' + if name == 'resealed-pe' {
				'org.vinix.wine-calculator/bin/program.exe'
			} else { 'org.vinix.wine-runtime/root/usr/lib/wine/x86_64-unix/winex11.so' }
			bytes := os.read_file(copy + '/' + file)!
			replace(copy + '/' + file, bytes + 'changed')!
			mut generated := hashes(copy + '/generated-before-boot.json')!; generated[file] = digest(copy + '/' + file)!
			replace(copy + '/generated-before-boot.json', json2.encode(generated))!
			expected = if name == 'resealed-pe' { 'GUI signed PE differs from admitted producer' } else { 'GUI runtime differs from admitted console runtime' }
		}
		proof := copy + '-retained'
		code := invoke([retainer, copy, baseline, proof], copy + '-audit.log')!
		if name == 'copied-baseline' {
			if code != 0 { return error('copied GUI baseline refused') }
		} else {
			if code == 0 || os.exists(proof) || !os.read_file(copy + '-audit.log')!.contains(expected) { return error('GUI control refused at wrong gate: ' + name) }
			refused << name
		}
	}
	for path, expected in inputs { if digest(path)! != expected { return error('GUI control input changed') } }
	if refused.len != 11 { return error('GUI refusal count differs') }
	os.write_file(out + '/controls.json', json2.encode(Report{baseline: 'original and copied admitted', refused: refused, inputs: inputs}))!
	println('WINE GUI CONTROLS PASS original/copied baselines and 11 targeted refusals')
}

fn main() { run() or { eprintln(err); exit(1) } }
