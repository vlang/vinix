// SPDX-License-Identifier: GPL-2.0-or-later
// Probe block notification observers with original cooked content and advertising skipped.
module main

import crypto.sha256
import frozenv
import os
import strconv

const prior_hash = '861032aa63e32609305f2874846030fab11cd32157250e8c73a8efacb12be47c'
const app_prefix = 'Payload/FortniteClient-IOS-Shipping.app/'
const fixtures = ['application-badge', 'window', 'string-float', 'string-cstring',
	'bundle-receipt', 'cf-string-output', 'search-path', 'home-directory',
	'inline-pthread-self', 'dictionary-snapshot', 'block-byref', 'processinfo',
	'vm-probe', 'main-selector', 'view-tag', 'responder', 'string-normalization', 'string-cstring-output', 'number-bool', 'url-resource', 'string-path', 'bundle-identifier', 'dictionary-file', 'string-get-cstring', 'bundle-info', 'locale-preferred', 'metal-device', 'notification-block']
const launch_resources = ['Info.plist', 'LaunchScreen.storyboardc/Info.plist',
	'LaunchScreen.storyboardc/LaunchScreen.nib',
	'LaunchScreen.storyboardc/01J-lp-oVM-view-Ze5-6b-2t3.nib', 'LaunchScreenIOS.png']
const descriptor_alert = 'Showing Alert:\n  Title:Message\n  Message:Failed to open descriptor file ../../../FortniteGame/FortniteGame.uproject\nFor troubleshooting, please go to https://docs.unrealengine.com/SharingAndReleasing/Mobile/iOS\n'
const startup_boundary = 'V panic: iOS: unimplemented Objective-C method AVAudioSession isOtherAudioPlaying\n'
const output_marker = 'IOS-NOTIFICATION-BLOCK: nil-queue callbacks, name and sender filters, block/token ownership, reentrant removal, unlocked captures, center cleanup, eight concurrent workers and two drained runtimes PASS'
const native_marker = 'IOS-NOTIFICATION-BLOCK-NATIVE: nil-queue synchronous delivery, filters, copied captures, owned tokens and removal during callbacks PASS'
const application_stop = 'IOS-PROBE-DESKTOP: stop=Broken pipe handshake=true builds=40 polls=39 closed=false supervisor_kill=false wait=256'
const fixture_stop = 'IOS-PROBE-DESKTOP: stop=session complete handshake=true builds=1 polls=2 closed=true supervisor_kill=false wait=0'
const zero_events = 'events=low 0;high 0;max 0;oom 0;oom_kill 0;oom_group_kill 0;'

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
	return path != '' && !path.starts_with('/') && !path.contains('\\')
		&& !path.contains('\n') && !path.contains('\r')
		&& path.split('/').all(it != '' && it != '.' && it != '..')
}

fn files(root string, relative string) ![]string {
	mut result := []string{}
	for name in os.ls(os.join_path(root, relative))! {
		path := if relative == '' { name } else { relative + '/' + name }
		if !safe_path(path) || os.is_link(root + '/' + path) { return error('unsafe evidence path: ' + path) }
		if os.is_dir(root + '/' + path) { result << files(root, path)! }
		else if os.is_file(root + '/' + path) { result << path }
		else { return error('unexpected evidence file type: ' + path) }
	}
	result.sort()
	return result
}

fn inventory(root string) !string {
	mut lines := []string{}
	for path in files(root, '')! { lines << digest(root + '/' + path)! + '  ' + path }
	return lines.join('\n') + '\n'
}

fn verify_inventory(root string, expected string) ! {
	listed := records(expected)!
	mut paths := listed.keys()
	paths.sort()
	if files(root, '')! != paths { return error('changed resource inventory') }
	for path, hash in listed {
		if digest(root + '/' + path)! != hash { return error('changed resource: ' + path) }
	}
}

fn records(text string) !map[string]string {
	mut result := map[string]string{}
	for line in text.trim_space().split_into_lines() {
		if line.len < 67 || line[64..66] != '  ' || line[..64].bytes().any(!it.is_hex_digit()) {
			return error('invalid hash record')
		}
		path := line[66..]
		if !safe_path(path) || path in result { return error('unsafe or duplicate hash path') }
		result[path] = line[..64]
	}
	return result
}

