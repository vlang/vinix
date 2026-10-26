// SPDX-License-Identifier: GPL-2.0-or-later
// Audit UIKit responder-chain semantics and the next real application boundary.
module main

import crypto.sha256
import os
import strconv

const previous_manifest = 'ff8b6295e7260f0323cb49dcdb9a1d1f80c6dc4c6d9848249e8d2b153ea1bd49'
const fixtures = ['application-badge', 'window', 'string-float', 'string-cstring',
	'bundle-receipt', 'cf-string-output', 'search-path', 'home-directory',
	'inline-pthread-self', 'dictionary-snapshot', 'block-byref', 'processinfo', 'vm-probe', 'main-selector', 'view-tag', 'responder']
const resources = ['Info.plist', 'LaunchScreen.storyboardc/Info.plist',
	'LaunchScreen.storyboardc/LaunchScreen.nib',
	'LaunchScreen.storyboardc/01J-lp-oVM-view-Ze5-6b-2t3.nib', 'LaunchScreenIOS.png']
const application_alert = 'Showing Alert:\n  Title:Message\n  Message:Failed to open descriptor file ../../../FortniteGame/FortniteGame.uproject\nFor troubleshooting, please go to https://docs.unrealengine.com/SharingAndReleasing/Mobile/iOS\n'
const selector_pass = 'IOS-RESPONDER: shared native cases, subclass inheritance, zeroing weak ownership and two drained runtimes PASS'
const native_pass = 'IOS-RESPONDER-NATIVE: view/controller chains, replacement, detached lifetimes, window/application delegates, metadata, signatures and direct IMP PASS'

const application_stop = 'IOS-PROBE-DESKTOP: stop=session complete handshake=true builds=86 polls=85 closed=true supervisor_kill=false wait=0'
const fixture_stop = 'IOS-PROBE-DESKTOP: stop=session complete handshake=true builds=1 polls=2 closed=true supervisor_kill=false wait=0'
const zero_events = 'events=low 0;high 0;max 0;oom 0;oom_kill 0;oom_group_kill 0;'

fn ordered(text string, markers []string) ! {
	mut previous := -1
	for marker in markers {
		position := text.index(marker) or { return error('missing ordered marker: ' + marker) }
		if position <= previous { return error('unexpected marker order: ' + marker) }
		previous = position
	}
}



fn memory_observation(serial string) ! {
	expected := 'IOS-PROBE-VM: op=mmap address=0x0 size=0x600000000 args=0x3,0x1042,0xf1000000,0x0,0x0,0x0,0x0,0x0,0x0,0x0 result='
	mut reservations := 0
	mut queries := 0
	mut children := 0
	mut finals := 0
	for line in serial.split_into_lines() {
		if line.starts_with(expected) {
			address := strconv.parse_uint(line.all_after('result=0x').all_before(' '), 16, 64)!
			if address == 0 || address == ~u64(0) || address % 4096 != 0 { return error('failed tagged reservation') }
			reservations++
		}
		if line.starts_with('iOS memory: os_proc_available_memory=') {
			available := strconv.parse_uint(line.all_after('='), 10, 64)!
			if available == 0 || available > 2147483648 { return error('invalid process headroom') }
			queries++
		}
		if line.starts_with('IOS-PROBE-BUDGET: child ') && line.contains(' max=2147483648 ') {
			current := strconv.parse_uint(line.all_after(' current=').all_before(' '), 10, 64)!
			headroom := strconv.parse_uint(line.all_after(' headroom='), 10, 64)!
			if current == 0 || current >= 2147483648 || headroom != u64(2147483648) - current {
				return error('invalid child memory budget')
			}
			children++
		}
		if line.starts_with('IOS-PROBE-BUDGET: final ') {
			current := strconv.parse_uint(line.all_after(' current=').all_before(' '), 10, 64)!
			if current >= 2147483648 || !line.ends_with(zero_events) { return error('application OOM or invalid final budget') }
			finals++
		}
	}
	if reservations != 1 || queries != 92 || children != 1 || finals != 1 {
		return error('changed memory observation accounting')
	}
	if serial.contains('result=0xffffffffffffffff') { return error('failed VM call') }
	ordered(serial, ['Using MallocBinned3 allocator.', expected, application_alert])!
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		count := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	return hash.sum([]u8{}).hex()
}

