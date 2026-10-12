// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tools.packages.pkgprotocol

fn progress_record(event pkgprotocol.Progress) {
	event.validate() or { panic(err) }
	path := os.getenv('VINIX_PACKAGE_PROGRESS_LOG')
	mut file := os.open_file(path, 'a', 0o600) or { panic(err) }
	file.writeln(json2.encode(event)) or { panic(err) }
	file.close()
	if event.phase == 'verify' {
		target := os.getenv('VINIX_PACKAGE_PROGRESS_CORRUPT')
		if target != '' && os.is_file(target) { os.write_file(target, 'corrupted copy') or { panic(err) } }
	}
}

fn progress_events(path string) ![]pkgprotocol.Progress {
	mut events := []pkgprotocol.Progress{}
	for line in os.read_file(path)!.split_into_lines() { events << pkgprotocol.decode_progress(line)! }
	return events
}

fn progress_workspace(label string) !string {
	path := os.temp_dir() + '/vinix-progress-' + label + '-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(path)!
	os.write_file(path + '/events', '')!
	os.setenv('VINIX_PACKAGE_PROGRESS_LOG', path + '/events', true)
	return path
}

fn test_progress_tracks_resumed_bytes_and_only_completes_after_activation() {
	work := progress_workspace('transaction')!
	defer { os.unsetenv('VINIX_PACKAGE_PROGRESS_LOG'); os.rmdir_all(work) or {} }
	root := work + '/root'
	os.mkdir_all(root + '/etc/vinix-packages')!
	os.mkdir_all(work + '/source/bin')!
	payload := 'signed application\n'.repeat(4096)
	os.write_file(work + '/source/bin/app', payload)!
	os.chmod(work + '/source/bin/app', 0o755)!
	key := keygen(work + '/seed')!
	config := Config{ architecture: 'aarch64', repositories: [Repository{ id: 'trusted', url: 'file://' + work + '/repository', public_key: key }], policy: Policy{ reserve_bytes: 0 } }
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
	os.write_file(work + '/manifest.json', json2.encode(Package{ id: 'app', name: 'Application', version: '1.0.0',
		architecture: 'aarch64', kind: 'native', license: 'MIT', entrypoint: 'bin/app' }))!
	p := pack(work + '/manifest.json', work + '/source', work + '/repository')!
	publish(work + '/repository', 'trusted', work + '/seed', 1, time.now().unix() + 3600)!
	service := Service{ root: root, progress: progress_record }
	service.refresh()!
	metadata := progress_events(work + '/events')!
	assert metadata.any(it.phase == 'metadata' && it.total == 0 && it.current > 0)
	assert metadata.last().phase == 'complete'
	os.write_file(work + '/events', '')!
	directory := state_directory(root)
	os.write_file(directory + '/objects/' + p.files[0].sha256 + '.part', payload[..16384])!
	mut review := service.review('install', ['app'])!
	os.mkdir_all(directory + '/generations/.stage-sentinel')!
	mut stale := false
	service.transact('install', ['app'], TransactionOptions{ expected_review: '0'.repeat(64) }) or { stale = err.msg().contains('stale') }
	assert stale && os.read_file(work + '/events')! == '' && os.is_dir(directory + '/generations/.stage-sentinel')
	state := service.transact('install', ['app'], TransactionOptions{ expected_review: review.fingerprint })!
	review.close()
	assert state.generation == 1 && service.verify()!.generation == 1
	events := progress_events(work + '/events')!
	downloads := events.filter(it.phase == 'download')
	assert downloads.first().current == 16384 && downloads.last().current == u64(payload.len)
	assert downloads.all(it.total == u64(payload.len) && it.current <= it.total)
	assert events.any(it.phase == 'copy') && events.any(it.phase == 'verify')
	assert events[events.len - 2].phase == 'activate' && events.last().phase == 'complete'
	// A damaged staged copy fails before publication and emits no completion.
	service.transact('remove', ['app'], TransactionOptions{})!
	os.write_file(work + '/events', '')!
	os.setenv('VINIX_PACKAGE_PROGRESS_CORRUPT', directory + '/generations/.stage-3/apps/app/bin/app', true)
	defer { os.unsetenv('VINIX_PACKAGE_PROGRESS_CORRUPT') }
	mut refused := false
	service.transact('install', ['app'], TransactionOptions{}) or { refused = err.msg().contains('staged payload verification failed') }
	assert refused && service.state()!.generation == 2
	assert progress_events(work + '/events')!.all(it.phase !in ['activate', 'complete'])
	assert !os.exists(directory + '/generations/.stage-3') && !os.exists(directory + '/generations/3')
}

fn test_transfer_monitor_reports_partial_failure_and_reaps_oversized_child() {
	work := progress_workspace('monitor')!
	defer { os.unsetenv('VINIX_PACKAGE_PROGRESS_LOG'); os.rmdir_all(work) or {} }
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	mut compiler := os.new_process(v)
	compiler.set_args(['-gc', 'none', '-no-skip-unused', '-o', work + '/transfer', 'tests/packages/transfer-fixture.v'])
	compiler.wait()
	assert compiler.code == 0
	compiler.close()
	for status in [0, 7] {
		os.write_file(work + '/events', '')!
		mut child := os.new_process(work + '/transfer')
		child.set_args([work + '/payload', '4', status.str()])
		child.run()
		mut failed := false
		monitor_transfer(mut child, work + '/payload', 512 * 1024,
			pkgprotocol.Progress{ phase: 'download', package: 'app', path: 'bin/app', total: 512 * 1024 }, progress_record) or { failed = true }
		assert failed == (status != 0) && !child.is_alive()
		assert os.file_size(work + '/payload') == 256 * 1024
		events := progress_events(work + '/events')!
		assert events.len >= 2 && events.last().current == 256 * 1024
		assert events.all(it.phase == 'download' && it.current <= it.total)
		child.close()
	}
	os.rm(work + '/payload')!
	mut child := os.new_process(work + '/transfer')
	child.set_args([work + '/payload', '64', '0'])
	child.run()
	mut refused := false
	monitor_transfer(mut child, work + '/payload', 64 * 1024,
		pkgprotocol.Progress{ phase: 'download', package: 'app', path: 'bin/app', total: 64 * 1024 }, progress_record) or { refused = err.msg().contains('size limit') }
	assert refused && !child.is_alive() && !os.exists(work + '/payload')
	child.close()
}
