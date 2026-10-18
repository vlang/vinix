// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

pub struct SoftwareRow {
pub:
	id                string
	name              string
	description       string
	version           string
	installed_version string
	installed_repository string
	installed_public_key string
	installed_dependencies_known bool
	installed_dependencies []Dependency
	installed_license string
	installed_proprietary bool
	installed_firmware bool
	installed_runtime string
	installed_name    string
	installed_kind    string
	installed_permissions []string
	installed_window_protocol int
	architecture      string
	kind              string
	runtime           string
	repository        string
	public_key        string
	license           string
	proprietary       bool
	firmware          bool
	permissions       []string
	requested         bool
	updatable         bool
	update_action     string // install, update, remove, or empty when unchanged
	diagnostic        string
}

pub struct SoftwareView {
pub:
	format        int = 1
	generation    u64
	architecture  string
	offline       bool
	catalog_error string
	update_error  string
	rows          []SoftwareRow
	launch_user   string
}

fn view_policy_allows(p Package, policy Policy) bool {
	check_policy(p, policy) or { unsafe { err.free() }; return false }
	return true
}

fn owned_view_dependencies(values []Dependency) []Dependency {
	mut owned := []Dependency{cap: values.len}
	for value in values {
		item := Dependency{id: value.id.clone(), minimum: value.minimum.clone(), before: value.before.clone()}
		pointer := unsafe { &item }
		unsafe { owned.push_many(pointer, 1) }
	}
	return owned
}

// Only service/catalog observations own all row fields. Caller-built values
// may borrow data and must retain their caller-managed lifetime.
pub fn (mut view SoftwareView) close() {
	unsafe {
		view.architecture.free(); view.launch_user.free(); view.catalog_error.free(); view.update_error.free()
		for row in view.rows {
			row.id.free(); row.name.free(); row.description.free(); row.version.free(); row.installed_version.free()
			row.installed_repository.free(); row.installed_public_key.free(); row.installed_license.free(); row.installed_runtime.free()
			row.installed_name.free(); row.installed_kind.free(); row.architecture.free(); row.kind.free(); row.runtime.free()
			row.repository.free(); row.public_key.free(); row.license.free(); row.update_action.free(); row.diagnostic.free()
			for permission in row.permissions { permission.free() }; (&array(&row.permissions)).free()
			for permission in row.installed_permissions { permission.free() }; (&array(&row.installed_permissions)).free()
			for dependency in row.installed_dependencies { dependency.id.free(); dependency.minimum.free(); dependency.before.free() }
			(&array(&row.installed_dependencies)).free()
		}
		(&array(&view.rows)).free()
	}
	view = SoftwareView{}
}

