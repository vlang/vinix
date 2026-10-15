// SPDX-License-Identifier: GPL-2.0-or-later
module vmcore

import devcore
import json2
import os
import sourcecommand

fn snapshot_test_command(args []string) ! {
	result := sourcecommand.capture(args, devcore.environment(0), 30, 65536, unsafe { nil })!
	assert result.status == 0, result.stdout + result.stderr
}

fn snapshot_test_pin(path string) !devcore.Pin {
	return devcore.Pin{os.real_path(path), devcore.file_hash(path)!}
}

fn snapshot_test_state(root string, image_tool string) !string {
	devcore.fresh_directory(root)!
	os.write_file(root + '/raw.img', '\x00'.repeat(1024 * 1024))!
	os.write_file(root + '/code.fd', 'firmware-code-fixture')!
	os.write_file(root + '/vars.fd', 'variables-anchor')!
	config := Config{
		architecture:  'aarch64'
		qemu:          snapshot_test_pin(image_tool)!
		qemu_img:      snapshot_test_pin(image_tool)!
		disk:          snapshot_test_pin(root + '/raw.img')!
		firmware_code: snapshot_test_pin(root + '/code.fd')!
		firmware_vars: snapshot_test_pin(root + '/vars.fd')!
	}
	state := root + '/vm'
	initialise(json2.encode(config), state)!
	return state
}

fn snapshot_test_disk(image_tool string, state string, destination string, value u8) ! {
	snapshot_test_command([image_tool, 'convert', '-f', 'qcow2', '-O', 'raw',
		state + '/disk.qcow2', destination])!
	bytes := os.read_bytes(destination)!
	assert bytes.len == 1024 * 1024
	assert bytes[..4096].all(it == value), 'restored disk must match the selected snapshot, not another snapshot ID'
	assert bytes[4096..].all(it == 0)
}

fn test_snapshot_inventory_requires_an_unambiguous_exact_name_and_id() {
	assert snapshot_target('{"format":"qcow2","snapshots":[{"id":"1","name":"anchor"},{"id":"2","name":"1"}]}', '1')!.id == '2'
	for text in [
		'{"format":"raw","snapshots":[{"id":"1","name":"target"}]}',
		'{"format":"qcow2","snapshots":[{"id":"target","name":"other"}]}',
		'{"format":"qcow2","snapshots":[{"id":"","name":"target"}]}',
		'{"format":"qcow2","snapshots":[{"id":"1\\u0000suffix","name":"target"}]}',
		'{"format":"qcow2","snapshots":[{"id":"1","name":"target"},{"id":"1","name":"other"}]}',
		'{"format":"qcow2","snapshots":[{"id":"1","name":"target"},{"id":"2","name":"target"}]}',
		'not JSON',
	] {
		mut refused := false
		snapshot_target(text, 'target') or { refused = true }
		assert refused
	}
}

fn test_numeric_snapshot_names_restore_the_matching_disk_and_firmware() {
	image_tool := os.find_abs_path_of_executable('qemu-img') or {
		println('SKIP: snapshot identity requires qemu-img and qemu-io')
		return
	}
	io_tool := os.find_abs_path_of_executable('qemu-io')!
	root := '/tmp/vinix-vm-snapshot-identity-${os.getpid()}'
	state := snapshot_test_state(root, image_tool)!
	defer { os.rmdir_all(root) or {} }
	snapshot('snapshot-create', state, 'anchor')!
	// anchor has ID 1. The name "1" gets a different ID, and "2" collides
	// with that snapshot's ID too. Disk and firmware bytes distinguish all three.
	for kind in 1 .. 3 {
		pattern := if kind == 1 { '0x56' } else { '0x78' }
		snapshot_test_command([io_tool, '-f', 'qcow2', '-c', 'write -P ${pattern} 0 4096',
			state + '/disk.qcow2'])!
		os.write_file(state + '/vars.fd', 'variables-${kind}')!
		snapshot('snapshot-create', state, kind.str())!
	}
	for name in ['1', '2', 'anchor'] {
		os.write_file(state + '/vars.fd', 'variables-current')!
		snapshot('snapshot-restore', state, name)!
		assert os.read_file(state + '/vars.fd')! == if name == 'anchor' { 'variables-anchor' } else { 'variables-${name}' }
		snapshot_test_disk(image_tool, state, root + '/restored-${name}.raw', match name {
			'1' { u8(0x56) }
			'2' { u8(0x78) }
			else { u8(0) }
		})!
		assert !os.exists(state + '/snapshot.pending.json') && !os.exists(state + '/vars.restore')
	}
	// Name lookup for deletion retains its existing behavior.
	snapshot('snapshot-delete', state, '1')!
	snapshot('snapshot-restore', state, '2')!
	snapshot_test_disk(image_tool, state, root + '/after-delete.raw', 0x78)!
}

