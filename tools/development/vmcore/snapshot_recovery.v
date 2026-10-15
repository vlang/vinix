// SPDX-License-Identifier: GPL-2.0-or-later
module vmcore

import devcore
import json2
import os

struct SnapshotPending {
	schema   int = 1
	action   string
	snapshot Snapshot
}

// Rename publishes a complete record across process interruption. This does
// not make the disk, variable image and journal one power-loss transaction.
fn write_snapshot_record(path string, text string) ! {
	os.write_file(path + '.new', text)!
	os.chmod(path + '.new', 0o600)!
	os.rename(path + '.new', path)!
}

fn write_snapshot_pending(state string, pending SnapshotPending) ! {
	write_snapshot_record(state + '/snapshot.pending.json', json2.encode(pending) + '\n')!
}

fn run_snapshot(config Config, state string, action string, selector string, log string) ! {
	flag := match action {
		'snapshot-create' { '-c' }
		'snapshot-restore' { '-a' }
		else { '-d' }
	}
	status := devcore.run([config.qemu_img.path, 'snapshot', '-f', 'qcow2', flag, selector,
		state + '/disk.qcow2'], state, devcore.environment(0), 300, state + '/' + log)!
	if status != 0 {
		// A nonzero exit cannot establish whether the backend changed the
		// image. Preserve the journal and every saved variable image.
		return error('snapshot operation failed; see ${log}')
	}
}

// Existing sidecars must agree before recovery overwrites or removes anything.
// A legacy manifest may lack the identity now recorded by the pending operation.
fn verify_snapshot_manifest(state string, saved Snapshot, required bool) ! {
	path := state + '/snapshots/' + saved.name + '.json'
	if !os.exists(path) && !required { return }
	existing := json2.decode[Snapshot](os.read_file(path)!, strict: true)!
	validate_snapshot_receipt(existing, saved.name)!
	if existing.vars_sha256 != saved.vars_sha256
		|| existing.disk_identity != '' && existing.disk_identity != saved.disk_identity {
		return error('snapshot manifest changed; recovery refused')
	}
}

fn finish_snapshot_create(state string, pending SnapshotPending) ! {
	saved := pending.snapshot
	devcore.verify(devcore.Pin{state + '/snapshots/' + saved.name + '.fd', saved.vars_sha256})!
	verify_snapshot_manifest(state, saved, false)!
	write_snapshot_record(state + '/snapshots/' + saved.name + '.json', json2.encode(saved) + '\n')!
}

fn finish_snapshot_restore(state string, saved Snapshot) ! {
	devcore.verify(devcore.Pin{state + '/vars.restore', saved.vars_sha256})!
	os.rename(state + '/vars.restore', state + '/vars.fd')!
}

fn verify_snapshot_delete(state string, saved Snapshot) ! {
	verify_snapshot_manifest(state, saved, false)!
	vars := state + '/snapshots/' + saved.name + '.fd'
	if os.exists(vars) { devcore.verify(devcore.Pin{vars, saved.vars_sha256})! }
}

fn confirm_snapshot_deleted(config Config, state string, name string) ! {
	if snapshot_inventory(inspect_snapshots(config, state)!)!.snapshots.any(it.name == name) {
		return error('snapshot still exists after deletion; recovery required')
	}
}

fn finish_snapshot_delete(state string, saved Snapshot) ! {
	verify_snapshot_delete(state, saved)!
	for suffix in ['.json', '.fd'] {
		path := state + '/snapshots/' + saved.name + suffix
		if os.exists(path) { os.rm(path)! }
	}
}

fn check_snapshot_image(config Config, state string) ! {
	// Interrupted qcow2 metadata updates can require repair. Check without
	// -r: recovery must not choose a repair policy on the account's behalf.
	status := devcore.run([config.qemu_img.path, 'check', '-f', 'qcow2', '--output=json',
		state + '/disk.qcow2'], state, devcore.environment(0), 300, state + '/snapshot-check.log')!
	if status != 0 { return error('snapshot image consistency check failed; see snapshot-check.log') }
}

pub fn snapshot_recover(path string) ! {
	state, config := load(path)!
	devcore.verify(config.qemu_img)!
	mut guard := lease(state)!
	defer { guard.release() }
	ensure_stopped(state)!
	marker := state + '/snapshot.pending.json'
	pending := json2.decode[SnapshotPending](os.read_file(marker)!, strict: true)!
	if pending.schema != 1 || pending.action !in ['snapshot-create', 'snapshot-restore', 'snapshot-delete'] {
		return error('unsupported snapshot journal; manual recovery required')
	}
	saved := pending.snapshot
	validate_snapshot_receipt(saved, saved.name)!
	if pending.action != 'snapshot-create' && saved.disk_identity == '' {
		return error('snapshot journal has no backend identity; manual recovery required')
	}
	check_snapshot_image(config, state)!
	inventory_text := inspect_snapshots(config, state)!
	inventory := snapshot_inventory(inventory_text)!
	exists := inventory.snapshots.any(it.name == saved.name)
	if pending.action == 'snapshot-create' && saved.disk_identity == '' {
		if exists {
			return error('created snapshot identity was not recorded; manual recovery required')
		}
		// No backend was created and no manifest could have been published.
		// Abandon this preparation only after checking the preserved variables.
		if os.exists(state + '/snapshots/' + saved.name + '.json') {
			return error('unexpected snapshot manifest; recovery refused')
		}
		vars := state + '/snapshots/' + saved.name + '.fd'
		if os.exists(vars) {
			devcore.verify(devcore.Pin{vars, saved.vars_sha256})!
			os.rm(vars)!
		}
	} else {
		mut target := DiskSnapshot{}
		if exists {
			target = snapshot_target(inventory_text, saved.name)!
			if disk_snapshot_identity(target)! != saved.disk_identity {
				return error('snapshot identity changed in disk image: ${saved.name}')
			}
		} else if pending.action != 'snapshot-delete' {
			return error('snapshot name not found in disk image: ${saved.name}')
		}
		match pending.action {
			'snapshot-create' { finish_snapshot_create(state, pending)! }
			'snapshot-restore' {
				verify_snapshot_manifest(state, saved, true)!
				vars := state + '/snapshots/' + saved.name + '.fd'
				devcore.verify(devcore.Pin{vars, saved.vars_sha256})!
				os.cp(vars, state + '/vars.restore')!
				// Reapplying the verified target also repairs an interruption
				// between applying the disk and replacing vars.fd.
				run_snapshot(config, state, pending.action, target.id, 'snapshot-recover.log')!
				finish_snapshot_restore(state, saved)!
			}
			else {
				verify_snapshot_delete(state, saved)!
				if exists {
					run_snapshot(config, state, pending.action, saved.name, 'snapshot-recover.log')!
					confirm_snapshot_deleted(config, state, saved.name)!
				}
				finish_snapshot_delete(state, saved)!
			}
		}
	}
	os.rm(marker)!
}
