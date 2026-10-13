// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore
import desktop.packagecore
import desktop.sessioncore
import tools.packages.pkgprotocol

struct Reply {
	code int
	text string
}

fn command(binary string, arguments []string) !Reply {
	mut process := os.new_process(binary)
	process.set_args(arguments)
	process.set_redirect_stdio_merged()
	process.run()
	text := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	return Reply{ code: code, text: text }
}

fn success(binary string, arguments []string) !string {
	result := command(binary, arguments)!
	if result.code != 0 { return error('CLI ${arguments.join(' ')} failed: ${result.text}') }
	return result.text
}

fn package_template(id string, version string) pkgcore.Package {
	return pkgcore.Package{
		id:           id
		version:      version
		architecture: 'aarch64'
		name:         id
		description:  'CLI distribution fixture'
		license:      'MIT'
		kind:         'native'
		entrypoint:   'bin/app'
		permissions: ['files']
		associations: ['text/plain']
	}
}

fn qualify_catalog_cli(binary string, work string) ! {
	for args in [['run-args', 'catalog-app'], ['run-args', 'catalog-app', '--data-cwd', '--data-cwd', '--'], ['run-args', 'catalog-app', '--file'], ['run-args', 'catalog-app', '--file', 'relative', '--'], ['ffmpeg-catalog', '1.0.0'], ['compose-catalog'], ['compose-catalog', '/tmp/unused', 'profile']] {
		assert command(binary, args)!.code != 0
	}
	assert command(binary, ['run-terminal-args', 'catalog-app', '--', '-version'])!.text.contains('terminal standard input and output')
	assert command(binary, ['--root', work, 'run-args', 'catalog-app', '--', '-version'])!.text.contains('alternate installation root')
	terminal := command(binary, ['run-terminal', 'catalog-app'])!
	assert terminal.code != 0 && terminal.text.contains('terminal standard input and output')
	assert command(binary, ['--root', work, 'run-terminal', 'catalog-app'])!.text.contains('alternate installation root')
	roots := work + '/catalog roots; $literal'
	os.mkdir_all(roots + '/aarch64/bin')!
	os.write_file(roots + '/aarch64/bin/app', 'pinned catalog application')!
	os.chmod(roots + '/aarch64/bin/app', 0o755)!
	p := pkgcore.Package{ ...package_template('catalog-app', '1.0.0'), files: [pkgcore.Payload{
		path: 'bin/app', bytes: os.file_size(roots + '/aarch64/bin/app'),
		sha256: pkgcore.hash_file(roots + '/aarch64/bin/app')!, executable: true }] }
	recipe := pkgcore.CatalogRecipe{ format: 1, architectures: ['aarch64'], packages: [
		pkgcore.CatalogImport{ source: 'aarch64', recipe: pkgcore.RootRecipe{ manifest: p,
			entries: [pkgcore.RootEntry{ source: 'bin/app', path: 'bin/app' }] } },
	] }
	path := work + '/catalog recipe.json'
	canonical_input := json2.encode(recipe)
	for invalid in [canonical_input.replace('"permissions":["files"]', '"permissions":null'),
		canonical_input.replace('"firmware":false,', ''),
		canonical_input.replace('"executable":true', '"executable":"true"')] {
		assert invalid != canonical_input
		os.write_file(path, invalid)!
		for args in [['pack-catalog', path, roots, work + '/schema-workspace'],
			['compose-catalog', work + '/schema-lock', 'fixture', path]] {
			refused := command(binary, args)!
			assert refused.code == 1 && refused.text != '' && !refused.text.contains('V panic:'), refused.text
		}
		assert !os.exists(work + '/schema-workspace') && !os.exists(work + '/schema-lock')
	}
	root_input := json2.encode(recipe.packages[0].recipe)
	os.write_file(path, root_input.replace('"firmware":false', '"firmware":true,"firm\\u0077are":false'))!
	root_refused := command(binary, ['pack-root', path, roots + '/aarch64', work + '/schema-root'])!
	assert root_refused.code == 1 && root_refused.text.contains('duplicate administration document field: firmware'), root_refused.text
	assert !os.exists(work + '/schema-root')
	os.write_file(path, canonical_input)!
	workspace := work + '/catalog workspace'
	info := json2.decode[pkgcore.CatalogInfo](success(binary, ['pack-catalog', path, roots, workspace])!)!
	assert info.format == 1 && info.directory == workspace && info.architectures == ['aarch64']
	assert info.package_count == 1 && info.object_count == 1
	assert info.catalog_sha256 == pkgcore.hash_file(workspace + '/catalog.json')!
	assert !os.exists(workspace + '/index.json') && !os.exists(workspace + '/.publisher')
	assert command(binary, ['pack-catalog', path, roots, workspace])!.code != 0
	assert command(binary, ['pack-catalog', path, roots])!.code != 0
	composed_directory := work + '/composed lock; $literal'
	composed := json2.decode[pkgcore.CompositionInfo](success(binary, ['compose-catalog', composed_directory, 'fixture', path])!)!
	assert composed.package_count == 1 && composed.sources.map(it.id) == ['fixture']
	assert composed.catalog_sha256 == pkgcore.hash_file(composed.catalog)!
	assert command(binary, ['compose-catalog', composed_directory, 'fixture', path])!.code != 0
	assert command(binary, ['compose-catalog', work + '/duplicate-composition', 'one', path, 'two', path])!.code != 0
	assert !os.exists(work + '/duplicate-composition')
	namespaced := work + '/composed-roots'
	os.mkdir_all(namespaced + '/fixture')!
	os.rename(roots + '/aarch64', namespaced + '/fixture/aarch64')!
	composed_workspace := work + '/composed workspace'
	assert json2.decode[pkgcore.CatalogInfo](success(binary, ['pack-catalog', composed.catalog, namespaced, composed_workspace])!)!.package_count == 1
	assert os.read_file(composed_workspace + '/manifests/catalog-app-aarch64-1.0.0.json')!
		== os.read_file(workspace + '/manifests/catalog-app-aarch64-1.0.0.json')!
	os.rename(namespaced + '/fixture/aarch64', roots + '/aarch64')!
	os.write_file(roots + '/aarch64/bin/app', 'changed source')!
	refused := command(binary, ['pack-catalog', path, roots, work + '/catalog-changed'])!
	assert refused.code != 0 && refused.text.contains('payload inventory differs') && !os.exists(work + '/catalog-changed')
}

