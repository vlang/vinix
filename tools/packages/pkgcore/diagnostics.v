// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Configuration/state decoding stays syntax-only so broken trust never blocks
// revocation or uninstall. Presentation uses the same key admission as launch.
// Cache only within this read: repository changes must take effect immediately.
fn package_diagnostic(config Config, installed Installed, mut keys map[string]bool) string {
	id := installed.package.id
	if !config.repositories.any(it.id == installed.repository && it.public_key == installed.public_key) {
		return '${id}: publisher key has been revoked; uninstall remains available'
	}
	if installed.public_key !in keys {
		if key := admitted_publisher_key(installed.public_key) {
			keys[installed.public_key] = true
			unsafe { key.free() }
		} else {
			keys[installed.public_key] = false
			unsafe { err.free() }
		}
	}
	if !keys[installed.public_key] {
		return '${id}: repository ${installed.repository} has an invalid publisher key; ask an administrator to review repository trust; uninstall remains available'
	}
	check_policy(installed.package, config.policy) or {
		// Return an independent message: returning err.msg() promotes the error
		// interface itself to an unretired box in the pinned compiler.
		owned := err.msg()
		message := owned.clone()
		unsafe { owned.free(); err.free() }
		return message
	}
	return ''
}

fn package_diagnostics(config Config, packages []Installed) map[string]string {
	mut diagnostics := map[string]string{}
	mut keys := map[string]bool{}
	mut dependents := map[string][]string{}
	mut pending := []string{cap: packages.len}
	defer {
		unsafe {
			keys.free()
			for _, users in dependents {
				for id in users { id.free() }
				(&array(&users)).free()
			}
			dependents.free()
			for id in pending { id.free() }
			(&array(&pending)).free()
		}
	}
	for installed in packages {
		id := installed.package.id
		diagnostic := package_diagnostic(config, installed, mut keys)
		diagnostics[id] = diagnostic
		if diagnostic != '' { pending << id }
		for dependency in installed.package.dependencies {
			mut users := dependents[dependency.id] or { []string{} }
			users.flags |= .noslices
			users << id
			dependents[dependency.id] = users
		}
	}
	// Each package enters the queue once. Denial flows through reverse edges,
	// including cycles, without repeatedly walking every application's closure.
	mut next := 0
	for next < pending.len {
		blocked := pending[next]
		next++
		users := dependents[blocked] or { continue }
		for id in users {
			if diagnostics[id] != '' { continue }
			diagnostics[id] = diagnostics[blocked].clone()
			pending << id
		}
	}
	return diagnostics
}

// Messages own their text, including propagated copies. Maps and array pushes
// clone their ID strings; their cleanup leaves caller-owned provenance intact.
fn close_package_diagnostics(diagnostics map[string]string) {
	unsafe {
		for _, message in diagnostics { message.free() }
		diagnostics.free()
	}
}
