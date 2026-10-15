// SPDX-License-Identifier: GPL-2.0-or-later
module vmcore

import devcore
import json2
import os
import sourcecommand

fn recovery_command(args []string) ! {
	result := sourcecommand.capture(args, os.environ(), 120, 65536, unsafe { nil })!
	assert result.status == 0, result.stdout + result.stderr
}

fn recovery_pin(path string) !devcore.Pin {
	return devcore.Pin{os.real_path(path), devcore.file_hash(path)!}
}

fn recovery_fixture(root string, image_tool string) !string {
	devcore.fresh_directory(root)!
	os.write_file(root + '/image-tool.path', image_tool)!
	recovery_command([@VEXE, '-gc', 'none', '-cc', 'cc', '-o', root + '/image-tool',
		os.dir(os.dir(@FILE)) + '/vmfixture/image.v'])!
	os.write_file(root + '/raw.img', '\x00'.repeat(1024 * 1024))!
	os.write_file(root + '/code.fd', 'firmware-code-fixture')!
	os.write_file(root + '/vars.fd', 'paired-variables')!
	config := Config{
		architecture: 'aarch64'
		qemu: recovery_pin(image_tool)!
		qemu_img: recovery_pin(root + '/image-tool')!
		disk: recovery_pin(root + '/raw.img')!
		firmware_code: recovery_pin(root + '/code.fd')!
		firmware_vars: recovery_pin(root + '/vars.fd')!
	}
	state := root + '/vm'
	initialise(json2.encode(config), state)!
	return state
}

fn recovery_failed_snapshot(action string, state string, name string) ! {
	mut refused := false
	snapshot(action, state, name) or {
		refused = true
		assert err.msg().contains('snapshot operation failed'), err.msg()
	}
	assert refused
	assert os.exists(state + '/snapshot.pending.json')
}

fn recovery_disk(image_tool string, state string, destination string, pattern u8) ! {
	recovery_command([image_tool, 'convert', '-f', 'qcow2', '-O', 'raw',
		state + '/disk.qcow2', destination])!
	bytes := os.read_bytes(destination)!
	assert bytes[..4096].all(it == pattern)
	assert bytes[4096..].all(it == 0)
}

fn recovery_refused(state string, reason string) ! {
	disk := devcore.file_hash(state + '/disk.qcow2')!
	vars := devcore.file_hash(state + '/vars.fd')!
	journal := os.read_file(state + '/snapshot.pending.json')!
	mut refused := false
	snapshot_recover(state) or {
		refused = true
		assert err.msg().contains(reason), err.msg()
	}
	assert refused, 'expected refusal: ${reason} in ${state}'
	assert devcore.file_hash(state + '/disk.qcow2')! == disk
	assert devcore.file_hash(state + '/vars.fd')! == vars
	assert os.read_file(state + '/snapshot.pending.json')! == journal
}

fn test_failed_snapshot_create_keeps_firmware_even_when_the_backend_completed() {
	image_tool := os.find_abs_path_of_executable('qemu-img') or {
		println('SKIP: snapshot recovery requires qemu-img')
		return
	}
	root := '/tmp/vinix-vm-recover-files-${os.getpid()}'
	state := recovery_fixture(root, image_tool)!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/image-tool.fault', 'after:-c')!
	recovery_failed_snapshot('snapshot-create', state, 'interrupted')!
	_, config := load(state)!
	assert snapshot_target(inspect_snapshots(config, state)!, 'interrupted')!.id != ''
	assert os.read_file(state + '/snapshots/interrupted.fd')! == 'paired-variables',
		'failure cannot establish that qemu-img left the disk unchanged; keep the firmware copy'
	assert os.exists(state + '/snapshot.pending.json')
	recovery_refused(state, 'identity was not recorded')!
	assert os.read_file(state + '/snapshots/interrupted.fd')! == 'paired-variables'
}