fn capture(out string, label string, args []string) ! {
	mut p := os.new_process(args[0])
	p.set_args(args[1..])
	frozenv.configure(mut p, args[0])!
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	os.write_file(out + '/' + label + '.log', 'COMMAND: ' + args.map(os.quoted_path(it)).join(' ') + '\n' + output)!
	os.write_file(out + '/' + label + '.status.txt', code.str() + '\n')!
	if code != 0 { return error(label + ' failed: ' + out + '/' + label + '.log') }
	println(label + ': PASS')
}

fn successful(out string, label string) ! {
	if os.read_file(out + '/' + label + '.status.txt')! != '0\n'
		|| !os.read_file(out + '/' + label + '.log')!.starts_with('COMMAND: ') {
		return error('failed validation: ' + label)
	}
}

// Validate the complete member list before allowing tar to touch the filesystem.
// Only the exact app root is extracted; symlinks and special files are rejected.
fn ipa_members(listing string, verbose string) ![]string {
	mut selected := []string{}
	mut seen := map[string]bool{}
	mut command := false
	for path in listing.split_into_lines() {
		plain := path.trim_right('/')
		if !safe_path(plain) || plain in seen { return error('unsafe or duplicate IPA member: ' + path) }
		seen[plain] = true
		if path == app_prefix + 'uecommandline.txt' { command = true }
		if path == app_prefix + 'uecommandline.txt' || path.starts_with(app_prefix + 'cookeddata/') {
			if !path.ends_with('/') { selected << path[app_prefix.len..] }
		}
	}
	for line in verbose.split_into_lines() {
		if line.len == 0 || line[0] !in [`-`, `d`] { return error('non-regular IPA member') }
	}
	if !command || selected.len < 2 { return error('missing cooked resources') }
	selected.sort()
	return selected
}

fn prepare(root string, out string, prior string, v string) ! {
	if os.exists(out + '/prior-manifest.sha256') { return error('already prepared') }
	os.mkdir_all(out)!
	if digest(prior + '/manifest.sha256')! != prior_hash { return error('unexpected prior checkpoint') }
	capture(out, 'prior-check', [prior + '/metal-device', 'check', prior])!
	os.cp(prior + '/manifest.sha256', out + '/prior-manifest.sha256')!
	os.write_file(out + '/prior-bundle.txt', prior + '\n')!
	capture(out, 'clone-application', ['/bin/cp', '-cR', prior + '/application', out + '/application'])!
	capture(out, 'clone-ipa', ['/bin/cp', '-c', prior + '/source.ipa', out + '/source.ipa'])!
	capture(out, 'clone-resources', ['/bin/cp', '-cR', prior + '/resources', out + '/resources'])!
	for path in ['ipa-members.txt', 'ipa-members-verbose.txt', 'resource-files.txt', 'resources.sha256'] {
		os.cp(prior + '/' + path, out + '/' + path)!
	}
	mut paths := []string{}
	for fixture in fixtures.filter(it != 'notification-block') {
		for suffix in ['', '.c'] {
			path := fixture + '-checks' + suffix
			os.cp(prior + '/' + path, out + '/' + path)!
			paths << path
		}
	}
	os.write_file(out + '/reused-files.txt', paths.join('\n') + '\n')!
	os.write_file(out + '/provenance.txt', 'Prior complete bundle: ' + prior + '\nPrior manifest SHA-256: ' + prior_hash +
		'\nOriginal IPA, application, cooked resources and 27 regression fixture builds reused unchanged.\n' +
		'Runtime, supervisor, notification block fixture rebuilt. Advertising skipped. Rendering unverified.\n')!
	for tool in ['notification-vm', 'notification-checks'] {
		capture(out, 'build-' + tool, [v, '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-O2', '-path',
			'@vlib|' + root + '/compat/ios|' + root + '/tests/ios|@vmodules', '-o', out + '/' + tool,
			root + '/tests/ios/' + tool + '.v'])!
	}
}

fn host_observation(log string) ! {
	if !log.starts_with('COMMAND: ') || log.count(output_marker) != 1 || log.count(native_marker) != 1 {
		return error('missing or duplicated host Notification block observer result')
	}
	for bad in ['> assert ', 'runtime error:', 'V panic:', 'AddressSanitizer', 'UndefinedBehaviorSanitizer'] {
		if log.contains(bad) { return error('host Notification block observer failure: ' + bad) }
	}
}

