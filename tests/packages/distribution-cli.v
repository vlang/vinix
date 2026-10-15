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

// These refusal probes must fail rather than hang even against the old CLI.
// Their diagnostics fit in the pipe; collect output after bounded child exit.
fn coordination_command(binary string, arguments []string) !Reply {
	mut process := os.new_process(binary)
	defer { process.close() }
	process.set_args(arguments)
	process.set_redirect_stdio_merged()
	process.run()
	deadline := time.sys_mono_now() + 2 * time.second
	for process.is_alive() && time.sys_mono_now() < deadline { time.sleep(10 * time.millisecond) }
	if process.is_alive() {
		process.signal_kill(); process.wait()
		return error('package coordination command exceeded its two-second deadline: ${arguments}')
	}
	process.wait()
	return Reply{ code: process.code, text: process.stdout_slurp() }
}

fn C.mkfifo(&char, u32) int
fn C.link(&char, &char) int

fn qualify_coordination_files(binary string, root string) ! {
	store := pkgcore.state_directory(root)
	path := store + '/lock'
	saved := path + '.coordination-saved'
	outside := root + '/coordination-outside'
	os.write_file(outside, 'preserved')!
	os.chmod(outside, 0o600)!
	defer { os.rm(outside) or {} }
	current := os.readlink(store + '/current')!
	retained := ['catalog.json', 'trust-history.json', current + '/state.json']
	mut hashes := []string{}
	for file in retained { hashes << pkgcore.hash_file(store + '/' + file)! }
	objects := os.ls(store + '/objects')!.sorted()
	sentinel := store + '/generations/.stage-coordination-sentinel'
	os.mkdir_all(sentinel)!
	os.write_file(sentinel + '/keep', 'retained')!
	defer { os.rmdir_all(sentinel) or {} }
	for kind in ['fifo', 'directory', 'symlink', 'dangling', 'missing', 'hardlink'] {
		os.rename(path, saved)!
		match kind {
			'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
			'directory' { os.mkdir(path)! }
			'symlink' { os.symlink(outside, path)! }
			'dangling' { os.symlink(outside + '-absent', path)! }
			'hardlink' { assert C.link(outside.str, path.str) == 0 }
			else {}
		}
		mut arguments := [['status'], ['--json', 'verify'], ['plan', 'install', 'app'], ['view'], ['policy'], ['repo-list'], ['repo-config'],
			['policy-review', root + '/absent-policy.json'], ['repo-review', 'revoke', 'fixture']]
		if kind != 'missing' { arguments << [['update'], ['install', 'app'], ['remove', 'app'], ['gc']] }
		for args in arguments {
			reply := coordination_command(binary, ['--root', root, ...args])!
			assert reply.code == 1 && !reply.text.contains('V panic:')
			assert reply.text.contains('lock') || reply.text.contains('state is unavailable'), reply.text
		}
		assert os.readlink(store + '/current')! == current && os.ls(store + '/objects')!.sorted() == objects
		for i, file in retained { assert pkgcore.hash_file(store + '/' + file)! == hashes[i] }
		assert os.read_file(sentinel + '/keep')! == 'retained'
		assert os.read_file(outside)! == 'preserved' && os.lstat(outside)!.mode & 0o777 == 0o600
		if kind == 'hardlink' { println('Package CLI: hard-linked locks refuse all read/write commands before chmod and preserve trust, state, cache and recovery data') }
		if kind == 'fifo' { assert os.lstat(path)!.mode & 0o777 == 0o600 }
		if kind == 'directory' { os.rmdir(path)! }
		else if os.exists(path) || os.is_link(path) { os.rm(path)! }
		os.rename(saved, path)!
		assert json2.decode[pkgcore.State](success(binary, ['--root', root, '--json', 'verify'])!)!.generation == 1
	}
	println('Package CLI: malformed locks refuse within two seconds, preserve state/cache/history and permit verified recovery')
}

fn success(binary string, arguments []string) !string {
	result := command(binary, arguments)!
	if result.code != 0 { return error('CLI ${arguments.join(' ')} failed: ${result.text}') }
	return result.text
}

