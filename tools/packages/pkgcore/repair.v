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
		mut damaged := !installed_namespace_valid(directory, current.generation, target.package)
		for payload in target.package.files {
			if damaged { break }
			path := '${directory}/generations/${number}/apps/${target.package.id}/${payload.path}'
			valid := verified_installed_file(path, payload)
			unsafe { path.free() }
			if !valid { damaged = true; break }
		}
		generation := '${directory}/generations/${number}'
		if damaged || !verified_registration(generation, target.package) { repairs << target.package.id.clone() }
		unsafe { generation.free() }
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