fn regression_observation(log string) ! {
	if !log.starts_with('COMMAND: ')
		|| log.count('IOS-NOTIFICATION-QUEUE-NATIVE: layout/encodings, main default queue, exact synchronous/deferred note identity, coalescing/dequeue matrices, sender/info identities, pending/cancelled ownership and callback batches') != 1
		|| log.count('IOS-NOTIFICATION-QUEUE: metadata, exact FIFO/coalescing identities, synchronous Now and deferred ASAP, nil filters/center, callback batches, pending ownership, unlocked constructor/removal callbacks, rollback, guarded storage, frame/native precedence, isa disposal and repeated drained shutdown cancellation') != 1 {
		return error('missing or duplicated notification queue regression result')
	}
	for bad in ['> assert ', 'runtime error:', 'V panic:', 'AddressSanitizer', 'UndefinedBehaviorSanitizer'] {
		if log.contains(bad) { return error('notification queue regression failure: ' + bad) }
	}
}

fn state(out string) !string {
	path := os.read_file(out + '/probe-no-ads-state.txt')!.trim_space()
	if os.dir(path) != out || !os.file_name(path).starts_with('probe-no-ads-') { return error('unsafe VM state pointer') }
	for name in ['boot.img', 'efivars.fd', 'initramfs.tar.gz', 'limine.conf', 'serial.log'] {
		if !os.is_file(path + '/' + name) { return error('missing guest media: ' + name) }
	}
	return path
}

fn guest_observation(serial string) ! {
	for bad in ['runtime error:', '> assert ', 'KERNEL PANIC', 'FATAL EXCEPTION',
		'IOS-NATIVE: FAIL', 'iOS FAIL:', 'ERROR: AddressSanitizer', 'supervisor_kill=true',
		'IOS-PROBE-CFSTRING:', 'iOS: UIKit apps must be launched by the Vinix desktop',
		'Showing Alert:', descriptor_alert,
		'iOS: unimplemented Objective-C method NSLocale preferredLanguages\n',
		'iOS: unimplemented Objective-C method NSNotificationCenter addObserverForName:object:queue:usingBlock:\n'] {
		if serial.contains(bad) { return error('guest failure: ' + bad) }
	}
	for marker in ['IOS-PROBE-BUDGET: enforcement and supervisor isolation PASS',
		'IOS-PROBE-BUDGET: check exceed=false wait=0', 'IOS-PROBE-BUDGET: check exceed=true wait=9',
		'IOS-PROBE-FAULT: signal context and restoration PASS',
		'IOS-PROBE-DESKTOP: UIKit window fixture PASS', 'IOS-WINDOW: desktop protocol closed PASS',
		'iOS startup: application entry', 'Using MallocBinned3 allocator.',
		startup_boundary, 'V panic:', output_marker, fixture_stop, application_stop, 'FORTNITE PROBE: process exit status 1\n',
		'FORTNITE PROBE COMPLETE'] {
		if serial.count(marker) != 1 { return error('missing or duplicated guest observation: ' + marker) }
	}
	for name in fixtures {
		if serial.count('IOS-NATIVE: /opt/ios/' + name + '-checks wait status 0') != 1 {
			return error('guest fixture failed: ' + name)
		}
	}
	if serial.count('iOS +load: ') != 9 || serial.count('iOS startup: initializers for ') != 3
		|| serial.count('iOS probe image: base=') != 3 || serial.count('IOS-PROBE-FAULT: signal=') != 1
		|| serial.count('IOS-PROBE-REGS:') != 1 || serial.count('FORTNITE PROBE: ') != 1 {
		return error('changed startup or fault accounting')
	}
	for line in serial.split_into_lines() {
		if line.starts_with('IOS-PROBE-REGS:') && line.count(' x') != 31 { return error('incomplete fault registers') }
	}
	application := serial.all_after('iOS startup: application entry')
	if application.contains('IOS-PROBE-FAULT:') || application.contains('IOS-PROBE-REGS:') {
		return error('unexpected application signal fault')
	}
	stops := application.split_into_lines().filter(it.starts_with('IOS-PROBE-DESKTOP: stop='))
	if stops != [application_stop] {
		return error('changed desktop outcome')
	}
	if serial.count('IOS-PROBE-DESKTOP: stop=') != 2
		|| serial.count('IOS-PROBE-DESKTOP: handshake version=10') != 2
		|| !application.contains('IOS-PROBE-DESKTOP: tree build=1 nodes=1 images=0 bytes=336') {
		return error('missing desktop exchange')
	}
	ordered(serial, [fixture_stop, 'IOS-PROBE-DESKTOP: UIKit window fixture PASS',
		'IOS-PROBE-BUDGET: enforcement and supervisor isolation PASS', ' max=2147483648 ',
		'Using MallocBinned3 allocator.', 'iOS startup: application entry', startup_boundary,
		stops[0], 'IOS-PROBE-BUDGET: final ', 'FORTNITE PROBE: process exit status 1\n',
		'FORTNITE PROBE COMPLETE'])!
	memory_observation(serial)!
}

