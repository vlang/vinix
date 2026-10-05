// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import katomic

pub fn dumpability(process &Process) u32 {
	return katomic.load(&process.dumpable)
}

pub fn set_dumpability(mut process Process, value u32) {
	katomic.store(mut &process.dumpable, value)
}

pub fn secure_loader_required(process &Process) bool {
	return process.uid != process.euid || process.gid != process.egid
}

pub fn dumpability_after_exec(mut process Process) {
	// Mixed real/effective credentials remain protected after exec. File
	// capabilities and set-ID execution must also select zero when added.
	set_dumpability(mut process, if secure_loader_required(process) { u32(0) } else { u32(1) })
}
