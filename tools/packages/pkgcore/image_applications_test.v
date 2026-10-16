// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tools.packages.pkgprotocol

fn C.mkfifo(&char, u32) int
fn C.link(&char, &char) int

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

fn test_image_catalog_refuses_identical_replaced_capture_before_report_and_declaration() {
	for architecture in ['aarch64', 'x86_64']! {
		work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {} }
		root := work + '/image'; os.mkdir(root)!
		source := image_apps_config(work, architecture, key, Policy{})!
		mut configuration := prepare_image_configuration(root, architecture, source)!; defer { configuration.close() }
		mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
		mut applications := unsafe { &configuration }.prepare_applications(unsafe { &repositories }, ['editor'])!
		defer { applications.close() }
		report := unsafe { &applications }.report()
		assert unsafe { &repositories }.publish()! && unsafe { &configuration }.publish()!
		mut current := prepare_image_configuration(root, architecture, '')!; defer { current.close() }
		capture := repositories.capture.clone()
		defer { os.rmdir_all(capture) or {} }
		os.rename(capture, work + '/saved-capture')!; os.cp_all(work + '/saved-capture', capture, true)!
		mut denied := false
		unsafe { &current }.check_applications(unsafe { &repositories }, ['editor']) or { denied = err.msg().contains('staging root identity changed') }
		assert denied
		denied = false
		unsafe { &applications }.publish(unsafe { &repositories }) or { denied = err.msg().contains('staging root identity changed') }
		assert denied && !os.exists(root + pkgprotocol.image_applications_path)
		denied = false; repositories.retire() or { denied = true }
		assert denied && repositories.capture == '' && os.is_dir(capture + '/native') && os.is_dir(work + '/saved-capture/native')
		repositories.close()
		assert unsafe { &applications }.report() == report
		deployment := json2.decode[ImageInputCheck](report)!.application_deployment
		assert deployment.packages == ['editor'] && deployment.locked.map(it.id) == ['editor', 'support']
		assert !os.exists(root + '/var') && os.is_file(root + image_repositories_path + '/native/index.json')
	}
	println('IMAGE CAPTURE replaced identical captures refuse application reports and declarations; independent review survives checked retirement and saved image bundle remains intact PASS')
}

fn test_image_catalog_declaration_captures_publishes_and_preserves_exact_both_host_locks() {
	for architecture in ['aarch64', 'x86_64']! {
		work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {} }
		root := work + '/image'; os.mkdir(root)!
		source := image_apps_config(work, architecture, key, Policy{})!
		mut configuration := prepare_image_configuration(root, architecture, source)!
		mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
		requirements := work + '/applications.json'
		os.write_file(requirements, '{"format":1,"architecture":"' + architecture + '","packages":["modern","editor"]}\n')!
		mut applications := unsafe { &configuration }.prepare_application_file(unsafe { &repositories }, requirements)!
		report_text := unsafe { &applications }.report()
		defer { unsafe { report_text.free() } }
		report := json2.decode[ImageInputCheck](report_text)!
		assert report.image_application_deployment_path == pkgprotocol.image_applications_path
		assert report.image_application_deployment_action == 'publish'
		assert report.image_application_deployment_sha256 == index_digest(applications.text)
		assert report.image_application_deployment_bytes == u64(applications.text.len)
		assert report.application_deployment_sha256 == '' && report.application_deployment_destination == ''
		assert applications.text == encode_deployment_lock(report.application_deployment, true)!
		assert os.ls(root)!.len == 0
		if _ := unsafe { &applications }.publish(unsafe { &repositories }) { assert false } else {}
		// Original release inputs cannot redirect or invalidate this capture.
		os.rm(requirements)!; os.rm(source)!; os.rmdir_all(work + '/bundle')!
		assert unsafe { &repositories }.publish()! && unsafe { &configuration }.publish()!
		assert unsafe { &applications }.publish(unsafe { &repositories })!
		path := root + pkgprotocol.image_applications_path
		assert os.read_file(path)! == applications.text && os.stat(path)!.mode & 0o7777 == 0o644
		assert !unsafe { &applications }.publish(unsafe { &repositories })! && !os.exists(root + '/var')
		applications.close(); repositories.close(); configuration.close()
		mut existing := prepare_image_configuration(root, architecture, '')!
		mut same := unsafe { &existing }.prepare_repositories(root + image_repositories_path)!
		mut preserved := unsafe { &existing }.prepare_applications(unsafe { &same }, ['editor', 'modern'])!
		assert json2.decode[ImageInputCheck](unsafe { &preserved }.report())!.image_application_deployment_action == 'preserve'
		assert !unsafe { &preserved }.publish(unsafe { &same })!
		preserved.close(); same.close(); existing.close()
		assert json2.decode[ImageInputCheck](report_text)!.application_deployment == report.application_deployment
	}
	println('IMAGE CATALOG captured both-host exact locks, stable source removal, publish ordering, canonical bytes/digest/mode, no consumer state and identical-file preservation PASS')
}