fn qualify_deployment_decoder_cli(binary string, root string, path string, text string, mirror_fingerprint string) ! {
	store := pkgcore.state_directory(root)
	current := os.readlink(store + '/current')!
	retained := [root + '/etc/vinix-packages/config.json', store + '/catalog.json',
		store + '/trust-history.json', store + '/' + current + '/state.json']
	mut hashes := []string{}
	for file in retained { hashes << pkgcore.hash_file(file)! }
	mut review := pkgprotocol.decode_review(success(binary, ['--root', root, 'deployment-review', path])!)!
	defer { review.close() }
	sentinel := store + '/generations/.stage-deployment-decode'
	os.mkdir_all(sentinel)!; os.write_file(sentinel + '/keep', 'retained')!
	defer { os.rmdir_all(sentinel) or {} }
	generation_names := os.ls(store + '/generations')!.sorted()
	objects := os.ls(store + '/objects')!.sorted()
	destination := root + '/uncreated-parent/deployment-mirror'
	for invalid in [text[..text.len / 2], text.replace('"format":2', '"format":2.0'),
		text.replace('"packages":["app"]', '"packages":["app","app"]'),
		text.replace('"minimum_sequence":1', '"minimum_sequence":18446744073709551616'),
		text.replace('"locked":[', '"locked":[null,'),
		text.replace('"id":"app"', '"id":"app","i\\u0064":"app"'),
		text.replace('"id":"app"', '"id":"' + 'a'.repeat(129) + '"')] {
		os.write_file(path, invalid)!
		for operation in [['deployment-review', path], ['deployment-apply', review.fingerprint, path], ['deploy', path],
			['deployment-audit', path], ['mirror-deployment-review', destination, path],
			['mirror-deployment-apply', mirror_fingerprint, destination, path]] {
			refused := command(binary, ['--root', root, ...operation])!
			assert refused.code != 0 && !refused.text.contains('V panic:') && refused.text.trim_space() != '', refused.text
		}
		assert os.readlink(store + '/current')! == current
		assert os.ls(store + '/generations')!.sorted() == generation_names && os.ls(store + '/objects')!.sorted() == objects
		for index, file in retained { assert pkgcore.hash_file(file)! == hashes[index] }
		assert os.read_file(sentinel + '/keep')! == 'retained' && !os.exists(root + '/uncreated-parent')
	}
	os.write_file(path, text)!
	println('Package CLI: malformed deployment review/apply/deploy/audit/mirror inputs preserve trust, catalog, activation, objects and recovery data before destination creation PASS')
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
		canonical_input.replace('"permissions":["files"]', '"permissions":["files","files"]'),
		canonical_input.replace('"permissions":["files"]', '"permissions":["audio","display","files","network","process","files"]'),
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
	for permissions in ['["files","files"]', '["audio","display","files","network","process","files"]'] {
		os.write_file(path, root_input.replace('"permissions":["files"]', '"permissions":' + permissions))!
		refused := command(binary, ['pack-root', path, roots + '/aarch64', work + '/permission-root'])!
		assert refused.code == 1 && refused.text.contains('distinct SDK 1 grants') && !refused.text.contains('V panic:'), refused.text
		assert !os.exists(work + '/permission-root')
		os.write_file(path, json2.encode(pkgcore.Package{ ...p, permissions: json2.decode[[]string](permissions)! }))!
		packed := command(binary, ['pack', path, roots + '/aarch64', work + '/permission-pack'])!
		assert packed.code == 1 && packed.text.contains('distinct SDK 1 grants') && !os.exists(work + '/permission-pack'), packed.text
	}
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
	assert !os.exists(workspace + '/index.json') && !os.exists(workspace + '/.publisher/history.json')
	assert os.ls(workspace + '/.publisher')! == ['lock']
	assert os.lstat(workspace + '/.publisher')!.mode & 0o777 == 0o700
	assert os.lstat(workspace + '/.publisher/lock')!.mode & 0o777 == 0o600
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
		['repo-config'], ['policy'], ['policy-review', root + '/absent-policy.json'], ['policy-apply', '0'.repeat(64), root + '/absent-policy.json'],
	] {
		reply := command(binary, ['--root', root, ...args])!
		assert reply.code != 0 && reply.text.contains('another package transaction'), '${args}: ${reply.text}'
	}
}