fn qualify_busy_configuration(binary string, root string) ! {
	guard := pkgcore.acquire(pkgcore.state_directory(root))!
	defer { guard.release() }
	path := root + '/etc/vinix-packages/config.json'
	original := os.read_file(path)!
	defer { os.write_file(path, original) or { panic(err) } }
	os.write_file(path, '{broken configuration')!
	for args in [
		['update'], ['status'], ['list'], ['--json', 'verify'], ['plan', 'install', 'app'],
		['review', 'install', 'app'], ['apply', '0'.repeat(64), 'install', 'app'],
		['install', 'app'], ['upgrade'], ['remove', 'app'], ['rollback'], ['gc'],
		['mirror', root + '/absent-mirror', 'app'], ['deploy', root + '/absent-deployment.json'],
		['mirror-review', root + '/absent-mirror', 'app'],
		['mirror-apply', '0'.repeat(64), root + '/absent-mirror', 'app'],
		['mirror-deployment-review', root + '/absent-mirror', root + '/absent-lock.json'],
		['mirror-deployment-apply', '0'.repeat(64), root + '/absent-mirror', root + '/absent-lock.json'],
		['deployment-lock', 'app'], ['deployment-review', root + '/absent-deployment.json'],
		['deployment-apply', '0'.repeat(64), root + '/absent-deployment.json'],
		['policy'], ['policy-review', root + '/absent-policy.json'], ['policy-apply', '0'.repeat(64), root + '/absent-policy.json'],
	] {
		reply := command(binary, ['--root', root, ...args])!
		assert reply.code != 0 && reply.text.contains('another package transaction'), '${args}: ${reply.text}'
	}
}

