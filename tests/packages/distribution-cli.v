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

fn qualify(binary string) ! {
	work := os.real_path(os.temp_dir()) + '/vinix-package-cli-' + os.getpid().str()
	os.mkdir_all(work + '/root/etc/vinix-packages')!
	os.mkdir_all(work + '/payload/bin')!
	defer { os.rmdir_all(work) or {} }
	key := success(binary, ['keygen', work + '/seed'])!.trim_space()
	assert key.len == 64
	assert os.stat(work + '/seed')!.mode & 0o777 == 0o600
	root_args := ['--root', work + '/root']
	repository := work + '/repository'
	config := pkgcore.Config{ architecture: 'aarch64', policy: pkgcore.Policy{ reserve_bytes: 0 } }
	os.write_file(work + '/root/etc/vinix-packages/config.json', json2.encode(config))!
	assert success(binary, [...root_args, 'repo-list'])!.contains('No trusted repositories')
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
	assert success(binary, [...root_args, 'search', 'distribution'])!.contains('app')
	assert command(binary, [...root_args, 'info', 'absent'])!.code != 0
	assert success(binary, [...root_args, 'plan', 'install', 'app'])!.contains('requested')
	review := json2.decode[pkgprotocol.Review](success(binary, [...root_args, 'review', 'install', 'app'])!)!
	review.validate()!
	assert review.rows.len == 1 && review.rows[0].permissions == ['files']
	assert json2.decode[pkgcore.State](success(binary, [...root_args, 'status'])!)!.generation == 0
	success(binary, [...root_args, 'apply', review.fingerprint, 'install', 'app'])!
	stale := command(binary, [...root_args, 'apply', review.fingerprint, 'install', 'app'])!
	assert stale.code != 0 && stale.text.contains('stale')
	installed := json2.decode[pkgcore.State](success(binary, [...root_args, 'status'])!)!
	assert installed.generation == 1
	assert installed.packages[0].package.id == 'app'
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
	assert success(binary, [...root_args, 'view'])!.contains('installed_version')
	// An unsatisfiable installed closure is a useful failure, not an empty
	// successful Updates result. View still exposes the installed provenance.
	enrolled_config := pkgcore.load_config(work + '/root')!
	os.write_file(work + '/root/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{
		...enrolled_config, policy: pkgcore.Policy{ ...enrolled_config.policy, permissions: [] }
	}))!
	blocked_view := json2.decode[pkgcore.SoftwareView](success(binary, [...root_args, 'view'])!)!
	assert blocked_view.update_error.contains('permissions blocked') && blocked_view.rows.all(!it.updatable)
	assert blocked_view.rows.any(it.id == 'app' && it.installed_version == '1.0.0' && it.repository == 'fixture')
	blocked_updates := command(binary, [...root_args, '--json', 'updates'])!
	assert blocked_updates.code != 0 && blocked_updates.text.contains('permissions blocked')
	assert pkgcore.read_state(store, 'aarch64')!.generation == installed.generation
	os.write_file(work + '/root/etc/vinix-packages/config.json', json2.encode(enrolled_config))!
	success(binary, [...root_args, 'verify'])!
	// A mirror is used by another completely clean installation, offline.
	success(binary, [...root_args, 'mirror', work + '/mirror', 'app'])!
	offline_root := work + '/offline'
	os.mkdir_all(offline_root + '/etc/vinix-packages')!
	offline := pkgcore.Config{ ...config, policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }
	os.write_file(offline_root + '/etc/vinix-packages/config.json', json2.encode(offline))!
	success(binary, ['--root', offline_root, 'repo-enroll', 'fixture', 'file://' + work + '/mirror/fixture', key])!
	success(binary, ['--root', offline_root, 'update'])!
	success(binary, ['--root', offline_root, 'install', 'app'])!
	assert command(binary, ['--root', offline_root, 'install', 'other'])!.code != 0
	assert json2.decode[pkgcore.State](success(binary, ['--root', offline_root, 'status'])!)!.packages.len == 1
	// Deployment reconciles roots and rollback restores the previous set.
	os.write_file(work + '/deployment.json', '{"format":1,"architecture":"aarch64","packages":["other"]}')!
	success(binary, [...root_args, 'deploy', work + '/deployment.json'])!
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
	println('Package CLI: authenticated enrollment, offline mirror, retained replay floors, deployment, rollback and revoked-publisher uninstall passed')
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
