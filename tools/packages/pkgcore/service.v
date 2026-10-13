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
	guard := acquire(directory)!
	defer { guard.release() }
	return refresh_progress(service.configuration()!, directory, service.progress)
}

pub fn (service Service) transact(operation string, names []string, options TransactionOptions) !State {
	directory := service.directory()!
	guard := acquire(directory)!
	defer { guard.release() }
	return transact_locked(service.configuration()!, directory, operation, names,
		TransactionOptions{ ...options, progress: service.progress })
}

pub fn (service Service) plan(operation string, names []string) !Plan {
	directory := service.directory()!
	guard := acquire_reader(directory)!
	defer { guard.release() }
	return preview_plan_locked(service.configuration()!, directory, operation, names)
}

pub fn (service Service) review(operation string, names []string) !pkgprotocol.Review {
	directory := service.directory()!
	guard := acquire_reader(directory)!
	defer { guard.release() }
	return review_operation_locked(service.configuration()!, directory, operation, names)
}

pub fn (service Service) rollback(expected string) !State {
	directory := service.directory()!
	guard := acquire(directory)!
	defer { guard.release() }
	return rollback_progress(service.configuration()!, directory, expected, service.progress)
}

pub fn (service Service) collect() ! {
	directory := service.directory()!
	guard := acquire(directory)!
	defer { guard.release() }
	collect_locked(service.configuration()!, directory)!
}

pub fn (service Service) mirror(destination string, names []string) ! {
	directory := service.directory()!
	guard := acquire(directory)!
	defer { guard.release() }
	mirror_export(service.configuration()!, directory, destination, names, MirrorOptions{ progress: service.progress })!
}

fn (service Service) installed_locked(directory string, verify bool) !State {
	config := service.configuration()!
	state := read_state(directory, config.architecture)!
	if verify {
		for installed in state.packages {
			for file in installed.package.files {
				path := directory + '/generations/' + state.generation.str() + '/apps/' + installed.package.id + '/' + file.path
				if !verified_file(path, file) {
					return error('${installed.package.id}: installed payload verification failed: ${file.path}')
				}
			}
		}
	}
	return state
}

fn (service Service) installed(verify bool) !State {
	directory := service.directory()!
	if os.exists(directory + '/lock') || os.is_link(directory + '/lock') {
		guard := acquire_reader(directory)!
		defer { guard.release() }
		return service.installed_locked(directory, verify)
	}
	// A fresh image's status does not create administrator-owned package state.
	return service.installed_locked(directory, verify)
}

pub fn (service Service) state() !State {
	return service.installed(false)
}

pub fn (service Service) verify() !State {
	return service.installed(true)
}

fn (service Service) prepare_launch(id string) !(Config, State, int) {
	directory := service.directory()!
	guard := acquire_reader(directory)!
	defer { guard.release() }
	config := service.configuration()!
	if os.geteuid() == 0 { return config, State{}, -1 }
	state, lease := generation_lease(directory, config.architecture, id)!
	return config, state, lease
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
	config, state, lease := service.prepare_launch(id)!
	if lease < 0 {
		// The ordinary child takes a new lock and rechecks trust. Do not hold the
		// parent's lock while waiting for the child or its generation lease.
		return run_in_session_request(config, id, input)
	}
	defer { C.close(lease) }
	return run_leased_mode(config, state_directory(service.root), state, id, input)
}
