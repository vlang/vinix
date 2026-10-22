// SPDX-License-Identifier: GPL-2.0-or-later
// Admit the frozen c035 native Software maintenance snapshot, then retain proof.
module main

import crypto.sha256
import json2
import os

struct Receipt {
	architecture string
	platform string
	artifacts map[string]string
	artifact_paths map[string]string
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if count == 0 { break }
		sum.write(buffer[..count])!
	}
	return sum.sum([]u8{}).hex()
}

fn exact_marker(transcript string, marker string) ! {
	if transcript.split_into_lines().filter(it.trim_right('\r') == marker).len != 1 {
		return error('missing or duplicated exact marker: ' + marker)
	}
}

fn proposal(line string, arch string, key string, operation string, version string,
	previous string, generation int, action string) ! {
	review := json2.decode[json2.Any](line.all_after('SOFTWARE MAINTENANCE PROPOSAL '))!.as_map()
	names := if operation in ['install', 'remove'] { ['org.vinix.counter'] } else { []string{} }
	roots := if operation == 'remove' { []string{} } else { ['org.vinix.counter'] }
	if review['operation']!.str() != operation || review['architecture']!.str() != arch ||
		review['generation']! != json2.Any(f64(generation)) ||
		review['fingerprint']!.str().len != 64 || review['rows']!.as_array().len != 1 ||
		review['names']!.as_array().map(it.str()) != names ||
		review['requested']!.as_array().map(it.str()) != roots ||
		(operation == 'rollback' && review['target_generation']! != json2.Any(f64(1))) {
		return error('maintenance proposal differs from the exact complete package set or generation')
	}
	row := review['rows']!.as_array()[0].as_map()
	if row['id']!.str() != 'org.vinix.counter' || row['version']!.str() != version ||
		row['installed_version']!.str() != previous || row['architecture']!.str() != arch ||
		row['kind']!.str() != 'native' || row['repository']!.str() != 'native' ||
		row['public_key']!.str() != key || row['license']!.str() != 'MIT' ||
		row['permissions']!.as_array().map(it.str()) != ['display'] ||
		row['requested']! != json2.Any(operation != 'remove') || row['action']!.str() != action {
		return error('maintenance proposal has incomplete signed publisher, permission or action details')
	}
}

