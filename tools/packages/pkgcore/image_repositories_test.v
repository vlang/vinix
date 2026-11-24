// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
$if macos || ios {
	fn C.mkfifo(&char, u16) int
} $else {
	fn C.mkfifo(&char, u32) int
}
struct ImageCaptureLimit { current u64 maximum u64 }

fn image_bundle_fixture(restricted bool) !(string, string) {
	work := os.real_path(os.temp_dir()) + '/vinix-image-bundle-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work, mode: 0o700)!
	key := keygen(work + '/seed')!
	os.mkdir_all(work + '/payload/share')!
	os.write_file(work + '/payload/share/data', 'authenticated offline application data')!
	for id in ['support', 'app']! {
		manifest := Package{ id: id, version: '1.0.0', architecture: 'all', name: 'Offline ' + id,
			description: 'Reviewed image repository fixture', license: if restricted { 'Company-EULA' } else { 'MIT' },
			proprietary: restricted, firmware: restricted, kind: 'data',
			dependencies: if id == 'app' { [Dependency{ id: 'support', minimum: '1.0.0' }] } else { []Dependency{} } }
		os.write_file(work + '/manifest.json', json2.encode(manifest))!
		pack(work + '/manifest.json', work + '/payload', work + '/workspace')!
	}
	publish_release(work + '/workspace', 'native', work + '/seed', 1, time.now().unix() + 3600, work + '/bundle/native')!
	return work, key
}
fn image_bundle_configuration(work string, architecture string, key string, policy Policy) !string {
	path := work + '/config-' + architecture + '.json'
	os.write_file(path, json2.encode(Config{ architecture: architecture, policy: policy,
		repositories: [Repository{ id: 'native', url: 'file://' + image_repositories_path + '/native', public_key: key }] }) + '\n')!
	return path
}
fn image_bundle_refused(configuration &ImageConfiguration, source string) {
	if mut plan := configuration.prepare_repositories(source) { plan.close(); assert false }
	else { message := err.msg(); unsafe { message.free(); err.free() } }
}
fn image_bundle_no_space(_ string) !u64 { return 0 }
fn image_bundle_corrupt_stage(phase string, path string) ! {
	if phase != 'staged' { return }
	for object in os.ls(path + '/native/objects')! { os.write_file(path + '/native/objects/' + object, 'corrupt')!; break }
}
fn image_bundle_race_target(phase string, path string) ! {
	if phase == 'staged' { os.mkdir(os.dir(path) + '/repositories')!; os.write_file(os.dir(path) + '/repositories/keep', 'concurrent owner data')! }
}
fn image_bundle_capture_refusal(_ string, _ string) ! { return error('injected capture interruption') }

fn image_bundle_replace_failed_stage(phase string, stage string) ! {
	if phase != 'staged' { return }
	parent := os.dir(stage)
	os.rename(stage, parent + '/saved-stage')!
	os.mkdir(stage)!
	os.write_file(stage + '/keep', 'replacement must survive')!
	return error('injected image export refusal')
}

fn test_image_bundle_close_preserves_replaced_capture_root() {
	work, key := image_bundle_fixture(false)!; defer { os.rmdir_all(work) or {} }
	root := work + '/image'; os.mkdir(root)!
	source := image_bundle_configuration(work, 'aarch64', key, Policy{})!
	mut configuration := prepare_image_configuration(root, 'aarch64', source)!; defer { configuration.close() }
	mut plan := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
	capture := plan.capture.clone()
	os.rename(capture, work + '/saved-capture')!
	os.mkdir(capture)!
	defer { os.rmdir_all(capture) or {} }
	os.write_file(capture + '/keep', 'replacement must survive')!
	plan.close(); plan.close()
	preserved := os.read_file(capture + '/keep') or { '' }
	println('IMAGE CAPTURE baseline close replacement-preserved=' + (preserved == 'replacement must survive').str())
	assert preserved == 'replacement must survive' && os.is_dir(work + '/saved-capture/native') && os.ls(root)!.len == 0
}

fn test_image_bundle_failed_publication_preserves_replaced_stage_root() {
	work, key := image_bundle_fixture(false)!; defer { os.rmdir_all(work) or {} }
	root := work + '/image'; os.mkdir(root)!
	source := image_bundle_configuration(work, 'aarch64', key, Policy{})!
	mut configuration := prepare_image_configuration(root, 'aarch64', source)!; defer { configuration.close() }
	mut plan := unsafe { &configuration }.prepare_repositories(work + '/bundle')!; defer { plan.close() }
	mut refused := false
	unsafe { &plan }.publish_with(ImageRepositoriesOptions{ checkpoint: image_bundle_replace_failed_stage }) or { refused = err.msg().contains('injected image export refusal') }
	parent := root + '/usr/share/vinix-packages'
	stages := os.ls(parent)!.filter(it.starts_with('.vinix-image-repositories-'))
	preserved := stages.len == 1 && os.read_file(parent + '/' + stages[0] + '/keep') or { '' } == 'replacement must survive'
	println('IMAGE CAPTURE baseline publication refused=' + refused.str() + ' replacement-preserved=' + preserved.str())
	assert refused && preserved && os.is_dir(parent + '/saved-stage/native') && !os.exists(root + image_repositories_path)
}