fn test_image_catalog_refuses_existing_and_late_substituted_destinations() {
	work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {} }
	for kind in ['file', 'link', 'dangling', 'fifo', 'directory', 'hardlink', 'mode']! {
		root := work + '/' + kind; os.mkdir(root)!
		source := image_apps_config(work, 'aarch64', key, Policy{})!
		mut configuration := prepare_image_configuration(root, 'aarch64', source)!
		defer { configuration.close() }
		mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
		defer { repositories.close() }
		mut applications := unsafe { &configuration }.prepare_applications(unsafe { &repositories }, ['editor'])!
		defer { applications.close() }
		assert unsafe { &repositories }.publish()! && unsafe { &configuration }.publish()!
		path := root + pkgprotocol.image_applications_path
		other := root + '/kept'; os.write_file(other, 'existing owner bytes')!
		match kind {
			'file' { os.write_file(path, 'existing declaration')! }
			'link' { os.symlink(other, path)! }
			'dangling' { os.symlink(root + '/absent', path)! }
			'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
			'directory' { os.mkdir(path)! }
			'hardlink' { assert C.link(other.str, path.str) == 0 }
			else { os.write_file(path, applications.text)!; os.chmod(path, 0o666)! }
		}
		before := os.lstat(path)!
		if _ := unsafe { &applications }.publish(unsafe { &repositories }) { assert false } else {}
		mut fresh := prepare_image_configuration(root, 'aarch64', '')!
		defer { fresh.close() }
		if mut refused := unsafe { &fresh }.prepare_applications(unsafe { &repositories }, ['editor']) { refused.close(); assert false } else {}
		after := os.lstat(path)!
		assert before.inode == after.inode && before.mode == after.mode && before.size == after.size
		assert os.read_file(other)! == 'existing owner bytes' && !os.exists(root + '/var')
		if kind == 'directory' { os.rmdir(path)! } else { os.rm(path)! }
		assert unsafe { &applications }.publish(unsafe { &repositories })!
	}
	println('IMAGE CATALOG occupied and late file/link/dangling/FIFO/directory/hardlink/shared-write destinations refuse unchanged before publication; removal and retry PASS')
}

fn image_catalog_checkpoint(phase string, temporary string) ! {
	kind := os.getenv('VINIX_IMAGE_CATALOG_FAULT')
	defer { unsafe { kind.free() } }
	if kind == 'race' && phase == 'flushed' { os.write_file(os.dir(temporary) + '/applications.json', 'concurrent owner bytes')! }
	if kind == phase { return error('injected image catalog failure') }
}

