// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only analysis of the controlled unsupported-GPU capture. This is not
// media integrity, rendering or launch qualification. Keep historical rejections.
module main

import os
import strconv

const gpu_gate_message = 'This device does not support the Apple family 3 GPU features (Apple A9+), which is required as the minimum for this engine version.'
const gpu_gate_extra_fixtures = ['storekit-purchase-checks', 'optional-metadata-checks',
	'optional-encoding-checks', 'optional-decoding-checks', 'session-configured-checks',
	'object-equality-checks', 'number-unsigned-checks', 'dictionary-single-checks',
	'dictionary-variadic-checks', 'session-defaults-checks', 'swift-optional-lookup-checks']!

fn one(text string, marker string) ! {
	if text.count(marker) != 1 { return error('missing or duplicated marker: ' + marker) }
}

fn field(line string, name string) !u64 {
	parts := line.split(' ').filter(it.starts_with(name + '='))
	if parts.len != 1 { return error('missing or duplicated field: ' + name) }
	return strconv.parse_uint(parts[0].all_after('='), 10, 64)!
}

fn analyze(raw string, base []string) !string {
	serial := raw.replace('\r\n', '\n')
	if base.len != 35 { return error('expected the 35 original fixtures') }
	mut names := map[string]bool{}
	for name in base { if name in names { return error('duplicate base fixture') }; names[name] = true }
	for name in gpu_gate_extra_fixtures { if name in names { return error('duplicate supplemental fixture') }; names[name] = true }
	for name, _ in names { one(serial, 'IOS-NATIVE: /opt/ios/' + name + ' wait status 0\n')! }
	if serial.split_into_lines().filter(it.starts_with('IOS-NATIVE: /opt/ios/')).len != names.len {
		return error('unexpected fixture result')
	}
	for marker in ['iOS startup: application entry\n',
		'IOS-PROBE-BUDGET: enforcement and supervisor isolation PASS\n',
		'IOS-PROBE-FAULT: signal context and restoration PASS\n',
		'IOS-PROBE-DESKTOP: UIKit window fixture PASS\n']! { one(serial, marker)! }
	app := serial.all_after('iOS startup: application entry\n')
	for marker in ['IOS-PROBE-DESKTOP: handshake version=10\n',
		'Showing Alert:\n  Title:Message\n  Message:' + gpu_gate_message + '\n',
		'FORTNITE PROBE: process exit status 0\n', 'FORTNITE PROBE COMPLETE\n']! { one(app, marker)! }
	for bad in ['V panic:', 'IOS-PROBE-FAULT:', 'IOS-PROBE-REGS:', 'KERNEL PANIC',
		'FATAL EXCEPTION', '> assert ', 'runtime error:', 'ERROR: AddressSanitizer', 'supervisor_kill=true']! {
		if app.contains(bad) { return error('unexpected application failure: ' + bad) }
	}
	lines := app.split_into_lines()
	trees := lines.filter(it.starts_with('IOS-PROBE-DESKTOP: tree '))
	if trees.len < 2 { return error('missing UI snapshots') }
	for i, tree in trees {
		nodes := field(tree, 'nodes')!
		if field(tree, 'build')! != u64(i + 1) || nodes !in [u64(1), 2]!
			|| field(tree, 'images')! != 0 || field(tree, 'bytes')! != nodes * 336 {
			return error('unexpected diagnostic UI snapshot')
		}
	}
	if field(trees.first(), 'nodes')! != 1 || field(trees.last(), 'nodes')! != 2 { return error('missing alert UI transition') }
	stops := lines.filter(it.starts_with('IOS-PROBE-DESKTOP: stop='))
	if stops.len != 1 || !stops[0].starts_with('IOS-PROBE-DESKTOP: stop=session complete handshake=true ')
		|| !stops[0].ends_with(' closed=true supervisor_kill=false wait=0')
		|| field(stops[0], 'builds')! != u64(trees.len) || field(stops[0], 'polls')! == 0 {
		return error('unexpected desktop termination')
	}
	budgets := lines.filter(it.starts_with('IOS-PROBE-BUDGET: final '))
	if budgets.len != 1 || !budgets[0].ends_with(' events=low 0;high 0;max 0;oom 0;oom_kill 0;oom_group_kill 0;') {
		return error('missing clean budget counters')
	}
	current := field(budgets[0], 'current')!
	return 'GPU-GATE-DIAGNOSTIC: fixtures=' + names.len.str() + ' status=0; snapshots=' + trees.len.str()
		+ ' images=0; unsupported Apple family 3 alert; controlled close, no runtime panic or OOM event; post-exit charge='
		+ current.str() + ' (not peak). No game frame, menu, login or gameplay is qualified.'
}