fn image_bundle_test_scratch() string { return os.getenv('VINIX_IMAGE_CAPTURE_CASE') + '/scratch' }

fn image_bundle_substitute(phase string, stage string) ! {
	if phase != os.getenv('VINIX_IMAGE_CAPTURE_PHASE') { return }
	work := os.getenv('VINIX_IMAGE_CAPTURE_CASE')
	if os.exists(work + '/stage-path') { return }
	os.write_file(work + '/stage-path', stage)!
	kind := os.getenv('VINIX_IMAGE_CAPTURE_KIND')
	if kind == 'parent' { os.rename(os.dir(stage), work + '/saved-parent')!; os.mkdir(os.dir(stage))! }
	else { os.rename(stage, work + '/saved-stage')! }
	match kind {
		'directory', 'parent' { os.mkdir(stage)!; os.write_file(stage + '/keep', 'preserved')! }
		'alias' { os.symlink(work + '/outside', stage)! }
		'dangling' { os.symlink(work + '/absent', stage)! }
		'fifo' { assert C.mkfifo(stage.str, 0o600) == 0 }
		'file' { os.write_file(stage, 'preserved')! }
		'missing' {}
		'clone' { os.cp_all(work + '/saved-stage', stage, true)! }
		else { panic('unknown image capture substitution') }
	}
	if os.getenv('VINIX_IMAGE_CAPTURE_FAIL') == 'yes' { return error('injected image capture refusal') }
}

fn image_bundle_assert_replacement(work string, kind string, index string) ! {
	stage := os.read_file(work + '/stage-path')!
	if kind in ['directory', 'parent']! { assert os.read_file(stage + '/keep')! == 'preserved' }
	if kind == 'file' { assert os.read_file(stage)! == 'preserved' }
	if kind == 'alias' { assert os.readlink(stage)! == work + '/outside' }
	if kind == 'dangling' { assert os.readlink(stage)! == work + '/absent' }
	if kind == 'fifo' { assert os.lstat(stage)!.mode & 0o170000 == 0o010000 }
	if kind == 'missing' { assert !os.exists(stage) && !os.is_link(stage) }
	if kind == 'clone' { assert os.read_file(stage + '/native/index.json')! == index }
	if kind == 'parent' { assert os.ls(work + '/saved-parent')!.len == 0 }
	else { assert os.read_file(work + '/saved-stage/native/index.json')! == index }
	assert os.read_file(work + '/outside/keep')! == 'preserved' && os.stat(work + '/outside')!.mode & 0o777 == 0o700
}

fn test_image_bundle_capture_and_publication_substitutions_preserve_inputs_and_retry() {
	mut original := ImageCaptureLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, unsafe { voidptr(&original) }) == 0
	limit := ImageCaptureLimit{ current: 32, maximum: original.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { voidptr(&limit) }) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, unsafe { voidptr(&original) }) == 0 }
	defer { for name in ['VINIX_IMAGE_CAPTURE_CASE', 'VINIX_IMAGE_CAPTURE_PHASE', 'VINIX_IMAGE_CAPTURE_KIND', 'VINIX_IMAGE_CAPTURE_FAIL']! { os.unsetenv(name) } }
	mut cases := 0
	for architecture in ['aarch64', 'x86_64']! {
		work, key := image_bundle_fixture(false)!; defer { os.rmdir_all(work) or {} }
		source := image_bundle_configuration(work, architecture, key, Policy{})!
		configuration_text := os.read_file(source)!
		index := os.read_file(work + '/bundle/native/index.json')!
		for phase in ['captured', 'prepared', 'staged']! {
			for kind in ['directory', 'alias', 'dangling', 'fifo', 'file', 'missing', 'clone', 'parent']! {
				for fail in if phase == 'prepared' { ['no'] } else { ['yes', 'no'] } {
					case := work + '/case-' + cases.str()
					os.mkdir_all(case + '/scratch')!; os.mkdir(case + '/image')!; os.mkdir(case + '/outside')!
					os.chmod(case + '/outside', 0o700)!; os.write_file(case + '/outside/keep', 'preserved')!
					for name, value in {'VINIX_IMAGE_CAPTURE_CASE': case, 'VINIX_IMAGE_CAPTURE_PHASE': phase, 'VINIX_IMAGE_CAPTURE_KIND': kind, 'VINIX_IMAGE_CAPTURE_FAIL': fail} { os.setenv(name, value, true) }
					mut configuration := prepare_image_configuration(case + '/image', architecture, source)!
					mut plan := ImageRepositories{}
					mut message := ''
					plan = unsafe { &configuration }.prepare_repositories_with(work + '/bundle', ImageRepositoriesOptions{ temporary_directory: image_bundle_test_scratch, checkpoint: image_bundle_substitute }) or { message = err.msg(); ImageRepositories{} }
					if phase == 'captured' { assert message != '' }
					else {
						assert message == ''
						if phase == 'prepared' {
							image_bundle_substitute('prepared', plan.capture)!
							mut refused := false
							unsafe { &configuration }.check_repositories(unsafe { &plan }) or { refused = true }
							assert refused && os.ls(case + '/image')!.len == 0
						}
						unsafe { &plan }.publish_with(ImageRepositoriesOptions{ checkpoint: image_bundle_substitute }) or { message = err.msg() }
						assert message != '' && !os.exists(case + '/image' + image_repositories_path)
						if phase == 'staged' {
							assert unsafe { &plan }.publish()!
							assert os.read_file(case + '/image' + image_repositories_path + '/native/index.json')! == index
						}
						mut cleanup := ''
						plan.retire() or { cleanup = err.msg() }
						assert (cleanup != '') == (phase == 'prepared' && kind != 'parent')
						if cleanup != '' { assert cleanup.contains('capture cleanup refused') && cleanup.contains('retain recovery data') }
						assert plan.capture == '' && plan.capture_stage.parent == -1 && plan.capture_stage.root == -1
						plan.close(); plan.close()
					}
					if phase != 'prepared' && fail == 'yes' { assert message.contains('injected image capture refusal') }
					if phase != 'prepared' && kind != 'parent' { assert message.contains('cleanup refused') }
					image_bundle_assert_replacement(case, kind, index)!
					if phase != 'staged' {
						assert os.ls(case + '/image')!.len == 0
						mut retry := unsafe { &configuration }.prepare_repositories_with(work + '/bundle', ImageRepositoriesOptions{ temporary_directory: image_bundle_test_scratch })!
						assert unsafe { &retry }.publish()!
						retry.retire()!; retry.close()
					}
					configuration.close()
					assert os.read_file(source)! == configuration_text && os.read_file(work + '/bundle/native/index.json')! == index
					assert !os.exists(case + '/image/var') && !os.exists(case + '/image/etc')
					os.rmdir_all(case)!
					cases++
				}
			}
		}
	}
	assert cases == 80
	println('IMAGE CAPTURE 80 capture/prepared/publication root and parent substitutions preserve replacements, recovery, trust and source; checked retirement and retry under 32 descriptors both targets PASS')
}

