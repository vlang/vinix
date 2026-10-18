// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import tools.packages.pkgprotocol

// An administrative client stores a root, an offline flag and an optional
// presentation observer, with no configuration or trust snapshot.
// Configuration, policy and trust are always loaded after acquiring the lock.
// The Config-taking APIs remain available for explicit snapshot-based fixtures.
pub struct Service {
pub:
	root    string
	offline bool
	progress fn (pkgprotocol.Progress) = no_progress
}

fn (service Service) directory() !string {
	if service.root != '' && (!service.root.starts_with('/') || !printable(service.root, 4096)) {
		return error('package service root must be an absolute directory')
	}
	return state_directory(service.root)
}

fn (service Service) configuration() !Config {
	initial := load_config(service.root)!
	return Config{ ...initial, policy: Policy{ ...initial.policy, offline: service.offline || initial.policy.offline } }
}

pub fn (service Service) refresh() !Catalog {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire(directory)!
	defer { guard.release() }
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	return refresh_progress(config, directory, service.progress)
}

pub fn (service Service) transact(operation string, names []string, options TransactionOptions) !State {
	directory := service.directory()!
	guard := acquire(directory)!
	defer { guard.release() }
	return transact_locked(service.configuration()!, directory, operation, names,
		TransactionOptions{ ...options, progress: service.progress })
}

// The observation owns every field independently. Retire it with Plan.close().
pub fn (service Service) plan(operation string, names []string) !Plan {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire_reader(directory)!
	defer { guard.release() }
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	return preview_plan_locked(config, directory, operation, names)
}

pub fn (service Service) review(operation string, names []string) !pkgprotocol.Review {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire_reader(directory)!
	defer { guard.release() }
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	return review_operation_locked(config, directory, operation, names)
}

pub fn (service Service) rollback(expected string) !State {
	directory := service.directory()!
	guard := acquire(directory)!
	defer { guard.release() }
	return rollback_progress(service.configuration()!, directory, expected, service.progress)
}

pub fn (service Service) collect() ! {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire(directory)!
	defer { guard.release() }
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	collect_locked(config, directory)!
}

pub fn (service Service) mirror(destination string, names []string) ! {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire(directory)!
	defer { guard.release() }
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	mirror_export(config, directory, destination, names, MirrorOptions{ progress: service.progress })!
}

fn (service Service) installed_locked(directory string, verify bool) !State {
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	current := read_state(directory, config.architecture)!
	// A fresh read_state borrows its architecture argument. Public observations
	// own it too, so configuration storage can retire before the caller returns.
	state := if current.generation == 0 {
		State{ ...current, architecture: current.architecture.clone() }
	} else { current }
	if verify {
		verify_installed(directory, state, service.progress) or {
			close_decoded_state(state)
			return err
		}
	}
	return state
}

fn (service Service) installed(verify bool) !State {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	if state_requires_lock(directory) {
		guard := acquire_reader(directory)!
		defer { guard.release() }
		return service.installed_locked(directory, verify)
	}
	// A fresh image's status does not create administrator-owned package state.
	return service.installed_locked(directory, verify)
}

// These read-only results own their fields. Retire them with State.close().
pub fn (service Service) state() !State {
	return service.installed(false)
}

pub fn (service Service) verify() !State {
	return service.installed(true)
}

fn (service Service) health_locked(directory string) !pkgprotocol.HealthReport {
	// This observation needs configuration/state, not repository metadata. Use
	// the decoded configuration directly so its independent storage can retire.
	config := load_config(service.root)!
	defer { close_decoded_configuration(config) }
	state := read_state(directory, config.architecture)!
	defer { if state.generation != 0 { close_decoded_state(state) } }
	return installed_health_report(directory, state, service.progress)
}

pub fn (service Service) health() !pkgprotocol.HealthReport {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	if state_requires_lock(directory) {
		guard := acquire_reader(directory)!
		defer { guard.release() }
		return service.health_locked(directory)
	}
	return service.health_locked(directory)
}

// This private owner spans preparation, validation and the synchronous child.
// Its empty configuration must not allocate the normal Policy defaults on
// construction or reset; only a loaded configuration owns policy storage here.
struct PreparedLaunch {
mut:
	directory string
	config Config = Config{ policy: Policy{ permissions: [] } }
	state State
	lease int = -1
}

fn (mut prepared PreparedLaunch) close() {
	if prepared.lease >= 0 { C.close(prepared.lease) }
	if prepared.state.generation != 0 { close_decoded_state(prepared.state) }
	close_decoded_configuration(prepared.config)
	unsafe { prepared.directory.free() }
	prepared = PreparedLaunch{}
}

fn (service Service) prepare_launch(id string) !PreparedLaunch {
	mut prepared := PreparedLaunch{ directory: service.directory()! }
	mut admitted := false
	defer { if !admitted { prepared.close() } }
	guard := acquire_reader(prepared.directory)!
	defer { guard.release() }
	prepared.config = service.configuration()!
	if os.geteuid() != 0 {
		state, lease := generation_lease(prepared.directory, prepared.config.architecture, id)!
		prepared.state = state
		prepared.lease = lease
	}
	admitted = true
	return prepared
}

pub fn (service Service) run(id string, documents []string) !int {
	return service.run_mode(id, LaunchInput{ documents: documents })
}

pub fn (service Service) run_terminal(id string, documents []string) !int {
	if C.isatty(0) != 1 || C.isatty(1) != 1 { return error('terminal launch requires terminal standard input and output') }
	return service.run_mode(id, LaunchInput{ documents: documents, terminal: true })
}

pub fn (service Service) run_window(id string, documents []string) !int {
	return service.run_mode(id, LaunchInput{ documents: documents, window: true })
}

pub fn (service Service) run_command(id string, input CommandLaunch, terminal bool) !int {
	validate_command(input)!
	if terminal && (C.isatty(0) != 1 || C.isatty(1) != 1) {
		return error('terminal launch requires terminal standard input and output')
	}
	return service.run_mode(id, LaunchInput{ documents: input.documents, arguments: input.arguments, terminal: terminal, command: true, data_cwd: input.data_cwd })
}

fn (service Service) run_mode(id string, input LaunchInput) !int {
	if service.root != '' { return error('application launch cannot use an alternate installation root') }
	mut prepared := service.prepare_launch(id)!
	defer { prepared.close() }
	if prepared.lease < 0 {
		// The ordinary child takes a new lock and rechecks trust. Do not hold the
		// parent's lock while waiting for the child or its generation lease.
		return run_in_session_request(prepared.config, id, input)
	}
	return run_leased_mode(prepared.config, prepared.directory, prepared.state, id, input)
}
