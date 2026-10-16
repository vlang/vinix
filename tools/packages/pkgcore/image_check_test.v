// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

fn C.mkfifo(&char, u32) int

fn image_check_work() !string {
	work := os.real_path(os.temp_dir()) + '/vinix-image-check-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work, mode: 0o700)!
	return work
}

fn image_check_fixture(restricted bool) !(string, string) {
	work := image_check_work()!
	key := keygen(work + '/seed')!
	os.mkdir_all(work + '/payload/share')!
	os.write_file(work + '/payload/share/data', 'one deduplicated offline object')!
	for architecture in ['all', 'aarch64', 'x86_64']! {
		manifest := Package{ id: if architecture == 'all' { 'support' } else { 'app' }, version: '1.0.0', architecture: architecture,
			name: 'Image input fixture', kind: 'data', license: if restricted { 'Company-EULA' } else { 'MIT' },
			proprietary: restricted, firmware: restricted, permissions: ['files'],
			dependencies: if architecture == 'all' { []Dependency{} } else { [Dependency{ id: 'support', minimum: '1.0.0' }] } }
		os.write_file(work + '/manifest.json', publisher_json(manifest))!
		pack(work + '/manifest.json', work + '/payload', work + '/workspace')!
	}
	for id in ['organization', 'native']! {
		publish_release(work + '/workspace', id, work + '/seed', if id == 'native' { 7 } else { 11 }, time.now().unix() + 3600, work + '/bundle/' + id)!
	}
	return work, key
}

fn image_check_source(work string, architecture string, key string, restricted bool) !string {
	path := work + '/configuration.json'
	os.write_file(path, publisher_json(Config{ architecture: architecture, launch_user: 'alex',
		policy: Policy{ offline: true, permissions: ['files'], reserve_bytes: 12345,
			licenses: if restricted { ['Company-EULA'] } else { []string{} }, allow_firmware: restricted },
		repositories: [Repository{ id: 'remote', url: 'https://packages.example.invalid/stable', public_key: key },
			Repository{ id: 'organization', url: 'file://' + image_repositories_path + '/organization', public_key: key },
			Repository{ id: 'native', url: 'file://' + image_repositories_path + '/native', public_key: key }] }))!
	return path
}

fn test_image_input_check_reports_reproducible_trust_policy_and_signed_bundle_without_publication() {
	for architecture in ['aarch64', 'x86_64']! {
		work, key := image_check_fixture(true)!
		defer { os.rmdir_all(work) or {} }
		root := work + '/image root ; $literal'; os.mkdir(root)!
		source := image_check_source(work, architecture, key, true)!
		mut configuration := prepare_image_configuration(root, architecture, source)!
		mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
		text := unsafe { &configuration }.check_repositories(unsafe { &repositories })!
		assert text == unsafe { &configuration }.check_repositories(unsafe { &repositories })!
		report := json2.decode[ImageInputCheck](text)!
		assert report.format == 1 && report.architecture == architecture && report.root == root
		assert report.configuration_path == root + '/etc/vinix-packages/config.json' && report.configuration_action == 'initialize'
		assert report.configuration_sha256 == hash_file(source)!
		assert report.configuration.launch_user == 'alex' && report.configuration.policy.offline
		assert report.configuration.policy.licenses == ['Company-EULA'] && report.configuration.policy.allow_firmware
		assert report.configuration.repositories.len == 3 && report.configuration.repositories.all(it.public_key == key)
		assert report.bundle_supplied && report.bundle_action == 'publish' && report.bundle_required_bytes == repositories.needed && report.bundle_reserve_bytes == 64 * 1024 * 1024
		assert report.bundled_repositories.map(it.id) == ['native', 'organization']
		for row in report.bundled_repositories {
			assert row.sequence == if row.id == 'native' { 7 } else { 11 }
			assert row.expires > time.now().unix() && row.index_sha256 == hash_file(work + '/bundle/' + row.id + '/index.json')!
			assert row.packages == 3 && row.aarch64_packages == 1 && row.x86_64_packages == 1 && row.shared_packages == 1
			assert row.proprietary_packages == 3 && row.firmware_packages == 3 && row.objects == 1
			assert row.payload_bytes == u64('one deduplicated offline object'.len)
		}
		capture := repositories.capture.clone()
		assert !text.contains(capture) && !text.contains(work + '/seed') && os.ls(root)!.len == 0
		// The report remains independent after all plans, captures and sources go.
		repositories.close(); repositories.close(); configuration.close(); configuration.close()
		assert !os.exists(capture)
		os.rmdir_all(work + '/bundle')!; os.rm(source)!
		assert json2.decode[ImageInputCheck](text)!.configuration.repositories[2].public_key == key
		assert os.ls(root)!.len == 0
	}
	println('IMAGE INPUT CHECK reproducible both-host trust/policy, exact signed digests, architecture/license/firmware counts and deduplicated bytes without image publication PASS')
}

