// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

fn C.mkfifo(&char, u32) int

fn image_configuration_fixture() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-image-config-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work, mode: 0o700)!
	return work
}
fn image_configuration_refused(root string, architecture string, source string) {
	if mut plan := prepare_image_configuration(root, architecture, source) { plan.close(); assert false }
	else { message := err.msg(); unsafe { message.free(); err.free() } }
}

fn test_image_configuration_defaults_are_unenrolled_and_existing_bytes_survive() {
	work := image_configuration_fixture()!; defer { os.rmdir_all(work) or {} }
	for architecture in ['aarch64', 'x86_64']! {
		root := work + '/' + architecture; os.mkdir(root)!
		mut plan := prepare_image_configuration(root, architecture, '')!
		assert os.ls(root)!.len == 0
		assert unsafe { &plan }.publish()!
		plan.close(); plan.close()
		config := load_config(root)!
		assert config.architecture == architecture && config.repositories.len == 0 && config.policy == Policy{}
		close_decoded_configuration(config)
		path := root + '/etc/vinix-packages/config.json'
		assert os.lstat(path)!.mode & 0o777 == 0o644
		bytes := os.read_file(path)!
		mut existing := prepare_image_configuration(root, architecture, work + '/missing-release-config')!
		assert !unsafe { &existing }.publish()!
		existing.close()
		assert os.read_file(path)! == bytes
		assert !os.exists(root + '/var')
		other := if architecture == 'aarch64' { 'x86_64' } else { 'aarch64' }
		image_configuration_refused(root, other, '')
		assert os.read_file(path)! == bytes
	}
}

fn test_image_configuration_captures_reviewed_trust_policy_and_source_bytes() {
	work := image_configuration_fixture()!; defer { os.rmdir_all(work) or {} }
	key := keygen(work + '/seed')!
	source := work + '/release.json'
	for architecture in ['aarch64', 'x86_64']! {
		root := work + '/' + architecture; os.mkdir(root)!
		config := Config{ architecture: architecture, launch_user: 'alex',
			repositories: [Repository{ id: 'release', url: 'https://packages.example.invalid/stable', public_key: key },
				Repository{ id: 'organization', url: 'file:///media/company', public_key: key }],
			policy: Policy{ offline: true, allowed: ['app'], permissions: ['files'], reserve_bytes: 1234,
				pins: [Dependency{ id: 'app', minimum: '1.0.0', before: '2.0.0' }], licenses: ['Company-EULA'], allow_firmware: true } }
		os.write_file(source, ' \n' + json2.encode(config) + '\t')!
		mut plan := prepare_image_configuration(root, architecture, source)!
		assert os.ls(root)!.len == 0
		os.write_file(source, '{broken replacement')!; os.rm(source)!
		assert unsafe { &plan }.publish()!; plan.close()
		actual := load_config(root)!
		assert actual == config
		close_decoded_configuration(actual)
		assert os.read_file(root + '/etc/vinix-packages/config.json')! == json2.encode(config) + '\n'
	}
}

fn test_image_configuration_refuses_bad_inputs_before_creating_configuration() {
	work := image_configuration_fixture()!; defer { os.rmdir_all(work) or {} }
	root := work + '/root'; os.mkdir(root)!
	key := keygen(work + '/seed')!
	source := work + '/release.json'
	valid := json2.encode(Config{ architecture: 'aarch64', repositories: [Repository{ id: 'release',
		url: 'https://packages.example.invalid/stable', public_key: key }] })
	for input in ['{broken', valid.replace('aarch64', 'x86_64'), valid.replace('"policy":', '"polciy":'),
		valid.replace('"offline":false', '"offline":null'), valid.replace('"repositories":[', '"repositories":null,"duplicate":['),
		valid.replace(key, '0'.repeat(64)), valid.replace(key, '01' + '0'.repeat(62)), valid.replace('https://', 'http://'),
		valid.replace('"format":1', '"format":1,"format":1'), valid.replace('"launch_user":""', '"launch_user":"root"')] {
		os.write_file(source, input)!
		image_configuration_refused(root, 'aarch64', source)
		assert os.ls(root)!.len == 0
	}
	os.write_file(source, ' '.repeat(max_metadata + 1))!
	image_configuration_refused(root, 'aarch64', source)
	os.write_file(source, valid)!
	alias := work + '/alias'; os.symlink(source, alias)!
	image_configuration_refused(root, 'aarch64', alias)
	fifo := work + '/fifo'; assert C.mkfifo(fifo.str, 0o600) == 0
	image_configuration_refused(root, 'aarch64', fifo)
	image_configuration_refused(root, 'arm64', source)
	image_configuration_refused('/', 'aarch64', source)
	image_configuration_refused(root, 'aarch64', source + '\x00ignored')
	assert os.ls(root)!.len == 0
}

fn test_image_configuration_preserves_raced_destinations_and_refuses_changed_roots() {
	work := image_configuration_fixture()!; defer { os.rmdir_all(work) or {} }
	root := work + '/root'; os.mkdir(root)!
	mut plan := prepare_image_configuration(root, 'aarch64', '')!
	defer { plan.close() }
	os.chmod(root, 0o777)!
	if _ := unsafe { &plan }.publish() { assert false } else {}
	image_configuration_refused(root, 'aarch64', '')
	assert os.ls(root)!.len == 0
	os.chmod(root, 0o755)!
	os.mkdir_all(root + '/etc/vinix-packages')!
	path := root + '/etc/vinix-packages/config.json'
	os.write_file(path, 'concurrent administrator configuration')!
	if _ := unsafe { &plan }.publish() { assert false } else {}
	assert os.read_file(path)! == 'concurrent administrator configuration'
	assert os.ls(os.dir(path))! == ['config.json']
	os.rm(path)!
	os.rename(root, root + '-old')!; os.mkdir(root)!
	if _ := unsafe { &plan }.publish() { assert false } else {}
	assert os.ls(root)!.len == 0
	alias := work + '/alias'; os.symlink(root, alias)!
	image_configuration_refused(alias, 'aarch64', '')
}