fn ordered(text string, markers []string) ! {
	mut previous := -1
	for marker in markers {
		position := text.index(marker) or { return error('missing ordered marker: ' + marker) }
		if position <= previous { return error('unexpected marker order: ' + marker) }
		previous = position
	}
}

fn memory_observation(serial string) ! {
	reservation := 'IOS-PROBE-VM: op=mmap address=0x0 size=0x600000000 args=0x3,0x1042,0xf1000000,0x0,0x0,0x0,0x0,0x0,0x0,0x0 result='
	mut reservations := 0
	mut queries := 0
	mut children := 0
	mut finals := 0
	for line in serial.split_into_lines() {
		if line.starts_with(reservation) {
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
	if reservations != 1 || queries == 0 || children != 1 || finals != 1
		|| serial.contains('result=0xffffffffffffffff') { return error('changed memory observation') }
}

fn guest_resources(out string) ! {
	// The frozen V's os.temp_dir() returns /tmp unconditionally on macOS.
	temporary := os.join_path(os.getenv('TMPDIR'), 'notification-block-guest-' + os.getpid().str())
	if os.exists(temporary) { return error('temporary directory exists') }
	os.mkdir(temporary)!
	defer { os.rmdir_all(temporary) or {} }
	mut paths := launch_resources.map('./opt/ios/' + it)
	paths << ['./opt/ios/uecommandline.txt', './opt/ios/cookeddata', './sbin/init', './opt/ios/run-ios',
		'./opt/ios/probe-desktop', './opt/ios/probe-memory-max']
	for name in fixtures { paths << './opt/ios/' + name + '-checks' }
	mut args := ['/usr/bin/tar', '-xzf', state(out)! + '/initramfs.tar.gz', '-C', temporary, '--']
	args << paths
	extracted := os.exec(args)
	if extracted.exit_code != 0 { return error('cannot extract guest resources: ' + extracted.output) }
	expected_resources := records(os.read_file(out + '/resources.sha256')!)!
	mut cooked_lines := []string{}
	for path, hash in expected_resources {
		if path.starts_with('cookeddata/') { cooked_lines << hash + '  ' + path['cookeddata/'.len..] }
	}
	verify_inventory(temporary + '/opt/ios/cookeddata', cooked_lines.join('\n') + '\n')!
	if digest(temporary + '/opt/ios/uecommandline.txt')! != expected_resources['uecommandline.txt'] {
		return error('changed guest command line')
	}
	if files(temporary + '/opt/ios/cookeddata', '')!.map('cookeddata/' + it) !=
		files(out + '/resources/cookeddata', '')!.map('cookeddata/' + it) { return error('changed guest resource inventory') }
	for path in launch_resources {
		if digest(temporary + '/opt/ios/' + path)! != digest(out + '/application/' + path)! { return error('changed launch resource') }
	}
	mut pairs := [['native-init', 'sbin/init'], ['run-ios-gles', 'opt/ios/run-ios']]
	for name in fixtures { pairs << [name + '-checks', 'opt/ios/' + name + '-checks'] }
	for pair in pairs {
		if digest(out + '/' + pair[0])! != digest(temporary + '/' + pair[1])! { return error('changed guest binary') }
	}
	if os.read_file(temporary + '/opt/ios/probe-desktop')! != '1'
		|| os.read_file(temporary + '/opt/ios/probe-memory-max')! != '2147483648' {
		return error('changed desktop or memory configuration')
	}
}

fn results(out string) ! {
	if digest(out + '/prior-manifest.sha256')! != prior_hash { return error('changed prior manifest') }
	prior := records(os.read_file(out + '/prior-manifest.sha256')!)!
	expected := fixtures.filter(it != 'notification-block').map(it + '-checks')
	mut reused := []string{}
	for name in expected { for suffix in ['', '.c'] { reused << name + suffix } }
	if os.read_lines(out + '/reused-files.txt')! != reused { return error('changed reused build inventory') }
	for path, hash in prior {
		if path.starts_with('application/') || path.starts_with('resources/') || path in reused
			|| path in ['source.ipa', 'resources.sha256', 'resource-files.txt', 'ipa-members.txt', 'ipa-members-verbose.txt'] {
			if digest(out + '/' + path)! != hash { return error('changed preserved input: ' + path) }
		}
	}
	for path in files(out + '/application', '')! {
		if 'application/' + path !in prior { return error('extra original application file') }
	}
	selected := ipa_members(os.read_file(out + '/ipa-members.txt')!, os.read_file(out + '/ipa-members-verbose.txt')!)!
	if os.read_lines(out + '/resource-files.txt')! != selected || files(out + '/resources', '')! != selected {
		return error('changed resource inventory')
	}
	if os.read_file(out + '/resources.sha256')! != inventory(out + '/resources')! { return error('changed resources') }
	for label in ['prior-check', 'clone-application', 'clone-ipa', 'clone-resources',
		'build-notification-vm', 'build-notification-checks', 'build-notification-block', 'build-init', 'build-runtime',
		'probe-no-ads', 'host-checks', 'regression-host-checks', 'audit-compiler-version', 'audit-inventory-build', 'audit-inventory', 'audit-checker-build', 'audit-selftest'] {
		successful(out, label)!
	}
	if !os.read_file(out + '/prior-check.log')!.contains('Metal device availability check: PASS') { return error('missing prior independent check') }
	revision := os.read_file(out + '/source-revision.txt')!.trim_space()
	if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { return error('invalid source revision') }
	for path in ['tests/ios/notification-block.v', 'tests/ios/notification-vm.v', 'tests/ios/native-init.v',
		'tests/ios/frozenv/toolchain.v',
		'tests/ios/notification-checks.v', 'compat/ios/runner/notifications.c.v', 'compat/ios/runner/objc_storage.c.v',
		'compat/ios/runner/ns_notification_block_test.v', 'compat/ios/runner/notification_queue_test.v'] {
		if path !in os.read_lines(out + '/source-files.txt')! { return error('missing source: ' + path) }
	}
	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3',
		'host-link', 'host', 'host-deterministic'] { successful(out + '/host', label)! }
	for label in ['host', 'host-deterministic'] { host_observation(os.read_file(out + '/host/' + label + '.log')!)! }
	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3',
		'host-link', 'host', 'host-deterministic'] { successful(out + '/regression-host', label)! }
	for label in ['host', 'host-deterministic'] { regression_observation(os.read_file(out + '/regression-host/' + label + '.log')!)! }
	guest_observation(os.read_file(state(out)! + '/serial.log')!.replace('\r\n', '\n'))!

}