fn test_image_catalog_failure_cleanup_and_changed_dependencies_refuse_before_publication() {
	work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {}; os.unsetenv('VINIX_IMAGE_CATALOG_FAULT') }
	root := work + '/image'; os.mkdir(root)!
	source := image_apps_config(work, 'x86_64', key, Policy{})!
	mut configuration := prepare_image_configuration(root, 'x86_64', source)!; defer { configuration.close() }
	mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!; defer { repositories.close() }
	mut applications := unsafe { &configuration }.prepare_applications(unsafe { &repositories }, ['editor'])!; defer { applications.close() }
	assert unsafe { &repositories }.publish()! && unsafe { &configuration }.publish()!
	path := root + pkgprotocol.image_applications_path
	config_path := root + '/etc/vinix-packages/config.json'; config := os.read_file(config_path)!
	os.write_file(config_path, config + ' ')!
	if _ := unsafe { &applications }.publish(unsafe { &repositories }) { assert false } else {}
	os.write_file(config_path, config)!
	objects := root + image_repositories_path + '/native/objects'
	object := objects + '/' + os.ls(objects)![0]; original := os.read_file(object)!
	os.write_file(object, 'changed published payload')!
	if _ := unsafe { &applications }.publish(unsafe { &repositories }) { assert false } else {}
	os.write_file(object, original)!
	os.rename(root, work + '/saved-image')!; os.mkdir(root)!
	if _ := unsafe { &applications }.publish(unsafe { &repositories }) { assert false } else {}
	os.rmdir(root)!; os.rename(work + '/saved-image', root)!
	os.chmod(root + '/usr/share/vinix-packages', 0o777)!
	if _ := unsafe { &applications }.publish(unsafe { &repositories }) { assert false } else {}
	os.chmod(root + '/usr/share/vinix-packages', 0o755)!
	assert !os.exists(path)
	for kind in ['created', 'written', 'flushed', 'published', 'space', 'directory-flush', 'race']! {
		os.setenv('VINIX_IMAGE_CATALOG_FAULT', kind, true)
		options := AtomicWriteOptions{ checkpoint: image_catalog_checkpoint,
			write: if kind == 'space' { image_export_no_space } else { atomic_write_bytes },
			flush: if kind == 'directory-flush' { image_export_directory_flush_failure } else { atomic_flush } }
		if _ := unsafe { &applications }.publish_with(unsafe { &repositories }, options) { assert false } else {
			if kind in ['published', 'directory-flush']! {
				assert err.msg().contains('saved, but') && os.read_file(path)! == applications.text
				assert !unsafe { &applications }.publish(unsafe { &repositories })!
			} else if kind == 'race' {
				assert os.read_file(path)! == 'concurrent owner bytes'
				if _ := unsafe { &applications }.publish(unsafe { &repositories }) { assert false } else {}
			} else { assert !os.exists(path); assert unsafe { &applications }.publish(unsafe { &repositories })! }
		}
		assert os.ls(os.dir(path))!.all(!it.starts_with('.package-'))
		os.rm(path)!
	}
	assert !os.exists(root + '/var')
	println('IMAGE CATALOG changed trust/payloads, write/space/flush/checkpoint failures and concurrent destinations refuse safely; saved diagnostics, cleanup and retry PASS')
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
		path := work + '/deployment.json'
		report := json2.decode[ImageInputCheck](unsafe { &configuration }.export_applications(unsafe { &repositories }, ['editor', 'modern'], path)!)!
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
		assert os.read_file(path)! == publisher_json(report.application_deployment)
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
	assert report.image_application_deployment_path == pkgprotocol.image_applications_path
	assert report.image_application_deployment_action == 'publish' && report.image_application_deployment_bytes > 0
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

fn test_image_deployment_exports_exact_owned_locks_and_saved_digests_for_inline_and_file_requirements() {
	for architecture in ['aarch64', 'x86_64']! {
		work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {} }
		root := work + '/image'; os.mkdir(root)!
		source := image_apps_config(work, architecture, key, Policy{})!
		mut configuration := prepare_image_configuration(root, architecture, source)!
		mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!
		path := work + '/saved é ; $literal.json'
		text := unsafe { &configuration }.export_applications(unsafe { &repositories }, ['modern', 'editor'], path)!
		report := json2.decode[ImageInputCheck](text)!
		assert report.application_deployment_destination == path && report.application_requirements_sha256 == ''
		assert report.application_deployment_sha256 == hash_file(path)!
		assert os.read_file(path)! == encode_deployment_lock(report.application_deployment, true)!
		assert os.stat(path)!.mode & 0o777 == 0o644 && os.lstat(path)!.nlink == 1
		requirements := work + '/applications.json'
		os.write_file(requirements, '{"format":1,"architecture":"' + architecture + '","packages":["editor","modern"]}\n')!
		file_path := work + '/from-file.json'
		from_file := json2.decode[ImageInputCheck](unsafe { &configuration }.export_application_file(unsafe { &repositories }, requirements, file_path)!)!
		assert from_file.application_requirements_sha256 == hash_file(requirements)! && from_file.application_deployment_destination == file_path
		assert from_file.application_deployment == report.application_deployment && os.read_file(file_path)! == os.read_file(path)!
		outside := json2.decode[ImageInputCheck](unsafe { &configuration }.export_applications(unsafe { &repositories }, ['editor', 'modern'], root + '/../outside.json')!)!
		assert outside.application_deployment_destination == work + '/outside.json' && os.read_file(work + '/outside.json')! == os.read_file(path)!
		unchecked := json2.decode[ImageInputCheck](unsafe { &configuration }.check_applications(unsafe { &repositories }, ['editor'])!)!
		assert unchecked.application_deployment_destination == '' && unchecked.application_deployment_sha256 == ''
		repositories.close(); configuration.close(); os.rm(requirements)!
		assert json2.decode[ImageInputCheck](text)!.application_deployment_sha256 == hash_file(path)! && os.ls(root)!.len == 0
	}
	println('IMAGE DEPLOYMENT EXPORT both-host exact canonical format-2 locks, inline/file parity, independent source/result digests, exclusive atomic publication and independent receipts PASS')
}