fn test_image_configuration_refuses_unsafe_existing_configuration_and_parents() {
	work := image_configuration_fixture()!; defer { os.rmdir_all(work) or {} }
	root := work + '/root'; os.mkdir(root)!
	mut plan := prepare_image_configuration(root, 'aarch64', '')!
	assert unsafe { &plan }.publish()!; plan.close()
	path := root + '/etc/vinix-packages/config.json'
	original := os.read_file(path)!
	os.chmod(path, 0o666)!
	image_configuration_refused(root, 'aarch64', '')
	os.chmod(path, 0o644)!
	os.rm(path)!; os.symlink(work + '/missing', path)!
	image_configuration_refused(root, 'aarch64', '')
	os.rm(path)!; os.write_file(path, '{broken')!
	image_configuration_refused(root, 'aarch64', '')
	assert os.read_file(path)! == '{broken'
	os.write_file(path, original)!
	mut existing := prepare_image_configuration(root, 'aarch64', '')!
	defer { existing.close() }
	os.write_file(path, original.replace('aarch64', 'x86_64'))!
	if _ := unsafe { &existing }.publish() { assert false } else {}
	os.write_file(path, original)!
	os.rename(root + '/etc/vinix-packages', root + '/saved')!
	os.symlink(root + '/saved', root + '/etc/vinix-packages')!
	image_configuration_refused(root, 'aarch64', '')
	if _ := unsafe { &existing }.publish() { assert false } else {}
	assert os.read_file(root + '/saved/config.json')! == original
}

fn test_image_configuration_never_reinitializes_missing_trust_over_package_state() {
	work := image_configuration_fixture()!; defer { os.rmdir_all(work) or {} }
	root := work + '/root'; os.mkdir(root)!
	mut plan := prepare_image_configuration(root, 'aarch64', '')!
	defer { plan.close() }
	store := root + '/var/lib/vinix-packages'; os.mkdir_all(store)!
	os.write_file(store + '/trust-history.json', 'retained administrator history')!
	image_configuration_refused(root, 'aarch64', '')
	if _ := unsafe { &plan }.publish() { assert false } else {}
	assert !os.exists(root + '/etc') && os.read_file(store + '/trust-history.json')! == 'retained administrator history'
	os.rm(store + '/trust-history.json')!
	os.rename(store, root + '/saved-state')!
	os.symlink(root + '/saved-state', store)!
	image_configuration_refused(root, 'aarch64', '')
	if _ := unsafe { &plan }.publish() { assert false } else {}
}

fn test_seeded_image_acquires_and_maintains_signed_catalog_without_configuration_edits() {
	work := image_configuration_fixture()!; defer { os.rmdir_all(work) or {} }
	key := keygen(work + '/seed')!
	os.mkdir_all(work + '/source/bin')!
	for architecture in ['aarch64', 'x86_64']! {
		for version in ['1.0.0', '2.0.0']! {
			os.write_file(work + '/source/bin/app', 'application ' + architecture + ' ' + version)!
			os.chmod(work + '/source/bin/app', 0o755)!
			manifest := Package{ id: 'app', name: 'Application', description: 'Signed release application', version: version,
				architecture: architecture, license: 'MIT', kind: 'native', entrypoint: 'bin/app' }
			os.write_file(work + '/manifest.json', json2.encode(manifest))!
			pack(work + '/manifest.json', work + '/source', work + '/repository')!
		}
	}
	publish_release(work + '/repository', 'release', work + '/seed', 1, time.now().unix() + 3600, work + '/export')!
	for architecture in ['aarch64', 'x86_64']! {
		root := work + '/' + architecture; os.mkdir(root)!
		source := work + '/release-' + architecture + '.json'
		os.write_file(source, json2.encode(Config{ architecture: architecture, policy: Policy{ reserve_bytes: 0 },
			repositories: [Repository{ id: 'release', url: 'file://' + work + '/export', public_key: key }] }))!
		mut plan := prepare_image_configuration(root, architecture, source)!
		assert unsafe { &plan }.publish()!; plan.close()
		configuration := os.read_file(root + '/etc/vinix-packages/config.json')!
		service := Service{ root: root }
		assert service.refresh()!.packages.len == 4
		mut review := service.review('install', ['app'])!
		service.transact('install', ['app'], TransactionOptions{ expected_review: review.fingerprint })!
		review.close()
		assert service.verify()!.packages[0].package.version == '2.0.0'
		assert os.exists(root + '/var/lib/vinix-packages/current/share/applications/vinix-app.desktop')
		service.transact('remove', ['app'], TransactionOptions{})!
		assert !os.exists(root + '/var/lib/vinix-packages/current/share/applications/vinix-app.desktop')
		service.rollback('')!
		assert service.verify()!.packages[0].package.version == '2.0.0'
		assert os.read_file(root + '/etc/vinix-packages/config.json')! == configuration
	}
	println('PACKAGE IMAGE CONFIG signed catalog install remove rollback both architectures PASS')
}