fn qualify_repository_configuration(binary string, root string) ! {
	store := pkgcore.state_directory(root)
	path := root + '/etc/vinix-packages/config.json'
	configuration := os.read_file(path)!
	config := pkgcore.load_config(root)!
	cache := os.read_file(store + '/catalog.json')!
	history := os.read_file(store + '/trust-history.json')!
	current := os.readlink(store + '/current')!
	state := os.read_file(store + '/' + current + '/state.json')!
	objects := os.ls(store + '/objects')!.sorted()
	defer {
		guard := pkgcore.acquire(store) or { panic(err) }
		os.write_file(path, configuration) or { panic(err) }
		os.write_file(store + '/catalog.json', cache) or { panic(err) }
		os.write_file(store + '/trust-history.json', history) or { panic(err) }
		guard.release()
	}
	for broken in ['cache', 'history', 'both'] {
		cached := if broken == 'history' { cache } else { '{broken catalog' }
		retained := if broken == 'cache' { history } else { '{broken replay history' }
		os.write_file(store + '/catalog.json', cached)!
		os.write_file(store + '/trust-history.json', retained)!
		mut listing := pkgprotocol.decode_repository_configuration(success(binary, ['--root', root, '--json', 'repo-config'])!)!
		assert listing.scope == 'configuration' && listing.architecture == config.architecture
		assert listing.repositories.len == config.repositories.len && listing.repositories[0].id == config.repositories[0].id
		listing.close()
		assert success(binary, ['--root', root, 'repo-config'])!.contains('have not been checked')
		assert command(binary, ['--root', root, 'repo-config', 'extra'])!.code != 0
		assert command(binary, ['--root', root, '--progress', 'repo-config'])!.code != 0
		assert command(binary, ['--root', root, '--json', 'repo-list'])!.code != 0
		repository := config.repositories[0]
		assert command(binary, ['--root', root, 'repo-review', 'enroll', repository.id, repository.url, repository.public_key])!.code != 0
		mut review := pkgprotocol.decode_repository_review(success(binary, ['--root', root, 'repo-review', 'revoke', repository.id])!)!
		assert review.operation == 'revoke' && review.public_key == repository.public_key
		if broken == 'both' {
			success(binary, ['--root', root, 'repo-apply', review.fingerprint, 'revoke', repository.id])!
			mut revoked := pkgprotocol.decode_repository_configuration(success(binary, ['--root', root, '--json', 'repo-config'])!)!
			assert revoked.repositories.len == config.repositories.len - 1
			revoked.close()
			assert command(binary, ['--root', root, 'update'])!.code != 0
		}
		review.close()
		assert os.read_file(store + '/catalog.json')! == cached
		assert os.read_file(store + '/trust-history.json')! == retained
		assert os.readlink(store + '/current')! == current
		assert os.read_file(store + '/' + current + '/state.json')! == state
		assert os.ls(store + '/objects')!.sorted() == objects
	}
	println('Package CLI: scoped repository configuration survives damaged cache/history; strict listing/enrollment/update still refuse; reviewed revocation preserves active state and recovery data')
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

fn qualify_metadata_files(binary string, root string) ! {
	store := pkgcore.state_directory(root)
	current := os.readlink(store + '/current')!
	paths := [root + '/etc/vinix-packages/config.json', store + '/catalog.json',
		store + '/trust-history.json', store + '/' + current + '/state.json']
	mut hashes := []string{}
	for path in paths { hashes << pkgcore.hash_file(path)! }
	objects := os.ls(store + '/objects')!.sorted()
	sentinel := store + '/generations/.stage-metadata-read'
	os.mkdir(sentinel)!
	os.write_file(sentinel + '/keep', 'retained recovery data')!
	defer { os.rmdir_all(sentinel) or {} }
	for index, path in paths {
		original := os.read_file(path)!
		outside := path + '.metadata-outside'
		saved := path + '.metadata-saved'
		os.write_file(outside, original)!
		os.chmod(outside, 0o600)!
		defer { os.rm(outside) or {} }
		for kind in ['fifo', 'directory', 'symlink', 'dangling', 'oversized'] {
			os.rename(path, saved)!
			match kind {
				'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
				'directory' { os.mkdir(path)! }
				'symlink' { os.symlink(outside, path)! }
				'dangling' { os.symlink(outside + '-absent', path)! }
				else {
					mut file := os.open_file(path, 'w', 0o600)!
					file.seek(pkgcore.max_metadata, .start)!; file.write_string('x')!; file.close()
				}
			}
			probes := if index in [0, 3] { [['status'], ['install', 'app'], ['gc']] }
				else { [['update'], ['install', 'app'], ['plan', 'install', 'app']] }
			for args in probes {
				reply := coordination_command(binary, ['--root', root, ...args])!
				assert reply.code == 1 && reply.text.contains('metadata must be a bounded regular file:')
					&& !reply.text.contains('V panic:'), '${path}/${kind}: ${reply.text}'
			}
			assert os.readlink(store + '/current')! == current && os.ls(store + '/objects')!.sorted() == objects
			assert os.read_file(sentinel + '/keep')! == 'retained recovery data'
			assert os.read_file(outside)! == original && os.lstat(outside)!.mode & 0o777 == 0o600
			for other, retained in paths { assert pkgcore.hash_file(if index == other { saved } else { retained })! == hashes[other] }
			if kind == 'directory' { os.rmdir(path)! } else { os.rm(path)! }
			os.rename(saved, path)!
			assert json2.decode[pkgcore.State](success(binary, ['--root', root, '--json', 'verify'])!)!.generation == 1
		}
	}
	println('Package CLI: special and oversized configuration, catalog, history and state refuse promptly, preserve recovery data and permit restored verification')
}

fn qualify_history_schema(binary string, root string, repository string, key string) ! {
	store := pkgcore.state_directory(root)
	path := store + '/trust-history.json'
	original := os.read_file(path)!
	defer { os.write_file(path, original) or { panic(err) } }
	configuration := os.read_file(root + '/etc/vinix-packages/config.json')!
	cache := os.read_file(store + '/catalog.json')!
	current := os.readlink(store + '/current')!
	for invalid in ['null', '{"format":1}', '{"format":1,"repositories":null}',
		original.replace('"repositories":', '"repositories":[],"repositories":'),
		original.replace('"sequence":2', '"sequence":1,"sequ\\u0065nce":2')] {
		assert invalid != original
		os.write_file(path, invalid)!
		for arguments in [['repo-list'], ['update'],
			['repo-review', 'enroll', 'fixture', 'file://' + repository, key],
			['repo-enroll', 'fixture', 'file://' + repository, key]] {
			reply := command(binary, ['--root', root, ...arguments])!
			assert reply.code == 1 && reply.text.contains('invalid repository trust history:') && !reply.text.contains('V panic:'), reply.text
		}
		assert os.read_file(path)! == invalid && os.read_file(store + '/catalog.json')! == cache
		assert os.read_file(root + '/etc/vinix-packages/config.json')! == configuration
		assert os.readlink(store + '/current')! == current
		assert !os.exists(store + '/refresh') && !os.exists(store + '/enrollment')
	}
	os.write_file(path, original)!
	println('Package CLI: malformed retained history refuses replay after revocation and empty refresh')
}

fn qualify_snapshot_schema(binary string, root string, repository string, key string) ! {
	store := pkgcore.state_directory(root)
	path := store + '/catalog.json'
	original := os.read_file(path)!
	defer { os.write_file(path, original) or { panic(err) } }
	current := os.readlink(store + '/current')!
	retained := ['trust-history.json', current + '/state.json']
	mut hashes := []string{}
	for file in retained { hashes << pkgcore.hash_file(store + '/' + file)! }
	configuration := os.read_file(root + '/etc/vinix-packages/config.json')!
	objects := os.ls(store + '/objects')!.sorted()
	sentinel := store + '/generations/.stage-snapshot-sentinel'
	os.mkdir(sentinel)!
	os.write_file(sentinel + '/keep', 'interrupted recovery work')!
	defer { os.rmdir_all(sentinel) or {} }
	for invalid in ['null', original.replace('"repository":', '"unknown":false,"repository":'),
		original.replace('"text":', '"te\\u0078t":"discarded","text":'),
		original.replace('"url":', '"url":null,"discard":')] {
		assert invalid != original
		os.write_file(path, invalid)!
		for arguments in [['update'], ['plan', 'install', 'app'], ['review', 'install', 'app'], ['install', 'app'],
			['repo-list'], ['repo-review', 'enroll', 'fixture', 'file://' + repository, key],
			['repo-enroll', 'fixture', 'file://' + repository, key]] {
			reply := command(binary, ['--root', root, ...arguments])!
			assert reply.code == 1 && reply.text.contains('invalid cached repository metadata:') && !reply.text.contains('V panic:'), reply.text
		}
		assert os.read_file(path)! == invalid && os.readlink(store + '/current')! == current
		assert os.read_file(root + '/etc/vinix-packages/config.json')! == configuration
		for i, file in retained { assert pkgcore.hash_file(store + '/' + file)! == hashes[i] }
		assert os.ls(store + '/objects')!.sorted() == objects && os.read_file(sentinel + '/keep')! == 'interrupted recovery work'
		assert json2.decode[pkgcore.State](success(binary, ['--root', root, '--json', 'verify'])!)!.generation == 1
		assert !os.exists(store + '/refresh') && !os.exists(store + '/enrollment')
	}
	os.write_file(path, original)!
	success(binary, ['--root', root, 'update'])!
	println('Package CLI: malformed cached snapshots preserve trust/state/recovery and permit verified refresh after restoration')
}

fn qualify_resolver_diagnostics(binary string, directory string) ! {
	os.mkdir_all(directory + '/payload/data')!
	os.write_file(directory + '/payload/data/value', 'Synthetic resolver fixture')!
	key := success(binary, ['keygen', directory + '/seed'])!.trim_space()
	repository := directory + '/repository'
	for version in ['1.0.0', '2.0.0']! {
		manifest := pkgcore.Package{ id: 'app', name: 'Application', version: version, architecture: 'all', kind: 'data',
			license: if version == '2.0.0' { 'Vendor-EULA' } else { 'MIT' }, proprietary: version == '2.0.0',
			dependencies: [pkgcore.Dependency{id: 'absent', minimum: '1.0.0', before: '3.0.0'}] }
		os.write_file(directory + '/manifest.json', json2.encode(manifest))!
		success(binary, ['pack', directory + '/manifest.json', directory + '/payload', repository])!
	}
	// Legacy publication permits incomplete catalogs; release publication must
	// still reject them. Consumers report the same precise cause through the CLI.
	expires := (time.now().unix() + 3600).str()
	success(binary, ['publish', repository, 'fixture', directory + '/seed', '1', expires])!
	refused_release := command(binary, ['publish-release', repository, 'fixture', directory + '/seed', '1', expires, directory + '/release'])!
	assert refused_release.code == 1 && refused_release.text.contains('Dependency path: app -> absent') && !os.exists(directory + '/release')
	for architecture in ['aarch64', 'x86_64']! {
		root := directory + '/' + architecture
		os.mkdir_all(root + '/etc/vinix-packages')!
		config := pkgcore.Config{ architecture: architecture, repositories: [pkgcore.Repository{ id: 'fixture', url: 'file://' + repository, public_key: key }], policy: pkgcore.Policy{ reserve_bytes: 0 } }
		os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
		success(binary, ['--root', root, 'update'])!
		store := pkgcore.state_directory(root)
		catalog := os.read_file(store + '/catalog.json')!; history := os.read_file(store + '/trust-history.json')!
		for args in [['plan', 'install', 'app'], ['review', 'install', 'app'], ['install', 'app']] {
			reply := command(binary, ['--root', root, ...args])!
			assert reply.code == 1 && reply.text.contains('absent') && !reply.text.contains('Vendor-EULA'), reply.text
			assert reply.text.contains('Dependency path: app -> absent') && reply.text.contains('Requirement: absent >= 1.0.0 < 3.0.0'), reply.text
			assert !os.exists(store + '/current') && !os.is_link(store + '/current')
			assert os.read_file(store + '/catalog.json')! == catalog && os.read_file(store + '/trust-history.json')! == history
		}
	}
	println('Package CLI: signed policy fallback reports the current missing requirement and dependency path on both targets; plan/review/install refusal preserves trust and activation, and release closure refusal stays explicit PASS')
}

fn qualify_install_preference(binary string, directory string) ! {
	os.mkdir_all(directory + '/payload/data')!
	os.write_file(directory + '/payload/data/value', 'Synthetic installed-preference payload')!
	key := success(binary, ['keygen', directory + '/seed'])!.trim_space()
	repository := directory + '/repository'
	mut ids := ['base']
	for i in 0 .. 20 { ids << 'node-' + i.str() }
	for id in ids {
		manifest := pkgcore.Package{id: id, name: id, version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT'}
		os.write_file(directory + '/manifest.json', json2.encode(manifest))!
		success(binary, ['pack', directory + '/manifest.json', directory + '/payload', repository])!
	}
	expires := (time.now().unix() + 3600).str()
	success(binary, ['publish', repository, 'fixture', directory + '/seed', '1', expires])!
	for architecture in ['aarch64', 'x86_64']! {
		root := directory + '/' + architecture
		os.mkdir_all(root + '/etc/vinix-packages')!
		config := pkgcore.Config{architecture: architecture, repositories: [pkgcore.Repository{id: 'fixture', url: 'file://' + repository, public_key: key}], policy: pkgcore.Policy{offline: true, reserve_bytes: 0}}
		os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
		success(binary, ['--root', root, 'update'])!
		success(binary, ['--root', root, 'install', ...ids])!
	}
	for id in ['base', 'node-0', 'zz-addon']! {
		manifest := pkgcore.Package{id: id, name: id, version: if id == 'zz-addon' { '1.0.0' } else { '2.0.0' },
			architecture: 'all', kind: 'data', license: 'MIT',
			dependencies: if id == 'zz-addon' { [pkgcore.Dependency{id: 'base', minimum: '2.0.0'}] } else { []pkgcore.Dependency{} }}
		os.write_file(directory + '/manifest.json', json2.encode(manifest))!
		success(binary, ['pack', directory + '/manifest.json', directory + '/payload', repository])!
	}
	success(binary, ['publish', repository, 'fixture', directory + '/seed', '2', expires])!
	for architecture in ['aarch64', 'x86_64']! {
		root := directory + '/' + architecture
		success(binary, ['--root', root, 'update'])!
		store := pkgcore.state_directory(root)
		before := os.readlink(store + '/current')!
		history := os.read_file(store + '/trust-history.json')!; catalog := os.read_file(store + '/catalog.json')!
		for operation in [['plan', 'install', 'zz-missing'], ['review', 'install', 'zz-missing'], ['install', 'zz-missing']] {
			reply := command(binary, ['--root', root, ...operation])!
			assert reply.code == 1 && reply.text.contains('zz-missing') && !reply.text.contains('search limit'), reply.text
			assert os.readlink(store + '/current')! == before && os.read_file(store + '/trust-history.json')! == history && os.read_file(store + '/catalog.json')! == catalog
		}
		success(binary, ['--root', root, 'plan', 'install', 'zz-addon'])!
		mut review := pkgprotocol.decode_review(success(binary, ['--root', root, '--json', 'review', 'install', 'zz-addon'])!)!
		defer { review.close() }
		assert review.rows.any(it.id == 'base' && it.version == '2.0.0') && review.rows.any(it.id == 'zz-addon')
		assert os.readlink(store + '/current')! == before
		success(binary, ['--root', root, 'apply', review.fingerprint, 'install', 'zz-addon'])!
		state := pkgcore.read_state(store, architecture)!
		assert state.generation == 2 && state.previous == 1 && state.packages.len == 22
		assert state.packages.filter(it.package.id == 'base')[0].package.version == '2.0.0'
		assert state.packages.filter(it.package.id == 'node-0')[0].package.version == '1.0.0'
		success(binary, ['--root', root, 'verify'])!
		success(binary, ['--root', root, 'rollback'])!
		assert pkgcore.read_state(store, architecture)!.packages.len == 21
		success(binary, ['--root', root, 'verify'])!
	}
	println('Package CLI: signed offline install backtracks past 20 unrelated installed identities; exact installed preference, missing-requirement refusal, reviewed activation and rollback pass on both targets PASS')
}

fn qualify_removal_guidance(binary string, directory string) ! {
	os.mkdir_all(directory + '/payload/data')!
	os.write_file(directory + '/payload/data/value', 'Synthetic dependency-removal payload')!
	key := success(binary, ['keygen', directory + '/seed'])!.trim_space()
	repository := directory + '/repository'
	for id in ['editor', 'bridge', 'shared']! {
		manifest := pkgcore.Package{id: id, name: id, version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT',
			dependencies: if id == 'editor' { [pkgcore.Dependency{id: 'bridge'}] } else if id == 'bridge' { [pkgcore.Dependency{id: 'shared'}] } else { []pkgcore.Dependency{} }}
		os.write_file(directory + '/manifest.json', json2.encode(manifest))!
		success(binary, ['pack', directory + '/manifest.json', directory + '/payload', repository])!
	}
	success(binary, ['publish', repository, 'fixture', directory + '/seed', '1', (time.now().unix() + 3600).str()])!
	for architecture in ['aarch64', 'x86_64']! {
		root := directory + '/' + architecture
		os.mkdir_all(root + '/etc/vinix-packages')!
		config := pkgcore.Config{architecture: architecture, repositories: [pkgcore.Repository{id: 'fixture', url: 'file://' + repository, public_key: key}], policy: pkgcore.Policy{offline: true, reserve_bytes: 0}}
		os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
		success(binary, ['--root', root, 'update'])!
		success(binary, ['--root', root, 'install', 'editor', 'shared'])!
	}
	os.rmdir_all(repository)!
	for architecture in ['aarch64', 'x86_64']! {
		root := directory + '/' + architecture
		store := pkgcore.state_directory(root)
		for revoked in [false, true]! {
			if revoked {
				mut review := pkgprotocol.decode_repository_review(success(binary, ['--root', root, 'repo-review', 'revoke', 'fixture'])!)!
				success(binary, ['--root', root, 'repo-apply', review.fingerprint, 'revoke', 'fixture'])!
				review.close()
				os.write_file(store + '/catalog.json', '{unavailable catalog')!
				os.write_file(store + '/trust-history.json', '{unavailable history')!
			}
			before := os.readlink(store + '/current')!
			state := os.read_file(store + '/' + before + '/state.json')!
			catalog := os.read_file(store + '/catalog.json')!; history := os.read_file(store + '/trust-history.json')!
			config := os.read_file(root + '/etc/vinix-packages/config.json')!
			generations := os.ls(store + '/generations')!.sorted()
			for id in ['shared', 'bridge']! {
				for operation in [['plan', 'remove', id], ['review', 'remove', id], ['remove', id]] {
					reply := command(binary, ['--root', root, ...operation])!
					assert reply.code == 1 && reply.text.contains('required by requested package editor'), reply.text
					assert reply.text.contains(if id == 'shared' { 'cannot remove shared' } else { 'bridge is not explicitly installed' }), reply.text
					assert os.readlink(store + '/current')! == before && os.read_file(store + '/' + before + '/state.json')! == state
					assert os.read_file(store + '/catalog.json')! == catalog && os.read_file(store + '/trust-history.json')! == history
					assert os.read_file(root + '/etc/vinix-packages/config.json')! == config && os.ls(store + '/generations')!.sorted() == generations
				}
			}
		}
		for object in os.ls(store + '/objects')! { os.rm(store + '/objects/' + object)! }
		mut review := pkgprotocol.decode_review(success(binary, ['--root', root, '--json', 'review', 'remove', 'editor'])!)!
		success(binary, ['--root', root, 'apply', review.fingerprint, 'remove', 'editor'])!
		review.close()
		state := pkgcore.read_state(store, architecture)!
		assert state.generation == 2 && state.requested == ['shared'] && state.packages.len == 1
		assert state.packages[0].package.id == 'shared'
		success(binary, ['--root', root, 'remove', 'shared'])!
		assert pkgcore.read_state(store, architecture)!.packages.len == 0
	}
	println('Package CLI: explicit and implicit removal refusals name a retained requested package on both targets; offline/revoked/damaged-cache refusals preserve state and reviewed dependent removal remains available PASS')
}

fn qualify(binary string) ! {
	work := os.real_path(os.temp_dir()) + '/vinix-package-cli-' + os.getpid().str()
	os.mkdir_all(work + '/root/etc/vinix-packages')!
	os.mkdir_all(work + '/payload/bin')!
	defer { os.rmdir_all(work) or {} }
	qualify_catalog_cli(binary, work)!
	qualify_resolver_diagnostics(binary, work + '/resolver-diagnostics')!
	qualify_install_preference(binary, work + '/install-preference')!
	qualify_removal_guidance(binary, work + '/removal-guidance')!
	key := success(binary, ['keygen', work + '/seed'])!.trim_space()
	assert key.len == 64
	assert os.stat(work + '/seed')!.mode & 0o777 == 0o600
	seed_text := os.read_file(work + '/seed')!
	assert success(binary, ['key-public', work + '/seed'])!.trim_space() == key
	assert command(binary, ['keygen', work + '/seed'])!.code == 1
	assert command(binary, ['key-public'])!.code == 1
	os.chmod(work + '/seed', 0o644)!
	assert command(binary, ['key-public', work + '/seed'])!.code == 1
	os.chmod(work + '/seed', 0o600)!
	assert success(binary, ['key-public', work + '/seed'])!.trim_space() == key && os.read_file(work + '/seed')! == seed_text
	println('Package CLI: durable private key creation, existing-seed refusal and read-only public-key recovery passed')
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
	publisher_history_path := repository + '/.publisher/history.json'
	publisher_history := os.read_file(publisher_history_path)!
	for invalid in ['null', '{"format":1}', '{"format":1,"indexes":null}',
		publisher_history.replace('"sequence":1', '"sequence":2,"sequ\\u0065nce":1')] {
		os.write_file(publisher_history_path, invalid)!
		refused := command(binary, ['publish-release', repository, 'fixture', work + '/seed', '1', expires.str(), work + '/history-refused-release'])!
		assert refused.code == 1 && refused.text.contains('invalid publisher release history:') && !refused.text.contains('V panic:'), refused.text
		assert os.read_file(publisher_history_path)! == invalid && !os.exists(work + '/history-refused-release')
		assert os.read_file(release_path + '/index.json')! == first_index
		assert os.read_file(release_path + '/index.sig')! == first_signature
	}
	os.write_file(publisher_history_path, publisher_history)!
	println('Package CLI: malformed publisher history refuses release without changing prior publication')
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
	qualify_repository_configuration(binary, work + '/root')!
	qualify_coordination_files(binary, work + '/root')!
	qualify_metadata_files(binary, work + '/root')!
	qualify_configuration_schema(binary, work + '/root')!
	qualify_snapshot_schema(binary, work + '/root', repository, key)!
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
	qualify_deployment_decoder_cli(binary, work + '/root', lock_path, lock_text, locked_mirror.mirror.review.fingerprint)!
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
	qualify_history_schema(binary, work + '/root', repository, key)!
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
