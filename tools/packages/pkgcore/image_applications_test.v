// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

fn C.mkfifo(&char, u32) int

fn image_apps_fixture() !(string, string) {
	work := os.real_path(os.temp_dir()) + '/vinix-image-apps-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir(work, mode: 0o700)!
	key := keygen(work + '/seed')!
	os.mkdir_all(work + '/payload/bin')!
	os.write_file(work + '/payload/bin/runner', 'structural package fixture, never executed\n')!
	os.chmod(work + '/payload/bin/runner', 0o755)!
	mut packages := [Package{ id: 'support', architecture: 'all', version: '1.0.0', kind: 'data', name: 'Support', license: 'MIT' },
		Package{ id: 'editor', architecture: 'all', version: '9.0.0', kind: 'data', name: 'Not an application', license: 'MIT' }]
	for architecture in ['aarch64', 'x86_64']! {
		packages << Package{ id: 'editor', architecture: architecture, version: '1.0.0', kind: 'native', name: 'Editor', license: 'MIT',
			entrypoint: 'bin/runner', permissions: ['files'], dependencies: [Dependency{ id: 'support' }] }
		for version in ['1.0.0', '2.0.0']! {
			packages << Package{ id: 'runtime', architecture: architecture, version: version, kind: 'runtime', name: 'Runtime', license: 'MIT' }
		}
		for id in ['legacy', 'modern']! {
			packages << Package{ id: id, architecture: architecture, version: '1.0.0', kind: 'windows', name: id, license: 'MIT',
				runtime: 'runtime', entrypoint: 'bin/runner',
				dependencies: [Dependency{ id: 'runtime', minimum: if id == 'legacy' { '1.0.0' } else { '2.0.0' }, before: if id == 'legacy' { '2.0.0' } else { '' } }] }
		}
	}
	packages << Package{ id: 'arm-only', architecture: 'aarch64', version: '1.0.0', kind: 'native', name: 'ARM app', license: 'MIT', entrypoint: 'bin/runner' }
	for p in packages {
		os.write_file(work + '/manifest.json', publisher_json(p))!
		pack(work + '/manifest.json', work + '/payload', work + '/workspace')!
	}
	for id in ['native', 'organization']! {
		publish_release(work + '/workspace', id, work + '/seed', if id == 'native' { 7 } else { 11 }, time.now().unix() + 3600, work + '/bundle/' + id)!
	}
	return work, key
}

fn image_apps_config(work string, architecture string, key string, policy Policy) !string {
	path := work + '/configuration.json'
	os.write_file(path, publisher_json(Config{ architecture: architecture, policy: policy,
		repositories: [Repository{ id: 'organization', public_key: key, url: 'file://' + image_repositories_path + '/organization' },
			Repository{ id: 'native', public_key: key, url: 'file://' + image_repositories_path + '/native' },
			Repository{ id: 'remote', public_key: key, url: 'https://packages.example.invalid/release' }] }))!
	return path
}

fn test_image_application_catalog_reports_owned_reproducible_joint_lock_for_both_hosts() {
	for architecture in ['aarch64', 'x86_64']! {
		work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {} }
		root := work + '/image'; os.mkdir(root)!
		source := image_apps_config(work, architecture, key, Policy{ offline: true, reserve_bytes: 0 })!
		mut configuration := prepare_image_configuration(root, architecture, source)!
		mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
		text := unsafe { &configuration }.check_applications(unsafe { &repositories }, ['modern', 'editor'])!
		assert text == unsafe { &configuration }.check_applications(unsafe { &repositories }, ['editor', 'modern'])!
		report := json2.decode[ImageInputCheck](text)!
		assert report.applications_checked && report.application_deployment.format == 2
		assert report.application_deployment.architecture == architecture
		assert report.application_deployment.packages == ['editor', 'modern']
		assert report.application_deployment.locked.map(it.id) == ['editor', 'modern', 'runtime', 'support']
		for pin in report.application_deployment.locked {
			assert pin.repository == 'native' && pin.public_key == key && pin.minimum_sequence == 7
			assert pin.architecture == if pin.id == 'support' { 'all' } else { architecture }
			assert pin.version == if pin.id == 'runtime' { '2.0.0' } else { '1.0.0' }
			p := repositories.repositories.filter(it.id == pin.repository)[0].index.packages.filter(it.id == pin.id && it.architecture == pin.architecture && it.version == pin.version)[0]
			assert pin.metadata_sha256 == package_metadata_digest(p)!
		}
		unchecked := json2.decode[ImageInputCheck](unsafe { &configuration }.check_repositories(unsafe { &repositories })!)!
		assert !unchecked.applications_checked && unchecked.application_deployment.packages.len == 0 && unchecked.application_deployment.locked.len == 0
		assert os.ls(root)!.len == 0
		repositories.close(); configuration.close()
		os.rmdir_all(work + '/bundle')!; os.rm(source)!
		assert json2.decode[ImageInputCheck](text)!.application_deployment == report.application_deployment
	}
	println('IMAGE APPLICATIONS reproducible both-host joint locks, signed provenance, runtime/shared closure, app-kind selection and independent reports PASS')
}