fn test_image_deployment_export_preserves_existing_outputs_and_refuses_image_namespaces_or_invalid_sets() {
	work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {} }
	root := work + '/image'; os.mkdir(root)!
	source := image_apps_config(work, 'aarch64', key, Policy{})!
	mut configuration := prepare_image_configuration(root, 'aarch64', source)!; defer { configuration.close() }
	mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!; defer { repositories.close() }
	os.write_file(work + '/keep', 'preserved owner bytes')!; os.chmod(work + '/keep', 0o600)!
	for kind in ['file', 'link', 'dangling', 'fifo', 'directory', 'hardlink']! {
		path := work + '/' + kind
		match kind {
			'file' { os.write_file(path, 'preserved output')! }
			'link' { os.symlink(work + '/keep', path)! }
			'dangling' { os.symlink(work + '/absent', path)! }
			'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
			'directory' { os.mkdir(path)! }
			'hardlink' { assert C.link((work + '/keep').str, path.str) == 0 }
			else {}
		}
		before := os.lstat(path)!
		if _ := unsafe { &configuration }.export_applications(unsafe { &repositories }, ['editor'], path) { assert false } else { assert err.msg().contains('already exists') }
		after := os.lstat(path)!; assert before.inode == after.inode && before.mode == after.mode && before.size == after.size
	}
	assert os.read_file(work + '/keep')! == 'preserved owner bytes' && os.stat(work + '/keep')!.mode & 0o777 == 0o600
	assert os.read_file(work + '/file')! == 'preserved output'
	os.mkdir(root + '/sub')!; os.symlink(root + '/sub', work + '/into-image')!
	for path in [root + '/new.json', root + '/sub/new.json', work + '/into-image/new.json', work + '/into-image/../new.json'] {
		if _ := unsafe { &configuration }.export_applications(unsafe { &repositories }, ['editor'], path) { assert false } else { assert err.msg().contains('outside the target image') }
	}
	for path in ['', '.', '..', work + '/bad\nname', work + '/bad\xff', work + '/bad\x00name', work + '/missing/new.json', work + '/trailing/'] {
		if _ := unsafe { &configuration }.export_applications(unsafe { &repositories }, ['editor'], path) { assert false } else {}
	}
	for index, roots in [ []string{}, ['editor', 'editor'], ['support'], ['absent'], ['legacy', 'modern'] ] {
		path := work + '/refused-' + index.str()
		if _ := unsafe { &configuration }.export_applications(unsafe { &repositories }, roots, path) { assert false } else {}
		assert !os.exists(path)
	}
	os.mkdir(work + '/shared')!; os.chmod(work + '/shared', 0o777)!
	if _ := unsafe { &configuration }.export_applications(unsafe { &repositories }, ['editor'], work + '/shared/refused') { assert false } else {}
	assert os.ls(work + '/shared')!.len == 0 && os.ls(root + '/sub')!.len == 0 && os.ls(root)! == ['sub']
	assert os.ls(work)!.all(!it.starts_with('.package-'))
	println('IMAGE DEPLOYMENT EXPORT existing file/link/FIFO/directory/hardlink outputs, direct/aliased image namespaces, unsafe parents, invalid paths and invalid app sets refuse unchanged PASS')
}

fn image_export_checkpoint(phase string, temporary string) ! {
	kind := os.file_name(os.dir(temporary))
	if kind == 'race' && phase == 'flushed' { os.write_file(os.dir(temporary) + '/result.json', 'concurrent owner bytes')! }
	if kind == phase { return error('injected image export ' + phase + ' failure') }
}

fn image_export_no_space(_ int, _ voidptr, _ usize) isize { C.errno = C.ENOSPC; return -1 }
fn image_export_directory_flush_failure(fd int) int {
	mut info := C.stat{}; assert C.fstat(fd, unsafe { &info }) == 0
	return if info.st_mode & 0o170000 == 0o040000 { -1 } else { C.fsync(fd) }
}

