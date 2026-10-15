// SPDX-License-Identifier: GPL-2.0-or-later
module vmcore

import devcore
import json2
import os
import sourcecommand

struct Snapshot {
	schema      int = 1
	name        string
	vars_sha256 string
}

struct DiskSnapshot {
	id   string
	name string
}

struct SnapshotInventory {
	format    string
	snapshots []DiskSnapshot
}

// qcow2 restore tries an internal ID before a name. Resolve the user's exact
// name first so a numeric name cannot select another snapshot's disk state.
fn snapshot_restore_id(text string, name string) !string {
	inventory := json2.decode[SnapshotInventory](text)!
	if inventory.format != 'qcow2' { return error('snapshot inventory must describe a qcow2 image') }
	mut id := ''
	mut matches := 0
	for entry in inventory.snapshots {
		if entry.name == name { id = entry.id; matches++ }
	}
	if matches == 0 { return error('snapshot name not found in disk image: ${name}') }
	if matches != 1 { return error('snapshot name is ambiguous in disk image: ${name}') }
	if id == '' || id.contains('\x00') { return error('invalid snapshot ID in disk image') }
	if inventory.snapshots.filter(it.id == id).len != 1 {
		return error('snapshot ID is ambiguous in disk image')
	}
	return id
}

fn inspect_restore_id(config Config, state string, name string) !string {
	result := sourcecommand.capture([config.qemu_img.path, 'info', '-f', 'qcow2',
		'--output=json', state + '/disk.qcow2'], devcore.environment(0), 30,
		1024 * 1024, unsafe { nil })!
	os.write_file(state + '/snapshot-info.log', result.stderr)!
	if result.status != 0 { return error('cannot inspect disk snapshots; see snapshot-info.log') }
	os.write_file(state + '/snapshot-info.json', result.stdout)!
	return snapshot_restore_id(result.stdout, name)
}

pub fn snapshot(action string, path string, name string) ! {
	if name == '' || name.len > 64 || !name.bytes().all(it.is_alnum() || it in [`-`, `_`]) {
		return error('snapshot name must contain only letters, digits, dash or underscore')
	}
	if action !in ['snapshot-create', 'snapshot-restore', 'snapshot-delete'] {
		return error('unknown snapshot action')
	}
	state, config := load(path)!
	devcore.verify(config.qemu_img)!
	mut guard := lease(state)!
	defer { guard.release() }
	ensure_stopped(state)!
	if os.exists(state + '/snapshot.pending.json') {
		return error('incomplete snapshot operation requires recovery')
	}
	manifest := state + '/snapshots/' + name + '.json'
	vars := state + '/snapshots/' + name + '.fd'
	mut disk_selector := name
	flag := match action {
		'snapshot-create' { '-c' }
		'snapshot-restore' { '-a' }
		else { '-d' }
	}
	if action == 'snapshot-create' {
		if os.exists(manifest) || os.exists(vars) {
			return error('snapshot already exists or is incomplete')
		}
		os.cp(state + '/vars.fd', vars)!
	} else {
		saved := json2.decode[Snapshot](os.read_file(manifest)!, strict: true)!
		if saved.schema != 1 || saved.name != name { return error('invalid snapshot receipt') }
		devcore.verify(devcore.Pin{vars, saved.vars_sha256})!
		if action == 'snapshot-restore' {
			// Inspect under the existing offline lease, before copying variables
			// or publishing an in-flight receipt. Old sidecars remain readable.
			disk_selector = inspect_restore_id(config, state, name)!
			os.cp(vars, state + '/vars.restore')!
		}
	}
	os.write_file(state + '/snapshot.pending.json', json2.encode({
		'action': action
		'name':   name
	}) + '\n')!
	status := devcore.run([config.qemu_img.path, 'snapshot', '-f', 'qcow2', flag, disk_selector, state + '/disk.qcow2'],
		state, devcore.environment(0), 300, state + '/snapshot.log')!
	if status != 0 {
		if action == 'snapshot-create' { os.rm(vars) or {} }
		return error('snapshot operation failed; see snapshot.log')
	}
	match action {
		'snapshot-create' {
			os.write_file(manifest, json2.encode(Snapshot{ name: name, vars_sha256: devcore.file_hash(vars)! }) + '\n')!
		}
		'snapshot-restore' {
			os.rename(state + '/vars.restore', state + '/vars.fd')!
		}
		else {
			os.rm(manifest)!
			os.rm(vars)!
		}
	}
	os.rm(state + '/snapshot.pending.json')!
}