fn image_bundle_flush_refusal(_ int) int { return -1 }

fn image_bundle_replace_capture_while_staged(phase string, _ string) ! {
	if phase != 'staged' { return }
	path := os.getenv('VINIX_IMAGE_LATE_CAPTURE')
	os.rename(path, path + '-saved')!
	os.cp_all(path + '-saved', path, true)!
}

fn test_image_bundle_rechecks_original_capture_after_publication_copy() {
	defer { os.unsetenv('VINIX_IMAGE_LATE_CAPTURE') }
	for architecture in ['aarch64', 'x86_64']! {
		work, key := image_bundle_fixture(false)!; defer { os.rmdir_all(work) or {} }
		root := work + '/image'; os.mkdir(root)!
		source := image_bundle_configuration(work, architecture, key, Policy{})!
		mut configuration := prepare_image_configuration(root, architecture, source)!; defer { configuration.close() }
		mut plan := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
		capture := plan.capture.clone()
		defer { os.rmdir_all(capture) or {}; os.rmdir_all(capture + '-saved') or {} }
		os.setenv('VINIX_IMAGE_LATE_CAPTURE', capture, true)
		mut message := ''
		unsafe { &plan }.publish_with(ImageRepositoriesOptions{ checkpoint: image_bundle_replace_capture_while_staged }) or { message = err.msg() }
		assert message.contains('staging root identity changed') && !os.exists(root + image_repositories_path)
		assert os.ls(root + '/usr/share/vinix-packages')!.len == 0
		mut refused := false
		plan.retire() or { refused = true }
		assert refused && os.is_dir(capture + '/native') && os.is_dir(capture + '-saved/native')
		plan.close()
	}
	println('IMAGE CAPTURE identical capture replacement after publication copy refuses, retires only owned output scratch and preserves both capture trees PASS')
}

fn test_image_bundle_post_publication_flush_failure_retains_output_and_capture_retirement_refuses_unsafe_root() {
	work, key := image_bundle_fixture(false)!; defer { os.rmdir_all(work) or {} }
	root := work + '/image'; os.mkdir(root)!
	source := image_bundle_configuration(work, 'aarch64', key, Policy{})!
	mut configuration := prepare_image_configuration(root, 'aarch64', source)!; defer { configuration.close() }
	mut plan := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
	mut message := ''
	unsafe { &plan }.publish_with(ImageRepositoriesOptions{ flush: image_bundle_flush_refusal }) or { message = err.msg() }
	assert message.contains('published at') && message.contains('directory flush failed')
	assert os.read_file(root + image_repositories_path + '/native/index.json')! == os.read_file(work + '/bundle/native/index.json')!
	assert !unsafe { &plan }.publish()!
	capture := plan.capture.clone()
	os.chmod(capture, 0o777)!
	mut refused := false
	plan.retire() or { refused = err.msg().contains('capture cleanup refused') }
	assert refused && plan.capture == '' && os.is_dir(capture + '/native')
	plan.close(); plan.retire()!
	os.chmod(capture, 0o700)!; os.rmdir_all(capture)!
	assert os.ls(root + '/usr/share/vinix-packages')! == ['repositories']
	println('IMAGE CAPTURE flush refusal retains complete output; unsafe capture retirement preserves recovery, reports refusal, closes metadata and permits repeated close PASS')
}