fn test_image_deployment_export_failure_cleanup_saved_diagnostics_and_retry_preserve_concurrent_files() {
	work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {} }
	root := work + '/image'; os.mkdir(root)!
	source := image_apps_config(work, 'x86_64', key, Policy{})!
	mut configuration := prepare_image_configuration(root, 'x86_64', source)!; defer { configuration.close() }
	mut repositories := unsafe { &configuration }.prepare_repositories(work + '/bundle')!; defer { repositories.close() }
	for kind in ['created', 'written', 'flushed', 'published', 'race', 'space', 'directory-flush']! {
		parent := work + '/' + kind; os.mkdir(parent)!
		path := parent + '/result.json'
		options := AtomicWriteOptions{ checkpoint: image_export_checkpoint,
			write: if kind == 'space' { image_export_no_space } else { atomic_write_bytes },
			flush: if kind == 'directory-flush' { image_export_directory_flush_failure } else { atomic_flush } }
		if _ := unsafe { &configuration }.check_inputs(unsafe { &repositories }, ['editor'], '', ImageDeploymentOutput{ destination: path, options: options }) { assert false } else {
			if kind in ['published', 'directory-flush']! {
				assert err.msg().contains('saved, but')
				mut document := decode_deployment(os.read_file(path)!, 'x86_64')!; assert document.packages == ['editor']; document.close()
			} else if kind == 'race' { assert os.read_file(path)! == 'concurrent owner bytes' }
			else { assert !os.exists(path) && !os.is_link(path) }
		}
		assert os.ls(parent)!.all(!it.starts_with('.package-'))
		if !os.exists(path) {
			assert unsafe { &configuration }.export_applications(unsafe { &repositories }, ['editor'], path)!.len > 0
		} else {
			before := os.read_file(path)!
			if _ := unsafe { &configuration }.export_applications(unsafe { &repositories }, ['editor'], path) { assert false } else {}
			assert os.read_file(path)! == before
		}
	}
	assert os.ls(root)!.len == 0
	println('IMAGE DEPLOYMENT EXPORT write/space/checkpoint/flush failures and destination races retire temporary files, report saved outputs accurately and permit safe retry without image writes PASS')
}

fn test_image_deployment_export_cli_requires_explicit_context_and_saves_a_reviewable_file_without_compilers() {
	binary := os.getenv('VINIX_PACKAGE_STAGE_CHECK_CLI'); if binary == '' { return }
	for architecture in ['aarch64', 'x86_64']! {
		work, key := image_apps_fixture()!; defer { os.rmdir_all(work) or {} }
		root := work + '/image'; os.mkdir(root)!
		source := image_apps_config(work, architecture, key, Policy{})!
		base := ['--arch', architecture, '--staging', root, '--config', source, '--repositories', work + '/bundle', '--cc', work + '/missing-compiler']
		path := work + '/reviewed é ; $literal.json'
		code, text := image_apps_cli(binary, [...base, '--require-app', 'editor', '--check', '--export-deployment', path])
		assert code == 0, text
		report := json2.decode[ImageInputCheck](text)!
		assert report.application_deployment_destination == path && report.application_deployment_sha256 == hash_file(path)!
		assert os.read_file(path)! == publisher_json(report.application_deployment)
		again, diagnostic := image_apps_cli(binary, ['--check', '--export-deployment', path, ...base, '--require-app', 'editor'])
		assert again != 0 && diagnostic.contains('already exists'), diagnostic
		requirements := work + '/applications.json'
		os.write_file(requirements, '{"format":1,"architecture":"' + architecture + '","packages":["editor"]}')!
		file_code, file_text := image_apps_cli(binary, ['--export-deployment', work + '/file.json', ...base, '--applications', requirements, '--check'])
		assert file_code == 0, file_text
		assert os.read_file(work + '/file.json')! == os.read_file(path)!
		for options in [['--check'], ['--require-app', 'editor']] {
			invalid, reason := image_apps_cli(binary, [...base, ...options, '--export-deployment', work + '/uncreated'])
			assert invalid != 0 && reason.contains('requires --check and selected application requirements'), reason
			assert !os.exists(work + '/uncreated')
		}
		in_image, image_error := image_apps_cli(binary, [...base, '--check', '--require-app', 'editor', '--export-deployment', root + '/refused.json'])
		assert in_image != 0 && image_error.contains('outside the target image'), image_error
		assert os.ls(root)!.len == 0
	}
	println('IMAGE DEPLOYMENT EXPORT real CLI both-host inline/file exports, option placement, compiler bypass, existing-file protection and required context preserve target images PASS')
}