fn seal(out string) ! {
	if os.exists(out + '/manifest.sha256') { return error('already sealed') }
	results(out)!
	guest_resources(out)!
	os.write_file(out + '/manifest.sha256', inventory(out)!)!
}

fn check(out string) ! {
	manifest := records(os.read_file(out + '/manifest.sha256')!)!
	actual := files(out, '')!.filter(it != 'manifest.sha256')
	mut listed := manifest.keys()
	listed.sort()
	if actual != listed { return error('missing or unmanifested evidence') }
	for path, hash in manifest {
		if digest(out + '/' + path)! != hash { return error('changed evidence: ' + path) }
	}
	results(out)!
	guest_resources(out)!
}

fn selftest(out string) ! {
	serial := os.read_file(state(out)! + '/serial.log')!.replace('\r\n', '\n')
	guest_observation(serial)!
	headroom := serial.split_into_lines().filter(it.starts_with('iOS memory: os_proc_available_memory='))[0]
	mut changes := [serial.replace(startup_boundary, ''), serial + startup_boundary,
		serial.replace('iOS startup: application entry', ''),
		serial.replace('IOS-PROBE-FAULT: signal context and restoration PASS', ''),
		serial.replace('IOS-PROBE-DESKTOP: UIKit window fixture PASS', ''),
		serial.replace(' closed=true supervisor_kill=false wait=0', ' closed=false supervisor_kill=false wait=0'),
		serial.replace('supervisor_kill=false', 'supervisor_kill=true'),
		serial.replace('FORTNITE PROBE: process exit status 1', 'FORTNITE PROBE: process exit status 0'),
		serial.replace('FORTNITE PROBE COMPLETE', ''),
		serial.replace('iOS +load: ', 'REMOVED-LOAD: '),
		serial.replace('iOS startup: initializers for ', 'REMOVED-INIT: '),
		serial.replace('iOS probe image: base=', 'REMOVED-IMAGE: '),
		serial.replace('IOS-PROBE-REGS:', 'REMOVED-REGS:'),
		serial.replace(' size=0x600000000 ', ' size=0x600001000 '),
		serial.replace(' max=2147483648 ', ' max=4294967296 '),
		serial.replace(headroom, 'iOS memory: os_proc_available_memory=0'),
		serial.replace(zero_events, zero_events.replace('oom_kill 0;', 'oom_kill 1;')),
		serial + '\nKERNEL PANIC\n', serial + '\nV panic: unexpected failure\n',
		serial + descriptor_alert,
		serial.replace(application_stop, application_stop.replace('wait=256', 'wait=0')),
		serial + '\nIOS-PROBE-FAULT: unexpected\n',
		serial + '\nIOS-PROBE-REGS: unexpected\n']
	changes << [serial.replace(output_marker, ''), serial + output_marker,
		serial + '\niOS: unimplemented Objective-C method NSLocale preferredLanguages\n',
		serial + '\niOS: unimplemented Objective-C method NSNotificationCenter addObserverForName:object:queue:usingBlock:\n']
	for name in fixtures {
		changes << serial.replace('/opt/ios/' + name + '-checks wait status 0', '/opt/ios/' + name + '-checks wait status 1')
	}
	for changed in changes {
		mut rejected := false
		guest_observation(changed) or { rejected = true }
		if !rejected { return error('guest mutation accepted') }
	}
	for label in ['host', 'host-deterministic'] {
		log := os.read_file(out + '/host/' + label + '.log')!
		host_observation(log)!
		for changed in [log.replace(output_marker, ''), log + output_marker,
			log.replace(native_marker, ''), log + native_marker, log + '\nruntime error: injected\n',
			log + '\nERROR: AddressSanitizer\n', log + '\nV panic: injected\n', log + '\n> assert false\n'] {
			mut rejected := false
			host_observation(changed) or { rejected = true }
			if !rejected { return error('host mutation accepted') }
		}
		regression := os.read_file(out + '/regression-host/' + label + '.log')!
		regression_observation(regression)!
		for changed in [regression.replace('IOS-NOTIFICATION-QUEUE:', 'MISSING:'),
			regression.replace('IOS-NOTIFICATION-QUEUE-NATIVE:', 'MISSING:'),
			regression + regression, regression + '\nruntime error: injected\n',
			regression + '\nERROR: AddressSanitizer\n', regression + '\nV panic: injected\n',
			regression + '\n> assert false\n', regression + '\nUndefinedBehaviorSanitizer\n'] {
			mut rejected := false
			regression_observation(changed) or { rejected = true }
			if !rejected { return error('notification queue regression mutation accepted') }
		}
	}
	good_members := app_prefix + 'uecommandline.txt\n' + app_prefix + 'cookeddata/game.pak\n'
	good_types := '-rw-r--r-- command\n-rw-r--r-- pak\n'
	if ipa_members(good_members, good_types)! != ['cookeddata/game.pak', 'uecommandline.txt'] {
		return error('valid IPA selection failed')
	}
	for bad in [good_members + '../escape\n', good_members + '/absolute\n',
		good_members + app_prefix + 'uecommandline.txt\n',
		good_members.replace('cookeddata/game.pak', 'cookeddata/../escape'),
		good_members.replace('uecommandline.txt', 'missing.txt')] {
		mut rejected := false
		ipa_members(bad, good_types) or { rejected = true }
		if !rejected { return error('unsafe IPA selection accepted') }
	}
	mut rejected_link := false
	ipa_members(good_members, good_types + 'lrwxr-xr-x link\n') or { rejected_link = true }
	if !rejected_link { return error('IPA symlink accepted') }
	temporary := os.join_path(os.getenv('TMPDIR'), 'notification-block-selftest-' + os.getpid().str())
	if os.exists(temporary) { return error('selftest directory exists') }
	os.mkdir(temporary)!
	defer { os.rmdir_all(temporary) or {} }
	os.write_file(temporary + '/sample', 'original')!
	expected := inventory(temporary)!
	verify_inventory(temporary, expected)!
	os.write_file(temporary + '/sample', 'changed')!
	mut rejected_change := false
	verify_inventory(temporary, expected) or { rejected_change = true }
	os.rm(temporary + '/sample')!
	mut rejected_missing := false
	verify_inventory(temporary, expected) or { rejected_missing = true }
	os.write_file(temporary + '/sample', 'original')!
	os.write_file(temporary + '/extra', 'extra')!
	mut rejected_extra := false
	verify_inventory(temporary, expected) or { rejected_extra = true }
	if !rejected_change || !rejected_missing || !rejected_extra { return error('resource mutation accepted') }
	for bad in [expected + expected, expected.replace('  sample', '  ../sample'), expected.replace('  ', ' ')] {
		mut rejected := false
		records(bad) or { rejected = true }
		if !rejected { return error('invalid manifest accepted') }
	}
	println('Rejected ' + changes.len.str() + ' guest mutations, 32 host mutations, unsafe IPA members and changed/missing/extra resources')
}