fn test_image_bundle_capture_publish_retry_and_real_offline_consumer() {
	for architecture in ['aarch64', 'x86_64']! {
		work, key := image_bundle_fixture(false)!; defer { os.rmdir_all(work) or {} }
		root := work + '/image'; os.mkdir(root)!
		source := image_bundle_configuration(work, architecture, key, Policy{ offline: true, reserve_bytes: 0 })!
		mut configuration := prepare_image_configuration(root, architecture, source)!
		defer { configuration.close() }
		mut plan := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
		capture := plan.capture.clone()
		defer { unsafe { capture.free() } }
		os.rmdir_all(work + '/bundle')!
		assert os.ls(root)!.len == 0
		assert unsafe { &plan }.publish()!
		assert unsafe { &configuration }.publish()!
		plan.close(); plan.close()
		assert !os.exists(capture)
		bytes := os.read_file(root + '/etc/vinix-packages/config.json')!
		assert bytes == os.read_file(source)!
		assert !os.exists(root + '/var')
		// A host consumer points at the published image export; the image's own
		// file URL has its intended meaning after booting the target filesystem.
		consumer := work + '/consumer'; os.mkdir_all(consumer + '/etc/vinix-packages')!
		os.write_file(consumer + '/etc/vinix-packages/config.json', json2.encode(Config{ architecture: architecture,
			policy: Policy{ offline: true, reserve_bytes: 0 }, repositories: [Repository{ id: 'native',
			url: 'file://' + root + image_repositories_path + '/native', public_key: key }] }))!
		service := Service{ root: consumer }
		assert service.refresh()!.packages.len == 2
		mut review := service.review('install', ['app'])!
		service.transact('install', ['app'], TransactionOptions{ expected_review: review.fingerprint })!
		review.close()
		mut state := service.verify()!
		assert state.packages.len == 2 && state.requested == ['app']
		state.close()
		mut existing := prepare_image_configuration(root, architecture, work + '/missing')!
		defer { existing.close() }
		mut same := unsafe { &existing }.prepare_repositories(root + image_repositories_path)!
		assert !unsafe { &same }.publish()!
		same.close()
		assert !unsafe { &existing }.publish()!
		assert os.read_file(root + '/etc/vinix-packages/config.json')! == bytes
	}
	println('PACKAGE IMAGE BUNDLE captured signed closure atomic publication offline dependency install both architectures PASS')
}

fn test_image_bundle_bootstraps_a_configured_https_publisher_offline() {
	for architecture in ['aarch64', 'x86_64']! {
		work, key := image_bundle_fixture(false)!
		defer { os.rmdir_all(work) or {} }
		root := work + '/image'
		os.mkdir(root)!
		repository := Repository{ id: 'native', url: 'https://packages.example.invalid/release', public_key: key }
		config := Config{ architecture: architecture, repositories: [repository],
			policy: Policy{ offline: architecture == 'x86_64', reserve_bytes: 0 } }
		source := work + '/https-config.json'
		os.write_file(source, json2.encode(config) + '\n')!
		mut configuration := prepare_image_configuration(root, architecture, source)!
		defer { configuration.close() }
		mut plan := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
		defer { plan.close() }
		assert unsafe { &plan }.publish()!
		assert unsafe { &configuration }.publish()!
		plan.retire()!
		assert !os.exists(state_directory(root))
		service := Service{ root: root, offline: !config.policy.offline }
		mut catalog := service.refresh()!
		assert catalog.packages.len == 2
		catalog.close()
		directory := state_directory(root)
		assert read_snapshots(directory)![0].repository == repository
		bundle := root + image_repositories_path + '/native'
		objects := bundle + '/objects'
		os.rename(objects, work + '/saved-objects')!
		os.symlink(work + '/saved-objects', objects)!
		if _ := service.transact('install', ['app'], TransactionOptions{}) { assert false }
		else { assert err.msg().contains('controlled ordinary directory') }
		assert service.state()!.generation == 0
		os.rm(objects)!
		os.rename(work + '/saved-objects', objects)!
		mut review := service.review('install', ['app'])!
		defer { review.close() }
		mut installed := service.transact('install', ['app'], TransactionOptions{ expected_review: review.fingerprint })!
		defer { installed.close() }
		assert installed.packages.len == 2 && installed.requested == ['app']
		assert installed.packages.all(it.public_key == key && it.repository == 'native' && it.sequence == 1)
		assert load_config(root)! == config
		old_export := work + '/old-export'
		// A symlink to another controlled export is still an invalid image bundle.
		os.rename(bundle, old_export)!
		os.symlink(old_export, bundle)!
		if _ := service.refresh() { assert false } else { assert err.msg().contains('controlled ordinary directory') }
		os.rm(bundle)!
		publish_release(work + '/workspace', 'native', work + '/seed', 2, time.now().unix() + 3600, bundle)!
		mut refreshed := service.refresh()!
		refreshed.close()
		catalog_bytes := os.read_file(directory + '/catalog.json')!
		history_bytes := os.read_file(directory + '/trust-history.json')!
		assert read_snapshots(directory)![0].repository == repository
		os.rename(bundle, work + '/new-export')!
		os.rename(old_export, bundle)!
		if _ := service.refresh() { assert false } else { assert err.msg().contains('retained trust history') }
		assert os.read_file(directory + '/catalog.json')! == catalog_bytes
		assert os.read_file(directory + '/trust-history.json')! == history_bytes
		assert load_config(root)! == config
	}
	println('PACKAGE IMAGE BUNDLE HTTPS publisher installs offline without trust changes and refuses replay on both targets PASS')
}