fn test_snapshot_recovery_replays_restore_and_finishes_partial_deletion() {
	image_tool := os.find_abs_path_of_executable('qemu-img') or {
		println('SKIP: snapshot recovery requires qemu-img and qemu-io')
		return
	}
	io_tool := os.find_abs_path_of_executable('qemu-io')!
	root := '/tmp/vinix-vm-recover-pair-${os.getpid()}'
	state := recovery_fixture(root, image_tool)!
	defer { os.rmdir_all(root) or {} }
	snapshot('snapshot-create', state, 'anchor')!
	recovery_command([io_tool, '-f', 'qcow2', '-c', 'write -P 0x56 0 4096', state + '/disk.qcow2'])!
	os.write_file(state + '/vars.fd', 'numeric-variables')!
	snapshot('snapshot-create', state, '1')!
	// A legacy completed receipt is still usable, but the pending operation
	// must acquire a backend identity before an interrupted command can recover.
	os.write_file(state + '/snapshots/1.json', json2.encode(Snapshot{
		name: '1', vars_sha256: devcore.file_hash(state + '/snapshots/1.fd')!
	}))!
	for phase in ['before', 'after'] {
		recovery_command([io_tool, '-f', 'qcow2', '-c', 'write -P 0x78 0 4096', state + '/disk.qcow2'])!
		os.write_file(state + '/vars.fd', 'current-variables')!
		os.write_file(root + '/image-tool.fault', phase + ':-a')!
		recovery_failed_snapshot('snapshot-restore', state, '1')!
		assert os.read_file(state + '/vars.fd')! == 'current-variables'
		recovery_disk(image_tool, state, root + '/${phase}-failure.raw', if phase == 'before' { u8(0x78) } else { u8(0x56) })!
		// A second failure leaves the same intent recoverable, including when
		// the backend succeeded but the manager did not publish the variables.
		os.write_file(root + '/image-tool.fault', 'after:-a')!
		mut refused := false
		snapshot_recover(state) or { refused = true; assert err.msg().contains('snapshot operation failed') }
		assert refused
		assert os.read_file(state + '/vars.fd')! == 'current-variables'
		assert os.exists(state + '/snapshot.pending.json')
		snapshot_recover(state)!
		recovery_disk(image_tool, state, root + '/${phase}-recovered.raw', 0x56)!
		assert os.read_file(state + '/vars.fd')! == 'numeric-variables'
		assert !os.exists(state + '/snapshot.pending.json') && !os.exists(state + '/vars.restore')
	}
	// Deletion can finish after either an unapplied command or a successful
	// backend deletion whose exit status was lost. Keep numeric-name safety.
	for phase in ['before', 'after'] {
		os.write_file(root + '/image-tool.fault', phase + ':-d')!
		recovery_failed_snapshot('snapshot-delete', state, '1')!
		journal := os.read_file(state + '/snapshot.pending.json')!
		assert os.read_file(state + '/snapshots/1.fd')! == 'numeric-variables'
		if phase == 'after' {
			// Simulate interruption between removing the two sidecars.
			os.rm(state + '/snapshots/1.json')!
		}
		snapshot_recover(state)!
		assert !os.exists(state + '/snapshots/1.json') && !os.exists(state + '/snapshots/1.fd')
		assert !os.exists(state + '/snapshot.pending.json')
		// Interruption after both sidecars disappeared is also recoverable.
		os.write_file(state + '/snapshot.pending.json', journal)!
		snapshot_recover(state)!
		assert !os.exists(state + '/snapshot.pending.json')
		snapshot('snapshot-restore', state, 'anchor')!
		recovery_disk(image_tool, state, root + '/${phase}-anchor.raw', 0)!
		recovery_command([io_tool, '-f', 'qcow2', '-c', 'write -P 0x56 0 4096', state + '/disk.qcow2'])!
		os.write_file(state + '/vars.fd', 'numeric-variables')!
		snapshot('snapshot-create', state, '1')!
	}
}

fn test_snapshot_recovery_abandons_uncreated_preparation_and_finishes_identified_creation() {
	image_tool := os.find_abs_path_of_executable('qemu-img') or {
		println('SKIP: snapshot recovery requires qemu-img')
		return
	}
	root := '/tmp/vinix-vm-recover-create-${os.getpid()}'
	state := recovery_fixture(root, image_tool)!
	defer { os.rmdir_all(root) or {} }
	for removed in [false, true] {
		os.write_file(root + '/image-tool.fault', 'before:-c')!
		recovery_failed_snapshot('snapshot-create', state, 'uncreated')!
		if removed { os.rm(state + '/snapshots/uncreated.fd')! }
		disk := devcore.file_hash(state + '/disk.qcow2')!
		snapshot_recover(state)!
		assert devcore.file_hash(state + '/disk.qcow2')! == disk
		assert os.read_file(state + '/vars.fd')! == 'paired-variables'
		assert !os.exists(state + '/snapshots/uncreated.fd') && !os.exists(state + '/snapshots/uncreated.json')
		assert !os.exists(state + '/snapshot.pending.json')
	}
	// Prevent only final manifest publication, after a real successful create
	// and after the pending journal has acquired the backend identity.
	os.mkdir(state + '/snapshots/identified.json.new')!
	mut refused := false
	snapshot('snapshot-create', state, 'identified') or { refused = true }
	assert refused
	os.rmdir(state + '/snapshots/identified.json.new')!
	pending := json2.decode[SnapshotPending](os.read_file(state + '/snapshot.pending.json')!, strict: true)!
	assert pending.snapshot.disk_identity.len == 64
	recovery_command([@VEXE, '-enable-globals', '-gc', 'none', '-cc', 'cc', '-o', root + '/vinix-vm',
		os.dir(os.dir(@FILE)) + '/vm.v'])!
	// Use a separate process: native record locks may be process scoped.
	journal := os.read_file(state + '/snapshot.pending.json')!
	mut guard := lease(state)!
	locked := sourcecommand.capture([root + '/vinix-vm', 'snapshot-recover', state], os.environ(),
		30, 65536, unsafe { nil })!
	assert locked.status != 0 && locked.stderr.contains('lock'), locked.stderr
	assert os.read_file(state + '/snapshot.pending.json')! == journal
	guard.release()
	recovery_command([root + '/vinix-vm', 'snapshot-recover', state])!
	assert !os.exists(state + '/snapshot.pending.json')
	assert os.read_file(state + '/snapshots/identified.fd')! == 'paired-variables'
	os.write_file(state + '/vars.fd', 'current-variables')!
	snapshot('snapshot-restore', state, 'identified')!
	assert os.read_file(state + '/vars.fd')! == 'paired-variables'
	// Replaying a fully published create is harmless if interruption happened
	// immediately before removing its pending marker.
	write_snapshot_pending(state, pending)!
	snapshot_recover(state)!
	assert !os.exists(state + '/snapshot.pending.json')
}

