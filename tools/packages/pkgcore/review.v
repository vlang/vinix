// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import tools.packages.pkgprotocol

struct ReviewIdentity {
	format            int = 1
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
	roots := desired_roots(current, operation, names)!
	// Uninstall remains available with expired/revoked publishers or tightened policy.
	catalog := if operation == 'remove' {
		Catalog{ packages: current.packages }
	} else {
		load_catalog(config, directory)!
	}
	mut licenses := []string{}
	if operation == 'remove' {
		for installed in current.packages {
			if installed.package.license !in licenses { licenses << installed.package.license }
		}
	}
	resolution_config := if operation == 'remove' {
		Config{ ...config, policy: Policy{ allow_firmware: true, licenses: licenses } }
	} else {
		config
	}
	plan := resolve(catalog, resolution_config, current, roots, operation in ['upgrade', 'deploy'])!
	if operation == 'remove' && plan.packages.any(it.package.id in names) {
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
	mut rows := []pkgprotocol.ReviewPackage{}
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
		rows << review_row(installed, version, installed.package.id in plan.requested, action)
	}
	for installed in current.packages {
		if !plan.packages.any(it.package.id == installed.package.id) {
			rows << review_row(installed, installed.package.version, false, 'remove')
		}
	}
	rows.sort(a.id < b.id)
	needed := if operation == 'rollback' || (current.requested == plan.requested && current.packages == plan.packages && repairs.len == 0) {
		u64(0)
	} else {
		estimate_transaction_space(plan, directory, current, operation)!
	}
	review := pkgprotocol.Review{
		format:            1
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
