// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn resolve_deployment_additions(config Config, catalog Catalog, current State, document DeploymentLock) !Plan {
	// Check the release on its own first. Installed candidates cannot fill
	// holes in the lock or make its extra, unrelated pins appear necessary.
	release := resolve_locked_deployment(config, catalog, current, document)!
	defer { unsafe { (&array(&release.requested)).free(); (&array(&release.packages)).free() } }

	roots := desired_roots(current, 'install', document.packages)!
	defer { unsafe { (&array(&roots)).free() } }
	mut retained := map[string]int{}
	defer { unsafe { retained.free() } }
	for index, item in current.packages {
		retained[item.package.id] = index
	}
	mut candidates := []Installed{cap: release.packages.len + retained.len}
	unsafe { candidates.flags |= .noslices }
	defer { unsafe { (&array(&candidates)).free() } }
	for pin in release.packages {
		retained.delete(pin.package.id)
		unsafe { candidates.push_many(&pin, 1) }
	}
	// Keep only byte-equivalent installed manifests with current authenticated
	// provenance outside the release lock. Missing and conflicting retained
	// apps fail resolution instead of being upgraded or dropped implicitly.
	for candidate in catalog.packages {
		if index := retained[candidate.package.id] {
			installed := current.packages[index]
			if candidate.package == installed.package && candidate.repository == installed.repository
				&& candidate.public_key == installed.public_key {
				unsafe { candidates.push_many(&candidate, 1) }
			}
		}
	}
	return resolve(Catalog{ packages: candidates }, config, current, roots, false)
}