fn test_missing_or_duplicate_snapshot_names_refuse_before_changing_disk_or_variables() {
	image_tool := os.find_abs_path_of_executable('qemu-img') or {
		println('SKIP: snapshot identity requires qemu-img')
		return
	}
	root := '/tmp/vinix-vm-snapshot-refusal-${os.getpid()}'
	state := snapshot_test_state(root, image_tool)!
	defer { os.rmdir_all(root) or {} }
	snapshot('snapshot-create', state, 'anchor')!
	// A retained sidecar must not fall back to the unrelated backend ID 1.
	os.cp(state + '/snapshots/anchor.fd', state + '/snapshots/1.fd')!
	os.write_file(state + '/snapshots/1.json', json2.encode(Snapshot{
		name: '1'
		vars_sha256: devcore.file_hash(state + '/snapshots/1.fd')!
	}))!
	snapshot('snapshot-create', state, 'duplicate')!
	snapshot_test_command([image_tool, 'snapshot', '-c', 'duplicate', state + '/disk.qcow2'])!
	os.write_file(state + '/vars.fd', 'current-variables-must-survive')!
	disk_hash := devcore.file_hash(state + '/disk.qcow2')!
	for name in ['1', 'duplicate'] {
		mut refused := false
		snapshot('snapshot-restore', state, name) or {
			refused = true
			assert err.msg().contains(if name == '1' { 'not found' } else { 'ambiguous' })
		}
		assert refused, 'missing or ambiguous names must refuse restoration'
		assert devcore.file_hash(state + '/disk.qcow2')! == disk_hash
		assert os.read_file(state + '/vars.fd')! == 'current-variables-must-survive'
		assert !os.exists(state + '/snapshot.pending.json') && !os.exists(state + '/vars.restore')
	}
	// A failed read-only inventory command also refuses before preparation.
	os.write_file(state + '/disk.qcow2', 'invalid-qcow2-fixture')!
	mut refused := false
	snapshot('snapshot-restore', state, 'anchor') or {
		refused = true
		assert err.msg().contains('cannot inspect disk snapshots')
	}
	assert refused
	assert os.read_file(state + '/disk.qcow2')! == 'invalid-qcow2-fixture'
	assert os.read_file(state + '/vars.fd')! == 'current-variables-must-survive'
	assert !os.exists(state + '/snapshot.pending.json') && !os.exists(state + '/vars.restore')
	assert os.read_file(state + '/snapshot-info.log')!.len > 0
}

fn test_snapshot_creation_refuses_an_existing_backend_name_without_sidecars() {
	image_tool := os.find_abs_path_of_executable('qemu-img') or {
		println('SKIP: snapshot creation identity requires qemu-img')
		return
	}
	root := '/tmp/vinix-vm-snapshot-create-${os.getpid()}'
	state := snapshot_test_state(root, image_tool)!
	defer { os.rmdir_all(root) or {} }
	snapshot_test_command([image_tool, 'snapshot', '-c', 'orphan', state + '/disk.qcow2'])!
	disk_hash := devcore.file_hash(state + '/disk.qcow2')!
	mut refused := false
	snapshot('snapshot-create', state, 'orphan') or {
		refused = true
		assert err.msg().contains('already exists')
	}
	assert refused, 'a backend snapshot name must not be duplicated when its sidecars are absent'
	assert devcore.file_hash(state + '/disk.qcow2')! == disk_hash
	assert os.read_file(state + '/vars.fd')! == 'variables-anchor'
	assert !os.exists(state + '/snapshots/orphan.json') && !os.exists(state + '/snapshots/orphan.fd')
	assert !os.exists(state + '/snapshot.pending.json')
}

