// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

pub struct Plan {
pub:
	requested []string
	packages  []Installed
}

fn candidate_order(a &Installed, b &Installed) int {
	if a.package.id != b.package.id { return if a.package.id < b.package.id { -1 } else { 1 } }
	versions := compare_versions(a.package.version, b.package.version)
	if versions != 0 { return -versions }
	if a.package.architecture != b.package.architecture {
		if a.package.architecture == 'all' { return 1 }
		if b.package.architecture == 'all' { return -1 }
		return if a.package.architecture < b.package.architecture { -1 } else { 1 }
	}
	if a.repository != b.repository { return if a.repository < b.repository { -1 } else { 1 } }
	if a.public_key != b.public_key { return if a.public_key < b.public_key { -1 } else { 1 } }
	return 0
}

// Move the exact installed variant to the front of its sorted identity group.
// Rotate in place so every catalog candidate occurs once and the remaining
// version/architecture order stays intact. Appending preferred copies gives
// unrelated single-version packages artificial alternatives during backtracking.
fn prefer_installed(mut candidates []Installed, current State) {
	mut installed := map[string]int{}
	defer { unsafe { installed.free() } }
	for index, candidate in current.packages { installed[candidate.package.id] = index }
	mut first := 0
	for first < candidates.len {
		id := candidates[first].package.id
		mut end := first + 1
		for end < candidates.len && candidates[end].package.id == id { end++ }
		if index := installed[id] {
			previous := current.packages[index]
			for choice in first .. end {
				candidate := candidates[choice]
				if candidate.package != previous.package || candidate.repository != previous.repository
					|| candidate.public_key != previous.public_key { continue }
				for at := choice; at > first; at-- { candidates[at] = candidates[at - 1] }
				candidates[first] = candidate
				break
			}
		}
		first = end
	}
}

pub fn resolve(catalog Catalog, config Config, current State, requested []string, upgrade bool) !Plan {
	config.validate()!
	if requested.len > 4096 || catalog.packages.len > 32768 { return error('dependency resolution exceeds its input limits') }
	mut roots := requested.clone()
	mut accepted := false
	defer { if !accepted { unsafe { (&array(&roots)).free() } } }
	roots.sort()
	mut pending := []Dependency{}
	unsafe { pending.flags |= .noslices }
	defer { unsafe { (&array(&pending)).free() } }
	for i, id in roots {
		if !identifier(id) || (i > 0 && id == roots[i - 1]) {
			return error('invalid or duplicate requested package: ${id}')
		}
		pending << Dependency{ id: id }
	}
	mut owners := map[string]string{}
	defer { unsafe { owners.free() } }
	for installed in current.packages { owners[installed.package.id] = installed.repository }
	// A package's disappearance from one publisher is not permission for
	// another enrolled repository to replace its installed identity.
	mut candidates := catalog.packages.filter(it.package.id !in owners
		|| owners[it.package.id] == it.repository)
	defer { unsafe { (&array(&candidates)).free() } }
	candidates.sort_with_compare(candidate_order)
	if !upgrade {
		// Reuse installed packages only when their exact provenance is still
		// present in the authenticated catalog; revoked/removed versions cannot
		// bypass current repository policy.
		prefer_installed(mut candidates, current)
	}
	// The returned closure borrows candidate fields, never this search object.
	// Own it explicitly: the pinned compiler promotes the local to the heap.
	mut search := &Search{ config: config, candidates: candidates }
	defer { unsafe { search.diagnostic.free(); free(search) } }
	mut packages := search.solve(pending)!
	packages.sort(a.package.id < b.package.id)
	accepted = true
	return Plan{ requested: roots, packages: packages }
}

pub fn desired_roots(state State, operation string, names []string) ![]string {
	// Returned arrays own their storage and borrow ID strings, like Plan roots.
	mut roots := []string{}
	match operation {
		'install' {
			if names.len == 0 { return error('install requires package IDs') }
			roots = state.requested.clone()
			unsafe { roots.flags |= .noslices }
			for id in names {
				if id in roots { continue }
				pointer := unsafe { &id }
				unsafe { roots.push_many(pointer, 1) }
			}
		}
		'remove' {
			if names.len == 0 { return error('remove requires package IDs') }
			for id in names {
				if id !in state.requested {
					if blocker := removal_blocker(state, names, id) {
						return error('${id} is not explicitly installed; required by requested package ${blocker.root}; review removal of dependent applications first')
					}
					return error('${id} is not explicitly installed; remove its dependents instead')
				}
			}
			roots = state.requested.filter(it !in names)
		}
		'upgrade', 'deploy' {
			if operation == 'deploy' {
				roots = names.clone()
			} else if names.len != 0 {
				return error('upgrade updates the complete installed closure')
			} else { roots = state.requested.clone() }
		}
		else { return error('unknown package operation: ${operation}') }
	}
	return roots
}