fn safe_path(path string) bool {
	return !path.starts_with('/') && !path.contains('\\')
		&& !path.split('/').any(it in ['', '.', '..'])
}

fn files(root string, relative string) ![]string {
	mut result := []string{}
	for name in os.ls(os.join_path(root, relative))! {
		path := if relative == '' { name } else { relative + '/' + name }
		if os.is_link(root + '/' + path) { return error('symlink in evidence: ' + path) }
		if os.is_dir(root + '/' + path) { result << files(root, path)! } else { result << path }
	}
	result.sort()
	return result
}

fn records(path string) !map[string]string {
	mut result := map[string]string{}
	for line in os.read_lines(path)! {
		if line.len < 67 || line[64..66] != '  ' || line[..64].bytes().any(!it.is_hex_digit()) {
			return error('invalid manifest record')
		}
		name := line[66..]
		if !safe_path(name) || name == 'manifest.sha256' || name in result {
			return error('unsafe/duplicate manifest path')
		}
		result[name] = line[..64]
	}
	if result.len == 0 { return error('empty manifest') }
	return result
}

fn checked_text(path string, text string, markers []string) !string {
	for marker in markers {
		if !text.contains(marker) { return error(path + ': missing ' + marker) }
	}
	for bad in ['runtime error:', '> assert ', 'KERNEL PANIC', 'panic:',
		'FATAL EXCEPTION', 'IOS-NATIVE: FAIL', 'iOS FAIL:', 'ERROR: AddressSanitizer'] {
		if text.contains(bad) { return error(path + ': ' + bad) }
	}
	return text
}

fn require_text(out string, path string, markers []string) !string {
	return checked_text(path, os.read_file(out + '/' + path)!.replace('\r\n', '\n'), markers)
}

fn successful(out string, label string) !string {
	if os.read_file(out + '/' + label + '.status.txt')!.trim_space() != '0' {
		return error(label + ': failed status')
	}
	return require_text(out, label + '.log', ['COMMAND: '])
}

fn probe_state(out string) !string {
	state := os.file_name(os.read_file(out + '/probe-no-ads-state.txt')!.trim_space())
	if !state.starts_with('probe-no-ads-') || !safe_path(state) { return error('invalid VM pointer') }
	for name in ['boot.img', 'efivars.fd', 'initramfs.tar.gz', 'limine.conf', 'serial.log'] {
		if !os.is_file(out + '/' + state + '/' + name) { return error('missing guest media: ' + name) }
	}
	return state
}

fn preserved_inputs(out string) ! {
	if digest(out + '/prior-manifest.sha256')! != previous_manifest { return error('changed prior manifest') }
	prior := records(out + '/prior-manifest.sha256')!
	mut expected := []string{}
	for name in fixtures {
		if name == 'responder' { continue }
		expected << name + '-checks'
		expected << name + '-checks.c'
	}
	listed := os.read_lines(out + '/reused-files.txt')!
	if listed != expected { return error('changed reused target inventory') }
	for path in files(out + '/application', '')! {
		name := 'application/' + path
		if name !in prior || digest(out + '/' + name)! != prior[name] {
			return error('changed original application: ' + path)
		}
	}
	for path, _ in prior {
		if path.starts_with('application/') && !os.is_file(out + '/' + path) {
			return error('missing original application: ' + path)
		}
	}
	for path in expected {
		if path !in prior || digest(out + '/' + path)! != prior[path] { return error('changed reused build: ' + path) }
	}
}