fn test_repository_media_import_keeps_https_identity_and_publishes_only_after_cache_verification() {
	work, key := image_bundle_fixture(false)!
	defer { os.rmdir_all(work) or {} }
	root := work + '/installed'
	config_path := root + '/etc/vinix-packages/config.json'
	os.mkdir_all(os.dir(config_path))!
	repo := Repository{ id: 'native', url: 'https://packages.example.invalid/release', public_key: key }
	config := Config{ architecture: 'aarch64', repositories: [repo], policy: Policy{ allowed: ['app', 'support'] } }
	configuration := json2.encode(config) + '\n'
	os.write_file(config_path, configuration)!
	service := Service{ root: root }
	first := work + '/bundle/native'
	mut catalog := service.import_repository_media('native', first)!
	assert catalog.packages.len == 2
	catalog.close()
	directory := state_directory(root)
	assert read_snapshots(directory)![0].repository == repo
	assert service.state()!.generation == 0
	old_catalog := os.read_file(directory + '/catalog.json')!
	old_history := os.read_file(directory + '/trust-history.json')!

	mut hashes := map[string]string{}
	for id in ['app', 'restricted']! {
		path := work + '/payload/share/data'
		os.write_file(path, 'second signed release ' + id)!
		hashes[id] = hash_file(path)!
		os.write_file(work + '/manifest.json', json2.encode(Package{ id: id, architecture: 'all',
			version: '2.0.0', kind: 'data', name: id, license: 'MIT',
			dependencies: if id == 'app' { [Dependency{ id: 'support' }] } else { []Dependency{} } }))!
		pack(work + '/manifest.json', work + '/payload', work + '/workspace')!
	}
	second := work + '/second release'
	publish_release(work + '/workspace', 'native', work + '/seed', 2, time.now().unix() + 3600, second)!
	object := second + '/objects/' + hashes['app']!
	bytes := os.read_file(object)!
	os.write_file(object, 'x'.repeat(bytes.len))!
	if _ := service.import_repository_media('native', second) { assert false }
	else { assert err.msg().contains('payload checksum or size mismatch') }
	assert os.read_file(directory + '/catalog.json')! == old_catalog
	assert os.read_file(directory + '/trust-history.json')! == old_history
	assert !os.exists(directory + '/objects/' + hashes['app']!)
	assert os.read_file(config_path)! == configuration
	assert service.state()!.generation == 0

	os.write_file(object, bytes)!
	mut updated := service.import_repository_media('native', second)!
	assert updated.packages.any(it.package.id == 'restricted')
	updated.close()
	assert os.is_file(directory + '/objects/' + hashes['app']!)
	assert !os.exists(directory + '/objects/' + hashes['restricted']!)
	assert read_snapshots(directory)![0].repository == repo
	new_catalog := os.read_file(directory + '/catalog.json')!
	new_history := os.read_file(directory + '/trust-history.json')!
	if _ := service.import_repository_media('native', first) { assert false }
	else { assert err.msg().contains('retained trust history') }
	assert os.read_file(directory + '/catalog.json')! == new_catalog
	assert os.read_file(directory + '/trust-history.json')! == new_history

	// Disconnect the media before reviewing and installing its cached objects.
	os.rename(second, work + '/disconnected')!
	offline := Service{ root: root, offline: true }
	mut review := offline.review('install', ['app'])!
	defer { review.close() }
	mut installed := offline.transact('install', ['app'], TransactionOptions{ expected_review: review.fingerprint })!
	defer { installed.close() }
	assert installed.packages.any(it.package.id == 'app' && it.package.version == '2.0.0' && it.sequence == 2)
	assert os.read_file(config_path)! == configuration
	println('REPOSITORY MEDIA keeps HTTPS identity, checks replay and objects, caches policy-allowed payloads and installs after disconnect PASS')
}