fn summary(out string) ! {
	paths := files(out + '/resources', '')!
	mut size := u64(0)
	for path in paths { size += os.file_size(out + '/resources/' + path) }
	println('Resource files: ' + paths.len.str() + '; bytes: ' + size.str())
	println('IPA SHA-256: ' + digest(out + '/source.ipa')!)
	println('Executable SHA-256: ' + digest(out + '/application/FortniteClient-IOS-Shipping')!)
	println('VM state: ' + state(out)!)
}

fn main() {
	if os.args.len < 3 { panic('usage: notification-block prepare OUT PRIOR | fixture|build|host|regression-host|probe|retry-probe OUT | audit OUT REVISION | seal|check|selftest|summary OUT | hash FILE') }
	if os.args[1] == 'hash' { println(digest(os.args[2])!); return }
	root := os.real_path(os.getwd())
	out := os.abs_path(os.args[2])
	if out == root || out.starts_with(root + '/') { panic('output must be external') }
	if os.args[1] !in ['check', 'selftest', 'summary'] && os.exists(out + '/manifest.sha256') { panic('bundle is sealed') }
	// Resource extraction can use separate scratch storage on space-limited hosts.
	// The complete input and evidence inventories are still checked in OUT.
	scratch := os.abs_path(os.getenv_opt('VINIX_IOS_AUDIT_TMPDIR') or { out + '/tmp' })
	if scratch == root || scratch.starts_with(root + '/') { panic('scratch must be external') }
	os.mkdir_all(scratch)!
	os.setenv('VINIX_IOS_AUDIT_TMPDIR', scratch, true)
	os.setenv('TMPDIR', scratch, true)
	os.setenv('V_RESOURCE_PATH', root + '/build/ios/fortnite/ns-calendar-checks/toolchain', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('VINIX_IOS_CHECK_NAME', 'notification-center-checks', true)
	v := root + '/build/ios/fortnite/ns-calendar-checks/toolchain/v'
	match os.args[1] {
		'prepare' {
			if os.args.len != 4 { panic('prepare requires PRIOR') }
			prepare(root, out, os.real_path(os.args[3]), v)!
		}
		'fixture' {
			for target in ['notification-block', 'init'] {
				capture(out, 'build-' + target, [out + '/notification-vm', 'build-' + target, out])!
			}
		}
		'build' { capture(out, 'build-runtime', [out + '/notification-vm', 'build-run-ios-gles', out])! }
		'host' { capture(out, 'host-checks', [out + '/notification-checks', 'notification-block-host', out + '/host'])! }
		'regression-host' { capture(out, 'regression-host-checks', [out + '/notification-checks', 'notification-queue-host', out + '/regression-host'])! }
		'probe' {
			os.setenv('VINIX_IOS_PROBE_MEMORY_MAX', '2147483648', true)
			os.setenv('VINIX_IOS_VM_GZIP_LEVEL', os.getenv_opt('VINIX_IOS_VM_GZIP_LEVEL') or { '1' }, true)
			os.setenv('VINIX_IOS_PROBE_DESKTOP', '1', true)
			os.setenv('VINIX_IOS_STORYBOARD_BUNDLE', out + '/application', true)
			os.setenv('VINIX_IOS_COOKED_BUNDLE', out + '/resources', true)
			capture(out, 'probe-no-ads', [out + '/notification-vm', 'probe-no-ads', out])!
		}
		'retry-probe' {
			vm_state := state(out)!
			failed := out + '/startup-timeout'
			if os.exists(failed) { panic('failed attempt already preserved') }
			if !os.read_file(out + '/probe-no-ads.log')!.contains('V panic: VM timeout: ')
				|| os.read_file(out + '/probe-no-ads.status.txt')!.trim_space() != '1' {
				panic('retry requires a recorded VM startup timeout')
			}
			os.mkdir(failed)!
			for name in ['probe-no-ads.log', 'probe-no-ads.status.txt', 'build-notification-vm.log', 'build-notification-vm.status.txt'] {
				os.cp(out + '/' + name, failed + '/' + name)!
			}
			for name in ['serial.log', 'efivars.fd'] { os.cp(vm_state + '/' + name, failed + '/' + name)! }
			capture(out, 'build-notification-vm', [v, '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-O2',
				'-path', '@vlib|' + root + '/compat/ios|' + root + '/tests/ios|@vmodules', '-o', out + '/notification-vm', root + '/tests/ios/notification-vm.v'])!
			capture(out, 'probe-no-ads', [out + '/notification-vm', 'replay-probe-no-ads', out])!
		}
		'audit' {
			if os.args.len != 4 { panic('audit requires full source revision') }
			// Allow audit tools to use a compatible host compiler independently of
			// the frozen runtime compiler. Record its identity with the evidence.
			audit_v := os.real_path(os.getenv_opt('VINIX_IOS_AUDIT_V') or { v })
			os.setenv('VEXE', audit_v, true)
			os.setenv('V_RESOURCE_PATH', os.dir(audit_v), true)
			os.write_file(out + '/audit-compiler.sha256', digest(audit_v)! + '  ' + audit_v + '\n')!
			capture(out, 'audit-compiler-version', [audit_v, 'version'])!
			inventory_source := os.exec(['git', 'show', os.args[3] + ':tests/ios/compiled-storyboard-input-inventory.v'])
			if inventory_source.exit_code != 0 { panic(inventory_source.output) }
			os.write_file(out + '/audit-inputs.v', inventory_source.output)!
			capture(out, 'audit-inventory-build', [audit_v, '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-O2',
				'-o', out + '/inventory-inputs', out + '/audit-inputs.v'])!
			capture(out, 'audit-inventory', [out + '/inventory-inputs', root, out, os.args[3]])!
			capture(out, 'audit-checker-build', [audit_v, '-nocache', '-gc', 'none', '-cc', 'clang', '-cflags', '-O2',
				'-path', '@vlib|' + out + '/source/tests/ios|@vmodules',
				'-o', out + '/notification-block', out + '/source/tests/ios/notification-block.v'])!
			capture(out, 'audit-selftest', [out + '/notification-block', 'selftest', out])!
		}
		'seal' { seal(out)! }
		'check' { check(out)! }
		'selftest' { selftest(out)! }
		'summary' { summary(out)! }
		else { panic('unknown mode') }
	}
	println('Notification block observer ' + os.args[1] + ': PASS (game rendering unverified)')
}
