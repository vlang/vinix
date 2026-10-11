// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

pub struct Plan {
pub:
	requested []string
	packages  []Installed
}

struct Search {
	config     Config
	candidates []Installed
mut:
	steps      int
	diagnostic string
}

// Backtracking checks every constraint, including those added after a package
// was selected. Cycles are legal; a selected package is expanded exactly once.
fn (mut s Search) solve(pending []Dependency, selected []Installed) ![]Installed {
	s.steps++
	if s.steps > 100000 {
		return error('dependency resolution exceeded its search limit; narrow the requested versions')
	}
	if pending.len == 0 {
		for installed in selected {
			p := installed.package
			if p.runtime == '' { continue }
			runtimes := selected.filter(it.package.id == p.runtime)
			if runtimes.len != 1 || runtimes[0].package.kind != 'runtime'
				|| !runtimes[0].package.files.any(it.path == p.entrypoint && it.executable) {
				s.diagnostic = '${p.id}: isolated runtime ${p.runtime} does not provide ${p.entrypoint}'
				return error(s.diagnostic)
			}
		}
		return selected
	}
	dependency := pending[0]
	rest := pending[1..].clone()
	for chosen in selected {
		if chosen.package.id == dependency.id {
			if !dependency.accepts(chosen.package) {
				s.diagnostic = 'conflicting version requirements for ${dependency.id}'
				return error(s.diagnostic)
			}
			return s.solve(rest, selected)
		}
	}
	for candidate in s.candidates {
		p := candidate.package
		if p.architecture !in [s.config.architecture, 'all'] || !dependency.accepts(p) { continue }
		check_policy(p, s.config.policy) or {
			s.diagnostic = err.msg()
			continue
		}
		mut next := selected.clone()
		next << candidate
		mut requirements := rest.clone()
		requirements << p.dependencies
		answer := s.solve(requirements, next) or { continue }
		return answer
	}
	if s.diagnostic == '' {
		s.diagnostic = 'no trusted ${s.config.architecture} candidate satisfies ${dependency.id} (${dependency.minimum} .. ${dependency.before})'
	}
	return error(s.diagnostic)
}

fn candidate_order(a &Installed, b &Installed) int {
	if a.package.id != b.package.id { return if a.package.id < b.package.id { -1 } else { 1 } }
	return -compare_versions(a.package.version, b.package.version)
}

pub fn resolve(catalog Catalog, config Config, current State, requested []string, upgrade bool) !Plan {
	config.validate()!
	mut roots := requested.clone()
	roots.sort()
	mut pending := []Dependency{}
	for i, id in roots {
		if !identifier(id) || (i > 0 && id == roots[i - 1]) {
			return error('invalid or duplicate requested package: ${id}')
		}
		pending << Dependency{ id: id }
	}
	mut owners := map[string]string{}
	for installed in current.packages { owners[installed.package.id] = installed.repository }
	// A package's disappearance from one publisher is not permission for
	// another enrolled repository to replace its installed identity.
	mut candidates := catalog.packages.filter(it.package.id !in owners
		|| owners[it.package.id] == it.repository)
	candidates.sort_with_compare(candidate_order)
	if !upgrade {
		// Reuse installed packages only when their exact provenance is still
		// present in the authenticated catalog; revoked/removed versions cannot
		// bypass current repository policy.
		mut preferred := []Installed{}
		for installed in current.packages {
			for candidate in candidates {
				if candidate.package == installed.package && candidate.repository == installed.repository && candidate.public_key == installed.public_key {
					preferred << candidate
				}
			}
		}
		preferred << candidates
		candidates = preferred.clone()
	}
	mut search := Search{ config: config, candidates: candidates }
	mut packages := search.solve(pending, [])!
	packages.sort(a.package.id < b.package.id)
	for installed in packages {
		p := installed.package
		if p.runtime == '' { continue }
		runtimes := packages.filter(it.package.id == p.runtime)
		if runtimes.len != 1 || runtimes[0].package.kind != 'runtime'
			|| !runtimes[0].package.files.any(it.path == p.entrypoint && it.executable) {
			return error('${p.id}: isolated runtime ${p.runtime} does not provide ${p.entrypoint}')
		}
	}
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