fn test_repository_media_batch_authenticates_and_acquires_before_catalog_publication() {
	work, key := image_bundle_fixture(false)!
	defer { os.rmdir_all(work) or {} }
	second_key := keygen(work + '/second-seed')!
	second_payload := work + '/second-payload'
	os.mkdir_all(second_payload + '/share')!
	os.cp(work + '/payload/share/data', second_payload + '/share/common')!
	unique := second_payload + '/share/extra'
	os.write_file(unique, 'payload held by the second publisher')!
	os.write_file(work + '/manifest.json', json2.encode(Package{ id: 'extra', architecture: 'all',
		version: '1.0.0', kind: 'data', name: 'Extra', license: 'MIT' }))!
	pack(work + '/manifest.json', second_payload, work + '/second-workspace')!
	second := work + '/bundle/organization'
	publish_release(work + '/second-workspace', 'organization', work + '/second-seed', 2,
		time.now().unix() + 3600, second)!
	root := work + '/installed'
	config_path := root + '/etc/vinix-packages/config.json'
	os.mkdir_all(os.dir(config_path))!
	repositories := [Repository{ id: 'native', url: 'https://packages.example.invalid/native', public_key: key },
		Repository{ id: 'organization', url: 'https://packages.example.invalid/organization', public_key: second_key }]
	config := json2.encode(Config{ architecture: 'aarch64', repositories: repositories }) + '\n'
	os.write_file(config_path, config)!
	service := Service{ root: root }
	first := work + '/bundle/native'
	sources := [RepositoryMediaSource{ id: 'organization', directory: second },
		RepositoryMediaSource{ id: 'native', directory: first }]
	if _ := service.import_repository_media_batch([sources[0], sources[0]]) { assert false }
	else { assert err.msg().contains('duplicate offline media repository') }
	if _ := service.import_repository_media_batch([RepositoryMediaSource{ id: 'unknown', directory: first }]) { assert false }
	else { assert err.msg().contains('repository is not configured') }
	if _ := service.import_repository_media('native', first) { assert false }
	else { assert err.msg().contains('organization: no authenticated cached index') }

	directory := state_directory(root)
	objects := directory + '/objects'
	catalog_path := directory + '/catalog.json'
	history_path := directory + '/trust-history.json'
	signature := second + '/index.sig'
	signed := os.read_file(signature)!
	os.write_file(signature, '0'.repeat(128) + '\n')!
	if _ := service.import_repository_media_batch(sources) { assert false }
	else { assert err.msg().contains('organization: repository signature verification failed') }
	assert os.ls(objects)!.len == 0 && !os.exists(catalog_path) && !os.exists(history_path)
	os.write_file(signature, signed)!

	shared_hash := hash_file(second_payload + '/share/common')!
	unique_hash := hash_file(unique)!
	object := second + '/objects/' + unique_hash
	bytes := os.read_file(object)!
	os.write_file(object, 'x'.repeat(bytes.len))!
	if _ := service.import_repository_media_batch(sources) { assert false }
	else { assert err.msg().contains('payload checksum or size mismatch') }
	assert os.ls(objects)! == [shared_hash]
	assert !os.exists(catalog_path) && !os.exists(history_path)
	assert os.read_file(config_path)! == config && service.state()!.generation == 0

	os.write_file(object, bytes)!
	mut catalog := service.import_repository_media_batch(sources)!
	assert catalog.packages.len == 3
	catalog.close()
	assert os.ls(objects)!.sorted() == [shared_hash, unique_hash].sorted()
	assert read_snapshots(directory)!.map(it.repository) == repositories
	assert service.state()!.generation == 0
	os.rename(work + '/bundle', work + '/disconnected')!
	offline := Service{ root: root, offline: true }
	mut review := offline.review('install', ['app', 'extra'])!
	defer { review.close() }
	mut installed := offline.transact('install', ['app', 'extra'], TransactionOptions{ expected_review: review.fingerprint })!
	defer { installed.close() }
	assert installed.requested == ['app', 'extra'] && installed.packages.len == 3
	assert installed.packages.any(it.repository == 'organization' && it.public_key == second_key && it.sequence == 2)
	assert os.read_file(config_path)! == config
	println('REPOSITORY MEDIA batch authenticates both publishers before acquisition, retains verified objects after refusal and installs from the repaired offline cache PASS')
}

fn test_online_install_reuses_payloads_from_the_authenticated_image_bundle() {
	for architecture in ['aarch64', 'x86_64']! {
		work, key := image_bundle_fixture(false)!
		defer { os.rmdir_all(work) or {} }
		root := work + '/image'
		os.mkdir(root)!
		repository := Repository{ id: 'native', url: 'https://127.0.0.1:1/release', public_key: key }
		config := Config{ architecture: architecture, repositories: [repository],
			policy: Policy{ reserve_bytes: 0 } }
		source := work + '/https-config.json'
		os.write_file(source, json2.encode(config) + '\n')!
		mut configuration := prepare_image_configuration(root, architecture, source)!
		defer { configuration.close() }
		mut plan := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
		defer { plan.close() }
		assert unsafe { &plan }.publish()!
		assert unsafe { &configuration }.publish()!
		plan.retire()!
		mut catalog := Service{ root: root, offline: true }.refresh()!
		catalog.close()
		service := Service{ root: root }
		mut review := service.review('install', ['app'])!
		defer { review.close() }
		mut installed := service.transact('install', ['app'], TransactionOptions{ expected_review: review.fingerprint })!
		defer { installed.close() }
		assert installed.generation == 1 && installed.requested == ['app'] && installed.packages.len == 2
		mut verified := service.verify()!
		defer { verified.close() }
		assert verified == installed
		assert load_config(root)! == config
		assert read_snapshots(state_directory(root))![0].repository == repository
	}
	println('PACKAGE IMAGE BUNDLE online installation reuses verified image payloads with inaccessible HTTPS objects PASS')
}

