// SPDX-License-Identifier: GPL-2.0-or-later
module vmcore

import devcore
import json2
import os

struct Snapshot {
	schema      int = 1
	name        string
	vars_sha256 string
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
		if action == 'snapshot-restore' { os.cp(vars, state + '/vars.restore')! }
	}
	os.write_file(state + '/snapshot.pending.json', json2.encode({
		'action': action
		'name':   name
	}) + '\n')!
	status := devcore.run([config.qemu_img.path, 'snapshot', flag, name, state + '/disk.qcow2'],
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