fn test_image_input_check_preserves_existing_configuration_and_consumer_state() {
	work := image_check_work()!; defer { os.rmdir_all(work) or {} }
	root := work + '/image'; os.mkdir(root)!
	mut initial := prepare_image_configuration(root, 'aarch64', '')!
	assert unsafe { &initial }.publish()!; initial.close()
	path := root + '/etc/vinix-packages/config.json'
	original := os.read_file(path)!
	os.write_file(path, ' \n' + original + '\t')!
	retained := os.read_file(path)!
	os.mkdir_all(root + '/var/lib/vinix-packages')!
	os.write_file(root + '/var/lib/vinix-packages/trust-history.json', 'retained consumer history')!
	mut configuration := prepare_image_configuration(root, 'aarch64', work + '/missing ignored source')!
	defer { configuration.close() }
	mut repositories := unsafe { &configuration }.prepare_repositories('')!
	defer { repositories.close() }
	text := unsafe { &configuration }.check_repositories(unsafe { &repositories })!
	report := json2.decode[ImageInputCheck](text)!
	assert report.configuration_action == 'preserve' && report.configuration_sha256 == hash_file(path)!
	assert report.configuration.repositories.len == 0 && !report.bundle_supplied && report.bundle_action == 'none'
	assert report.bundled_repositories.len == 0 && report.bundle_required_bytes == 0 && report.bundle_reserve_bytes == 0
	assert os.read_file(path)! == retained && os.read_file(root + '/var/lib/vinix-packages/trust-history.json')! == 'retained consumer history'
	assert os.ls(root)!.sorted() == ['etc', 'var']
	println('IMAGE INPUT CHECK preserved literal existing configuration and consumer history; no-bundle scope and zero bundle estimate PASS')
}

fn test_image_input_check_revalidates_captured_inputs_and_refuses_mismatched_plans() {
	work, key := image_check_fixture(false)!; defer { os.rmdir_all(work) or {} }
	root := work + '/image'; os.mkdir(root)!
	source := image_check_source(work, 'aarch64', key, false)!
	mut configuration := prepare_image_configuration(root, 'aarch64', source)!
	defer { configuration.close() }
	mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
	defer { repositories.close() }
	text := unsafe { &configuration }.check_repositories(unsafe { &repositories })!
	os.rmdir_all(work + '/bundle')!; os.rm(source)!
	assert text == unsafe { &configuration }.check_repositories(unsafe { &repositories })!
	object_dir := repositories.capture + '/native/objects'
	object := object_dir + '/' + os.ls(object_dir)![0]
	original := os.read_file(object)!
	os.write_file(object, 'broken capture')!
	if _ := unsafe { &configuration }.check_repositories(unsafe { &repositories }) { assert false } else {}
	os.write_file(object, original)!
	assert text == unsafe { &configuration }.check_repositories(unsafe { &repositories })!
	other := work + '/other'; os.mkdir(other)!
	mut unrelated := prepare_image_configuration(other, 'aarch64', '')!
	defer { unrelated.close() }
	if _ := unsafe { &unrelated }.check_repositories(unsafe { &repositories }) { assert false } else {}
	os.mkdir_all(root + '/var/lib/vinix-packages')!
	os.write_file(root + '/var/lib/vinix-packages/keep', 'state appeared')!
	if _ := unsafe { &configuration }.check_repositories(unsafe { &repositories }) { assert false } else {}
	os.rmdir_all(root + '/var')!
	os.rename(root, root + '-saved')!; os.mkdir(root)!
	if _ := unsafe { &configuration }.check_repositories(unsafe { &repositories }) { assert false } else {}
	assert os.ls(root)!.len == 0 && os.ls(other)!.len == 0
	println('IMAGE INPUT CHECK capture corruption, unrelated plans, appeared consumer state and replaced roots refuse with unchanged targets; stable capture survives source removal PASS')
}

