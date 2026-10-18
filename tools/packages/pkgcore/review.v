// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import tools.packages.pkgprotocol

struct ReviewIdentity {
	// Opaque identity version 2 invalidates approvals from pointer-only rollback.
	format            int = 2
	config            Config
	operation         string
	names             []string
	current           State
	plan              Plan
	target_generation u64
	repairs           []string @[omitempty]
}

fn review_fingerprint(config Config, operation string, names []string, current State, plan Plan, target u64, repairs []string) string {
	text := json2.encode(ReviewIdentity{
		config:            config
		operation:         operation
		names:             names
		current:           current
		plan:              plan
		target_generation: target
		repairs:           repairs
	})
	bytes := text.bytes()
	result := sha256.sum(bytes).hex()
	unsafe {
		bytes.free()
		text.free()
	}
	return result
}

fn check_review(expected string, actual string) ! {
	if expected != '' && (!digest_valid(expected) || expected != actual) {
		return error('package review is stale: installed state, policy or resolved packages changed; review the operation again')
	}
}

fn operation_plan(config Config, directory string, current State, operation string, names []string) !Plan {
	if operation == 'deploy' && names.len == 0 {
		// An explicit empty target only removes packages. Like uninstall, it
		// must remain available without an authenticated catalog or publisher.
		config.validate()!
		return Plan{}
	}
	if operation == 'repair' {
		if names.len != 0 { return error('repair takes no package IDs; it preserves the complete installed closure') }
		if current.packages.len == 0 { return Plan{ requested: current.requested, packages: current.packages } }
		// Repair cannot turn a missing/withdrawn installed version into an update.
		// Authenticate the exact manifests and provenance against today's cached
		// catalog, then retain the already validated persistent dependency closure.
		catalog := load_catalog(config, directory)!
		defer { close_authenticated_catalog(catalog) }
		for installed in current.packages {
			if !catalog.packages.any(it.package == installed.package
				&& it.repository == installed.repository && it.public_key == installed.public_key) {
				return error('${installed.package.id}: installed manifest is unavailable in the authenticated catalog; refresh repositories or review updates')
			}
			check_policy(installed.package, config.policy)!
		}
		return Plan{ requested: current.requested, packages: current.packages }
	}
	roots := desired_roots(current, operation, names)!
	defer { unsafe { (&array(&roots)).free() } }
	// Uninstall remains available with expired/revoked publishers or tightened policy.
	catalog := if operation == 'remove' {
		Catalog{ packages: current.packages }
	} else {
		load_catalog(config, directory)!
	}
	mut licenses := []string{}
	unsafe { licenses.flags |= .noslices }
	defer { unsafe { (&array(&licenses)).free() } }
	if operation == 'remove' {
		for installed in current.packages {
			license := installed.package.license
			if license in licenses { continue }
			pointer := unsafe { &license }
			unsafe { licenses.push_many(pointer, 1) }
		}
	}
	resolution_config := if operation == 'remove' {
		Config{ ...config, policy: Policy{ allow_firmware: true, licenses: licenses } }
	} else {
		config
	}
	defer { if operation == 'remove' { unsafe { (&array(&resolution_config.policy.permissions)).free() } } }
	plan := resolve(catalog, resolution_config, current, roots, operation in ['upgrade', 'deploy'])!
	if operation == 'remove' && plan.packages.any(it.package.id in names) {
		unsafe { (&array(&plan.requested)).free(); (&array(&plan.packages)).free() }
		if blocker := removal_blocker(current, names, '') {
			return error('cannot remove ${blocker.id}: still required by requested package ${blocker.root}; review removal of dependent applications first')
		}
		return error('cannot remove a package still required by another installed application')
	}
	return plan
}

pub fn preview_plan(config Config, directory string, operation string, names []string) !Plan {
	guard := acquire_reader(directory)!
	defer { guard.release() }
	return preview_plan_locked(config, directory, operation, names)
}

fn preview_plan_locked(config Config, directory string, operation string, names []string) !Plan {
	current := read_state(directory, config.architecture)!
	return operation_plan(config, directory, current, operation, names)
}

fn review_strings(values []string) []string {
	mut owned := []string{cap: values.len}
	for value in values { owned << value.clone() }
	return owned
}

