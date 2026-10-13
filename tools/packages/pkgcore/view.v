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
	check_policy(p, policy) or { return false }
	return true
}

// New applications advertise catalog metadata; installation still requires
// complete review. Installed changes come from one full upgrade resolution,
// including dependency additions/removals and same-version manifest changes.
fn catalog_view(config Config, catalog Catalog, current State, catalog_error string) !SoftwareView {
	mut installed := map[string]Installed{}
	mut choices := map[string]Installed{}
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
	mut changes := map[string]string{}
	if catalog_error == '' && current.requested.len > 0 {
		plan := resolve(catalog, config, current, current.requested, true) or {
			update_error = err.msg()
			Plan{}
		}
		if update_error == '' {
			mut targets := map[string]bool{}
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
			for id in installed.keys() {
				if id !in targets { changes[id] = 'remove' }
			}
		}
	}
	mut rows := []SoftwareRow{}
	mut ids := choices.keys()
	if ids.len > 4096 { return error('software catalog exceeds its supported row limit') }
	ids.sort()
	for id in ids {
		candidate := choices[id]
		p := candidate.package
		old := installed[id] or { Installed{} }
		mut diagnostic := ''
		if !config.repositories.any(it.id == candidate.repository && it.public_key == candidate.public_key) {
			diagnostic = '${id}: publisher key has been revoked; uninstall remains available'
		} else {
			check_policy(p, config.policy) or { diagnostic = err.msg() }
		}
		action := changes[id] or { '' }
		rows << SoftwareRow{
			id:                id
			name:              p.name
			description:       p.description
			version:           p.version
			installed_version: old.package.version
			installed_name:    old.package.name
			installed_kind:    old.package.kind
			installed_permissions: old.package.permissions
			installed_window_protocol: old.package.window_protocol
			architecture:      p.architecture
			kind:              p.kind
			runtime:           p.runtime
			repository:        candidate.repository
			public_key:        candidate.public_key
			license:           p.license
			proprietary:       p.proprietary
			firmware:          p.firmware
			permissions:       p.permissions
			requested:         id in current.requested
			updatable:         action != ''
			update_action:     action
			diagnostic:        diagnostic
		}
	}
	return SoftwareView{
		generation:    current.generation
		architecture:  config.architecture
		offline:       config.policy.offline
		catalog_error: catalog_error
		update_error:  update_error
		rows:          rows
		launch_user:   if os.geteuid() == 0 { config.launch_user } else { '' }
	}
}

fn read_software_view(root string, offline bool) !SoftwareView {
	initial := load_config(root)!
	config := Config{ ...initial, policy: Policy{ ...initial.policy, offline: offline || initial.policy.offline } }
	directory := state_directory(root)
	current := read_state(directory, config.architecture)!
	mut catalog_error := if config.repositories.len == 0 {
		'No trusted repositories are configured. An administrator must enroll a publisher with vinix-package repo-enroll.'
	} else {
		''
	}
	catalog := load_catalog(config, directory) or {
		catalog_error = err.msg()
		Catalog{}
	}
	return catalog_view(config, catalog, current, catalog_error)
}

pub fn software_view(root string, offline bool) !SoftwareView {
	directory := state_directory(root)
	if os.exists(directory + '/lock') || os.is_link(directory + '/lock') {
		guard := acquire_reader(directory)!
		defer { guard.release() }
		return read_software_view(root, offline)
	}
	// A fresh image can display its enrollment diagnostic without a write.
	return read_software_view(root, offline)
}