fn qualify_configuration_schema(binary string, root string) ! {
	path := root + '/etc/vinix-packages/config.json'
	original := os.read_file(path)!
	defer { os.write_file(path, original) or { panic(err) } }
	store := pkgcore.state_directory(root)
	current := os.readlink(store + '/current')!
	retained := ['catalog.json', 'trust-history.json', current + '/state.json']
	mut hashes := []string{}
	for file in retained { hashes << pkgcore.hash_file(store + '/' + file)! }
	objects := os.ls(store + '/objects')!
	sentinel := store + '/generations/.stage-configuration-schema'
	os.mkdir_all(sentinel)!
	defer { os.rmdir_all(sentinel) or {} }
	os.write_file(sentinel + '/keep', 'retained recovery state')!
	for invalid in [original.replace('"permissions":', '"permissons":'),
		original.replace('"allowed":[]', '"allowed":null'),
		original.replace('"offline":false', '"offline":true,"off\\u006cine":false'),
		original.replace('"reserve_bytes":0', '"reserve_bytes":"0"')] {
		assert invalid != original
		os.write_file(path, invalid)!
		for arguments in [['update'], ['--json', 'verify'], ['install', 'app'], ['remove', 'app'],
			['rollback'], ['gc'], ['repo-revoke', 'fixture']] {
			reply := command(binary, ['--root', root, ...arguments])!
			assert reply.code == 1 && reply.text.contains('invalid package configuration:') && !reply.text.contains('V panic:'), reply.text
		}
		assert os.read_file(path)! == invalid && os.readlink(store + '/current')! == current
		for i, file in retained { assert pkgcore.hash_file(store + '/' + file)! == hashes[i] }
		assert os.ls(store + '/objects')! == objects
		assert os.read_file(sentinel + '/keep')! == 'retained recovery state'
	}
	os.write_file(path, original)!
	assert json2.decode[pkgcore.State](success(binary, ['--root', root, '--json', 'verify'])!)!.generation == 1
	println('Package CLI: ambiguous configuration refused without activation, cache or trust changes')
}