fn review_row(installed Installed, previous_version string, requested bool, action string) pkgprotocol.ReviewPackage {
	p := installed.package
	mut permissions := []string{cap: 5}
	for permission in p.permissions {
		if permission !in permissions { permissions << permission.clone() }
	}
	return pkgprotocol.ReviewPackage{
		id:                p.id.clone()
		name:              p.name.clone()
		description:       p.description.clone()
		version:           p.version.clone()
		installed_version: previous_version.clone()
		architecture:      p.architecture.clone()
		kind:              p.kind.clone()
		runtime:           p.runtime.clone()
		repository:        installed.repository.clone()
		public_key:        installed.public_key.clone()
		license:           p.license.clone()
		proprietary:       p.proprietary
		firmware:          p.firmware
		permissions:       permissions
		requested:         requested
		action:            action.clone()
	}
}

fn review_row_previous(installed Installed, previous Installed, requested bool, action string) pkgprotocol.ReviewPackage {
	return pkgprotocol.ReviewPackage{...review_row(installed, previous.package.version, requested, action),
		installed_permissions_known: true, installed_permissions: review_strings(previous.package.permissions)}
}

pub fn review_operation(config Config, directory string, operation string, names []string) !pkgprotocol.Review {
	config.validate()!
	guard := acquire_reader(directory)!
	defer { guard.release() }
	return review_operation_locked(config, directory, operation, names)
}

fn review_operation_locked(config Config, directory string, operation string, names []string) !pkgprotocol.Review {
	current := read_state(directory, config.architecture)!
	mut target := u64(0)
	plan := if operation == 'rollback' {
		if names.len != 0 { return error('rollback takes no package IDs') }
		old := rollback_target(config, directory, current)!
		target = old.generation
		Plan{ requested: old.requested, packages: old.packages }
	} else {
		operation_plan(config, directory, current, operation, names)!
	}
	repairs := transaction_repairs(directory, current, plan, operation)
	defer { close_transaction_repairs(repairs) }
	return review_plan(config, directory, current, operation, names, plan, target, repairs,
		review_fingerprint(config, operation, names, current, plan, target, repairs))
}

fn review_plan(config Config, directory string, current State, operation string, names []string, plan Plan, target u64, repairs []string, fingerprint string) !pkgprotocol.Review {
	changed := operation == 'rollback' || current.requested != plan.requested || current.packages != plan.packages || repairs.len > 0
	if changed {
		encoded := encode_generation_state(State{
			generation: next_generation(directory)!
			previous: current.generation
			architecture: config.architecture
			requested: plan.requested
			packages: plan.packages
		})!
		unsafe { encoded.free() }
	}
	mut rows := []pkgprotocol.ReviewPackage{cap: plan.packages.len + current.packages.len}
	for installed in plan.packages {
		previous := current.packages.filter(it.package.id == installed.package.id)
		version := if previous.len == 0 { '' } else { previous[0].package.version }
		action := if previous.len == 0 {
			'install'
		} else if installed.package == previous[0].package
			&& installed.repository == previous[0].repository && installed.public_key == previous[0].public_key
			&& installed.package.id !in repairs {
			'keep'
		} else {
			'update'
		}
		rows << if previous.len == 0 { review_row(installed, version, installed.package.id in plan.requested, action) }
			else { review_row_previous(installed, previous[0], installed.package.id in plan.requested, action) }
		unsafe { (&array(&previous)).free() }
	}
	for installed in current.packages {
		if !plan.packages.any(it.package.id == installed.package.id) {
			rows << review_row_previous(installed, installed, false, 'remove')
		}
	}
	rows.sort(a.id < b.id)
	needed := if !changed {
		u64(0)
	} else {
		estimate_transaction_space(plan, directory, current, operation)!
	}
	review := pkgprotocol.Review{
		format:            2
		operation:         operation.clone()
		names:             review_strings(names)
		architecture:      config.architecture.clone()
		generation:        current.generation
		target_generation: target
		fingerprint:       fingerprint
		requested:         review_strings(plan.requested)
		rows:              rows
		disk_needed:       needed
		disk_available:    free_bytes(directory)!
		disk_reserve:      config.policy.reserve_bytes
	}
	review.validate()!
	return review
}