fn test_image_input_check_cli_uses_preflight_before_any_compiler_lookup() {
	binary := os.getenv('VINIX_PACKAGE_STAGE_CHECK_CLI')
	if binary == '' { return }
	work, key := image_check_fixture(false)!; defer { os.rmdir_all(work) or {} }
	root := work + '/image root ; $literal'; os.mkdir(root)!
	source := image_check_source(work, 'x86_64', key, false)!
	os.setenv('VINIX_PACKAGE_IMAGE_CONFIG', work + '/ignored-invalid-config', true)
	os.setenv('VINIX_PACKAGE_IMAGE_REPOSITORIES', work + '/ignored-invalid-bundle', true)
	defer { os.unsetenv('VINIX_PACKAGE_IMAGE_CONFIG'); os.unsetenv('VINIX_PACKAGE_IMAGE_REPOSITORIES') }
	mut expected := ''
	for placement in [0, 1]! {
		mut args := ['--arch', 'x86_64', '--staging', root, '--config', source, '--repositories', work + '/bundle', '--cc', work + '/nonexistent-compiler']
		if placement == 0 { args.insert(0, '--check') } else { args << '--check' }
		mut child := os.new_process(binary); child.set_args(args); child.set_redirect_stdio_merged(); child.run()
		text := child.stdout_slurp(); child.wait(); code := child.code; child.close()
		assert code == 0, text
		if placement == 0 { expected = text } else { assert text == expected }
		report := json2.decode[ImageInputCheck](text)!
		assert report.architecture == 'x86_64' && report.bundle_supplied && report.bundled_repositories.len == 2
		assert report.configuration.repositories[0].id == 'remote' && report.configuration_action == 'initialize'
		assert os.ls(root)!.len == 0 && !os.exists(work + '/nonexistent-compiler')
	}
	os.setenv('VINIX_PACKAGE_IMAGE_CONFIG', source, true)
	os.setenv('VINIX_PACKAGE_IMAGE_REPOSITORIES', work + '/bundle', true)
	mut from_env := os.new_process(binary)
	from_env.set_args(['--check', '--arch', 'x86_64', '--staging', root, '--cc', work + '/nonexistent-compiler'])
	from_env.set_redirect_stdio_merged(); from_env.run(); env_text := from_env.stdout_slurp(); from_env.wait(); env_code := from_env.code; from_env.close()
	assert env_code == 0 && env_text == expected && os.ls(root)!.len == 0
	mut normal := os.new_process(binary)
	normal.set_args(['--arch', 'x86_64', '--staging', root, '--cc', work + '/nonexistent-compiler'])
	normal.set_redirect_stdio_merged(); normal.run(); normal_text := normal.stdout_slurp(); normal.wait(); normal_code := normal.code; normal.close()
	assert normal_code != 0 && normal_text.contains('target compiler is missing or not executable:') && normal_text.contains('nonexistent-compiler') && os.ls(root)!.len == 0, normal_text
	os.write_file(work + '/non-executable-compiler', 'preserved ordinary file')!
	os.chmod(work + '/non-executable-compiler', 0o644)!
	mut invalid_compiler := os.new_process(binary)
	invalid_compiler.set_args(['--arch', 'x86_64', '--staging', root, '--cc-argv', json2.encode([work + '/non-executable-compiler', 'literal ; $argument'])])
	invalid_compiler.set_redirect_stdio_merged(); invalid_compiler.run(); compiler_text := invalid_compiler.stdout_slurp(); invalid_compiler.wait(); compiler_code := invalid_compiler.code; invalid_compiler.close()
	assert compiler_code != 0 && compiler_text.contains('target compiler is missing or not executable:') && os.ls(root)!.len == 0, compiler_text
	assert os.read_file(work + '/non-executable-compiler')! == 'preserved ordinary file'
	// Invalid selected input still fails, even though no compiler is needed.
	mut child := os.new_process(binary); child.set_args(['--check', '--arch', 'aarch64', '--staging', root, '--config', source, '--repositories', work + '/bundle'])
	child.set_redirect_stdio_merged(); child.run(); diagnostic := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	assert code != 0 && diagnostic.contains('another architecture') && os.ls(root)!.len == 0
	println('IMAGE INPUT CHECK CLI flag placement, literal paths, environment/explicit selection and reproducible compiler-free reports; normal staging and invalid-input refusals PASS')
}