fn test_image_application_catalog_refuses_incompatible_sets_missing_hosts_nonapps_and_invalid_roots() {
	work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {} }
	root := work + '/image'; os.mkdir(root)!
	source := image_apps_config(work, 'x86_64', key, Policy{})!
	mut configuration := prepare_image_configuration(root, 'x86_64', source)!
	defer { configuration.close() }
	mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
	defer { repositories.close() }
	for id in ['legacy', 'modern']! {
		assert json2.decode[ImageInputCheck](unsafe { &configuration }.check_applications(unsafe { &repositories }, [id])!)!.applications_checked
	}
	if _ := unsafe { &configuration }.check_applications(unsafe { &repositories }, ['legacy', 'modern']) { assert false } else {
		assert err.msg().contains('runtime') && err.msg().contains('Dependency path:')
	}
	for id in ['missing', 'arm-only', 'support', 'runtime']! {
		if _ := unsafe { &configuration }.check_applications(unsafe { &repositories }, [id]) { assert false } else {
			assert err.msg().contains('required image application ' + id + ' has no bundled application candidate for x86_64')
		}
	}
	for names in [ []string{}, ['editor', 'editor'], ['../editor'], [''], ['Editor'], ['editor;echo'], []string{len: 4097, init: 'editor'} ] {
		if _ := unsafe { &configuration }.check_applications(unsafe { &repositories }, names) { assert false } else {}
	}
	mut empty := unsafe { &configuration }.prepare_repositories('')!
	defer { empty.close() }
	if _ := unsafe { &configuration }.check_applications(unsafe { &empty }, ['editor']) { assert false } else {
		assert err.msg().contains('need a selected signed repository bundle')
	}
	assert os.ls(root)!.len == 0
	assert unsafe { &configuration }.check_applications(unsafe { &repositories }, ['editor'])!.len > 0
	println('IMAGE APPLICATIONS individually valid conflicting runtimes, missing/wrong-host/nonapp roots, duplicate/invalid/oversized sets and absent bundles refuse without publication; retry PASS')
}

fn test_image_application_catalog_retains_policy_gates_and_rechecks_capture_before_resolution() {
	work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {} }
	root := work + '/image'; os.mkdir(root)!
	for policy in [Policy{ permissions: []string{} }, Policy{ allowed: ['editor'] }, Policy{ pins: [Dependency{ id: 'runtime', minimum: '3.0.0' }] }] {
		source := image_apps_config(work, 'aarch64', key, policy)!
		mut configuration := prepare_image_configuration(root, 'aarch64', source)!
		if mut rejected := unsafe { &configuration }.prepare_repositories(work + '/bundle') { rejected.close(); assert false } else {
			assert err.msg().contains('policy') || err.msg().contains('organization')
		}
		configuration.close()
		assert os.ls(root)!.len == 0
	}
	source := image_apps_config(work, 'aarch64', key, Policy{})!
	mut configuration := prepare_image_configuration(root, 'aarch64', source)!
	defer { configuration.close() }
	mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
	defer { repositories.close() }
	text := unsafe { &configuration }.check_applications(unsafe { &repositories }, ['arm-only'])!
	objects := repositories.capture + '/native/objects'
	object := objects + '/' + os.ls(objects)![0]; original := os.read_file(object)!
	os.write_file(object, 'tampered capture')!
	if _ := unsafe { &configuration }.check_applications(unsafe { &repositories }, ['arm-only']) { assert false } else {}
	os.write_file(object, original)!
	assert text == unsafe { &configuration }.check_applications(unsafe { &repositories }, ['arm-only'])!
	assert os.ls(root)!.len == 0
	println('IMAGE APPLICATIONS organization permissions/allowlist/pins and captured payload integrity remain mandatory before app resolution; restoration/retry PASS')
}

