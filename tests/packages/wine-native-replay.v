// SPDX-License-Identifier: GPL-2.0-or-later
// Replay a retained x86 rollback image without copying its runtime or ISO.
module main

import os
import json2
import time
import tests.packages.winesource

struct RecordedOutcome {
	scenario string
	interrupted bool
}

const required = [
	'Wine ordinary-caller-SIGKILL outer-status137 holder-alive PASS',
	'Wine manager-SIGKILL adopted-server foreign-refusal126 lease-busy PASS',
	'Wine migration stale-generation refusal all-targets-unchanged PASS',
	'Wine rollback stale-generation refusal all-targets-unchanged PASS',
	'Wine rollback prefix migrated and real Win64 relaunched status37 PASS',
	'Wine rolled-back prefix relaunch status37 private-data lease-free collected PASS',
	'HWTEST PASS packaged-Wine',
]

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
		forbidden := serial.contains('HWTEST FAIL') || serial.contains('Kernel panic') || serial.contains('KERNEL PANIC') || serial.contains('FATAL EXCEPTION')
		complete := required.all(serial.contains(it))
		unsafe { serial.free() }
		if forbidden {
			reason = 'forbidden guest output'; break
		}
		if complete { passed = true; break }
		if !child.is_alive() { reason = 'guest stopped before acceptance'; break }
		if time.sys_mono_now() - started > 900 * time.second { reason = 'guest exceeded unchanged 900-second rollback bound'; break }
		time.sleep(100 * time.millisecond)
	}
	if child.is_alive() { child.signal_kill() }
	child.wait()
	os.write_file(work + '/result.json', json2.encode({'passed': json2.Any(passed), 'reason': reason,
		'seconds': f64(time.sys_mono_now() - started) / f64(time.second), 'original': original,
		'scope': 'replay of exact existing signed x86 Wine image; original outcome unchanged'}))!
	verify(inputs)!
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	if !passed { return error('Wine replay failed: ' + reason) }
	println('WINE NATIVE REPLAY PASS original outcome preserved; exact ISO and VM profile')
}

fn main() { run() or { eprintln(err); exit(1) } }
