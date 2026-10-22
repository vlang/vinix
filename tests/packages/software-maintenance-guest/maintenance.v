// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time

const media = '/usr/share/vinix-packages/repositories/native'
const newer_media = '/usr/share/software-maintenance-release-1.1.0'
const launcher = '/var/lib/vinix-packages/current/share/applications/vinix-org.vinix.counter.desktop'

fn approvals() !int {
	log := os.read_file('/var/log/vinix/auth.log') or { '' }
	defer { unsafe { log.free() } }
	if log.contains('graphical acceptance password') { return error('password appeared in authentication audit') }
	lines := log.split_into_lines()
	defer { unsafe { lines.free() } }
	mut count := 0
	for line in lines {
		if line.contains('uid=1000 run packages-change as alex: exit 0') { count++ }
	}
	return count
}

fn state_text() string {
	return os.read_file('/var/lib/vinix-packages/current/state.json') or { '' }
}

fn verify_state(version string, count int) ! {
	command(['/usr/bin/vinix-package', 'verify'], '')!
	state := json2.decode[json2.Any](state_text())!.as_map()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	configuration := json2.decode[json2.Any](os.read_file('/etc/vinix-packages/config.json')!)!.as_map()
	key := configuration['repositories']!.as_array()[0].as_map()['public_key']!.str()
	if state['architecture']!.str() != architecture || approvals()! != count {
		return error('maintenance architecture or exact ordinary approval count differs')
	}
	packages := state['packages']!.as_array()
	if version == '' {
		if packages.len != 0 || state['requested']!.as_array().len != 0 || os.exists(launcher) {
			return error('uninstall retained package state or active launcher')
		}
	} else {
		if packages.len != 1 || state['requested']!.as_array().map(it.str()) != ['org.vinix.counter'] {
			return error('maintenance activated a different requested closure')
		}
		installed := packages[0].as_map()
		package := installed['package']!.as_map()
		if installed['repository']!.str() != 'native' || installed['public_key']!.str() != key ||
			package['id']!.str() != 'org.vinix.counter' || package['version']!.str() != version ||
			package['architecture']!.str() != architecture || package['kind']!.str() != 'native' ||
			package['license']!.str() != 'MIT' || package['permissions']!.as_array().map(it.str()) != ['display'] ||
			!os.read_file(launcher)!.contains('org.vinix.counter') {
			return error('maintenance signed manifest/provenance or launcher differs')
		}
	}
	metadata := os.lstat('/var/lib/vinix-packages/current/state.json')!
	if metadata.uid != 0 || metadata.mode & 0o022 != 0 { return error('package state is writable by ordinary account') }
}

fn private_data(value string) !InstalledFile {
	file := observed_file(counter_path)!
	directory := os.lstat(os.dir(counter_path))!
	if os.read_file(counter_path)! != value || file.uid != 1000 || directory.uid != 1000 ||
		directory.mode & 0o077 != 0 { return error('maintenance changed exact private Counter data/ownership/mode') }
	return file
}

fn wait_version(mut desktop os.Process, version string, count int, deadline i64) ! {
	for {
		if !desktop.is_alive() || time.sys_mono_now() >= deadline { return error('maintenance state transition timed out') }
		text := state_text()
		matched := if version == '' { text.contains('"packages":[]') } else { text.contains('"version":"' + version + '"') }
		unsafe { text.free() }
		if matched && approvals()! == count { verify_state(version, count)!; return }
		time.sleep(100 * time.millisecond)
	}
}

fn wait_data(mut desktop os.Process, value string, deadline i64) ! {
	for {
		if !desktop.is_alive() || time.sys_mono_now() >= deadline { return error('maintenance Counter save timed out') }
		text := os.read_file(counter_path) or { '' }
		matched := text == value
		unsafe { text.free() }
		if matched { private_data(value)!; wait_counter_closed(mut desktop)!; return }
		time.sleep(100 * time.millisecond)
	}
}