fn test_image_application_catalog_lock_works_with_normal_reviewed_offline_deployment() {
	for architecture in ['aarch64', 'x86_64']! {
		work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {} }
		root := work + '/image'; os.mkdir(root)!
		source := image_apps_config(work, architecture, key, Policy{ offline: true, reserve_bytes: 0 })!
		mut configuration := prepare_image_configuration(root, architecture, source)!
		mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
		report := json2.decode[ImageInputCheck](unsafe { &configuration }.check_applications(unsafe { &repositories }, ['editor', 'modern'])!)!
		assert !os.exists(root + '/var')
		assert unsafe { &repositories }.publish()! && unsafe { &configuration }.publish()!
		repositories.close(); configuration.close()
		retained := os.read_file(root + '/etc/vinix-packages/config.json')!
		mut existing := prepare_image_configuration(root, architecture, work + '/ignored-missing-release-config')!
		mut same := unsafe { &existing }.prepare_repositories(root + image_repositories_path)!
		preserved := json2.decode[ImageInputCheck](unsafe { &existing }.check_applications(unsafe { &same }, ['modern', 'editor'])!)!
		assert preserved.configuration_action == 'preserve' && preserved.bundle_action == 'preserve'
		assert preserved.application_deployment == report.application_deployment
		same.close(); existing.close()
		// Host/alternate-root file URLs point at the published image. On a
		// booted image its staged absolute file URLs already name this bundle.
		consumer := work + '/consumer'; os.mkdir_all(consumer + '/etc/vinix-packages')!
		os.write_file(consumer + '/etc/vinix-packages/config.json', publisher_json(Config{ architecture: architecture,
			policy: Policy{ offline: true, reserve_bytes: 0 }, repositories: [Repository{ id: 'native', public_key: key,
				url: 'file://' + root + image_repositories_path + '/native' }] }))!
		path := work + '/deployment.json'; os.write_file(path, publisher_json(report.application_deployment))!
		service := Service{ root: consumer, offline: true }
		service.refresh()!
		mut review := service.review_deployment(path)!; defer { review.close() }
		assert review.rows.len == 4 && review.rows.all(it.action == 'install')
		// Transaction results borrow manifests/provenance; only the independent
		// state/verify observations below have the State.close ownership contract.
		service.apply_deployment(path, review.fingerprint)!
		mut verified := service.verify()!; defer { verified.close() }
		assert verified.requested == report.application_deployment.packages && verified.packages.len == 4
		for pin in report.application_deployment.locked {
			candidate := verified.packages.filter(it.package.id == pin.id)[0]
			assert candidate.repository == pin.repository && candidate.public_key == pin.public_key
			assert package_metadata_digest(candidate.package)! == pin.metadata_sha256
		}
		assert os.read_file(root + '/etc/vinix-packages/config.json')! == retained && !os.exists(root + '/var')
	}
	println('IMAGE APPLICATIONS exported format-2 locks drive ordinary reviewed offline install and integrity verification for both hosts; staged trust and consumer state remain separate PASS')
}

fn image_apps_cli(binary string, args []string) (int, string) {
	mut child := os.new_process(binary); child.set_args(args); child.set_redirect_stdio_merged(); child.run()
	text := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	return code, text
}

fn test_image_application_catalog_real_staging_cli_gates_normal_and_check_paths_before_compilers() {
	binary := os.getenv('VINIX_PACKAGE_STAGE_CHECK_CLI'); if binary == '' { return }
	work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {} }
	root := work + '/image ; $literal'; os.mkdir(root)!
	source := image_apps_config(work, 'x86_64', key, Policy{})!
	base := ['--arch', 'x86_64', '--staging', root, '--config', source, '--repositories', work + '/bundle', '--cc', work + '/missing-compiler']
	code, text := image_apps_cli(binary, ['--check', '--require-app', 'modern', ...base, '--require-app', 'editor'])
	assert code == 0, text
	report := json2.decode[ImageInputCheck](text)!
	assert report.applications_checked && report.application_deployment.packages == ['editor', 'modern']
	other_code, other := image_apps_cli(binary, [...base, '--require-app', 'editor', '--check', '--require-app', 'modern'])
	assert other_code == 0 && other == text, other
	for check in [false, true]! {
		for names in [['legacy', 'modern'], ['arm-only'], ['support'], ['editor', 'editor'], ['../editor']] {
			mut args := base.clone(); if check { args << '--check' }
			for name in names { args << ['--require-app', name] }
			failure, diagnostic := image_apps_cli(binary, args)
			assert failure != 0 && !diagnostic.contains('target compiler') && !diagnostic.contains('missing-compiler'), diagnostic
			assert os.ls(root)!.len == 0
		}
	}
	missing, compiler := image_apps_cli(binary, [...base, '--require-app', 'editor'])
	assert missing != 0 && compiler.contains('target compiler is missing or not executable:'), compiler
	no_bundle, bundle_error := image_apps_cli(binary, ['--check', '--arch', 'x86_64', '--staging', root, '--config', source, '--require-app', 'editor'])
	assert no_bundle != 0 && bundle_error.contains('need a selected signed repository bundle'), bundle_error
	assert os.ls(root)!.len == 0
	println('IMAGE APPLICATIONS real CLI repeated/position-independent app requirements, canonical compiler-free reports and normal/check refusal before compiler lookup PASS')
}