fn selftest() ! {
	base := []string{len: 35, init: 'fixture-' + index.str()}
	mut serial := ''
	for name in base { serial += 'IOS-NATIVE: /opt/ios/' + name + ' wait status 0\n' }
	for name in gpu_gate_extra_fixtures { serial += 'IOS-NATIVE: /opt/ios/' + name + ' wait status 0\n' }
	serial += 'IOS-PROBE-BUDGET: enforcement and supervisor isolation PASS\nIOS-PROBE-FAULT: signal context and restoration PASS\nIOS-PROBE-DESKTOP: UIKit window fixture PASS\niOS startup: application entry\nIOS-PROBE-DESKTOP: handshake version=10\nIOS-PROBE-DESKTOP: tree build=1 nodes=1 images=0 bytes=336\nIOS-PROBE-DESKTOP: tree build=2 nodes=2 images=0 bytes=672\nShowing Alert:\n  Title:Message\n  Message:' + gpu_gate_message + '\nIOS-PROBE-DESKTOP: stop=session complete handshake=true builds=2 polls=1 closed=true supervisor_kill=false wait=0\nIOS-PROBE-BUDGET: final current=10 events=low 0;high 0;max 0;oom 0;oom_kill 0;oom_group_kill 0;\nFORTNITE PROBE: process exit status 0\nFORTNITE PROBE COMPLETE\n'
	analyze(serial, base)!
	analyze(serial.replace('\n', '\r\n'), base)!
	for changed in [serial.replace('fixture-0 wait status 0', 'fixture-0 wait status 1'),
		serial + 'IOS-NATIVE: /opt/ios/fixture-0 wait status 0\n',
		serial.replace(gpu_gate_message, 'different alert'), serial + 'V panic: unexpected\n',
		serial.replace('images=0', 'images=1'), serial.replace('build=2', 'build=3'),
		serial.replace('supervisor_kill=false', 'supervisor_kill=true'), serial.replace('oom 0;', 'oom 1;'),
		serial.replace('process exit status 0', 'process exit status 1'), serial.replace('current=10', 'current=bad'),
		serial.replace('handshake version=10\n', ''), serial.replace('FORTNITE PROBE COMPLETE\n', '')] {
		if _ := analyze(changed, base) { return error('accepted changed diagnostic') }
	}
	println('GPU gate diagnostic self-test: 12 corruption controls PASS; not launch qualification')
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'selftest' { selftest()!; return }
	if os.args.len != 3 || os.args[1] != 'inspect' { panic('usage: gpu-gate-diagnostic selftest | inspect EXTERNAL_BUNDLE') }
	out := os.real_path(os.args[2])
	if out == os.getwd() || out.starts_with(os.getwd() + '/') { panic('requires external evidence') }
	state := os.read_file(out + '/probe-no-ads-state.txt')!.trim_space()
	if os.dir(state) != out || !os.file_name(state).starts_with('probe-no-ads-') { panic('unsafe guest state') }
	if os.read_file(out + '/probe-no-ads.status.txt')! != '0\n' { panic('failed capture') }
	println(analyze(os.read_file(state + '/serial.log')!, os.read_lines(out + '/fixtures.txt')!)!)
}
