// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the diagnostic command without representing synthetic audio as a guest run.
module main

import crypto.sha256
import json2
import math
import os

struct Control {
	name string
	code int
	output string
}

struct Report {
	format int = 1
	result string = 'PASS'
	platform string = 'synthetic-basic-diagnostic-controls'
	qualification bool
	checker string
	retainer string
	inputs map[string]string
	controls []Control
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn le16(value int) []u8 { return [u8(value), u8(value >> 8)] }
fn le32(value int) []u8 { return [u8(value), u8(value >> 8), u8(value >> 16), u8(value >> 24)] }

fn wave(frequencies []int, right int, gap int, leading int) []u8 {
	mut pcm := []u8{len: leading * 4}
	for frequency in frequencies {
		for frame in 0 .. 48000 {
			value := math.sin(2 * math.pi * frequency * frame / 48000)
			pcm << le16(int(value * 12000))
			pcm << le16(int(value * right))
		}
		pcm << []u8{len: gap * 4}
	}
	mut bytes := 'RIFF'.bytes()
	bytes << le32(36 + pcm.len)
	bytes << 'WAVEfmt '.bytes()
	bytes << le32(16)
	bytes << le16(1)
	bytes << le16(2)
	bytes << le32(48000)
	bytes << le32(192000)
	bytes << le16(4)
	bytes << le16(16)
	bytes << 'data'.bytes()
	bytes << le32(pcm.len)
	bytes << pcm
	return bytes
}

fn sample_serial() string {
	login := 'AUDIO LOGIN uid=1000 home=/home/alex supplementary-users PASS'
	mut lines := ['HWTEST START packages-audio-basic', 'AUDIO SETUP signed tone and noaudio installed PASS',
		'AUDIO CONTROL group0-forged-account-action refused PASS']
	for run, mode in {'missing': 'refuse', 'policy': 'tone', 'forged': 'forged', 'service': 'service', 'changed': 'changed', 'sequence': 'sequence'} {
		lines << login
		if run != 'policy' {
			lines << ['AUDIO PAYLOAD ${run} uid=1000 groups=0 signed-context direct-device-refused PASS', 'AUDIO PAYLOAD ${run} ${mode} PASS']
		}
		lines << match run {
			'missing' { 'AUDIO CONTROL absent-permission refused PASS' }
			'policy' { 'AUDIO CONTROL organization-policy refused PASS' }
			'forged' { 'AUDIO CONTROL forged-endpoint refused PASS' }
			'sequence' { 'AUDIO PCM exact sequence 440 660 880 PASS' }
			else { 'AUDIO CONTROL ${run} refused and cleanup PASS' }
		}
	}
	lines << 'HWTEST PASS packages-audio-basic'
	return lines.join('\n') + '\n'
}

fn fixture(run string) ! {
	state := run + '/run/packages-audio-basic'
	os.mkdir_all(state)!
	os.write_file(state + '/outcome.json', json2.encode({
		'scenario': json2.Any('packages-audio-basic'), 'passed': json2.Any(true),
		'interrupted': json2.Any(false), 'seconds': json2.Any(25.0),
		'reason': json2.Any(''), 'state': json2.Any(state),
	}))!
	os.write_file(state + '/serial.log', sample_serial())!
	os.write_file_array(state + '/sound.wav', wave([440, 660, 880], 12000, 57600, 57600))!
	os.write_file(state + '/qemu.log', '')!
	os.write_file(state + '/qmp.log', '[1] <- {"event":"SHUTDOWN","data":{"guest":true,"reason":"guest-shutdown"}}\n')!
}

fn replace(path string, bytes []u8) ! {
	os.rm(path)!
	os.write_file_array(path, bytes)!
}

fn clone(original string, run string) ! {
	state := run + '/run/packages-audio-basic'
	os.mkdir_all(state)!
	for name in ['outcome.json', 'serial.log', 'sound.wav', 'qemu.log', 'qmp.log'] {
		os.link(original + '/run/packages-audio-basic/' + name, state + '/' + name)!
	}
	path := state + '/outcome.json'
	mut value := json2.decode[json2.Any](os.read_file(path)!)!.as_map()
	value['state'] = json2.Any(state)
	replace(path, json2.encode(value).bytes())!
}

fn call(program string, args []string, name string, out string) !Control {
	os.write_file(out + '/' + name + '.argv.json', json2.encode([program, ...args]) + '\n')!
	mut p := os.new_process(program)
	defer { p.close() }
	p.set_args(args)
	p.set_redirect_stdio_merged()
	p.run()
	C.close(p.stdio_fd[0]); p.stdio_fd[0] = -1
	output := p.stdout_slurp()
	p.wait()
	os.write_file(out + '/' + name + '.log', output)!
	return Control{name, p.code, output}
}

fn mutate(run string, name string) !string {
	state := run + '/run/packages-audio-basic'
	if name in ['missing-outcome.json', 'missing-serial.log', 'missing-sound.wav', 'missing-qemu.log', 'missing-qmp.log'] {
		os.rm(state + '/' + name.all_after('missing-'))!
		return 'missing raw basic artifact: ' + name.all_after('missing-')
	}
	if name in ['failed-outcome', 'interrupted-outcome', 'reason-outcome', 'wrong-scenario', 'wrong-state', 'zero-seconds', 'long-seconds'] {
		path := state + '/outcome.json'
		mut value := json2.decode[json2.Any](os.read_file(path)!)!.as_map()
		match name {
			'failed-outcome' { value['passed'] = json2.Any(false) }
			'interrupted-outcome' { value['interrupted'] = json2.Any(true) }
			'reason-outcome' { value['reason'] = json2.Any('failure') }
			'wrong-scenario' { value['scenario'] = json2.Any('packages-audio-seat') }
			'wrong-state' { value['state'] = json2.Any(os.dir(state)) }
			'zero-seconds' { value['seconds'] = json2.Any(0.0) }
			else { value['seconds'] = json2.Any(301.0) }
		}
		replace(path, json2.encode(value).bytes())!
		return 'raw hardware outcome did not pass'
	}
	if name in ['missing-refusal', 'duplicate-marker', 'reordered-marker', 'wrong-identity', 'panic'] {
		path := state + '/serial.log'
		text := os.read_file(path)!
		changed := match name {
			'missing-refusal' { text.replace('AUDIO CONTROL absent-permission refused PASS\n', '') }
			'duplicate-marker' { text + 'HWTEST PASS packages-audio-basic\n' }
			'reordered-marker' { text.replace('HWTEST START packages-audio-basic\nAUDIO SETUP signed tone and noaudio installed PASS',
				'AUDIO SETUP signed tone and noaudio installed PASS\nHWTEST START packages-audio-basic') }
			'wrong-identity' { text.replace('uid=1000 groups=0', 'uid=0 groups=0') }
			else { text + 'KERNEL PANIC\n' }
		}
		replace(path, changed.bytes())!
		return if name == 'panic' { 'forbidden serial marker' } else { 'ordered exact serial markers differ' }
	}
	if name in ['wrong-shutdown', 'duplicate-shutdown'] {
		path := state + '/qmp.log'
		text := os.read_file(path)!
		replace(path, if name == 'wrong-shutdown' { text.replace('guest-shutdown', 'host-qmp-quit').bytes() } else { (text + text).bytes() })!
		return if name == 'wrong-shutdown' { 'requires guest-initiated QMP shutdown' } else { 'missing or duplicated guest QMP shutdown' }
	}
	path := state + '/sound.wav'
	if name == 'symlink-wav' {
		os.rm(path)!
		os.symlink('../foreign.wav', path)!
		return 'requires regular evidence file'
	}
	mut bytes := match name {
		'wrong-frequency' { wave([440, 700, 880], 12000, 57600, 57600) }
		'silent-channel' { wave([440, 660, 880], 0, 57600, 57600) }
		'extra-tone' { wave([440, 660, 880, 440], 12000, 57600, 57600) }
		'short-gap' { wave([440, 660, 880], 12000, 9600, 57600) }
		'short-leading' { wave([440, 660, 880], 12000, 57600, 9600) }
		else { os.read_bytes(path)! }
	}
	if name == 'unfinalized-wav' { for i in 40 .. 44 { bytes[i] = 0 } }
	if name == 'noisy-leading' {
		for frame in 9600 .. 14400 { bytes[44 + frame * 4] = 80; bytes[46 + frame * 4] = 80 }
	}
	replace(path, bytes)!
	return match name {
		'wrong-frequency', 'silent-channel' { 'frequency' }
		'extra-tone' { 'audible runs' }
		'short-gap' { 'recorded quiet gap is shorter' }
		'short-leading' { 'recording lacks one-second leading or trailing quiet' }
		'unfinalized-wav' { 'nonempty complete stereo data' }
		'noisy-leading' { 'background contains nonquiet output' }
		else { return error('unknown basic control') }
	}
}

fn run(program string, out string) ! {
	$if prod {} $else { return error('compile basic control runner with -prod') }
	if digest(@FILE)! != sha256.sum($embed_file('audio-portal-basic-check.v').to_string().bytes()).hex() { return error('basic checker changed after compilation') }
	if !os.is_abs_path(out) || os.abs_path(out) != out || os.real_path(os.dir(out)) != os.dir(out)
		|| os.exists(out) || os.is_link(out) { return error('requires new canonical external control directory') }
	os.mkdir(out)!
	mut tools := map[string]string{}
	for path in [@FILE, os.executable(), program] { tools[path] = digest(path)! }
	os.write_file(out + '/tools-before.json', json2.encode(tools) + '\n')!
	original := out + '/representative-synthetic-basic'
	fixture(original)!
	mut inputs := map[string]string{}
	for name in ['outcome.json', 'serial.log', 'sound.wav', 'qemu.log', 'qmp.log'] {
		path := original + '/run/packages-audio-basic/' + name
		inputs[path] = digest(path)!
	}
	mut controls := []Control{}
	baseline_out := out + '/positive-result'
	positive := call(program, ['--diagnostic-basic', original, baseline_out, 'aarch64'], 'representative-positive', out)!
	if positive.code != 0 { return error('representative basic positive refused: ' + positive.output) }
	value := json2.decode[json2.Any](os.read_file(baseline_out + '/basic-diagnostic.json')!)!.as_map()
	if value['diagnostic_only']! != json2.Any(true) || value['qualification']! != json2.Any(false)
		|| value['requested_architecture']! != json2.Any('aarch64') || value['result']! != json2.Any('PASS')
		|| os.exists(baseline_out + '/qualification.json') || os.exists(baseline_out + '/retained.json') {
		return error('basic positive did not remain diagnostic-only')
	}
	controls << positive
	for name in ['missing-outcome.json', 'missing-serial.log', 'missing-sound.wav', 'missing-qemu.log', 'missing-qmp.log',
		'failed-outcome', 'interrupted-outcome', 'reason-outcome', 'wrong-scenario', 'wrong-state', 'zero-seconds', 'long-seconds',
		'missing-refusal', 'duplicate-marker', 'reordered-marker', 'wrong-identity', 'panic', 'wrong-shutdown', 'duplicate-shutdown',
		'wrong-frequency', 'silent-channel', 'extra-tone', 'short-gap', 'short-leading', 'unfinalized-wav', 'noisy-leading', 'symlink-wav'] {
		work := out + '/' + name
		clone(original, work)!
		reason := mutate(work, name)!
		result_out := out + '/' + name + '-result'
		result := call(program, ['--diagnostic-basic', work, result_out, 'aarch64'], name, out)!
		if result.code == 0 || (reason != '' && !result.output.contains(reason)) || os.exists(result_out) {
			return error('basic control did not refuse before output: ' + name + ': ' + result.output)
		}
		controls << result
	}
	for name, args in {
		'wrong-architecture': ['--diagnostic-basic', original, out + '/wrong-arch-result', 'x86_64']
		'normal-incomplete': [original, out + '/normal-result', 'aarch64']
		'diagnostic-out-inside': ['--diagnostic-basic', original, original + '/result', 'aarch64']
	} {
		result := call(program, args, name, out)!
		if result.code == 0 { return error('incomplete or out-of-scope control accepted: ' + name) }
		controls << result
	}
	for path, expected in inputs { if digest(path)! != expected { return error('original synthetic evidence changed') } }
	mut after := map[string]string{}
	for path, expected in tools {
		after[path] = digest(path)!
		if after[path] != expected { return error('diagnostic control tool or source changed') }
	}
	os.write_file(out + '/tools-after.json', json2.encode(after) + '\n')!
	os.write_file(out + '/basic-controls.json', json2.encode(Report{
		checker: digest(os.executable())!, retainer: digest(program)!, inputs: inputs, controls: controls,
	}) + '\n')!
	println('AUDIO BASIC DIAGNOSTIC CONTROLS PASS controls=' + controls.len.str() + ' qualification=false')
}

fn main() {
	if os.args.len != 3 { eprintln('use RETAINER_PROGRAM NEW_OUTPUT_DIRECTORY'); exit(1) }
	run(os.real_path(os.args[1]), os.args[2]) or { eprintln(err); exit(1) }
}
