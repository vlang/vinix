// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// A reviewed lock is borrowed from the selection. Resolving unpinned roots
// returns a new owned lock.
fn image_application_deployment(config Config, repositories &ImageRepositories, selection DeploymentLock) !DeploymentLock {
	if repositories.capture == '' { return error('required image applications need a selected signed repository bundle') }
	mut roots := map[string]bool{}
	mut keys := map[string]string{}
	mut candidates := []Installed{cap: 128}
	unsafe { candidates.flags |= .noslices }
	defer { unsafe { roots.free(); keys.free(); (&array(&candidates)).free() } }
	for id in selection.packages { roots[id] = false }
	for repository in config.repositories { keys[repository.id] = repository.public_key }
	for repository in repositories.repositories {
		for p in repository.index.packages {
			if p.architecture !in [config.architecture, 'all']! { continue }
			if p.id in roots {
				// A runtime/data variant with the same ID cannot satisfy an
				// advertised application, even if its version is newer.
				if p.kind in ['runtime', 'data']! { continue }
				roots[p.id] = true
			}
			if candidates.len == 32768 { return error('image application catalog exceeds the dependency resolver input limit') }
			candidate := Installed{ package: p, repository: repository.id,
				public_key: keys[repository.id], sequence: repository.index.sequence }
			unsafe { candidates.push_many(&candidate, 1) }
		}
	}
	for id in selection.packages {
		if !roots[id] { return error('required image application ${id} has no bundled application candidate for ${config.architecture}') }
	}
	catalog := Catalog{ packages: candidates }
	current := State{ architecture: config.architecture }
	// A fresh install has no historical publisher owners or preferred versions.
	// Resolve all advertised roots in one transaction: individually installable
	// applications may still require mutually incompatible runtime versions.
	plan := if selection.format == 2 { resolve_locked_deployment(config, catalog, current, selection)! }
		else { resolve(catalog, config, current, selection.packages, true)! }
	defer { unsafe { (&array(&plan.requested)).free(); (&array(&plan.packages)).free() } }
	if selection.format == 2 { return selection }
	return owned_deployment_lock(config.architecture, plan)
}