fn test_image_bundle_requires_explicit_trust_exact_export_and_safe_sources() {
	work, key := image_bundle_fixture(false)!; defer { os.rmdir_all(work) or {} }
	root := work + '/image'; os.mkdir(root)!
	source := image_bundle_configuration(work, 'aarch64', key, Policy{})!
	mut configuration := prepare_image_configuration(root, 'aarch64', source)!
	defer { configuration.close() }
	mut empty := unsafe { &configuration }.prepare_repositories('')!
	assert !unsafe { &empty }.publish()!; empty.close(); empty.close()
	for entry in ['seed', '.publisher']! {
		os.write_file(work + '/bundle/native/' + entry, 'must never ship')!
		image_bundle_refused(unsafe { &configuration }, work + '/bundle')
		os.rm(work + '/bundle/native/' + entry)!
	}
	os.mkdir(work + '/bundle/unconfigured')!
	image_bundle_refused(unsafe { &configuration }, work + '/bundle')
	os.rmdir(work + '/bundle/unconfigured')!
	index_path := work + '/bundle/native/index.json'
	index := os.read_file(index_path)!
	os.write_file(index_path, index.replace('Offline app', 'Untrusted app'))!
	image_bundle_refused(unsafe { &configuration }, work + '/bundle')
	os.write_file(index_path, index)!
	objects := os.ls(work + '/bundle/native/objects')!
	object := work + '/bundle/native/objects/' + objects[0]
	original := os.read_file(object)!
	os.write_file(object, 'corrupt')!
	image_bundle_refused(unsafe { &configuration }, work + '/bundle')
	os.write_file(object, original)!
	os.symlink(work + '/bundle', work + '/alias')!
	image_bundle_refused(unsafe { &configuration }, work + '/alias')
	image_bundle_refused(unsafe { &configuration }, work + '/bundle\x00ignored')
	os.chmod(work + '/bundle', 0o777)!
	image_bundle_refused(unsafe { &configuration }, work + '/bundle')
	os.chmod(work + '/bundle', 0o755)!
	os.rename(object, object + '-saved')! // an unexpected object also refuses
	os.symlink(object + '-saved', object)!
	image_bundle_refused(unsafe { &configuration }, work + '/bundle')
	os.rm(object)!; os.rename(object + '-saved', object)!
	os.rename(work + '/bundle/native/objects', work + '/saved-objects')!
	os.symlink(work + '/saved-objects', work + '/bundle/native/objects')!
	image_bundle_refused(unsafe { &configuration }, work + '/bundle')
	os.rm(work + '/bundle/native/objects')!; os.rename(work + '/saved-objects', work + '/bundle/native/objects')!
	assert os.ls(root)!.len == 0
	mut unenrolled := prepare_image_configuration(root, 'aarch64', '')!
	defer { unenrolled.close() }
	image_bundle_refused(unsafe { &unenrolled }, work + '/bundle')
	other_key := keygen(work + '/other-seed')!
	other_source := image_bundle_configuration(work, 'aarch64', other_key, Policy{})!
	mut wrong := prepare_image_configuration(root, 'aarch64', other_source)!
	defer { wrong.close() }
	image_bundle_refused(unsafe { &wrong }, work + '/bundle')
	assert os.ls(root)!.len == 0
}

fn test_image_bundle_license_firmware_and_organization_policy_are_explicit() {
	work, key := image_bundle_fixture(true)!; defer { os.rmdir_all(work) or {} }
	root := work + '/image'; os.mkdir(root)!
	for policy in [Policy{}, Policy{ licenses: ['Company-EULA'] },
		Policy{ licenses: ['Company-EULA'], allow_firmware: true, allowed: ['app'] }] {
		source := image_bundle_configuration(work, 'aarch64', key, policy)!
		mut configuration := prepare_image_configuration(root, 'aarch64', source)!
		image_bundle_refused(unsafe { &configuration }, work + '/bundle')
		configuration.close()
		assert os.ls(root)!.len == 0
	}
	source := image_bundle_configuration(work, 'aarch64', key, Policy{ licenses: ['Company-EULA'], allow_firmware: true })!
	mut configuration := prepare_image_configuration(root, 'aarch64', source)!
	defer { configuration.close() }
	mut plan := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
	defer { plan.close() }
	assert unsafe { &plan }.publish()!
	assert os.ls(root)!.len == 1 && !os.exists(root + '/etc')
}

fn test_image_bundle_disk_capture_and_publication_failures_preserve_destination() {
	work, key := image_bundle_fixture(false)!; defer { os.rmdir_all(work) or {} }
	root := work + '/image'; os.mkdir(root)!
	source := image_bundle_configuration(work, 'aarch64', key, Policy{})!
	mut configuration := prepare_image_configuration(root, 'aarch64', source)!
	defer { configuration.close() }
	if mut refused := unsafe { &configuration }.prepare_repositories_with(work + '/bundle', ImageRepositoriesOptions{ available_space: image_bundle_no_space }) { refused.close(); assert false } else {}
	if mut refused := unsafe { &configuration }.prepare_repositories_with(work + '/bundle', ImageRepositoriesOptions{ checkpoint: image_bundle_capture_refusal }) { refused.close(); assert false } else {}
	assert os.ls(root)!.len == 0
	mut plan := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
	defer { plan.close() }
	if _ := unsafe { &plan }.publish_with(ImageRepositoriesOptions{ available_space: image_bundle_no_space }) { assert false } else {}
	assert os.ls(root)!.len == 0
	if _ := unsafe { &plan }.publish_with(ImageRepositoriesOptions{ checkpoint: image_bundle_corrupt_stage }) { assert false } else {}
	parent := root + '/usr/share/vinix-packages'
	assert os.ls(parent)!.len == 0
	if _ := unsafe { &plan }.publish_with(ImageRepositoriesOptions{ checkpoint: image_bundle_race_target }) { assert false } else {}
	assert os.read_file(parent + '/repositories/keep')! == 'concurrent owner data'
	assert os.ls(parent)! == ['repositories']
	if _ := unsafe { &plan }.publish() { assert false } else {}
	assert os.read_file(parent + '/repositories/keep')! == 'concurrent owner data'
}