fn test_snapshot_recovery_refuses_changed_identities_variables_manifests_and_legacy_journals() {
	image_tool := os.find_abs_path_of_executable('qemu-img') or {
		println('SKIP: snapshot recovery requires qemu-img')
		return
	}
	root := '/tmp/vinix-vm-recover-refuse-${os.getpid()}'
	state := recovery_fixture(root, image_tool)!
	defer { os.rmdir_all(root) or {} }
	for action in ['snapshot-restore', 'snapshot-delete'] {
		name := if action == 'snapshot-restore' { 'restore' } else { 'delete' }
		snapshot('snapshot-create', state, name)!
		manifest_path := state + '/snapshots/' + name + '.json'
		vars_path := state + '/snapshots/' + name + '.fd'
		manifest := os.read_file(manifest_path)!
		os.write_file(root + '/image-tool.fault', if action == 'snapshot-restore' { 'before:-a' } else { 'before:-d' })!
		recovery_failed_snapshot(action, state, name)!
		os.write_file(root + '/image-tool.fault', 'before:check')!
		recovery_refused(state, 'consistency check failed')!
		// Account ownership and the executable pin remain mandatory during
		// recovery; neither may be bypassed by an otherwise valid journal.
		os.chmod(state, 0o755)!
		recovery_refused(state, 'mode 0700')!
		os.chmod(state, 0o700)!
		config_text := os.read_file(state + '/config.json')!
		config := json2.decode[Config](config_text, strict: true)!
		os.write_file(state + '/config.json', json2.encode(Config{
			...config, qemu_img: devcore.Pin{config.qemu_img.path, '0'.repeat(64)}
		}))!
		recovery_refused(state, 'input changed')!
		os.write_file(state + '/config.json', config_text)!
		os.write_file(vars_path, 'changed-saved-variables')!
		recovery_refused(state, 'input changed')!
		assert os.read_file(vars_path)! == 'changed-saved-variables'
		os.write_file(vars_path, 'paired-variables')!
		mut changed := json2.decode[Snapshot](manifest, strict: true)!
		changed = Snapshot{...changed, disk_identity: '0'.repeat(64)}
		os.write_file(manifest_path, json2.encode(changed))!
		recovery_refused(state, 'manifest changed')!
		assert os.read_file(manifest_path)! == json2.encode(changed)
		os.write_file(manifest_path, manifest)!
		recovery_command([image_tool, 'snapshot', '-c', name, state + '/disk.qcow2'])!
		recovery_refused(state, 'ambiguous')!
		assert os.read_file(manifest_path)! == manifest
		assert os.read_file(vars_path)! == 'paired-variables'
		// This fixture deliberately leaves the duplicate untouched. Use another
		// name for the next refusal case without resolving external ambiguity.
		os.rm(state + '/snapshot.pending.json')!
	}
	// A separate, valid pending operation proves identity drift is rejected.
	snapshot('snapshot-create', state, 'drift')!
	os.write_file(root + '/image-tool.fault', 'before:-a')!
	recovery_failed_snapshot('snapshot-restore', state, 'drift')!
	recovery_command([image_tool, 'snapshot', '-d', 'drift', state + '/disk.qcow2'])!
	recovery_refused(state, 'not found')!
	recovery_command([image_tool, 'snapshot', '-c', 'drift', state + '/disk.qcow2'])!
	recovery_refused(state, 'identity changed')!
	for text in ['{}', '{"action":"snapshot-create","name":"legacy"}', 'not JSON',
		'{"schema":1,"action":"snapshot-delete","snapshot":{"name":"../vars","vars_sha256":"' + '0'.repeat(64) + '"}}'] {
		os.write_file(state + '/snapshot.pending.json', text)!
		recovery_refused(state, '')!
	}
	// An unreadable image also fails the real check without removing the
	// journal or attempting repair, independent of the delegate's injection.
	pending := SnapshotPending{action: 'snapshot-restore', snapshot: json2.decode[Snapshot](
		os.read_file(state + '/snapshots/drift.json')!, strict: true)!}
	write_snapshot_pending(state, pending)!
	os.write_file(state + '/disk.qcow2', 'corrupt-qcow2-fixture')!
	recovery_refused(state, 'consistency check failed')!
}