fn guest_resources(out string) ! {
	temporary := os.join_path(os.temp_dir(), 'responder-evidence-' + os.getpid().str())
	if os.exists(temporary) { return error('resource check temporary directory exists') }
	os.mkdir(temporary)!
	defer { os.rmdir_all(temporary) or {} }
	mut paths := resources.map('./opt/ios/' + it)
	for name in fixtures { paths << './opt/ios/' + name + '-checks' }
	paths << ['./sbin/init', './opt/ios/run-ios',
		'./opt/ios/probe-desktop', './opt/ios/probe-memory-max']
	mut args := ['/usr/bin/tar', '-xzf', out + '/' + probe_state(out)! + '/initramfs.tar.gz', '-C', temporary, '--']
	args << paths
	extracted := os.exec(args)
	if extracted.exit_code != 0 { return error('extract guest resources: ' + extracted.output) }
	for path in resources {
		if digest(out + '/application/' + path)! != digest(temporary + '/opt/ios/' + path)! {
			return error('guest resource differs from application: ' + path)
		}
	}
	mut pairs := [['native-init', 'sbin/init'], ['run-ios-gles', 'opt/ios/run-ios']]
	for name in fixtures { pairs << [name + '-checks', 'opt/ios/' + name + '-checks'] }
	for pair in pairs {
		if digest(out + '/' + pair[0])! != digest(temporary + '/' + pair[1])! { return error('changed guest binary') }
	}
	if os.read_file(temporary + '/opt/ios/probe-desktop')! != '1'
		|| os.read_file(temporary + '/opt/ios/probe-memory-max')! != '2147483648' {
		return error('changed guest desktop/budget configuration')
	}
}

fn host_observation(text string) ! {
	checked_text('responder host', text, [selector_pass, native_pass])!
	if text.count(selector_pass) != 1 || text.count(native_pass) != 1 { return error('duplicated host result') }
}

fn guest_observation(serial string) ! {
	mut markers := ['IOS-PROBE-BUDGET: enforcement and supervisor isolation PASS',
		'IOS-PROBE-BUDGET: check exceed=false wait=0', 'IOS-PROBE-BUDGET: check exceed=true wait=9',
		'IOS-PROBE-FAULT: signal context and restoration PASS',
		'IOS-PROBE-DESKTOP: UIKit window fixture PASS', 'IOS-WINDOW: desktop protocol closed PASS',
		'iOS startup: application entry', 'Using MallocBinned3 allocator.',
		'IOS-PROCESSINFO-THERMAL: nominal fallback,',
		'iOS: translated 13 inline pthread_self operations in /opt/ios/FortniteClient-IOS-Shipping']
	for name in fixtures { markers << 'IOS-NATIVE: /opt/ios/' + name + '-checks wait status 0' }
	markers << selector_pass
	if serial.count(selector_pass) != 1 || serial.contains('IOS-PROBE-CFSTRING:') { return error('changed selector/CFString observation') }

	// The full descriptor alert is the recorded boundary; no panic is permitted.
	if serial.count(application_alert) != 1 || serial.count('Showing Alert:') != 1 {
		return error('changed application alert')
	}
	checked_text('guest serial', serial, markers)!
	if serial.count('IOS-PROBE-FAULT: signal=') != 1 || serial.count('IOS-PROBE-REGS:') != 1
		|| serial.count('iOS +load: ') != 9 || serial.count('iOS startup: initializers for ') != 3
		|| serial.count('iOS startup: application entry') != 1 || serial.count('iOS probe image: base=') != 3 {
		return error('changed startup/fault accounting')
	}
	for line in serial.split_into_lines() {
		if line.starts_with('IOS-PROBE-REGS:') && line.count(' x') != 31 { return error('incomplete fault registers') }
	}
	if serial.contains('iOS: UIKit apps must be launched by the Vinix desktop') {
		return error('desktop descriptors missing')
	}
	if serial.count('IOS-PROBE-DESKTOP: handshake version=10') != 2
		|| serial.count('IOS-PROBE-DESKTOP: tree build=1 nodes=1 images=0 bytes=336') != 2
		|| serial.count('IOS-PROBE-DESKTOP: stop=') != 2
		|| serial.count(fixture_stop) != 1 || serial.count(application_stop) != 1
		|| serial.count('FORTNITE PROBE: ') != 1 || serial.count('FORTNITE PROBE COMPLETE') != 1
		|| serial.contains('supervisor_kill=true') {
		return error('changed desktop/application outcome')
	}
	application := serial.all_after('iOS startup: application entry')
	for build in 3 .. 87 {
		if application.count('IOS-PROBE-DESKTOP: tree build=${build} nodes=1 images=0 bytes=336\n') != 1 {
			return error('changed application tree')
		}
	}
	ordered(serial, [fixture_stop, 'IOS-PROBE-DESKTOP: UIKit window fixture PASS',
		'IOS-PROBE-BUDGET: enforcement and supervisor isolation PASS',
		' max=2147483648 ', 'iOS startup: application entry', application_alert,
		application_stop, 'IOS-PROBE-BUDGET: final ', 'FORTNITE PROBE: process exit status 0\n',
		'FORTNITE PROBE COMPLETE'])!
	// Concurrent guest tracing interleaves the second tree's printed line.
	// Its validated count is preserved in the complete peer stop record above.
	ordered(application, ['IOS-PROBE-DESKTOP: handshake version=10',
		'IOS-PROBE-DESKTOP: tree build=1 nodes=1 images=0 bytes=336', application_alert,
		'IOS-PROBE-DESKTOP: tree build=3 nodes=1 images=0 bytes=336', application_stop])!
	memory_observation(serial)!
}