fn test_image_input_check_distinguishes_preserved_bundles_and_refuses_unsafe_or_changed_destinations() {
	work, key := image_check_fixture(false)!; defer { os.rmdir_all(work) or {} }
	root := work + '/image'; os.mkdir(root)!
	source := image_check_source(work, 'aarch64', key, false)!
	mut configuration := prepare_image_configuration(root, 'aarch64', source)!
	mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
	// An occupied fresh configuration would make actual publication refuse too.
	os.mkdir_all(root + '/etc/vinix-packages')!
	os.write_file(configuration.path, configuration.text)!
	if _ := unsafe { &configuration }.check_repositories(unsafe { &repositories }) { assert false } else {}
	assert os.read_file(configuration.path)! == configuration.text
	os.rmdir_all(root + '/etc')!
	assert unsafe { &repositories }.publish()! && unsafe { &configuration }.publish()!
	repositories.close(); configuration.close()
	mut existing := prepare_image_configuration(root, 'aarch64', work + '/ignored')!
	defer { existing.close() }
	mut retained := unsafe { &existing }.prepare_repositories(work + '/bundle')!
	defer { retained.close() }
	text := unsafe { &existing }.check_repositories(unsafe { &retained })!
	check := json2.decode[ImageInputCheck](text)!
	assert check.configuration_action == 'preserve' && check.bundle_action == 'preserve'
	target := root + image_repositories_path
	for kind in ['alias', 'file', 'fifo', 'empty-directory', 'mode']! {
		os.rename(target, target + '-saved')!
		match kind {
			'alias' { os.symlink(target + '-saved', target)! }
			'file' { os.write_file(target, 'concurrent owner data')! }
			'fifo' { assert C.mkfifo(target.str, 0o600) == 0 }
			'empty-directory' { os.mkdir(target)! }
			'mode' { os.rename(target + '-saved', target)!; os.chmod(target, 0o777)! }
			else {}
		}
		if _ := unsafe { &existing }.check_repositories(unsafe { &retained }) { assert false } else {}
		if kind == 'file' { assert os.read_file(target)! == 'concurrent owner data' }
		if kind == 'mode' { os.chmod(target, 0o755)! } else {
			if kind == 'empty-directory' { assert os.ls(target)!.len == 0; os.rmdir(target)! } else { os.rm(target)! }
			os.rename(target + '-saved', target)!
		}
		assert text == unsafe { &existing }.check_repositories(unsafe { &retained })!
	}
	object_dir := target + '/native/objects'
	object := object_dir + '/' + os.ls(object_dir)![0]
	bytes := os.read_file(object)!
	os.write_file(object, 'damaged retained payload')!
	if _ := unsafe { &existing }.check_repositories(unsafe { &retained }) { assert false } else {}
	assert os.read_file(object)! == 'damaged retained payload'
	os.write_file(object, bytes)!
	assert text == unsafe { &existing }.check_repositories(unsafe { &retained })!
	println('IMAGE INPUT CHECK publish/preserve/none decisions, occupied configuration, aliased/special/shared-write/damaged bundles refuse without overwriting destinations PASS')
}