// New applications advertise catalog metadata; installation still requires
// complete review. Installed changes come from one full upgrade resolution,
// including dependency additions/removals and same-version manifest changes.
fn catalog_view(config Config, catalog Catalog, current State, catalog_error string) !SoftwareView {
	installed_diagnostics := package_diagnostics(config, current.packages)
	defer { close_package_diagnostics(installed_diagnostics) }
	mut publisher_keys := map[string]bool{}
	defer { unsafe { publisher_keys.free() } }
	mut installed := map[string]Installed{}
	mut choices := map[string]Installed{}
	defer { unsafe { installed.free(); choices.free() } }
	for item in current.packages {
		installed[item.package.id] = item
		choices[item.package.id] = item
	}
	for candidate in catalog.packages {
		p := candidate.package
		if p.architecture !in [config.architecture, 'all'] || p.kind in ['runtime', 'data']
			|| p.id in installed {
			continue
		}
		old := choices[p.id] or { Installed{} }
		allowed := view_policy_allows(p, config.policy)
		old_allowed := view_policy_allows(old.package, config.policy)
		if old.package.id == '' || (allowed && !old_allowed)
			|| (allowed == old_allowed && compare_versions(p.version, old.package.version) > 0) {
			choices[p.id] = candidate
		}
	}
	mut update_error := ''
	defer { unsafe { update_error.free() } }
	mut changes := map[string]string{}
	defer { unsafe { changes.free() } }
	if catalog_error == '' && current.requested.len > 0 {
		plan := resolve(catalog, config, current, current.requested, true) or {
			message := err.msg()
			update_error = message.clone()
			unsafe { message.free(); err.free() }
			Plan{}
		}
		defer { unsafe { (&array(&plan.requested)).free(); (&array(&plan.packages)).free() } }
		if update_error == '' {
			mut targets := map[string]bool{}
			defer { unsafe { targets.free() } }
			for candidate in plan.packages {
				id := candidate.package.id
				targets[id] = true
				choices[id] = candidate
				old := installed[id] or { Installed{} }
				if old.package.id == '' {
					changes[id] = 'install'
				} else if old.package != candidate.package || old.repository != candidate.repository
					|| old.public_key != candidate.public_key {
					changes[id] = 'update'
				}
			}
			for id, _ in installed {
				if id !in targets { changes[id] = 'remove' }
				unsafe { id.free() }
			}
		}
	}
	mut ids := choices.keys()
	defer { unsafe { for id in ids { id.free() }; (&array(&ids)).free() } }
	if ids.len > 4096 { return error('software catalog exceeds its supported row limit') }
	mut rows := []SoftwareRow{cap: ids.len}
	ids.sort()
	for id in ids {
		candidate := choices[id]
		p := candidate.package
		old := installed[id] or { Installed{} }
		// Pending updates do not repair the installed launch closure until they
		// activate. Keep its blocker visible even when the preview drops it.
		diagnostic := if installed_diagnostics[id] != '' {
			installed_diagnostics[id].clone()
		} else {
			package_diagnostic(config, candidate, mut publisher_keys)
		}
		action := changes[id] or { '' }
		row := SoftwareRow{
			id:                id.clone()
			name:              p.name.clone()
			description:       p.description.clone()
			version:           p.version.clone()
			installed_version: old.package.version.clone()
			installed_repository: old.repository.clone()
			installed_public_key: old.public_key.clone()
			installed_dependencies_known: old.package.id != ''
			installed_dependencies: owned_view_dependencies(old.package.dependencies)
			installed_license: old.package.license.clone()
			installed_proprietary: old.package.proprietary
			installed_firmware: old.package.firmware
			installed_runtime: old.package.runtime.clone()
			installed_name:    old.package.name.clone()
			installed_kind:    old.package.kind.clone()
			installed_permissions: review_strings(old.package.permissions)
			installed_window_protocol: old.package.window_protocol
			architecture:      p.architecture.clone()
			kind:              p.kind.clone()
			runtime:           p.runtime.clone()
			repository:        candidate.repository.clone()
			public_key:        candidate.public_key.clone()
			license:           p.license.clone()
			proprietary:       p.proprietary
			firmware:          p.firmware
			permissions:       review_strings(p.permissions)
			requested:         id in current.requested
			updatable:         action != ''
			update_action:     action.clone()
			diagnostic:        diagnostic
		}
		pointer := unsafe { &row }
		unsafe { rows.push_many(pointer, 1) }
	}
	return SoftwareView{
		generation:    current.generation
		architecture:  config.architecture.clone()
		offline:       config.policy.offline
		catalog_error: catalog_error.clone()
		update_error:  update_error.clone()
		rows:          rows
		launch_user:   if os.geteuid() == 0 { config.launch_user.clone() } else { '' }
	}
}

fn read_software_view(root string, offline bool) !SoftwareView {
	initial := load_config(root)!
	defer { close_decoded_configuration(initial) }
	config := Config{ ...initial, policy: Policy{ ...initial.policy, offline: offline || initial.policy.offline } }
	directory := state_directory(root)
	defer { unsafe { directory.free() } }
	current := read_state(directory, config.architecture)!
	defer { if current.generation != 0 { close_decoded_state(current) } }
	mut catalog_error := if config.repositories.len == 0 {
		'No trusted repositories are configured. An administrator must enroll a publisher with vinix-package repo-enroll.'
	} else {
		''
	}
	defer { unsafe { catalog_error.free() } }
	catalog := load_catalog(config, directory) or {
		message := err.msg()
		catalog_error = message.clone()
		unsafe { message.free(); err.free() }
		Catalog{}
	}
	defer { close_authenticated_catalog(catalog) }
	return catalog_view(config, catalog, current, catalog_error)
}

pub fn software_view(root string, offline bool) !SoftwareView {
	directory := state_directory(root)
	defer { unsafe { directory.free() } }
	if state_requires_lock(directory) {
		guard := acquire_reader(directory)!
		defer { guard.release() }
		return read_software_view(root, offline)
	}
	// A fresh image can display its enrollment diagnostic without a write.
	return read_software_view(root, offline)
}
