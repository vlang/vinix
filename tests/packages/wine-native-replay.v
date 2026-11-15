// SPDX-License-Identifier: GPL-2.0-or-later
// Replay a retained x86 rollback image without copying its runtime or ISO.
module main

import os
import json2
import time
import tests.packages.winesource
import tests.packages.winereplay

struct RecordedOutcome {
	scenario string
	interrupted bool
}

fn verify(inputs map[string]string) ! {
	for path, hash in inputs {
		if winesource.file_digest(path)! != hash { return error('replay input changed: ' + path) }
	}
}

fn run() ! {
	if os.args.len != 3 { return error('usage: wine-native-replay ORIGINAL_NATIVE_RUN FRESH_OUTPUT') }
	original := os.real_path(os.args[1]); work := os.abs_path(os.args[2])
	if os.exists(work) || os.is_link(work) { return error('replay output must be fresh') }
	declaration := json2.decode[map[string]string](os.read_file(original + '/declaration.json')!)!
	if declaration['architecture'] != 'x86_64' || declaration['run'] != original { return error('replay requires the original x86 namespace') }
	outcome := json2.decode[RecordedOutcome](os.read_file(original + '/result.json')!)!
	if outcome.scenario != 'packaged-Wine' || outcome.interrupted { return error('replay requires a completed native attempt') }
	mut inputs := json2.decode[map[string]string](os.read_file(original + '/inputs.json')!)!
	if inputs != json2.decode[map[string]string](os.read_file(original + '/inputs-verified.json')!)! { return error('original input verification differs') }
	for path in [declaration['qemu'], declaration['firmware']] {
		if path == '' || path !in inputs { return error('original VM executable or firmware is not inventoried') }
	}
	for relative, hash in json2.decode[map[string]string](os.read_file(original + '/generated-before-boot.json')!)! {
		inputs[original + '/' + relative] = hash
	}
	boot := original + '/boot'
	mut args := json2.decode[[]string](os.read_file(boot + '/qemu-0.argv.json')!)!
	expected := [declaration['qemu'], '-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-m', '3072', '-smp', '2',
		'-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + declaration['firmware'], '-cdrom', boot + '/test.iso',
		'-display', 'none', '-monitor', 'none', '-serial', 'file:' + boot + '/serial.log', '-no-reboot',
		'-qmp', 'unix:' + boot + '/qmp.sock,server=on,wait=off', '-cpu', 'max']
	if args != expected { return error('original VM arguments differ from the rollback profile') }
	for path in [@FILE, os.executable(), boot + '/test.iso', boot + '/qemu-0.argv.json', original + '/result.json',
		original + '/declaration.json', original + '/inputs.json', original + '/inputs-verified.json', original + '/generated-before-boot.json'] {
		inputs[path] = winesource.file_digest(path)!
	}
	verify(inputs)!
	os.mkdir_all(work)!
	os.write_file(work + '/inputs.json', json2.encode(inputs))!
	args[20] = 'file:' + work + '/serial.log'
	args[23] = 'unix:' + work + '/qmp.sock,server=on,wait=off'
	os.write_file(work + '/qemu.argv.json', json2.encode(args))!
	mut child := os.new_process(args[0])
	defer { if child.is_alive() { child.signal_kill(); child.wait() }; child.close() }
	child.set_args(args[1..]); child.run()
	started := time.sys_mono_now()
	mut passed := false
	mut reason := ''
	for {
		serial := os.read_file(work + '/serial.log') or { '' }
		decision := winereplay.assess(serial, time.sys_mono_now() - started, child.is_alive())
		unsafe { serial.free() }
		if decision.finished {
			passed = decision.passed; reason = decision.reason; break
		}
		time.sleep(100 * time.millisecond)
	}
	if child.is_alive() { child.signal_kill() }
	child.wait()
	result := json2.encode({'passed': json2.Any(passed), 'reason': reason,
		'seconds': f64(time.sys_mono_now() - started) / f64(time.second), 'original': original,
		'scope': 'replay of exact existing signed x86 Wine image; original outcome unchanged'})
	os.write_file(work + '/guest-outcome.json', result)!
	verify(inputs)!
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	os.write_file(work + '/result.json', result)!
	if !passed { return error('Wine replay failed: ' + reason) }
	println('WINE NATIVE REPLAY PASS original outcome preserved; exact ISO and VM profile')
}

fn main() { run() or { eprintln(err); exit(1) } }