fn admit_serial(path string, boot int, arch string, key string) ! {
	if (os.stat(path)!).size > 16 * 1024 * 1024 { return error('serial transcript exceeds limit') }
	// x86 firmware leaves its cursor-home sequence immediately before PID 1's
	// first serial line on cold boot 2. Keep exact line matching after that
	// known non-text prefix; all guest marker bytes remain required.
	transcript := os.read_file(path)!.replace('\x1b[01;01H', '')
	for marker in ['SOFTWARE MAINTENANCE FAIL', 'KERNEL PANIC', 'V panic:', 'FATAL EXCEPTION',
		'sysdisk: running from memory', 'sysdisk: updating the system on'] {
		if transcript.contains(marker) { return error('forbidden serial marker: ' + marker) }
	}
	mut markers := ['SOFTWARE MAINTENANCE START',
		'SOFTWARE MAINTENANCE INSTALLED disk-root declaration modes digests PASS',
		'SOFTWARE MAINTENANCE ordinary-compositor uid=1000 home=/home/alex PASS']
	if boot == 1 {
		markers << [
			'SOFTWARE MAINTENANCE review=install unchanged-state approvals=0 PASS',
			'SOFTWARE MAINTENANCE installed version=1.0.0 approvals=1 exact-signed-state launcher PASS',
			'SOFTWARE MAINTENANCE private Counter value=2 uid=1000 mode=0700 PASS',
			'SOFTWARE MAINTENANCE newer signed medium available PASS',
			'SOFTWARE MAINTENANCE refreshed signed=1.1.0 active=1.0.0 approvals=2 PASS',
			'SOFTWARE MAINTENANCE review=upgrade unchanged-state approvals=2 PASS',
			'SOFTWARE MAINTENANCE upgraded version=1.1.0 approvals=3 private=2 launcher PASS',
			'SOFTWARE MAINTENANCE INSTALLED BOOT 1 acquired refreshed upgraded pointer-saved checkpoint PASS',
		]
	} else {
		exact_marker(transcript, 'SOFTWARE MAINTENANCE INSTALLED BOOT 2 exact tools accounts trust state private-data retained PASS')!
		markers << [
			'SOFTWARE MAINTENANCE BOOT 2 retained upgraded=1.1.0 approvals=3 private=3 PASS',
			'SOFTWARE MAINTENANCE review=rollback unchanged-state approvals=3 PASS',
			'SOFTWARE MAINTENANCE rolled-back version=1.0.0 approvals=4 private=3 launcher PASS',
			'SOFTWARE MAINTENANCE review=remove unchanged-state approvals=4 PASS',
			'SOFTWARE MAINTENANCE uninstalled requested=[] packages=[] launcher-absent approvals=5 private=3 PASS',
			'SOFTWARE MAINTENANCE cache-only both repository payload directories absent PASS',
			'SOFTWARE MAINTENANCE review=install unchanged-state approvals=5 PASS',
			'SOFTWARE MAINTENANCE cache-reinstalled version=1.1.0 approvals=6 private=3 launcher PASS',
			'SOFTWARE MAINTENANCE INSTALLED BOOT 2 retained rollback uninstall cache-reinstall pointer-saved PASS',
		]
	}
	mut position := -1
	for marker in markers {
		exact_marker(transcript, marker)!
		next := transcript.index(marker) or { return error('missing maintenance marker') }
		if next <= position { return error('maintenance state, review and approval order differs') }
		position = next
	}
	closed := 'SOFTWARE MAINTENANCE native Counter launch child closed PASS'
	if transcript.split_into_lines().filter(it.trim_right('\r') == closed).len != if boot == 1 { 2 } else { 1 } {
		return error('missing or duplicated native Counter retirement marker')
	}
	lines := transcript.split_into_lines().filter(it.starts_with('SOFTWARE MAINTENANCE PROPOSAL '))
	if lines.len != if boot == 1 { 2 } else { 3 } { return error('missing or duplicated complete maintenance proposal') }
	if boot == 1 {
		proposal(lines[0], arch, key, 'install', '1.0.0', '', 0, 'install')!
		proposal(lines[1], arch, key, 'upgrade', '1.1.0', '1.0.0', 1, 'update')!
	} else {
		proposal(lines[0], arch, key, 'rollback', '1.0.0', '1.1.0', 2, 'update')!
		proposal(lines[1], arch, key, 'remove', '1.0.0', '1.0.0', 3, 'remove')!
		proposal(lines[2], arch, key, 'install', '1.1.0', '', 4, 'install')!
	}
	for index, line in lines {
		operation := json2.decode[json2.Any](line.all_after('SOFTWARE MAINTENANCE PROPOSAL '))!.as_map()['operation']!.str()
		count := if boot == 1 { if index == 0 { 0 } else { 2 } } else { index + 3 }
		marker := 'SOFTWARE MAINTENANCE review=' + operation + ' unchanged-state approvals=' + count.str() + ' PASS'
		at := transcript.index(line) or { return error('missing complete maintenance proposal') }
		after := transcript.index(marker) or { return error('missing read-only maintenance observation') }
		if at >= after { return error('maintenance proposal follows its read-only observation') }
	}
	if arch == 'aarch64' { exact_marker(transcript, 'syspower: power off: stopping devices')! }
}

fn admit_shutdown(path string, boot int) ! {
	if (os.stat(path)!).size > 1024 * 1024 { return error('QMP shutdown transcript exceeds limit') }
	lines := os.read_file(path)!.split_into_lines()
	if lines.len < 4 { return error('missing exact guest SHUTDOWN event') }
	mut count := 0
	for index, line in lines {
		object := json2.decode[json2.Any](line)!.as_map()
		if index == 0 {
			binding := object['graphical_boot'] or { return error('QMP shutdown boot binding differs') }
			if binding !is f64 || binding.f64() != f64(boot) { return error('QMP shutdown boot binding differs') }
		}
		if index == 1 && 'QMP' !in object { return error('invalid shutdown QMP greeting') }
		if index == 2 && 'return' !in object { return error('shutdown QMP capabilities refused') }
		event := (object['event'] or { json2.Any('') }).str()
		if event in ['RESET', 'GUEST_PANICKED'] { return error('forbidden QMP power event: ' + event) }
		if event == 'SHUTDOWN' {
			data := (object['data'] or { return error('QMP shutdown has no data') }).as_map()
			if (data['guest'] or { json2.Any(false) }) != json2.Any(true) ||
				(data['reason'] or { json2.Any('') }) != json2.Any('guest-shutdown') {
				return error('QMP did not report guest-initiated shutdown')
			}
			count++
		}
	}
	if count != 1 { return error('missing or duplicated exact guest SHUTDOWN event') }
}

