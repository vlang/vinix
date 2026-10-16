// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import encoding.utf8
import tools.packages.pkgprotocol

fn save_deployment_snapshot_locked(service Service, directory string, path string, names []string) !pkgprotocol.DeploymentSnapshotSaved {
	config := service.configuration()!; defer { close_decoded_configuration(config) }
	current := read_state(directory, config.architecture)!
	defer { if current.generation != 0 { close_decoded_state(current) } }
	plan := installed_deployment_plan(current, names)!
	defer { unsafe { for root in plan.requested { root.free() }; (&array(&plan.requested)).free(); (&array(&plan.packages)).free() } }
	mut document := owned_deployment_lock(config.architecture, plan)!; defer { document.close() }
	text := encode_deployment_lock(document, true)!; defer { unsafe { text.free() } }
	mut saved := pkgprotocol.DeploymentSnapshotSaved{ generation: current.generation, architecture: config.architecture.clone(),
		destination: path.clone(), sha256: index_digest(text), roots: u64(document.packages.len), packages: u64(document.locked.len) }
	mut accepted := false
	defer { if !accepted { saved.close() } }
	saved.validate()!
	atomic_write_new(path, text)!
	accepted = true
	return saved
}

// Capture one installed generation and publish only to a new user-selected file.
// No catalog, cache objects, replay history, trust enrollment or policy changes.
pub fn (service Service) save_deployment_snapshot(path string, names []string) !pkgprotocol.DeploymentSnapshotSaved {
	if path == '' || !printable(path, 4096) || !utf8.validate_str(path) { return error('deployment snapshot requires a printable UTF-8 new-file path of at most 4096 bytes') }
	directory := service.directory()!; defer { unsafe { directory.free() } }
	if state_requires_lock(directory) {
		guard := acquire_reader(directory)!; defer { guard.release() }
		return save_deployment_snapshot_locked(service, directory, path, names)
	}
	return save_deployment_snapshot_locked(service, directory, path, names)
}