fn results(out string) ! {
	revision := os.read_file(out + '/source-revision.txt')!.trim_space()
	if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { return error('invalid source revision') }
	mut sources := map[string]bool{}
	for path in os.read_lines(out + '/source-files.txt')! {
		if !safe_path(path) || path in sources || !os.is_file(out + '/source/' + path) { return error('invalid source inventory') }
		sources[path] = true
	}
	for path in ['tests/ios/responder-run.v', 'tests/ios/responder-evidence.v',
		'tests/ios/notification-checks.v', 'tests/ios/probedesktop/peer.c.v', 'tests/ios/native-init.v',
		'tests/ios/notification-vm.v', 'compat/ios/runner/views.v',
		'compat/ios/runner/ui_responder_test.v', 'compat/ios/runner/uikit.v',
		'compat/ios/runner/objc_runtime.c.v', 'compat/ios/runner/scenes.c.v',
		'compat/ios/runner/objc.c.v', 'compat/ios/runner/objc_storage.c.v', 'compat/ios/runner/storyboard.v'] {
		if path !in sources { return error('missing source: ' + path) }
	}
	audit_revision := os.read_file(out + '/audit-revision.txt')!.trim_space()
	if audit_revision.len != 40 || audit_revision.bytes().any(!it.is_hex_digit()) { return error('invalid audit revision') }
	for name in ['responder-run', 'responder-evidence', 'compiled-storyboard-input-inventory'] {
		if os.read_file(out + '/audit-source/tests/ios/' + name + '.v')!.len == 0 { return error('missing audit tool source') }
	}
	inputs := os.read_lines(out + '/build-inputs.sha256')!
	if inputs.len == 0 { return error('empty selected build input inventory') }
	for line in inputs {
		if line.len < 67 || line[64..66] != '  ' || line[..64].bytes().any(!it.is_hex_digit()) { return error('invalid build input record') }
	}
	for label in ['prior-check', 'clone-application', 'tool-notification-checks', 'tool-notification-vm',
		'tool-inventory-inputs', 'build-run-ios-gles', 'audit-inventory-build', 'audit-checker-build',
		'audit-driver-build', 'audit-inventory', 'build-responder', 'build-init', 'responder-host'] {
		successful(out, label)!
	}
	require_text(out, 'prior-check.log', ['View-tag evidence check: PASS'])!
	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3', 'host-link', 'host', 'host-deterministic'] {
		text := successful(out, 'host/' + label)!
		if label in ['host', 'host-deterministic'] { host_observation(text)! }
		if label == 'host-generate' && text.contains("'-prod'") { return error('selector assertions disabled') }
		if label in ['host-object-0', 'host-link'] { checked_text(label, text, ['-fsanitize=address,undefined'])! }
	}
	for path in ['host/payload/center-host.c', 'host/payload/host-0.o', 'host/payload/host-1.o',
		'host/payload/host-2.o', 'host/payload/host-3.o',
		'host/NotificationChecks.app/Contents/Info.plist',
		'host/NotificationChecks.app/Contents/MacOS/center-host'] {
		if !os.is_file(out + '/' + path) { return error('missing host artifact: ' + path) }
	}
	archives := os.walk_ext(out + '/host/payload/tls', '.a')
	if archives.len != 1 || os.file_name(archives[0]) != 'libios-tls.a' { return error('missing/extra host TLS archive') }
	if os.read_file(os.dir(archives[0]) + '/compile.status.txt')!.trim_space() != '0' { return error('failed host TLS build') }
	for name in ['run-ios-gles', 'responder-checks', 'native-init'] {
		for suffix in ['', '.c'] { if !os.is_file(out + '/' + name + suffix) { return error('missing fresh build') } }
	}
	for tool in ['notification-checks', 'notification-vm', 'audit-inventory-inputs', 'responder-run', 'responder-evidence'] {
		if !os.is_file(out + '/' + tool) { return error('missing tool: ' + tool) }
	}
	require_text(out, 'provenance.txt', ['Prior manifest SHA-256: ' + previous_manifest,
		'Application and 15 fixtures reused; responder fixture, supervisor and runner rebuilt.',
		'Advertising skipped; desktop protocol is compositor-free. No rendered frame claim.'])!
	successful(out, 'probe-no-ads')!
	require_text(out, 'probe-no-ads.log', ['probe-no-ads: COMPLETE (see guest process status)'])!
	guest_observation(os.read_file(out + '/' + probe_state(out)! + '/serial.log')!.replace('\r\n', '\n'))!
}


