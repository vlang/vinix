// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import json2
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
	return service.refresh_selected('', '')
}

// Refresh one configured source. Every other source must have a current,
// authenticated snapshot for its exact configured identity.
pub fn (service Service) refresh_repository(id string) !Catalog {
	if !identifier(id) { return error('invalid repository ID') }
	return service.refresh_selected(id, '')
}

// Refresh authenticated metadata and cache local objects under the currently
// enrolled identity. The media path is used only during this call.
pub fn (service Service) import_repository_media(id string, source string) !Catalog {
	sources := [RepositoryMediaSource{ id: id, directory: source }]
	defer { unsafe { sources.free() } }
	return service.import_repository_media_batch(sources)
}

// Authenticate all selected publishers together before saving their shared
// catalog and replay floors. Omitted publishers keep their current snapshots.
pub fn (service Service) import_repository_media_batch(sources []RepositoryMediaSource) !Catalog {
	if sources.len == 0 || sources.len > max_image_repository_indexes {
		return error('offline media import requires at least one repository and directory pair')
	}
	mut selected := map[string]bool{}
	defer { unsafe { selected.free() } }
	for source in sources {
		if !identifier(source.id) { return error('invalid repository ID') }
		if !source.directory.starts_with('/') || !printable(source.directory, 4096) {
			return error('offline repository media requires an absolute directory')
		}
		if source.id in selected { return error('duplicate offline media repository: ${source.id}') }
		selected[source.id] = true
	}
	return service.import_repository_media_sources(sources, '', none)
}

// Import enrolled repositories found directly inside an exported bundle.
pub fn (service Service) import_repository_media_bundle(source string) !Catalog {
	if !source.starts_with('/') || !printable(source, 4096) {
		return error('offline media bundle requires an absolute directory')
	}
	return service.import_repository_media_sources([], source, none)
}

// Import exactly the media named by an independently verified ISO receipt.
pub fn (service Service) import_repository_media_bundle_with_receipt(source string, path string, expected_sha256 string) !Catalog {
	catalog, mut result := service.import_repository_media_bundle_result(source, path, expected_sha256)!
	result.close()
	return catalog
}

// Return the verified digests from the same receipt used to publish the catalog.
pub fn (service Service) import_repository_media_bundle_result(source string, path string, expected_sha256 string) !(Catalog, pkgprotocol.MediaImportResult) {
	if !source.starts_with('/') || !printable(source, 4096) || !path.starts_with('/')
		|| !printable(path, 4096) || !digest_valid(expected_sha256) {
		return error('offline media receipt import requires absolute media and receipt paths and a SHA-256 digest')
	}
	text := read_metadata(path)!
	defer { unsafe { text.free() } }
	digest := index_digest(text)
	defer { unsafe { digest.free() } }
	if digest != expected_sha256 { return error('ISO package receipt SHA-256 differs from the expected digest') }
	receipt := json2.decode[IsoPackageReceipt](text)!
	defer { receipt.close_decoded() }
	if receipt.format != 1 || !digest_valid(receipt.iso_sha256) || !digest_valid(receipt.configuration_sha256)
		|| !digest_valid(receipt.deployment_sha256) || receipt.applications.len == 0
		|| receipt.publishers.len == 0 || receipt.publishers.len > max_image_repository_indexes {
		return error('offline media import requires an ISO package receipt with applications and bundled publishers')
	}
	catalog := service.import_repository_media_sources([], source, receipt)!
	return catalog, pkgprotocol.MediaImportResult{
		receipt_sha256: digest.clone()
		deployment_sha256: receipt.deployment_sha256.clone()
	}
}

fn (service Service) import_repository_media_sources(sources []RepositoryMediaSource, bundle string, receipt ?IsoPackageReceipt) !Catalog {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire(directory)!
	defer { guard.release() }
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	for source in sources {
		if !config.repositories.any(it.id == source.id) { return error('${source.id}: repository is not configured') }
	}
	mut batch := RepositoryMediaBatch{ receipt: receipt }
	defer { batch.close() }
	if bundle != '' {
		batch.open_bundle(bundle, config)!
	} else {
		for source in sources { batch.sources[source.id] = open_repository_media(source.directory)! }
	}
	return refresh_progress_from(config, directory, '', unsafe { &batch }, service.progress)
}

// Refuse a different URL or key for a previously displayed repository ID.
pub fn (service Service) refresh_repository_with_identity(id string, fingerprint string) !Catalog {
	if !identifier(id) { return error('invalid repository ID') }
	if !digest_valid(fingerprint) { return error('invalid repository identity fingerprint') }
	return service.refresh_selected(id, fingerprint)
}

fn check_repository_refresh_identity(config Config, id string, fingerprint string) ! {
	for repository in config.repositories {
		if repository.id != id { continue }
		actual := pkgprotocol.repository_refresh_fingerprint(pkgprotocol.Repository{
			id: repository.id, url: repository.url, public_key: repository.public_key
		})
		defer { free_owned_string(actual) }
		if actual == fingerprint { return }
		break
	}
	return error('${id}: repository identity changed; reload the repository list and review the current URL and publisher key')
}

fn (service Service) refresh_selected(id string, fingerprint string) !Catalog {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire(directory)!
	defer { guard.release() }
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	if fingerprint != '' { check_repository_refresh_identity(config, id, fingerprint)! }
	return refresh_progress(config, directory, id, service.progress)
}

pub fn (service Service) transact(operation string, names []string, options TransactionOptions) !State {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire(directory)!
	defer { guard.release() }
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	return transact_locked(config, directory, operation, names,
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
	defer { unsafe { directory.free() } }
	guard := acquire(directory)!
	defer { guard.release() }
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	return rollback_progress(config, directory, expected, service.progress)
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
	return run_leased_mode_with_lease(prepared.config, prepared.directory, prepared.state, id, input, prepared.lease)
}
