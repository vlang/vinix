// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.pkgprotocol

fn compare_deployment(expected DeploymentLock, installed DeploymentLock, generation u64, digest string) !pkgprotocol.DeploymentAudit {
	mut targets := map[string]int{}; mut actual := map[string]int{}
	mut ids := []string{cap: expected.locked.len + installed.locked.len}
	defer { unsafe { targets.free(); actual.free(); ids.free() } }
	for i, pin in expected.locked { targets[pin.id] = i; ids << pin.id }
	for root in expected.packages { if root !in targets { return error('deployment audit root is absent from its locked records: ${root}') } }
	for i, pin in installed.locked { actual[pin.id] = i; if pin.id !in targets { ids << pin.id } }
	ids.sort()
	mut rows := []pkgprotocol.DeploymentAuditRow{cap: ids.len}
	mut accepted := false
	defer { if !accepted { mut partial := pkgprotocol.DeploymentAudit{ rows: rows }; partial.close() } }
	mut matches := true
	absent := DeploymentPackage{ id: '', version: '', architecture: '', repository: '', public_key: '', minimum_sequence: 0, metadata_sha256: '' }
	for id in ids {
		wanted := if id in targets { expected.locked[targets[id]] } else { absent }
		found := if id in actual { installed.locked[actual[id]] } else { absent }
		mut differences := []string{cap: 7}
		if wanted.id != '' && found.id != '' {
			if wanted.architecture != found.architecture { differences << 'architecture'.clone() }
			if wanted.metadata_sha256 != found.metadata_sha256 { differences << 'metadata_sha256'.clone() }
			if wanted.public_key != found.public_key { differences << 'public_key'.clone() }
			if wanted.repository != found.repository { differences << 'repository'.clone() }
			if (id in expected.packages) != (id in installed.packages) { differences << 'requested'.clone() }
			if found.minimum_sequence < wanted.minimum_sequence { differences << 'sequence'.clone() }
			if wanted.version != found.version { differences << 'version'.clone() }
		}
		status := if wanted.id == '' { 'unexpected' } else if found.id == '' { 'missing' }
			else if differences.len > 0 { 'changed' } else { 'match' }
		if status != 'match' { matches = false }
		rows << pkgprotocol.DeploymentAuditRow{ id: id.clone(), status: status.clone(),
			expected_version: wanted.version.clone(), installed_version: found.version.clone(), differences: differences }
	}
	report := pkgprotocol.DeploymentAudit{ generation: generation, architecture: installed.architecture.clone(),
		deployment_sha256: digest.clone(), matches: matches, rows: rows }
	report.validate() or { mut discarded := report; discarded.close(); accepted = true; return err }
	accepted = true
	return report
}

fn audit_deployment_locked(service Service, directory string, path string) !pkgprotocol.DeploymentAudit {
	config := service.configuration()!; defer { close_decoded_configuration(config) }
	// Read exactly once. The report's digest identifies the same bytes decoded
	// here, even if the pathname is replaced before the comparison finishes.
	text := read_metadata(path)!; defer { unsafe { text.free() } }
	mut expected := decode_deployment(text, config.architecture)!; defer { expected.close() }
	if expected.format != 2 { return error('deployment audit requires an exact format-2 lock; export deployment-lock or deployment-snapshot first') }
	current := read_state(directory, config.architecture)!
	defer { if current.generation != 0 { close_decoded_state(current) } }
	mut installed := owned_deployment_lock(config.architecture, Plan{ requested: current.requested, packages: current.packages })!
	defer { installed.close() }
	digest := index_digest(text); defer { unsafe { digest.free() } }
	return compare_deployment(expected, installed, current.generation, digest)
}

// Inspect one coherent installed generation without catalog, cache, replay or
// payload access. This is drift detection, not trust or integrity attestation.
pub fn (service Service) audit_deployment(path string) !pkgprotocol.DeploymentAudit {
	directory := service.directory()!; defer { unsafe { directory.free() } }
	if state_requires_lock(directory) {
		guard := acquire_reader(directory)!; defer { guard.release() }
		return audit_deployment_locked(service, directory, path)
	}
	return audit_deployment_locked(service, directory, path)
}
