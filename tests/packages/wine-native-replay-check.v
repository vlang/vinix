// SPDX-License-Identifier: GPL-2.0-or-later
// Synthetic host controls only; this program never executes Wine or QEMU.
module main

import os
import json2
import time
import tests.packages.winesource
import tests.packages.winereplay

fn fake_vm() ! {
	if os.args.len != 26 { return error('unexpected synthetic VM arguments') }
	mode := os.getenv('VINIX_REPLAY_CONTROL')
	if mode == 'changed-input' { os.write_file(os.args[12].all_after('file='), 'changed firmware')! }
	serial := os.args[20].all_after('file:')
	os.write_file(serial, if mode == 'forbidden' { 'HWTEST FAIL synthetic guest\n' } else { winereplay.markers[..].join('\n') + '\n' })!
	time.sleep(3 * time.second)
}

struct Verdict { passed bool; seconds f64 }

fn control(cli string, work string, mode string) ! {
	original := work + '/' + mode
	os.mkdir_all(original + '/boot')!
	firmware := original + '/firmware'
	os.write_file(firmware, 'firmware fixture')!
	os.write_file(original + '/boot/test.iso', 'synthetic image, never booted')!
	os.write_file(original + '/result.json', '{"scenario":"packaged-Wine","interrupted":false}')!
	os.write_file(original + '/declaration.json', json2.encode({'architecture': 'x86_64', 'run': original,
		'qemu': os.executable(), 'firmware': firmware}))!
	mut inputs := {os.executable(): winesource.file_digest(os.executable())!}
	if mode != 'missing-input' { inputs[firmware] = winesource.file_digest(firmware)! }
	os.write_file(original + '/inputs.json', json2.encode(inputs))!
	os.write_file(original + '/inputs-verified.json', json2.encode(inputs))!
	os.write_file(original + '/generated-before-boot.json', '{}')!
	args := [os.executable(), '-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-m',
		if mode == 'changed-profile' { '4096' } else { '3072' }, '-smp', '2', '-drive',
		'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware, '-cdrom', original + '/boot/test.iso',
		'-display', 'none', '-monitor', 'none', '-serial', 'file:' + original + '/boot/serial.log', '-no-reboot',
		'-qmp', 'unix:' + original + '/boot/qmp.sock,server=on,wait=off', '-cpu', 'max']
	os.write_file(original + '/boot/qemu-0.argv.json', json2.encode(args))!
	os.setenv('VINIX_REPLAY_CONTROL', mode, true)
	defer { os.unsetenv('VINIX_REPLAY_CONTROL') }
	output := original + '/replayed'
	mut child := os.new_process(cli)
	defer { child.close() }
	child.set_args([original, output]); child.set_redirect_stdio_merged(); child.run()
	text := child.stdout_slurp(); child.wait()
	os.write_file(original + '/runner.log', text)!
	match mode {
		'pass' {
			if child.code != 0 || !json2.decode[Verdict](os.read_file(output + '/result.json')!)!.passed
				|| !os.exists(output + '/inputs-verified.json') { return error('synthetic passing replay refused') }
		}
		'changed-input' {
			if child.code != 1 || !text.contains('replay input changed:') || os.exists(output + '/result.json')
				|| os.exists(output + '/inputs-verified.json')
				|| !json2.decode[Verdict](os.read_file(output + '/guest-outcome.json')!)!.passed {
				return error('changed input published a verified replay verdict')
			}
		}
		'forbidden' {
			if child.code != 1 || json2.decode[Verdict](os.read_file(output + '/result.json')!)!.passed {
				return error('forbidden guest output accepted')
			}
		}
		else {
			message := if mode == 'missing-input' { 'not inventoried' } else { 'VM arguments differ' }
			if child.code != 1 || !text.contains(message) || os.exists(output) { return error('unsafe preflight admitted') }
		}
	}
}

fn run() ! {
	if os.args.len !in [3, 4] { return error('usage: wine-native-replay-check REPLAY_EXECUTABLE FRESH_OUTPUT [RETAINED_REPLAY]') }
	work := os.abs_path(os.args[2])
	if os.exists(work) || os.is_link(work) { return error('fresh control output required') }
	os.mkdir_all(work)!
	for mode in ['pass', 'changed-input', 'forbidden', 'missing-input', 'changed-profile'] { control(os.args[1], work, mode)! }
	if os.args.len == 4 {
		prior := json2.decode[Verdict](os.read_file(os.args[3] + '/result.json')!)!
		serial := os.read_file(os.args[3] + '/serial.log')!
		if !prior.passed || prior.seconds <= 0 || !winereplay.assess(serial, i64(prior.seconds * f64(time.second)), true).passed {
			return error('retained passing serial does not satisfy the stricter verdict')
		}
		println('Retained serial compatibility PASS; no new VM execution')
	}
	println('WINE REPLAY HOST CONTROLS PASS synthetic VM only; no Wine execution claimed')
}

fn main() {
	if os.args.len > 1 && os.args[1] == '-machine' { fake_vm() or { eprintln(err); exit(1) }; return }
	run() or { eprintln(err); exit(1) }
}