fn test_image_requirements_file_captures_exact_digest_and_resolves_owned_target_locks() {
	for architecture in ['aarch64', 'x86_64']! {
		work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {} }
		root := work + '/image'; os.mkdir(root)!
		source := image_apps_config(work, architecture, key, Policy{})!
		mut configuration := prepare_image_configuration(root, architecture, source)!
		mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
		path := work + '/reviewed apps ; $literal.json'
		first := '{"format":1,"architecture":"' + architecture + '","packages":["modern","editor"]}\n'
		os.write_file(path, first)!
		text := unsafe { &configuration }.check_application_file(unsafe { &repositories }, path)!
		report := json2.decode[ImageInputCheck](text)!
		assert report.applications_checked && report.application_requirements_sha256 == index_digest(first)
		inline := json2.decode[ImageInputCheck](unsafe { &configuration }.check_applications(unsafe { &repositories }, ['editor', 'modern'])!)!
		assert inline.application_requirements_sha256 == '' && inline.application_deployment == report.application_deployment
		assert text == unsafe { &configuration }.check_application_file(unsafe { &repositories }, path)!
		other := ' \n{"packages":["editor","modern"],"architecture":"' + architecture + '","format":1}\t'
		os.write_file(path, other)!
		changed := json2.decode[ImageInputCheck](unsafe { &configuration }.check_application_file(unsafe { &repositories }, path)!)!
		assert changed.application_requirements_sha256 == index_digest(other) && changed.application_requirements_sha256 != report.application_requirements_sha256
		assert changed.application_deployment == report.application_deployment && os.ls(root)!.len == 0
		repositories.close(); configuration.close(); os.rm(path)!
		assert json2.decode[ImageInputCheck](text)!.application_requirements_sha256 == index_digest(first)
	}
	println('IMAGE REQUIREMENTS FILE exact-byte digests, canonical both-host joint locks, inline parity, whitespace/order provenance and independent reports without publication PASS')
}

fn test_image_requirements_file_refuses_unpinned_lock_downgrades_bad_documents_and_special_inputs() {
	work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {} }
	root := work + '/image'; os.mkdir(root)!
	source := image_apps_config(work, 'aarch64', key, Policy{})!
	mut configuration := prepare_image_configuration(root, 'aarch64', source)!
	defer { configuration.close() }
	mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
	defer { repositories.close() }
	path := work + '/requirements.json'
	valid := '{"format":1,"architecture":"aarch64","packages":["editor"]}'
	inline := json2.decode[ImageInputCheck](unsafe { &configuration }.check_applications(unsafe { &repositories }, ['editor'])!)!
	os.write_file(path, publisher_json(inline.application_deployment))!
	if _ := unsafe { &configuration }.check_application_file(unsafe { &repositories }, path) { assert false } else {
		assert err.msg().contains('exact format-2 deployment locks cannot be used as unpinned requirements')
	}
	for text in ['{}', valid + '{}', valid.replace('1,', 'true,'), valid.replace('"editor"', 'null'),
		valid.replace('"editor"', '"editor","editor"'), valid.replace('"editor"', '"../editor"'),
		valid.replace('"editor"', '"support"'), valid.replace('"editor"', '"missing"'),
		valid.replace('"editor"', ''), valid.replace('aarch64', 'x86_64'), valid.replace('"format":1', '"format":1,"format":1'),
		valid.replace('"format":1', '"format":1,"unknown":0'), valid.replace('"editor"', '"legacy","modern"'),
		valid.replace('"editor"', '"editor",'.repeat(4096) + '"editor"')] {
		os.write_file(path, text)!
		if _ := unsafe { &configuration }.check_application_file(unsafe { &repositories }, path) { assert false } else {}
		assert os.read_file(path)! == text && os.ls(root)!.len == 0
	}
	os.write_file(path, ' '.repeat(8 * 1024 * 1024 + 1))!
	if _ := unsafe { &configuration }.check_application_file(unsafe { &repositories }, path) { assert false } else {
		assert err.msg().contains('bounded regular file')
	}
	os.rm(path)!
	for kind in ['missing', 'directory', 'link', 'fifo']! {
		match kind {
			'directory' { os.mkdir(path)! }
			'link' { os.write_file(work + '/real', valid)!; os.symlink(work + '/real', path)! }
			'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
			else {}
		}
		if _ := unsafe { &configuration }.check_application_file(unsafe { &repositories }, path) { assert false } else { assert err.msg().contains('bounded regular file') }
		if kind == 'directory' { os.rmdir(path)! } else if kind != 'missing' { os.rm(path)! }
	}
	os.write_file(path, valid)!
	assert unsafe { &configuration }.check_application_file(unsafe { &repositories }, path)!.len > 0 && os.ls(root)!.len == 0
	println('IMAGE REQUIREMENTS FILE format-2 pin downgrades, schema/host/empty/invalid/oversized/conflicting sets and missing/aliased/special/oversized files refuse unchanged; restore/retry PASS')
}