fn qualify(binary string) ! {
	work := os.real_path(os.temp_dir()) + '/vinix-package-cli-' + os.getpid().str()
	os.mkdir_all(work + '/root/etc/vinix-packages')!
	os.mkdir_all(work + '/payload/bin')!
	defer { os.rmdir_all(work) or {} }
	qualify_catalog_cli(binary, work)!
	key := success(binary, ['keygen', work + '/seed'])!.trim_space()
	assert key.len == 64
	assert os.stat(work + '/seed')!.mode & 0o777 == 0o600
	root_args := ['--root', work + '/root']
	repository := work + '/repository'
	config := pkgcore.Config{ architecture: 'aarch64', policy: pkgcore.Policy{ reserve_bytes: 0 } }
	os.write_file(work + '/root/etc/vinix-packages/config.json', json2.encode(config))!
	assert success(binary, [...root_args, 'repo-list'])!.contains('No trusted repositories')
	initial_policy := json2.decode[pkgcore.PolicyDocument](success(binary, [...root_args, '--offline', 'policy'])!)!
	assert !initial_policy.policy.offline && !os.exists(pkgcore.state_directory(work + '/root'))
	for id in ['app', 'other'] {
		os.write_file(work + '/payload/bin/app', id + ' payload')!
		os.chmod(work + '/payload/bin/app', 0o755)!
		os.write_file(work + '/manifest.json', json2.encode(package_template(id, '1.0.0')))!
		if id == 'other' {
			os.mkdir_all(work + '/prepared/bin')!
			os.mkdir_all(work + '/prepared/opt')!
			os.cp(work + '/payload/bin/app', work + '/prepared/bin/app')!
			os.chmod(work + '/prepared/bin/app', 0o755)!
			os.symlink('/bin/app', work + '/prepared/opt/alias')!
			recipe := pkgcore.RootRecipe{ manifest: package_template(id, '1.0.0'),
				entries: [pkgcore.RootEntry{ source: 'opt/alias', path: 'bin/app' }] }
			os.write_file(work + '/recipe.json', json2.encode(recipe))!
			packed := json2.decode[pkgcore.Package](success(binary, ['pack-root', work + '/recipe.json', work + '/prepared', repository])!)!
			assert packed.files.len == 1 && packed.files[0].executable
			assert os.is_link(work + '/prepared/opt/alias')
		} else {
			success(binary, ['pack', work + '/manifest.json', work + '/payload', repository])!
		}
	}
	success(binary, ['publish', repository, 'fixture', work + '/seed', '1',
		(time.now().unix() + 3600).str()])!
	first_index := os.read_file(repository + '/index.json')!
	first_signature := os.read_file(repository + '/index.sig')!
	expires := json2.decode[pkgcore.Index](first_index)!.expires
	release_path := work + '/published-release'
	release := json2.decode[pkgcore.ReleaseInfo](success(binary, ['publish-release', repository,
		'fixture', work + '/seed', '1', expires.str(), release_path])!)!
	assert release.format == 1 && release.public_key == key && release.sequence == 1
	assert release.directory == release_path && release.package_count == 2 && release.object_count == 2
	assert os.read_file(release_path + '/index.json')! == first_index
	assert os.read_file(release_path + '/index.sig')! == first_signature
	assert os.ls(release_path)!.len == 3 && !os.exists(release_path + '/manifests') && !os.exists(release_path + '/.publisher')
	for numbers in [['18446744073709551616', expires.str()], ['1', '9223372036854775808']] {
		assert command(binary, ['publish-release', repository, 'fixture', work + '/seed', ...numbers, work + '/overflow'])!.code != 0
		assert !os.exists(work + '/overflow')
	}
	forked_release := command(binary, ['publish-release', repository, 'fixture', work + '/seed', '1', (expires + 1).str(), work + '/fork'])!
	assert forked_release.code != 0 && forked_release.text.contains('sequence equivocation') && !os.exists(work + '/fork')
	release_root := work + '/release-client'
	os.mkdir_all(release_root + '/etc/vinix-packages')!
	os.write_file(release_root + '/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{
		architecture: 'aarch64', policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 }
	}))!
	success(binary, ['--root', release_root, 'repo-enroll', 'fixture', 'file://' + release_path, key])!
	success(binary, ['--root', release_root, 'update'])!
	success(binary, ['--root', release_root, 'install', 'app', 'other'])!
	assert json2.decode[pkgcore.State](success(binary, ['--root', release_root, '--json', 'verify'])!)!.packages.len == 2
	mut trust := pkgprotocol.decode_repository_review(success(binary, [...root_args, '--offline', 'repo-review', 'enroll', 'fixture', 'file://' + repository, key])!)!
	defer { trust.close() }
	assert trust.sequence == 1 && trust.package_count == 2 && pkgcore.load_config(work + '/root')!.repositories.len == 0
	success(binary, [...root_args, '--offline', 'repo-apply', trust.fingerprint, 'enroll', 'fixture', 'file://' + repository, key])!
	stale_trust := command(binary, [...root_args, 'repo-apply', trust.fingerprint, 'enroll', 'fixture', 'file://' + repository, key])!
	assert stale_trust.code != 0 && stale_trust.text.contains('stale')
	enrolled := json2.decode[pkgcore.RepositoryStatus](success(binary, [...root_args, '--json', 'repo-list'])!)!
	assert enrolled.repositories.len == 1 && enrolled.history.len == 1
	assert enrolled.repositories[0].public_key == key && enrolled.history[0].sequence == 1
	assert !pkgcore.load_config(work + '/root')!.policy.offline
	success(binary, [...root_args, 'update'])!
	qualify_busy_configuration(binary, work + '/root')!
	assert success(binary, [...root_args, 'search', 'distribution'])!.contains('app')
	assert command(binary, [...root_args, 'info', 'absent'])!.code != 0
	assert success(binary, [...root_args, 'plan', 'install', 'app'])!.contains('requested')
	review := json2.decode[pkgprotocol.Review](success(binary, [...root_args, 'review', 'install', 'app'])!)!
	review.validate()!
	assert review.rows.len == 1 && review.rows[0].permissions == ['files']
	assert json2.decode[pkgcore.State](success(binary, [...root_args, 'status'])!)!.generation == 0
	progress_text := success(binary, [...root_args, '--progress', 'apply', review.fingerprint, 'install', 'app'])!
	mut progress_events := []pkgprotocol.Progress{}
	for line in progress_text.split_into_lines() {
		if line.starts_with(pkgprotocol.progress_prefix) {
			progress_events << pkgprotocol.decode_progress(line[pkgprotocol.progress_prefix.len..])!
		}
	}
	assert progress_events.any(it.phase == 'download' && it.current == it.total && it.package == 'app')
	assert progress_events.any(it.phase == 'verify') && progress_events.any(it.phase == 'copy')
	assert progress_events[progress_events.len - 2].phase == 'activate' && progress_events.last().phase == 'complete'
	for args in [['--progress', 'view'], ['--json', '--progress', 'verify'], ['--progress', 'run', 'app']] {
		assert command(binary, [...root_args, ...args])!.code != 0
	}
	stale := command(binary, [...root_args, 'apply', review.fingerprint, 'install', 'app'])!
	assert stale.code != 0 && stale.text.contains('stale')
	installed := json2.decode[pkgcore.State](success(binary, [...root_args, 'status'])!)!
	assert installed.generation == 1
	assert installed.packages[0].package.id == 'app'
	qualify_configuration_schema(binary, work + '/root')!
	mut launchers := packagecore.Registry{}
	defer { launchers.close() }
	store := pkgcore.state_directory(work + '/root')
	assert launchers.refresh(store, u32(os.geteuid()), 'aarch64')!
	assert launchers.apps.len == 1
	assert launchers.apps[0].start_action == 'start.package.app'
	assert (launchers.handler('package.app', 'text/plain') or { panic('missing handler') }) == 'app'
	assert launchers.handler('package.app', 'image/png') == none
	assert !launchers.refresh(store, u32(os.geteuid()), 'aarch64')!
	mut associations := sessioncore.Associations{}
	associations.set('text/plain', 'package.' + 'a'.repeat(128), false)!
	assert sessioncore.decode_associations(associations.encode())!.count == 1
	mut installed_view := pkgprotocol.decode_software_view(success(binary, [...root_args, 'view'])!)!
	assert installed_view.generation == installed.generation && installed_view.rows.map(it.id) == ['app', 'other']
	assert installed_view.rows[0].installed_version == '1.0.0' && installed_view.rows[0].installed_kind == 'native'
	assert installed_view.rows[0].permissions == ['files'] && installed_view.rows[0].installed_permissions == ['files']
	assert installed_view.rows[1].installed_version == '' && installed_view.rows[1].installed_kind == ''
	installed_view.close()
	// An unsatisfiable installed closure is a useful failure, not an empty
	// successful Updates result. View still exposes the installed provenance.
	enrolled_config := pkgcore.load_config(work + '/root')!
	policy_path := work + '/organization-policy.json'
	os.write_file(policy_path, json2.encode(pkgcore.PolicyDocument{ architecture: 'aarch64',
		policy: pkgcore.Policy{ ...enrolled_config.policy, permissions: [] } }))!
	mut policy_review := pkgcore.decode_policy_review(success(binary, [...root_args, 'policy-review', policy_path])!)!
	defer { policy_review.close() }
	assert policy_review.rows.len == 1 && policy_review.rows[0].diagnostic_before == ''
	assert policy_review.rows[0].diagnostic_after.contains('permissions blocked')
	assert pkgcore.load_config(work + '/root')!.policy == enrolled_config.policy
	// A valid fingerprint cannot authorize an ambiguous policy file, even when
	// the decoder's last value would reproduce the reviewed policy.
	policy_text := os.read_file(policy_path)!
	for ambiguous in [policy_text.replace('"offline":false', '"offline":true,"offline":false'),
		policy_text.replace('"permissions":[]', '"permissions":["files"],"permissions":[]'),
		policy_text.replace('"policy":{', '"policy":{"allow_firmwar":true,')] {
		os.write_file(policy_path, ambiguous)!
		for operation in [['policy-review', policy_path], ['policy-apply', policy_review.fingerprint, policy_path]] {
			refused := command(binary, [...root_args, ...operation])!
			assert refused.code != 0 && refused.text.contains('document field'), refused.text
		}
		assert pkgcore.load_config(work + '/root')! == enrolled_config
		assert pkgcore.read_state(store, 'aarch64')!.generation == installed.generation
	}
	os.write_file(policy_path, policy_text)!
	success(binary, [...root_args, 'policy-apply', policy_review.fingerprint, policy_path])!
	stale_policy := command(binary, [...root_args, 'policy-apply', policy_review.fingerprint, policy_path])!
	assert stale_policy.code != 0 && stale_policy.text.contains('stale')
	assert pkgcore.load_config(work + '/root')!.repositories == enrolled_config.repositories
	mut blocked_view := pkgprotocol.decode_software_view(success(binary, [...root_args, 'view'])!)!
	assert blocked_view.update_error.contains('permissions blocked') && blocked_view.rows.all(!it.updatable)
	assert blocked_view.rows.any(it.id == 'app' && it.installed_version == '1.0.0' && it.repository == 'fixture')
	blocked_view.close()
	blocked_updates := command(binary, [...root_args, '--json', 'updates'])!
	assert blocked_updates.code != 0 && blocked_updates.text.contains('permissions blocked')
	assert pkgcore.read_state(store, 'aarch64')!.generation == installed.generation
	os.write_file(policy_path, json2.encode(pkgcore.PolicyDocument{ architecture: 'aarch64', policy: enrolled_config.policy }))!
	mut restore_policy := pkgcore.decode_policy_review(success(binary, [...root_args, 'policy-review', policy_path])!)!
	success(binary, [...root_args, 'policy-apply', restore_policy.fingerprint, policy_path])!
	restore_policy.close()
	success(binary, [...root_args, 'verify'])!
	// JSON output must not bypass integrity verification.
	installed_file := store + '/generations/' + installed.generation.str() + '/apps/app/bin/app'
	original_payload := os.read_file(installed_file)!
	os.write_file(installed_file, 'tampered payload')!
	invalid_json_verify := command(binary, [...root_args, '--json', 'verify'])!
	assert invalid_json_verify.code != 0 && invalid_json_verify.text.contains('installed payload verification failed')
	os.write_file(installed_file, original_payload)!
	assert json2.decode[pkgcore.State](success(binary, [...root_args, '--json', 'verify'])!)!.generation == installed.generation
	// A mirror is used by another completely clean installation, offline.
	mut mirror_review := pkgprotocol.decode_mirror_review(success(binary, [...root_args, 'mirror-review', work + '/mirror', 'app'])!)!
	defer { mirror_review.close() }
	assert mirror_review.review.rows.len == 1 && mirror_review.review.rows[0].action == 'export'
	assert !os.exists(work + '/mirror')
	changed_mirror := command(binary, [...root_args, 'mirror-apply', mirror_review.review.fingerprint, work + '/other-mirror', 'app'])!
	assert changed_mirror.code != 0 && changed_mirror.text.contains('stale') && !os.exists(work + '/other-mirror')
	mirror_text := success(binary, [...root_args, '--progress', 'mirror-apply', mirror_review.review.fingerprint, work + '/mirror', 'app'])!
	assert mirror_text.contains('"phase":"copy"') && mirror_text.contains('"phase":"complete"')
	assert os.ls(work)!.all(!it.starts_with('.vinix-mirror-'))
	for object in os.ls(work + '/mirror/fixture/objects')! {
		assert os.stat(work + '/mirror/fixture/objects/' + object)!.mode & 0o777 == 0o644
	}
	repeat_mirror := command(binary, [...root_args, 'mirror', work + '/mirror', 'other'])!
	assert repeat_mirror.code != 0 && repeat_mirror.text.contains('must be new')
	assert os.ls(work + '/mirror/fixture/objects')!.len == 1
	offline_root := work + '/offline'
	os.mkdir_all(offline_root + '/etc/vinix-packages')!
	offline := pkgcore.Config{ ...config, policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }
	os.write_file(offline_root + '/etc/vinix-packages/config.json', json2.encode(offline))!
	success(binary, ['--root', offline_root, 'repo-enroll', 'fixture', 'file://' + work + '/mirror/fixture', key])!
	success(binary, ['--root', offline_root, 'update'])!
	lock_path := work + '/locked-deployment.json'
	lock_text := success(binary, [...root_args, 'deployment-lock'])!
	lock_document := json2.decode[pkgcore.DeploymentLock](lock_text)!
	locked_media := work + '/locked media; $literal'
	os.write_file(lock_path, lock_text)!
	mut locked_mirror := pkgprotocol.decode_deployment_mirror_review(success(binary,
		[...root_args, 'mirror-deployment-review', locked_media, lock_path])!)!
	defer { locked_mirror.close() }
	assert locked_mirror.deployment_sha256 == pkgcore.hash_file(lock_path)!
	assert !os.exists(locked_media)
	locked_output := success(binary, [...root_args, '--progress', 'mirror-deployment-apply',
		locked_mirror.mirror.review.fingerprint, locked_media, lock_path])!
	assert locked_output.contains('"phase":"complete"')
	assert os.read_file(locked_media + '/_deployment.json')! == lock_text
	assert lock_document.format == 2 && lock_document.packages == ['app'] && lock_document.locked.len == 1
	os.write_file(lock_path, lock_text)!
	mut deploy_review := pkgprotocol.decode_review(success(binary, ['--root', offline_root, 'deployment-review', lock_path])!)!
	defer { deploy_review.close() }
	assert deploy_review.operation == 'deploy' && deploy_review.rows[0].public_key == key
	success(binary, ['--root', offline_root, 'deployment-apply', deploy_review.fingerprint, lock_path])!
	stale_deployment := command(binary, ['--root', offline_root, 'deployment-apply', deploy_review.fingerprint, lock_path])!
	assert stale_deployment.code != 0 && stale_deployment.text.contains('stale')
	assert command(binary, ['--root', offline_root, 'install', 'other'])!.code != 0
	assert json2.decode[pkgcore.State](success(binary, ['--root', offline_root, 'status'])!)!.packages.len == 1
	// Deployment reconciles roots and rollback restores the previous set.
	os.write_file(work + '/deployment.json', '{"format":1,"architecture":"aarch64","packages":["other"]}')!
	mut roots_review := pkgprotocol.decode_review(success(binary, [...root_args, 'deployment-review', work + '/deployment.json'])!)!
	success(binary, [...root_args, 'deployment-apply', roots_review.fingerprint, work + '/deployment.json'])!
	roots_review.close()
	os.write_file(work + '/invalid-deployment.json', '{"architecture":"aarch64","packages":[]}')!
	assert command(binary, [...root_args, 'deploy', work + '/invalid-deployment.json'])!.code != 0
	assert launchers.refresh(store, u32(os.geteuid()), 'aarch64')!
	assert launchers.find('app') == none
	assert (launchers.find('other') or { panic('missing application') }) == 0
	assert json2.decode[pkgcore.State](success(binary, [...root_args, 'status'])!)!.requested == ['other']
	rollback_review := json2.decode[pkgprotocol.Review](success(binary, [...root_args, 'review', 'rollback'])!)!
	assert rollback_review.rows.any(it.id == 'other' && it.action == 'remove')
	assert rollback_review.rows.any(it.id == 'app' && it.action == 'install')
	success(binary, [...root_args, 'apply', rollback_review.fingerprint, 'rollback'])!
	assert launchers.refresh(store, u32(os.geteuid()), 'aarch64')!
	assert (launchers.handler('package.app', 'text/plain') or { panic('missing handler') }) == 'app'
	assert launchers.find('other') == none
	assert json2.decode[pkgcore.State](success(binary, [...root_args, 'status'])!)!.requested == ['app']
	success(binary, ['publish', repository, 'fixture', work + '/seed', '2',
		(time.now().unix() + 3600).str()])!
	success(binary, [...root_args, 'update'])!
	latest_index := os.read_file(repository + '/index.json')!
	latest_signature := os.read_file(repository + '/index.sig')!
	// Acquisition fails after trust revocation, but uninstall remains usable.
	mut revoke := pkgprotocol.decode_repository_review(success(binary, [...root_args, 'repo-review', 'revoke', 'fixture'])!)!
	defer { revoke.close() }
	success(binary, [...root_args, 'repo-apply', revoke.fingerprint, 'revoke', 'fixture'])!
	assert command(binary, [...root_args, 'install', 'other'])!.code != 0
	assert success(binary, [...root_args, 'plan', 'remove', 'app'])!.contains('"requested":[]')
	remove_review := json2.decode[pkgprotocol.Review](success(binary, [...root_args, 'review', 'remove', 'app'])!)!
	assert remove_review.rows.all(it.action == 'remove')
	success(binary, [...root_args, 'apply', remove_review.fingerprint, 'remove', 'app'])!
	assert launchers.refresh(store, u32(os.geteuid()), 'aarch64')!
	assert launchers.apps.len == 0
	assert json2.decode[pkgcore.State](success(binary, [...root_args, 'status'])!)!.packages.len == 0
	success(binary, [...root_args, 'gc'])!
	success(binary, [...root_args, 'update'])!
	assert pkgcore.read_snapshots(store)!.len == 0
	os.write_file(repository + '/index.json', first_index)!
	os.write_file(repository + '/index.sig', first_signature)!
	replay := command(binary, [...root_args, 'repo-enroll', 'fixture', 'file://' + repository, key])!
	assert replay.code != 0 && replay.text.contains('retained trust history')
	assert pkgcore.load_config(work + '/root')!.repositories.len == 0
	os.write_file(repository + '/index.json', latest_index)!
	os.write_file(repository + '/index.sig', latest_signature)!
	success(binary, [...root_args, 'repo-enroll', 'fixture', 'file://' + repository, key])!
	success(binary, [...root_args, 'update'])!
	println('Package CLI: lock-scoped configuration, JSON verification, authenticated enrollment, offline mirror, reviewed deployment locks, rollback and revoked-publisher uninstall passed')
}

fn main() {
	if os.args.len != 2 {
		eprintln('usage: distribution-cli BINARY')
		exit(2)
	}
	qualify(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