fn maintenance_proposal(operation string, names []string, count int, value string) ! {
	before := state_text()
	defer { unsafe { before.free() } }
	data := if value != '' { private_data(value)! } else { InstalledFile{} }
	if approvals()! != count { return error('unexpected approval before read-only maintenance review') }
	mut child := os.new_process('/usr/bin/vinix-package')
	defer { child.close() }
	child.set_args(['review', operation, ...names])
	child.set_redirect_stdio()
	child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	diagnostic := child.stderr_slurp()
	child.wait()
	if child.code != 0 || output.len > 1024 * 1024 { return error('read-only maintenance review failed: ' + diagnostic) }
	review := json2.decode[json2.Any](output)!.as_map()
	if review['operation']!.str() != operation || review['rows']!.as_array().len != 1 ||
		review['fingerprint']!.str().len != 64 { return error('maintenance proposal is incomplete') }
	if state_text() != before || approvals()! != count ||
		(value != '' && private_data(value)! != data) {
		return error('read-only maintenance proposal changed activation, approval or private data')
	}
	println('SOFTWARE MAINTENANCE PROPOSAL ' + json2.encode(review))
	println('SOFTWARE MAINTENANCE review=' + operation + ' unchanged-state approvals=' + count.str() + ' PASS')
}

fn maintenance(mut desktop os.Process, fresh bool) ! {
	deadline := time.sys_mono_now() + 1200 * time.second
	if fresh {
		require_uninstalled()!
		maintenance_proposal('install', ['org.vinix.counter'], 0, '')!
		wait_version(mut desktop, '1.0.0', 1, deadline)!
		println('SOFTWARE MAINTENANCE installed version=1.0.0 approvals=1 exact-signed-state launcher PASS')
		wait_data(mut desktop, '2', deadline)!
		println('SOFTWARE MAINTENANCE private Counter value=2 uid=1000 mode=0700 PASS')
		// Only the fixture's repository medium changes. Software performs refresh
		// and all activation through real ordinary-account approval UI.
		os.rename(media, media + '-initial')!
		os.rename(newer_media, media)!
		index := os.read_file(media + '/index.json')!
		defer { unsafe { index.free() } }
		encoded := json2.encode(index)
		defer { unsafe { encoded.free() } }
		pattern := '"text":' + encoded
		defer { unsafe { pattern.free() } }
		println('SOFTWARE MAINTENANCE newer signed medium available PASS')
		for {
			if !desktop.is_alive() || time.sys_mono_now() >= deadline { return error('GUI refresh timed out') }
			catalog := os.read_file('/var/lib/vinix-packages/catalog.json') or { '' }
			updated := catalog.contains(pattern)
			unsafe { catalog.free() }
			if updated && approvals()! == 2 { break }
			time.sleep(100 * time.millisecond)
		}
		verify_state('1.0.0', 2)!
		private_data('2')!
		println('SOFTWARE MAINTENANCE refreshed signed=1.1.0 active=1.0.0 approvals=2 PASS')
		maintenance_proposal('upgrade', [], 2, '2')!
		wait_version(mut desktop, '1.1.0', 3, deadline)!
		private_data('2')!
		println('SOFTWARE MAINTENANCE upgraded version=1.1.0 approvals=3 private=2 launcher PASS')
		wait_data(mut desktop, '3', deadline)!
		verify_state('1.1.0', 3)!
		return
	}
	verify_state('1.1.0', 3)!
	data := private_data('3')!
	println('SOFTWARE MAINTENANCE BOOT 2 retained upgraded=1.1.0 approvals=3 private=3 PASS')
	maintenance_proposal('rollback', [], 3, '3')!
	wait_version(mut desktop, '1.0.0', 4, deadline)!
	if private_data('3')! != data { return error('rollback changed retained private file metadata') }
	println('SOFTWARE MAINTENANCE rolled-back version=1.0.0 approvals=4 private=3 launcher PASS')
	maintenance_proposal('remove', ['org.vinix.counter'], 4, '3')!
	wait_version(mut desktop, '', 5, deadline)!
	if private_data('3')! != data { return error('uninstall changed retained private file metadata') }
	for path in [media + '-initial/objects', media + '/objects'] { os.rmdir_all(path)! }
	println('SOFTWARE MAINTENANCE uninstalled requested=[] packages=[] launcher-absent approvals=5 private=3 PASS')
	println('SOFTWARE MAINTENANCE cache-only both repository payload directories absent PASS')
	maintenance_proposal('install', ['org.vinix.counter'], 5, '3')!
	wait_version(mut desktop, '1.1.0', 6, deadline)!
	if private_data('3')! != data || os.exists(media + '-initial/objects') || os.exists(media + '/objects') {
		return error('cached reinstall changed private data or restored repository payloads')
	}
	println('SOFTWARE MAINTENANCE cache-reinstalled version=1.1.0 approvals=6 private=3 launcher PASS')
	wait_data(mut desktop, '4', deadline)!
	verify_state('1.1.0', 6)!
}