fn test_image_requirements_file_cli_explicit_and_environment_inputs_preserve_precedence_and_gate_staging() {
	binary := os.getenv('VINIX_PACKAGE_STAGE_CHECK_CLI'); if binary == '' { return }
	previous := os.getenv_opt('VINIX_PACKAGE_IMAGE_APPLICATIONS')
	defer { if value := previous { os.setenv('VINIX_PACKAGE_IMAGE_APPLICATIONS', value, true) } else { os.unsetenv('VINIX_PACKAGE_IMAGE_APPLICATIONS') } }
	for architecture in ['aarch64', 'x86_64']! {
		work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {} }
		root := work + '/image'; os.mkdir(root)!
		source := image_apps_config(work, architecture, key, Policy{})!
		path := work + '/reviewed ; $literal.json'
		os.write_file(path, '{"format":1,"architecture":"' + architecture + '","packages":["modern","editor"]}\n')!
		base := ['--arch', architecture, '--staging', root, '--config', source, '--repositories', work + '/bundle', '--cc', work + '/missing-compiler']
		os.setenv('VINIX_PACKAGE_IMAGE_APPLICATIONS', work + '/invalid-environment-file', true)
		explicit_code, explicit := image_apps_cli(binary, ['--applications', path, ...base, '--check'])
		assert explicit_code == 0, explicit
		report := json2.decode[ImageInputCheck](explicit)!
		assert report.application_requirements_sha256 == hash_file(path)! && report.application_deployment.packages == ['editor', 'modern']
		ids_code, ids := image_apps_cli(binary, [...base, '--require-app', 'editor', '--require-app', 'modern', '--check'])
		assert ids_code == 0, ids
		assert json2.decode[ImageInputCheck](ids)!.application_requirements_sha256 == ''
		assert json2.decode[ImageInputCheck](ids)!.application_deployment == report.application_deployment
		os.setenv('VINIX_PACKAGE_IMAGE_APPLICATIONS', path, true)
		env_code, environment := image_apps_cli(binary, ['--check', ...base])
		assert env_code == 0 && environment == explicit, environment
		for check in [true, false]! {
			mut args := base.clone(); if check { args << '--check' }
			for mixed in [['--applications', path, '--require-app', 'editor'], ['--require-app', 'editor', '--applications', path]] {
				code, error_text := image_apps_cli(binary, [...args, ...mixed])
				assert code != 0 && error_text.contains('alternative application requirement inputs'), error_text
			}
			os.write_file(path, '{"format":1,"architecture":"' + architecture + '","packages":["legacy","modern"]}')!
			code, diagnostic := image_apps_cli(binary, args)
			assert code != 0 && diagnostic.contains('Dependency path:') && !diagnostic.contains('missing-compiler'), diagnostic
		}
		os.write_file(path, '{"format":1,"architecture":"' + architecture + '","packages":["editor"]}')!
		normal_code, normal := image_apps_cli(binary, base)
		assert normal_code != 0 && normal.contains('target compiler is missing or not executable:'), normal
		empty_code, empty := image_apps_cli(binary, [...base, '--applications', ''])
		assert empty_code != 0 && empty.contains('--applications requires a reviewed application requirements file'), empty
		assert os.ls(root)!.len == 0
	}
	println('IMAGE REQUIREMENTS FILE CLI both-host inherited/explicit selection, inline override, mutual exclusion and normal/check compiler gates preserve unchanged images PASS')
}