fn test_snapshot_deletion_refuses_an_ambiguous_backend_name() {
	image_tool := os.find_abs_path_of_executable('qemu-img') or {
		println('SKIP: snapshot deletion identity requires qemu-img')
		return
	}
	root := '/tmp/vinix-vm-snapshot-delete-${os.getpid()}'
	state := snapshot_test_state(root, image_tool)!
	defer { os.rmdir_all(root) or {} }
	snapshot('snapshot-create', state, 'duplicate')!
	snapshot_test_command([image_tool, 'snapshot', '-c', 'duplicate', state + '/disk.qcow2'])!
	disk_hash := devcore.file_hash(state + '/disk.qcow2')!
	manifest := os.read_file(state + '/snapshots/duplicate.json')!
	mut refused := false
	snapshot('snapshot-delete', state, 'duplicate') or {
		refused = true
		assert err.msg().contains('ambiguous')
	}
	assert refused, 'ambiguous deletion must preserve both backend snapshots and the sidecars'
	assert devcore.file_hash(state + '/disk.qcow2')! == disk_hash
	assert os.read_file(state + '/snapshots/duplicate.json')! == manifest
	assert os.read_file(state + '/snapshots/duplicate.fd')! == 'variables-anchor'
	assert !os.exists(state + '/snapshot.pending.json')
}

fn test_recreated_backend_snapshot_with_recycled_id_refuses_stale_sidecars() {
	image_tool := os.find_abs_path_of_executable('qemu-img') or {
		println('SKIP: snapshot binding requires qemu-img and qemu-io')
		return
	}
	io_tool := os.find_abs_path_of_executable('qemu-io')!
	root := '/tmp/vinix-vm-snapshot-binding-${os.getpid()}'
	state := snapshot_test_state(root, image_tool)!
	defer { os.rmdir_all(root) or {} }
	snapshot('snapshot-create', state, 'paired')!
	before := sourcecommand.capture([image_tool, 'info', '--output=json', state + '/disk.qcow2'],
		devcore.environment(0), 30, 65536, unsafe { nil })!
	assert before.status == 0
	before_info := json2.decode[SnapshotInventory](before.stdout)!
	snapshot_test_command([image_tool, 'snapshot', '-d', 'paired', state + '/disk.qcow2'])!
	snapshot_test_command([io_tool, '-f', 'qcow2', '-c', 'write -P 0x56 0 4096', state + '/disk.qcow2'])!
	snapshot_test_command([image_tool, 'snapshot', '-c', 'paired', state + '/disk.qcow2'])!
	after := sourcecommand.capture([image_tool, 'info', '--output=json', state + '/disk.qcow2'],
		devcore.environment(0), 30, 65536, unsafe { nil })!
	assert after.status == 0
	after_info := json2.decode[SnapshotInventory](after.stdout)!
	assert before_info.snapshots.len == 1 && after_info.snapshots.len == 1
	assert before_info.snapshots[0].id == after_info.snapshots[0].id, 'exercise actual qcow2 ID reuse'
	os.write_file(state + '/vars.fd', 'current-variables-must-survive')!
	disk_hash := devcore.file_hash(state + '/disk.qcow2')!
	manifest := os.read_file(state + '/snapshots/paired.json')!
	for action in ['snapshot-restore', 'snapshot-delete'] {
		mut refused := false
		snapshot(action, state, 'paired') or {
			refused = true
			assert err.msg().contains('identity changed')
		}
		assert refused, 'a recreated disk snapshot must not use a previous snapshot\'s firmware sidecar'
		assert devcore.file_hash(state + '/disk.qcow2')! == disk_hash
		assert os.read_file(state + '/vars.fd')! == 'current-variables-must-survive'
		assert os.read_file(state + '/snapshots/paired.json')! == manifest
		assert os.read_file(state + '/snapshots/paired.fd')! == 'variables-anchor'
		assert !os.exists(state + '/snapshot.pending.json') && !os.exists(state + '/vars.restore')
	}
}

fn test_legacy_snapshot_receipts_still_restore_an_exact_name() {
	image_tool := os.find_abs_path_of_executable('qemu-img') or {
		println('SKIP: legacy snapshot identity requires qemu-img')
		return
	}
	root := '/tmp/vinix-vm-snapshot-legacy-${os.getpid()}'
	state := snapshot_test_state(root, image_tool)!
	defer { os.rmdir_all(root) or {} }
	snapshot('snapshot-create', state, 'legacy')!
	hash := devcore.file_hash(state + '/snapshots/legacy.fd')!
	os.write_file(state + '/snapshots/legacy.json', '{"schema":1,"name":"legacy","vars_sha256":"${hash}"}\n')!
	os.write_file(state + '/vars.fd', 'changed-variables')!
	snapshot('snapshot-restore', state, 'legacy')!
	assert os.read_file(state + '/vars.fd')! == 'variables-anchor'
	snapshot_test_disk(image_tool, state, root + '/restored.raw', 0)!
}
