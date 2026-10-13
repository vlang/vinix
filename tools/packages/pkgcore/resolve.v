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
		mut preferred := []Installed{cap: candidates.len * 2}
		unsafe { preferred.flags |= .noslices }
		for installed in current.packages {
			for candidate in candidates {
				if candidate.package == installed.package && candidate.repository == installed.repository && candidate.public_key == installed.public_key {
					preferred << candidate
				}
			}
		}
		preferred << candidates
		unsafe { (&array(&candidates)).free() }
		candidates = unsafe { preferred }
	}
	mut search := Search{ config: config, candidates: candidates }
	defer { unsafe { search.diagnostic.free() } }
	mut packages := search.solve(pending)!
	packages.sort(a.package.id < b.package.id)
	accepted = true
	return Plan{ requested: roots, packages: packages }
}

pub fn desired_roots(state State, operation string, names []string) ![]string {
	mut roots := state.requested.clone()
	match operation {
		'install' {
			if names.len == 0 { return error('install requires package IDs') }
			for id in names { if id !in roots { roots << id } }
		}
		'remove' {
			if names.len == 0 { return error('remove requires package IDs') }
			for id in names {
				if id !in roots {
					return error('${id} is not explicitly installed; remove its dependents instead')
				}
			}
			roots = roots.filter(it !in names)
		}
		'upgrade', 'deploy' {
			if operation == 'deploy' {
				roots = names.clone()
			} else if names.len != 0 {
				return error('upgrade updates the complete installed closure')
			}
		}
		else { return error('unknown package operation: ${operation}') }
	}
	return roots
}
