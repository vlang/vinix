// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

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