fn test_image_bundle_rechecks_configuration_root_parents_and_retained_state() {
	work, key := image_bundle_fixture(false)!; defer { os.rmdir_all(work) or {} }
	root := work + '/image'; os.mkdir(root)!
	source := image_bundle_configuration(work, 'aarch64', key, Policy{})!
	mut configuration := prepare_image_configuration(root, 'aarch64', source)!
	defer { configuration.close() }
	mut plan := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
	defer { plan.close() }
	os.mkdir_all(root + '/var/lib/vinix-packages')!
	os.write_file(root + '/var/lib/vinix-packages/trust-history.json', 'retained')!
	if _ := unsafe { &plan }.publish() { assert false } else {}
	assert !os.exists(root + '/usr')
	os.rmdir_all(root + '/var')!
	assert unsafe { &configuration }.publish()!
	path := root + '/etc/vinix-packages/config.json'
	original := os.read_file(path)!
	os.write_file(path, original.replace('"offline":false', '"offline":true'))!
	if _ := unsafe { &plan }.publish() { assert false } else {}
	os.write_file(path, original)!
	os.mkdir_all(root + '/usr/share')!; os.mkdir(work + '/outside')!
	os.symlink(work + '/outside', root + '/usr/share/vinix-packages')!
	if _ := unsafe { &plan }.publish() { assert false } else {}
	assert os.ls(work + '/outside')!.len == 0
	os.rm(root + '/usr/share/vinix-packages')!
	os.rename(root, root + '-saved')!; os.mkdir(root)!
	if _ := unsafe { &plan }.publish() { assert false } else {}
	assert os.ls(root)!.len == 0
}

fn image_bundle_replace_disk_ancestor(ancestor string) !u64 {
	os.rename(ancestor, ancestor + '.moved')!
	os.mkdir(ancestor)!
	os.write_file(ancestor + '/sentinel', 'replacement contents')!
	return ~u64(0)
}

fn image_bundle_replace_verified_directory(phase string, target string) ! {
	if phase != 'verified-existing' { return }
	os.rename(target, target + '.moved')!
	os.cp_all(target + '.moved', target, true)!
}

fn test_image_bundle_publish_keeps_budget_ancestor_and_preserved_bundle_bound_to_captures() {
	work, key := image_bundle_fixture(false)!
	defer { os.rmdir_all(work) or {} }
	source := image_bundle_configuration(work, 'aarch64', key, Policy{})!
	index := os.read_file(work + '/bundle/native/index.json')!
	for partial_tree in [false, true]! {
		root := work + '/' + if partial_tree { 'partial' } else { 'fresh' }
		os.mkdir(root)!
		ancestor := if partial_tree { root + '/usr/share' } else { root }
		if partial_tree { os.mkdir_all(ancestor)! }
		mut configuration := prepare_image_configuration(root, 'aarch64', source)!
		defer { configuration.close() }
		mut plan := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
		defer { plan.close() }
		mut diagnostic := ''
		unsafe { &plan }.publish_with(ImageRepositoriesOptions{ available_space: image_bundle_replace_disk_ancestor }) or {
			diagnostic = err.msg()
		}
		expected := if partial_tree { 'repository ancestor changed' } else { 'image root changed' }
		assert diagnostic.contains(expected), diagnostic
		assert os.ls(ancestor)! == ['sentinel'] && os.ls(ancestor + '.moved')!.len == 0
		assert os.read_file(ancestor + '/sentinel')! == 'replacement contents'
		os.rename(ancestor, ancestor + '.replacement')!
		os.rename(ancestor + '.moved', ancestor)!
		assert unsafe { &plan }.publish()!

		target := root + image_repositories_path
		diagnostic = ''
		unsafe { &plan }.publish_with(ImageRepositoriesOptions{ checkpoint: image_bundle_replace_verified_directory }) or {
			diagnostic = err.msg()
		}
		assert diagnostic.contains('published image repository directory changed during verification'), diagnostic
		assert os.read_file(target + '/native/index.json')! == index
		assert os.read_file(target + '.moved/native/index.json')! == index
		assert os.ls(os.dir(target))!.sorted() == ['repositories', 'repositories.moved']
		os.rename(target, target + '.replacement')!
		os.rename(target + '.moved', target)!
		assert !unsafe { &plan }.publish()!
		assert !os.exists(root + '/etc') && !os.exists(root + '/var')
	}
	println('IMAGE BUNDLE ancestor replacement during budgeting and identical bundle replacement during verification refuse; restoration permits publication and preservation PASS')
}
