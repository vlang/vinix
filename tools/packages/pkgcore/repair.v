// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Only unchanged target manifests need an extra rewrite reason. Other target
// changes already stage fresh authenticated payloads. Removal and rollback keep
// their independent recovery/trust rules.
fn transaction_repairs(directory string, current State, plan Plan, operation string) []string {
	if current.generation == 0 || operation !in ['install', 'upgrade', 'deploy'] { return []string{} }
	mut positions := map[string]int{}
	defer { unsafe { positions.free() } }
	for index, installed in current.packages { positions[installed.package.id] = index }
	mut repairs := []string{cap: plan.packages.len}
	unsafe { repairs.flags |= .noslices }
	number := current.generation.str()
	defer { unsafe { number.free() } }
	for target in plan.packages {
		index := positions[target.package.id] or { continue }
		old := current.packages[index]
		if old.package != target.package || old.repository != target.repository || old.public_key != target.public_key { continue }
		for payload in target.package.files {
			path := '${directory}/generations/${number}/apps/${target.package.id}/${payload.path}'
			valid := verified_file(path, payload)
			unsafe { path.free() }
			if !valid { repairs << target.package.id.clone(); break }
		}
	}
	repairs.sort()
	return repairs
}

fn close_transaction_repairs(repairs []string) {
	unsafe {
		for id in repairs { id.free() }
		(&array(&repairs)).free()
	}
}