fn seal(out string) ! {
	results(out)!
	preserved_inputs(out)!
	guest_resources(out)!
	mut lines := []string{}
	for path in files(out, '')! {
		if path != 'manifest.sha256' { lines << digest(out + '/' + path)! + '  ' + path }
	}
	os.write_file(out + '/manifest.sha256', lines.join('\n') + '\n')!
}

fn check(out string) ! {
	entries := records(out + '/manifest.sha256')!
	actual := files(out, '')!
	if actual.len != entries.len + 1 { return error('manifest file count mismatch') }
	for path in actual {
		if path == 'manifest.sha256' { continue }
		if path !in entries || digest(out + '/' + path)! != entries[path] { return error('unmanifested/changed file: ' + path) }
	}
	results(out)!
	preserved_inputs(out)!
	guest_resources(out)!
}

fn selftest(out string) ! {
	check(out)!
	serial := os.read_file(out + '/' + probe_state(out)! + '/serial.log')!.replace('\r\n', '\n')
	headroom := serial.split_into_lines().filter(it.starts_with('iOS memory: os_proc_available_memory='))[0]
	mut mutations := [serial.replace('IOS-PROBE-DESKTOP: UIKit window fixture PASS', 'REMOVED-FIXTURE'),
		serial.replace(' x30=', ' removed30='), serial + '\nIOS-PROBE-FAULT: signal=unexpected\n',
		serial + '\npanic: unexpected\n', serial.replace('iOS startup: application entry', 'REMOVED-ENTRY'),
		serial.replace(application_alert, ''), serial.replace(application_alert, 'Showing Alert:\n  Message:Different failure\n'),
		serial + application_alert, serial.replace('supervisor_kill=false wait=0', 'supervisor_kill=true wait=9'),
		serial.replace('builds=86 polls=85 closed=true', 'builds=86 polls=85 closed=false'),
		serial.replace('FORTNITE PROBE: process exit status 0', 'FORTNITE PROBE: process exit status 1'),
		serial.replace('tree build=86 nodes=1 images=0', 'tree build=86 nodes=1 images=1'),
		serial.replace('IOS-PROBE-BUDGET: final current=', 'REMOVED-FINAL current='),
		serial.replace(zero_events, 'events=low 0;high 0;max 1;oom 1;oom_kill 1;oom_group_kill 0;'),
		serial.replace('size=0x600000000', 'size=0x600001000'),
		serial.replace(headroom, 'iOS memory: os_proc_available_memory=0'),
		serial.replace(selector_pass, 'REMOVED-SELECTOR-PASS'), serial + selector_pass,
		serial + '\nIOS-PROBE-CFSTRING: unexpected\n']
	for name in fixtures {
		mutations << serial.replace('/opt/ios/' + name + '-checks wait status 0', '/opt/ios/' + name + '-checks wait status 1')
	}
	for changed in mutations {
		if changed == serial { return error('selftest did not mutate guest') }
		mut rejected := false
		guest_observation(changed) or { rejected = true }
		if !rejected { return error('changed guest semantics accepted') }
	}
	println('failed fixtures, changed desktop/alert/exit/budget/reservation/headroom and missing entry/registers: rejected')
	for label in ['host', 'host-deterministic'] {
		host := os.read_file(out + '/host/' + label + '.log')!
		for marker in [selector_pass, native_pass] {
			for changed in [host.replace(marker, 'REMOVED-CASE'), host + marker] {
				if changed == host { return error('selftest did not mutate host case') }
				mut rejected := false
				host_observation(changed) or { rejected = true }
				if !rejected { return error('changed host case accepted') }
			}
		}
	}
	println('each missing/duplicated native/runtime host case: rejected')
	media := out + '/' + probe_state(out)! + '/boot.img'
	backup := media + '.selftest'
	if os.exists(backup) { return error('backup exists') }
	os.mv(media, backup)!
	mut rejected := false
	probe_state(out) or { rejected = true }
	os.mv(backup, media)!
	if !rejected { return error('missing guest media accepted') }
	for path in ['build-responder.status.txt', 'build-init.status.txt', 'responder-host.status.txt',
		'host/host.status.txt', 'host/host-deterministic.status.txt', 'build-run-ios-gles.status.txt',
		'probe-no-ads.status.txt', 'source-revision.txt', 'audit-revision.txt', 'provenance.txt'] {
		before := os.read_file(out + '/' + path)!
		os.write_file(out + '/' + path, 'SELFTEST-CHANGED\n')!
		rejected = false
		results(out) or { rejected = true }
		os.write_file(out + '/' + path, before)!
		if !rejected { return error('changed validation accepted: ' + path) }
	}
	extra := out + '/selftest-unmanifested.txt'
	if os.exists(extra) { return error('selftest extra exists') }
	os.write_file(extra, 'unmanifested\n')!
	rejected = false
	check(out) or { rejected = true }
	os.rm(extra)!
	if !rejected { return error('unmanifested file accepted') }
	println('missing media, changed validation and unmanifested file: rejected')
	check(out)!
}


fn main() {
	if os.args.len != 3 { eprintln('usage: responder-evidence seal|check|selftest DIR | hash FILE | guest SERIAL_LOG'); exit(2) }
	if os.args[1] == 'hash' { println(digest(os.args[2]) or { eprintln(err); exit(1) }); return }
	if os.args[1] == 'guest' {
		serial := os.read_file(os.args[2]) or { eprintln(err); exit(1) }
		guest_observation(serial.replace('\r\n', '\n')) or { eprintln(err); exit(1) }
		println('Responder guest observation: PASS (descriptor alert; bounded peer close; rendering unverified)')
		return
	}
	out := os.real_path(os.args[2]); root := os.real_path(os.getwd())
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') { eprintln('evidence must be outside repository'); exit(2) }
	match os.args[1] {
		'seal' { seal(out) or { eprintln(err); exit(1) } }
		'check' { check(out) or { eprintln(err); exit(1) } }
		'selftest' { selftest(out) or { eprintln(err); exit(1) } }
		else { eprintln('unknown mode'); exit(2) }
	}
	println('Responder evidence ' + os.args[1] + ': PASS (game rendering remains unverified)')
}