fn retain() ! {
	$if prod {} $else { return error('compile the maintenance retainer with -prod') }
	if sha256.sum($embed_file('software-maintenance-retain.v').to_string().bytes()).hex() != digest(@FILE)! {
		return error('retainer source changed after retainer compilation')
	}
	if os.args.len != 7 { return error('use RUN_DIRECTORY DESKTOP_BUILD_DIRECTORY KERNEL_ELF CONTROLLER_ELF OUTPUT_DIRECTORY ARCH') }
	run := os.abs_path(os.args[1])
	build := os.abs_path(os.args[2])
	out := os.abs_path(os.args[5])
	arch := os.args[6]
	receipt := json2.decode[Receipt](os.read_file(run + '/qualification.json')!)!
	if arch !in ['aarch64', 'x86_64'] || receipt.architecture != arch ||
		receipt.platform != 'qemu-framebuffer-ordinary-seat-maintenance-installed-root-two-boots' {
		return error('requires the selected architecture installed ordinary maintenance receipt')
	}
	for name, expected in {
		'software-maintenance-check.v': $embed_file('software-maintenance-check.v').to_string()
		'software-graphical-build.v': $embed_file('software-graphical-build.v').to_string()
		'guest/main.v': $embed_file('software-maintenance-guest/main.v').to_string()
		'guest/installed.v': $embed_file('software-maintenance-guest/installed.v').to_string()
		'guest/maintenance.v': $embed_file('software-maintenance-guest/maintenance.v').to_string()
	} {
		if digest(run + '/source/' + name)! != sha256.sum(expected.bytes()).hex() {
			return error('qualified maintenance fixture differs from the embedded source: ' + name)
		}
	}
	if arch == 'x86_64' && digest(run + '/source/plainiso.v')! !=
		sha256.sum($embed_file('../hardware-platform/plainiso/iso.v').to_string().bytes()).hex() {
		return error('qualified maintenance fixture differs from the embedded source: plainiso.v')
	}
	mut paths := {
		'controller': os.abs_path(os.args[4])
		'desktop': build + '/vinix-desktop'
		'desktop-build': run + '/desktop-build.json'
		'desktop-build-original': build + '/desktop-build.json'
		'kernel': os.abs_path(os.args[3])
		'config': run + '/rootfs/etc/vinix-packages/config.json'
		'initramfs': run + '/initramfs.tar'
		'serial': run + '/serial.log'
		'serial-2': run + '/serial-2.log'
		'guest': run + '/guest-build/init'
		'guest-c': run + '/guest-build/init.c'
		'shutdown-1': run + '/shutdown-1.jsonl'
		'shutdown-2': run + '/shutdown-2.jsonl'
		'system-disk': run + '/system.vjfs'
		'installed-declaration': run + '/rootfs/usr/share/software-maintenance-installed.json'
	}
	if arch == 'x86_64' {
		paths['source/plainiso.v'] = run + '/source/plainiso.v'
		paths['boot-iso'] = run + '/test.iso'
		paths['boot-configuration'] = run + '/iso/iso-root/boot/limine.conf'
		paths['boot-image-commands'] = run + '/image-commands.json'
	}
	for name in ['software-maintenance-check.v', 'software-graphical-build.v'] { paths['source/' + name] = run + '/source/' + name }
	for name in ['main.v', 'installed.v', 'maintenance.v'] { paths['source/guest/' + name] = run + '/source/guest/' + name }
	for name, location in {
		'repository': '/usr/share/vinix-packages/repositories/native'
		'repository-newer': '/usr/share/software-maintenance-release-1.1.0'
	} {
		base := run + '/rootfs' + location
		for path in os.walk_ext(base, '') {
			if os.is_file(path) { paths[name + '/' + path[base.len + 1..]] = path }
		}
		for required in ['index.json', 'index.sig'] {
			if name + '/' + required !in paths { return error('missing required signed repository input') }
		}
	}
	mut shots := []string{}
	for path in os.walk_ext(run, '.png') {
		if os.dir(path) != run { continue }
		name := os.file_name(path).all_before_last('.')
		shots << name
		paths[name] = path
	}
	mut required_shots := ['01-catalog', '02-counter-zero', '03-counter-two', '03-counter-saved', '04-updates',
		'05-upgraded', '06-upgraded-counter-two', '07-upgraded-counter-three', '10-reboot-upgraded',
		'11-retained-upgraded', '12-rolled-back', '13-uninstalled', '14-cache-reinstalled',
		'15-reinstalled-counter-three', '16-reinstalled-counter-four']
	for phase in ['install', 'refresh', 'update', 'rollback', 'uninstall', 'reinstall'] {
		required_shots << [phase + '-administrator', phase + '-password-mask']
		if phase != 'refresh' { required_shots << phase + '-review' }
	}
	shots.sort()
	required_shots.sort()
	if shots != required_shots { return error('maintenance run lacks the exact required screenshot set') }
	for name, path in paths {
		if name !in receipt.artifacts { return error('missing required artifact digest: ' + name) }
		if os.real_path(path) != receipt.artifact_paths[name] { return error('receipt input path mismatch: ' + name) }
	}
	if receipt.artifact_paths.len != receipt.artifacts.len { return error('receipt artifact paths do not cover every recorded digest') }
	if receipt.artifacts['desktop-build-original'] != receipt.artifacts['desktop-build'] {
		return error('original desktop build manifest differs from run copy')
	}
	baseline := if arch == 'aarch64' {
		$embed_file('results/2026-10-22/software-first-run-native-aarch64.desktop-build.json').to_string()
	} else { $embed_file('results/2026-10-22/software-first-run-native-x86_64.desktop-build.json').to_string() }
	if sha256.sum(baseline.bytes()).hex() != receipt.artifacts['desktop-build'] {
		return error('maintenance compositor differs from the frozen c035 first-run snapshot')
	}
	manifest := json2.decode[map[string]string](os.read_file(build + '/desktop-build.json')!)!
	if manifest['vinix-desktop'] != receipt.artifacts['desktop'] { return error('desktop receipt does not bind the qualified executable') }
	mut source_count := 0
	for name, expected in manifest {
		if name in ['compiler', 'repository-head'] { continue }
		if name.starts_with('/') || '..' in name.split('/') { return error('desktop manifest contains an invalid path') }
		input := build + if name.starts_with('app/') || name == 'vinix-desktop' { '/' + name } else { '/source/' + name }
		if digest(input)! != expected { return error('qualified frozen desktop input differs: ' + name) }
		source_count++
	}
	configuration := json2.decode[json2.Any](os.read_file(paths['config'])!)!.as_map()
	repositories := configuration['repositories']!.as_array()
	if configuration['architecture']!.str() != arch || configuration['launch_user']!.str() != 'alex' || repositories.len != 1 {
		return error('maintenance configuration differs from the ordinary architecture-matched repository')
	}
	key := repositories[0].as_map()['public_key']!.str()
	if key.len != 64 { return error('maintenance configuration has no exact publisher key') }
	for boot in 1 .. 3 {
		admit_serial(run + if boot == 1 { '/serial.log' } else { '/serial-2.log' }, boot, arch, key)!
		admit_shutdown(run + '/shutdown-' + boot.str() + '.jsonl', boot)!
	}
	// Semantic refusals need not stream a sparse system disk. Every recorded
	// digest still has to pass before the first retained directory is created.
	for name, expected in receipt.artifacts {
		path := receipt.artifact_paths[name] or { return error('missing artifact path: ' + name) }
		if digest(path)! != expected { return error('receipt mismatch: ' + name) }
	}
	os.mkdir_all(out)!
	prefix := out + '/software-maintenance-native-' + arch
	for name, suffix in {
		'qualification.json': '.json'
		'desktop-build.json': '.desktop-build.json'
		'serial.log': '.serial.txt'
		'serial-2.log': '.serial-2.txt'
		'shutdown-1.jsonl': '.shutdown-1.jsonl'
		'shutdown-2.jsonl': '.shutdown-2.jsonl'
	} { os.cp(run + '/' + name, prefix + suffix)! }
	for name in shots { os.cp(run + '/' + name + '.png', prefix + '.' + name + '.png')! }
	println('SOFTWARE MAINTENANCE RETAIN PASS ' + arch + ': ' + receipt.artifacts.len.str() +
		' artifact digests, ' + source_count.str() + ' frozen desktop inputs, five complete proposals, six approvals, two guest shutdowns')
}

fn main() { retain() or { eprintln(err); exit(1) } }
