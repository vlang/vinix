// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

#include <sys/resource.h>
fn C.link(&char, &char) int

struct PackageCollectionLimit {
	current u64
	maximum u64
}

fn package_collection_limit_probe(root string) !int {
	mut original := PackageCollectionLimit{}
	if C.getrlimit(C.RLIMIT_NOFILE, voidptr(&original)) != 0 { return error('cannot read collector descriptor limit') }
	limited := PackageCollectionLimit{ current: 32, maximum: original.maximum }
	if C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limited)) != 0 { return error('cannot lower collector descriptor limit') }
	mut actual := PackageCollectionLimit{}
	if C.getrlimit(C.RLIMIT_NOFILE, voidptr(&actual)) != 0 || actual.current != 32 {
		return error('collector descriptor limit was not applied')
	}
	arguments := [c'/usr/bin/vinix-package', c'--root', &char(root.str), c'gc', &char(unsafe { nil })]!
	C.execv(c'/usr/bin/vinix-package', unsafe { &arguments[0] })
	return error('cannot execute the limited package collector')
}

fn reviewed_package_operation(operation string, names []string) !string {
	mut review := pkgprotocol.decode_review(package_success(['review', operation, ...names])!)!
	defer { review.close() }
	return package_success(['apply', review.fingerprint, operation, ...names])
}

fn package_progress_events(text string) ![]pkgprotocol.Progress {
	mut events := []pkgprotocol.Progress{}
	for line in text.split_into_lines() {
		if line.starts_with(pkgprotocol.progress_prefix) { events << pkgprotocol.decode_progress(line[pkgprotocol.progress_prefix.len..])! }
	}
	return events
}

fn qualify_package_download_refusal(root string, architecture string, repository string, key string, application pkgcore.Package) ! {
	os.mkdir_all(root + '/etc/vinix-packages')!
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{
		architecture: architecture, policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 }
	}))!
	package_success(['--root', root, 'repo-enroll', 'fixture', 'file://' + repository, key])!
	package_success(['--root', root, 'update'])!
	package_success(['--root', root, 'install', application.id])!
	package_success(['--root', root, 'remove', application.id])!
	payload := application.files.filter(it.path == 'bin/probe')[0]
	directory := pkgcore.state_directory(root)
	object := directory + '/objects/' + payload.sha256
	part := object + '.part'
	source := repository + '/objects/' + payload.sha256
	original := os.read_bytes(source)!
	defer { os.write_file_array(source, original) or { panic(err) } }
	os.rm(object)!
	os.write_file(part, 'damaged prefix')!
	os.write_file(source, 'x'.repeat(int(payload.bytes)))!
	refused := run(['/usr/bin/vinix-package', '--root', root, '--progress', 'install', application.id], '', none, none)
	assert refused.status != 0 && refused.output.contains('payload checksum or size mismatch'), refused.output
	assert refused.output.count('resumed payload failed verification') == 1
	events := package_progress_events(refused.output)!
	assert events.filter(it.phase == 'verify' && it.path == payload.path).len == 2
	assert events.all(it.phase !in ['activate', 'complete'])
	assert !os.exists(object) && !os.exists(part)
	assert os.ls(directory + '/generations')!.sorted() == ['1', '2']
	assert pkgcore.read_state(directory, architecture)!.generation == 2
	package_success(['--root', root, 'verify'])!
	package_success(['--root', root, 'rollback'])!
	package_success(['--root', root, 'verify'])!
	assert pkgcore.read_state(directory, architecture)!.generation == 1
}

fn qualify_package_oversized_offline_source(architecture string, repository string, key string, application pkgcore.Package) ! {
	root := '/tmp/oversized-source-client'
	os.mkdir_all(root + '/etc/vinix-packages')!
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{
		architecture: architecture, policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 }
	}))!
	package_success(['--root', root, 'repo-enroll', 'fixture', 'file://' + repository, key])!
	package_success(['--root', root, 'update'])!
	package_success(['--root', root, 'install', application.id])!
	package_success(['--root', root, 'remove', application.id])!
	payload := application.files.filter(it.path == 'bin/probe')[0]
	directory := pkgcore.state_directory(root)
	object := directory + '/objects/' + payload.sha256
	part := object + '.part'
	source := repository + '/objects/' + payload.sha256
	original := os.read_bytes(source)!
	assert original.len > 64
	defer { os.write_file_array(source, original) or { panic(err) } }
	os.rm(object)!
	os.write_file_array(part, original[..64])!
	mut oversized := original.clone(); oversized << u8(0)
	os.write_file_array(source, oversized)!
	refused := run(['/usr/bin/vinix-package', '--root', root, '--progress', 'install', application.id], '', none, none)
	assert refused.status != 0 && refused.output.contains('exceeds authenticated size'), refused.output
	assert os.read_bytes(part)! == original[..64] && !os.exists(object)
	assert pkgcore.read_state(directory, architecture)!.generation == 2
	assert os.ls(directory + '/generations')!.sorted() == ['1', '2']
	assert package_progress_events(refused.output)!.all(it.phase !in ['activate', 'complete'])
	package_success(['--root', root, 'verify'])!
	os.write_file_array(source, original)!
	recovered := package_success(['--root', root, '--progress', 'install', application.id])!
	assert package_progress_events(recovered)!.filter(it.phase == 'download' && it.package == application.id && it.path == payload.path).first().current == 64
	assert pkgcore.verified_file(object, payload) && !os.exists(part)
	assert pkgcore.read_state(directory, architecture)!.generation == 3
	package_success(['--root', root, 'verify'])!
}

fn qualify_package_configuration_lock() ! {
	guard := pkgcore.acquire('/var/lib/vinix-packages')!
	defer { guard.release() }
	path := '/etc/vinix-packages/config.json'
	original := os.read_file(path)!
	defer { os.write_file(path, original) or { panic(err) } }
	os.write_file(path, '{broken configuration')!
	for args in [
		['update'], ['status'], ['--json', 'verify'], ['review', 'install', 'linux-probe'],
		['apply', '0'.repeat(64), 'install', 'linux-probe'], ['rollback'], ['gc'],
		['run', 'linux-probe'],
		['policy'], ['policy-review', '/tmp/absent-policy.json'],
		['policy-apply', '0'.repeat(64), '/tmp/absent-policy.json'],
		['deployment-lock'], ['deployment-review', '/tmp/absent-deployment.json'],
		['deployment-apply', '0'.repeat(64), '/tmp/absent-deployment.json'],
		['mirror-review', '/tmp/missing-media/export', 'linux-probe'],
		['mirror-apply', '0'.repeat(64), '/tmp/missing-media/export', 'linux-probe'],
		['mirror-deployment-review', '/tmp/missing-media/export', '/tmp/missing-lock.json'],
		['mirror-deployment-apply', '0'.repeat(64), '/tmp/missing-media/export', '/tmp/missing-lock.json'],
	] {
		busy := run(['/usr/bin/vinix-package', ...args], '', none, none)
		assert busy.status != 0 && busy.output.contains('another package transaction'), busy.output
	}
}

fn qualify_package_payload_hash(architecture string, application pkgcore.Package) ! {
	root := '/tmp/oversized-source-client'
	directory := pkgcore.state_directory(root)
	before := pkgcore.read_state(directory, architecture)!
	assert before.generation == 3
	payload := application.files.filter(it.path == 'bin/probe')[0]
	path := directory + '/generations/3/apps/' + application.id + '/' + payload.path
	original := os.read_bytes(path)!
	assert pkgcore.hash_file(path)! == payload.sha256 && pkgcore.verified_file(path, payload)
	outside := '/tmp/hash-outside'
	os.write_file_array(outside, original)!
	os.chmod(outside, 0o600)!
	for kind in ['alias', 'fifo', 'directory', 'wrong-length', 'wrong-bytes'] {
		os.rename(path, path + '.saved')!
		match kind {
			'alias' { os.symlink(outside, path)! }
			'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
			'directory' { os.mkdir(path)! }
			'wrong-length' { mut bytes := original.clone(); bytes << u8(0); os.write_file_array(path, bytes)! }
			'wrong-bytes' { mut bytes := original.clone(); bytes[0] ^= 1; os.write_file_array(path, bytes)! }
			else { return error('unknown payload hash fixture') }
		}
		assert !pkgcore.verified_file(path, payload), kind
		if kind in ['alias', 'fifo', 'directory'] {
			mut refused := false
			pkgcore.hash_file(path) or { refused = true }
			assert refused, kind
		}
		refused := run(['/usr/bin/vinix-package', '--root', root, 'verify'], '', none, none)
		assert refused.status != 0 && refused.output.contains('installed payload verification failed'), refused.output
		assert pkgcore.read_state(directory, architecture)! == before
		assert os.ls(directory + '/generations')!.sorted() == ['1', '2', '3']
		assert os.read_bytes(outside)! == original && mode_of(outside) == 0o600
		assert os.read_bytes(path + '.saved')! == original
		if kind == 'directory' { os.rmdir(path)! } else { os.rm(path)! }
		os.rename(path + '.saved', path)!
		assert pkgcore.verified_file(path, payload)
		package_success(['--root', root, 'verify'])!
	}
	assert !pkgcore.verified_file(path + '\x00ignored', payload)
	mut refused := false
	pkgcore.hash_file(path + '\x00ignored') or { refused = true }
	assert refused
}

fn qualify_package_atomic_metadata(architecture string) ! {
	root := '/tmp/oversized-source-client'
	directory := pkgcore.state_directory(root)
	before := pkgcore.read_state(directory, architecture)!
	history := pkgcore.repository_status(root)!.history
	victim := '/tmp/atomic-metadata-outside'
	os.write_file(victim, 'preserved outside metadata')!
	os.chmod(victim, 0o600)!
	config := root + '/etc/vinix-packages/config.json'
	configuration := os.read_file(config)!
	for path in [config + '.new', directory + '/trust-history.json.new'] { os.symlink(victim, path)! }
	legacy := directory + '/catalog.json.new'
	for kind in ['alias', 'hardlink', 'fifo', 'directory'] {
		match kind {
			'alias' { os.symlink(victim, legacy)! }
			'hardlink' { assert C.link(victim.str, legacy.str) == 0 }
			'fifo' { assert C.mkfifo(legacy.str, 0o600) == 0 }
			'directory' { os.mkdir(legacy)! }
			else { return error('unknown stale metadata fixture') }
		}
		package_success(['--root', root, 'update'])!
		assert !os.is_link(directory + '/catalog.json')
		assert os.read_file(victim)! == 'preserved outside metadata' && mode_of(victim) == 0o600
		assert os.read_file(config)! == configuration
		assert pkgcore.read_state(directory, architecture)! == before
		assert pkgcore.repository_status(root)!.history == history
		assert os.ls(directory)!.all(!it.starts_with('.package-'))
		assert os.ls(root + '/etc/vinix-packages')!.all(!it.starts_with('.package-'))
		package_success(['--root', root, 'verify'])!
		if kind == 'directory' { assert os.ls(legacy)!.len == 0; os.rmdir(legacy)! }
		else { os.rm(legacy)! }
	}
	for path in [config + '.new', directory + '/trust-history.json.new'] { assert os.is_link(path); os.rm(path)! }
	os.mkdir('/tmp/atomic-outside-folder')!
	os.symlink('/tmp/atomic-outside-folder', '/tmp/atomic-destination')!
	pkgcore.atomic_write('/tmp/atomic-destination', 'complete metadata')!
	assert !os.is_link('/tmp/atomic-destination') && os.read_file('/tmp/atomic-destination')! == 'complete metadata'
	assert os.ls('/tmp/atomic-outside-folder')!.len == 0
	mut refused := false
	pkgcore.atomic_write('/tmp/atomic-destination\x00ignored', 'unsafe metadata') or { refused = true }
	assert refused && os.read_file('/tmp/atomic-destination')! == 'complete metadata'
}

fn qualify_package_stored_state(root string, architecture string, application_id string, runtime_id string) ! {
	directory := pkgcore.state_directory(root)
	path := directory + '/generations/1/state.json'
	text := os.read_file(path)!
	original := pkgcore.read_state(directory, architecture)!
	assert original.generation == 1 && original.previous == 0
	package_success(['--root', root, 'remove', application_id])!
	assert pkgcore.read_state(directory, architecture)!.generation == 2
	os.mkdir(directory + '/generations/3')!
	os.write_file(directory + '/generations/3/lease', '')!
	orphan := directory + '/objects/' + 'f'.repeat(64)
	assert !os.exists(orphan)
	os.write_file(orphan, 'unused cache sentinel')!
	// This data package satisfies the dependency's version and validates on
	// its own, but cannot provide the application's executable runtime.
	bad := pkgcore.State{ ...original, packages: original.packages.map(if it.package.id == runtime_id {
		pkgcore.Installed{ ...it, package: pkgcore.Package{ ...it.package, kind: 'data', architecture: 'all' } }
	} else { it }) }
	os.write_file(path, json2.encode(bad))!
	for command in ['rollback', 'gc'] {
		refused := run(['/usr/bin/vinix-package', '--root', root, command], '', none, none)
		assert refused.status != 0 && refused.output.contains('persistent isolated runtime'), refused.output
		assert os.is_dir(directory + '/generations/3') && os.exists(orphan)
		assert os.readlink(directory + '/current')! == 'generations/2'
	}
	os.write_file(path, text)!
	package_success(['--root', root, 'gc'])!
	assert !os.exists(directory + '/generations/3') && !os.exists(orphan)
	package_success(['--root', root, 'rollback'])!
	package_success(['--root', root, 'verify'])!
	os.write_file(path, text.replace('"generation":1', '"generation":1,"generat\\u0069on":1'))!
	for command in ['status', 'verify', 'view', 'gc'] {
		refused := run(['/usr/bin/vinix-package', '--root', root, command], '', none, none)
		assert refused.status != 0 && refused.output.contains('duplicate administration document field'), refused.output
	}
	os.write_file(path, text)!
	os.mkdir(directory + '/generations/01')!
	os.write_file(directory + '/generations/01/state.json', text)!
	os.rm(directory + '/current')!
	os.symlink('generations/01', directory + '/current')!
	alias := run(['/usr/bin/vinix-package', '--root', root, 'status'], '', none, none)
	assert alias.status != 0 && alias.output.contains('canonical positive u64'), alias.output
	os.rm(directory + '/current')!
	os.symlink('generations/1', directory + '/current')!
	os.rmdir_all(directory + '/generations/01')!
	package_success(['--root', root, 'verify'])!
	// Generation 2 already exists. Add 127 obsolete published directories so
	// the production CLI must handle 128 candidates under a 32-FD limit.
	for generation in 3 .. 130 {
		path_generation := directory + '/generations/' + generation.str()
		os.mkdir(path_generation)!
		os.write_file(path_generation + '/lease', '')!
		os.write_file(path_generation + '/payload', 'lease sentinel')!
	}
	lease := C.open((directory + '/generations/64/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	assert lease >= 0 && C.flock(lease, C.LOCK_SH) == 0
	defer { C.close(lease) }
	os.write_file(orphan, 'unused cache sentinel')!
	limited_gc := run(['/sbin/init', 'package-collection-limit-probe', root], '', none, none)
	assert limited_gc.status == 0, limited_gc.output
	assert os.ls(directory + '/generations')!.sorted() == ['1', '64']
	assert os.read_file(directory + '/generations/64/payload')! == 'lease sentinel'
	assert !os.exists(orphan) && os.readlink(directory + '/current')! == 'generations/1'
	assert C.flock(lease, C.LOCK_UN) == 0
	package_success(['--root', root, 'gc'])!
	assert os.ls(directory + '/generations')! == ['1']
	package_success(['--root', root, 'verify'])!
}

fn qualify_package_linux(mut t Test) ! {
	// Crypto's gc-none allocations belong to the probe process, not PID 1's
	// later package workflow. Reap it before starting installation scenarios.
	signing_probe := run(['/sbin/init', 'package-signing-probe'], '', none, none)
	assert signing_probe.status == 0, signing_probe.output
	t.say('PACKAGE SIGNING rfc8032 reference-keys reference-signatures tamper-refusal PASS')
	db := t.make_accounts()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	source_roots := '/tmp/linux-catalog-roots'
	prepared := source_roots + '/' + architecture
	for directory in ['bin', 'lib', 'usr/lib', 'licenses'] {
		os.mkdir_all(prepared + '/' + directory)!
	}
	for source, destination in {
		'linux-probe':   'bin/probe'
		'linux-runner':  'bin/vinix-linux-runner'
		'musl':          'lib/libc.so'
		'linux-library': 'usr/lib/libfixture.so.1'
	} {
		os.cp('/usr/share/package-fixtures/' + source, prepared + '/' + destination)!
		os.chmod(prepared + '/' + destination, 0o755)!
	}
	os.symlink('/lib/libc.so', prepared + '/lib/ld-musl-' + architecture + '.so.1')!
	os.symlink('libfixture.so.1', prepared + '/usr/lib/libfixture.so')!
	os.write_file(prepared + '/licenses/COPYING', read_text('/usr/share/package-fixtures/COPYING'))!
	os.write_file(prepared + '/licenses/musl-COPYRIGHT', read_text('/usr/share/package-fixtures/musl-COPYRIGHT'))!
	repository := '/tmp/linux-repository'
	runtime := pkgcore.Package{
		id:           'musl-fixture'
		version:      '1.0.0'
		architecture: architecture
		name:         'Explicit musl Linux runtime fixture'
		license:      'GPL-2.0-or-later AND MIT'
		kind:         'runtime'
	}
	application := pkgcore.Package{
		id:           'linux-probe'
		version:      '1.0.0'
		architecture: architecture
		name:         'Dynamic Linux qualification'
		license:      'GPL-2.0-or-later'
		kind:         'linux'
		runtime:      runtime.id
		entrypoint:   'bin/vinix-linux-runner'
		arguments:    ['@RUNTIME@/lib/ld-musl-' + architecture + '.so.1', '@APP@/bin/probe',
			'a space; $literal', '@unchanged']
		dependencies: [pkgcore.Dependency{ id: runtime.id, minimum: '1.0.0', before: '2.0.0' }]
	}
	mut catalog_imports := []pkgcore.CatalogImport{}
	for recipe in [
		pkgcore.RootRecipe{
			manifest: runtime
			entries:  [
				pkgcore.RootEntry{ source: 'bin/vinix-linux-runner', path: 'bin/vinix-linux-runner' },
				pkgcore.RootEntry{ source: 'lib', path: 'lib' },
				pkgcore.RootEntry{ source: 'usr/lib', path: 'usr/lib' },
				pkgcore.RootEntry{ source: 'licenses', path: 'licenses' },
			]
		},
		pkgcore.RootRecipe{
			manifest: application
			entries:  [
				pkgcore.RootEntry{ source: 'bin/probe', path: 'bin/probe' },
				pkgcore.RootEntry{ source: 'licenses/COPYING', path: 'licenses/COPYING' },
			]
		},
	] {
		os.write_file('/tmp/linux-recipe.json', json2.encode(recipe))!
		packed := json2.decode[pkgcore.Package](package_success(['pack-root', '/tmp/linux-recipe.json',
			prepared, '/tmp/linux-single-imports'])!)!
		assert packed.id == recipe.manifest.id && packed.files.len > 0
		catalog_imports << pkgcore.CatalogImport{ source: architecture,
			recipe: pkgcore.RootRecipe{ ...recipe, manifest: packed } }
	}
	catalog_path := '/tmp/linux-catalog.json'
	os.write_file(catalog_path, json2.encode(pkgcore.CatalogRecipe{ format: 1,
		architectures: [architecture], packages: catalog_imports }))!
	catalog := json2.decode[pkgcore.CatalogInfo](package_success(['pack-catalog', catalog_path, source_roots, repository])!)!
	assert catalog.package_count == 2 && catalog.architectures == [architecture]
	assert os.stat(repository)!.mode & 0o777 == 0o700
	catalog_imports.reverse_in_place()
	os.write_file(catalog_path, json2.encode(pkgcore.CatalogRecipe{ format: 1,
		architectures: [architecture], packages: catalog_imports }))!
	second_catalog := json2.decode[pkgcore.CatalogInfo](package_success(['pack-catalog', catalog_path,
		source_roots, '/tmp/linux-catalog-reordered'])!)!
	assert second_catalog.catalog_sha256 == catalog.catalog_sha256
	catalog_probe_bytes := os.read_bytes(prepared + '/bin/probe')!
	os.write_file(prepared + '/bin/probe', 'changed bytes')!
	changed_catalog := run(['/usr/bin/vinix-package', 'pack-catalog', catalog_path,
		source_roots, '/tmp/linux-catalog-changed'], '', none, none)
	assert changed_catalog.status != 0 && changed_catalog.output.contains('payload inventory differs'), changed_catalog.output
	assert !os.exists('/tmp/linux-catalog-changed') && os.ls('/tmp')!.all(!it.starts_with('.vinix-catalog-'))
	os.write_file_array(prepared + '/bin/probe', catalog_probe_bytes)!
	t.say('PACKAGE CATALOG pinned-import architecture-closure canonical-workspace refusal-cleanup PASS')
	key := pkgcore.keygen('/tmp/linux-signing-seed')!
	pkgcore.publish(repository, 'fixture', '/tmp/linux-signing-seed', 1, time.now().unix() + 3600)!
	first_index := os.read_file(repository + '/index.json')!
	first_signature := os.read_file(repository + '/index.sig')!
	expires := json2.decode[pkgcore.Index](first_index)!.expires
	release_path := '/tmp/linux-published-release'
	release := json2.decode[pkgcore.ReleaseInfo](package_success(['publish-release', repository,
		'fixture', '/tmp/linux-signing-seed', '1', expires.str(), release_path])!)!
	assert release.package_count == 2 && release.public_key == key && release.sequence == 1
	assert os.read_file(release_path + '/index.json')! == first_index
	assert os.read_file(release_path + '/index.sig')! == first_signature
	assert os.ls(release_path)!.len == 3 && !os.exists(release_path + '/manifests') && !os.exists(release_path + '/.publisher')
	forked_release := run(['/usr/bin/vinix-package', 'publish-release', repository, 'fixture',
		'/tmp/linux-signing-seed', '1', (expires + 1).str(), '/tmp/linux-forked-release'], '', none, none)
	assert forked_release.status != 0 && forked_release.output.contains('sequence equivocation'), forked_release.output
	assert !os.exists('/tmp/linux-forked-release') && os.ls('/tmp')!.all(!it.starts_with('.vinix-release-'))
	release_root := '/tmp/release-client'
	os.mkdir_all(release_root + '/etc/vinix-packages')!
	os.write_file(release_root + '/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{
		architecture: architecture, policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 }
	}))!
	package_success(['--root', release_root, 'repo-enroll', 'fixture', 'file://' + release_path, key])!
	package_success(['--root', release_root, 'update'])!
	package_success(['--root', release_root, 'install', application.id])!
	release_state := pkgcore.read_state(pkgcore.state_directory(release_root), architecture)!
	assert release_state.packages.len == 2 && release_state.requested == [application.id]
	package_success(['--root', release_root, '--json', 'verify'])!
	t.say('PACKAGE RELEASE reproducible-index complete-runtime-closure private-state-exclusion sequence-fork-refusal offline-install PASS')
	config := pkgcore.Config{
		architecture: architecture
		launch_user:  'alex'
		policy:       pkgcore.Policy{ reserve_bytes: 0 }
	}
	os.mkdir_all('/etc/vinix-packages')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(config))!
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	mut trust := pkgprotocol.decode_repository_review(package_success(['repo-review', 'enroll', 'fixture', 'file://' + repository, key])!)!
	defer { trust.close() }
	assert trust.sequence == 1 && trust.package_count == 2 && trust.public_key == key && trust.previous_public_key == ''
	assert pkgcore.load_config('')!.repositories.len == 0
	package_success(['repo-apply', trust.fingerprint, 'enroll', 'fixture', 'file://' + repository, key])!
	stale_trust := run(['/usr/bin/vinix-package', 'repo-apply', trust.fingerprint, 'enroll', 'fixture', 'file://' + repository, key], '', none, none)
	assert stale_trust.status != 0 && stale_trust.output.contains('review is stale'), stale_trust.output
	enrolled := json2.decode[pkgcore.RepositoryStatus](package_success(['--json', 'repo-list'])!)!
	assert enrolled.repositories.len == 1 && enrolled.repositories[0].public_key == key
	assert enrolled.history.len == 1 && enrolled.history[0].sequence == 1
	assert pkgcore.load_config('')!.launch_user == 'alex'
	os.write_file('/home/alex/outside.txt', 'not granted\n')!
	os.chown('/home/alex/outside.txt', 1000, 1000)!
	package_success(['update'])!
	qualify_package_configuration_lock()!
	mut installation := pkgprotocol.decode_review(package_success(['review', 'install', application.id])!)!
	defer { installation.close() }
	assert installation.rows.len == 2
	assert installation.rows.any(it.id == runtime.id && it.kind == 'runtime' && it.license == runtime.license)
	assert installation.rows.all(it.action == 'install' && it.repository == 'fixture' && it.public_key == key)
	assert pkgcore.read_state('/var/lib/vinix-packages', architecture)!.generation == 0
	enrolled_config := pkgcore.load_config('')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{
		...enrolled_config, policy: pkgcore.Policy{ ...enrolled_config.policy, reserve_bytes: 1 }
	}))!
	stale_policy := run(['/usr/bin/vinix-package', 'apply', installation.fingerprint, 'install', application.id], '', none, none)
	assert stale_policy.status != 0 && stale_policy.output.contains('review is stale'), stale_policy.output
	assert os.ls('/var/lib/vinix-packages/objects')!.len == 0
	os.write_file('/etc/vinix-packages/config.json', json2.encode(enrolled_config))!
	package_success(['apply', installation.fingerprint, 'install', application.id])!
	stale := run(['/usr/bin/vinix-package', 'apply', installation.fingerprint, 'install', application.id], '', none, none)
	assert stale.status != 0 && stale.output.contains('review is stale'), stale.output
	t.say('PACKAGE REVIEW full-runtime-closure provenance stale-confirmation PASS')
	state := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	assert state.requested == [application.id]
	assert state.packages.len == 2 && state.packages.any(it.package.id == runtime.id)
	generation := '/var/lib/vinix-packages/generations/' + state.generation.str()
	loader := generation + '/apps/' + runtime.id + '/lib/ld-musl-' + architecture + '.so.1'
	assert os.is_file(loader) && !os.is_link(loader)
	assert package_success(['run', application.id])!.contains('PACKAGE LINUX')
	data := '/home/alex/.local/share/vinix-apps/linux-probe/result'
	assert owner_of(data) == 1000 && read_text(data) == 'packaged shared library: 23\n'
	// Failure leaves no final mirror. Retry retains verified source-cache objects
	// and a clean offline installation receives the complete Linux/runtime closure.
	exporter := '/tmp/mirror-exporter'
	os.mkdir_all(exporter + '/etc/vinix-packages')!
	os.write_file(exporter + '/etc/vinix-packages/config.json', json2.encode(enrolled_config))!
	package_success(['--root', exporter, 'update'])!
	runtime_package := state.packages.filter(it.package.id == runtime.id)[0].package
	probe_package := state.packages.filter(it.package.id == application.id)[0].package
	missing_object := repository + '/objects/' + runtime_package.files.filter(it.path == 'bin/vinix-linux-runner')[0].sha256
	missing_bytes := os.read_bytes(missing_object)!
	os.rm(missing_object)!
	defer { os.write_file_array(missing_object, missing_bytes) or {} }
	mirror_path := '/tmp/offline-mirror'
	mut mirror_review := pkgprotocol.decode_mirror_review(package_success(['--root', exporter, 'mirror-review', mirror_path, application.id])!)!
	defer { mirror_review.close() }
	assert mirror_review.review.rows.len == 2 && mirror_review.review.rows.all(it.action == 'export')
	assert mirror_review.review.rows.all(it.public_key == key) && mirror_review.review.generation == 0
	assert mirror_review.cache_needed > 0 && mirror_review.shared_disk
	assert !os.exists(mirror_path) && os.ls(pkgcore.state_directory(exporter) + '/objects')!.len == 0
	wrong_destination := '/tmp/not-created/export'
	stale_mirror := run(['/usr/bin/vinix-package', '--root', exporter, 'mirror-apply', mirror_review.review.fingerprint,
		wrong_destination, application.id], '', none, none)
	assert stale_mirror.status != 0 && stale_mirror.output.contains('stale') && !os.exists('/tmp/not-created'), stale_mirror.output
	failed_export := run(['/usr/bin/vinix-package', '--root', exporter, '--progress', 'mirror-apply', mirror_review.review.fingerprint,
		mirror_path, application.id], '', none, none)
	assert failed_export.status != 0 && failed_export.output.contains('unavailable'), failed_export.output
	assert package_progress_events(failed_export.output)!.all(it.phase != 'complete')
	assert !os.exists(mirror_path) && os.ls('/tmp')!.all(!it.starts_with('.vinix-mirror-'))
	probe_object := repository + '/objects/' + probe_package.files.filter(it.path == 'bin/probe')[0].sha256
	probe_bytes := os.read_bytes(probe_object)!
	os.rm(probe_object)!
	defer { os.write_file_array(probe_object, probe_bytes) or {} }
	os.write_file_array(missing_object, missing_bytes)!
	mirror_progress := package_progress_events(package_success(['--root', exporter, '--progress', 'mirror-apply',
		mirror_review.review.fingerprint, mirror_path, application.id])!)!
	assert mirror_progress.first().phase == 'resolve' && mirror_progress.last().phase == 'complete'
	assert mirror_progress.any(it.phase == 'copy' && it.current == it.total) && mirror_progress.any(it.phase == 'verify')
	assert mirror_progress.all(it.phase != 'activate')
	t.say('PACKAGE MIRROR REVIEW read-only closure destination-binding progress interrupted-retry PASS')
	os.write_file_array(probe_object, probe_bytes)!
	assert pkgcore.read_state(pkgcore.state_directory(exporter), architecture)!.generation == 0
	assert os.ls('/tmp')!.all(!it.starts_with('.vinix-mirror-'))
	for payload in probe_package.files {
		path := mirror_path + '/fixture/objects/' + payload.sha256
		assert pkgcore.verified_file(path, payload) && mode_of(path) == 0o644
		ordinary := run([os.executable(), 'probe', 'read', path], '', db, must_user(db, 'alex'))
		assert ordinary.status == 0 && ordinary.output.contains('ok '), ordinary.output
	}
	repeated_export := run(['/usr/bin/vinix-package', '--root', exporter, 'mirror', mirror_path, application.id], '', none, none)
	assert repeated_export.status != 0 && repeated_export.output.contains('must be new'), repeated_export.output
	offline_root := '/tmp/offline-client'
	os.mkdir_all(offline_root + '/etc/vinix-packages')!
	os.write_file(offline_root + '/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{
		architecture: architecture, policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 }
	}))!
	package_success(['--root', offline_root, 'repo-enroll', 'fixture', 'file://' + mirror_path + '/fixture', key])!
	package_success(['--root', offline_root, 'update'])!
	deployment_path := '/tmp/locked-deployment.json'
	deployment_text := package_success(['deployment-lock'])!
	deployment := json2.decode[pkgcore.DeploymentLock](deployment_text)!
	assert deployment.format == 2 && deployment.packages == [application.id] && deployment.locked.len == 2
	assert deployment.locked.all(it.public_key == key && it.minimum_sequence == 1)
	os.write_file(deployment_path, deployment_text)!
	mut deployment_review := pkgprotocol.decode_review(package_success(['--root', offline_root, 'deployment-review', deployment_path])!)!
	defer { deployment_review.close() }
	assert deployment_review.rows.len == 2 && deployment_review.rows.all(it.action == 'install')
	// A damaged short application prefix must recover within this reviewed
	// deployment. An invalid complete runtime partial must start at byte zero.
	offline_objects := pkgcore.state_directory(offline_root) + '/objects/'
	recovery_payload := probe_package.files.filter(it.path == 'bin/probe')[0]
	runner_payload := state.packages.filter(it.package.id == runtime.id)[0].package.files.filter(it.path == 'bin/vinix-linux-runner')[0]
	os.write_file(offline_objects + recovery_payload.sha256 + '.part', 'x'.repeat(64))!
	os.write_file(offline_objects + runner_payload.sha256 + '.part', 'x'.repeat(int(runner_payload.bytes)))!
	installation_output := package_success(['--root', offline_root, '--progress', 'deployment-apply', deployment_review.fingerprint, deployment_path])!
	assert installation_output.contains('Restarting ' + application.id + '/bin/probe: resumed payload failed verification')
	installation_progress := package_progress_events(installation_output)!
	recovery_downloads := installation_progress.filter(it.phase == 'download' && it.path == recovery_payload.path && it.package == application.id)
	assert recovery_downloads.first().current == 64 && recovery_downloads.filter(it.current == 0).len == 1
	assert recovery_downloads.filter(it.current == it.total).len == 2
	assert installation_progress.filter(it.phase == 'download' && it.path == runner_payload.path)[0].current == 0
	assert installation_progress.any(it.phase == 'download' && it.current == it.total)
	assert installation_progress.any(it.phase == 'copy') && installation_progress.any(it.phase == 'verify')
	assert installation_progress[installation_progress.len - 2].phase == 'activate' && installation_progress.last().phase == 'complete'
	stale_deployment := run(['/usr/bin/vinix-package', '--root', offline_root, 'deployment-apply', deployment_review.fingerprint, deployment_path], '', none, none)
	assert stale_deployment.status != 0 && stale_deployment.output.contains('review is stale'), stale_deployment.output
	offline_state := pkgcore.read_state(pkgcore.state_directory(offline_root), architecture)!
	assert offline_state.requested == state.requested && offline_state.packages == state.packages
	package_success(['--root', offline_root, '--json', 'verify'])!
	t.say('PACKAGE OFFLINE atomic-export failure-cleanup cached-retry ordinary-read signed-runtime-closure PASS')
	qualify_package_download_refusal('/tmp/recovery-client', architecture, mirror_path + '/fixture', key, probe_package)!
	t.say('PACKAGE DOWNLOAD RECOVERY damaged-prefix complete-partial bounded-retry bad-source-refusal preserved-rollback PASS')
	qualify_package_oversized_offline_source(architecture, mirror_path + '/fixture', key, probe_package)!
	t.say('PACKAGE OFFLINE COPY captured-files oversized-source retained-prefix restored-resume PASS')
	qualify_package_payload_hash(architecture, probe_package)!
	t.say('PACKAGE PAYLOAD HASH captured-files signed-length special-file-refusal preserved-state restored-retry PASS')
	qualify_package_atomic_metadata(architecture)!
	t.say('PACKAGE METADATA WRITE exclusive-temporary captured-parent stale-names preserved-state restored-verification PASS')
	output_check := run(['/usr/share/package-fixtures/https-output-check', '--producer',
		'/usr/share/package-fixtures/output-producer'], '', none, none)
	assert output_check.status == 0, output_check.output
	t.say('PACKAGE PIPE OUTPUT bounded-writes resume range-refusal closed-descriptors reaped-children PASS')
	seed_check := run(['/usr/share/package-fixtures/signing-seed-check', '/usr/bin/vinix-package',
		'/tmp/signing-seed-contract'], '', none, none)
	assert seed_check.status == 0, seed_check.output
	t.say('PACKAGE SIGNING SEED private-owner bounded-capture hardlink-refusal reproducible-retry PASS')
	durability_check := run(['/usr/share/package-fixtures/durability-check', '/tmp/package-durability-contract'], '', none, none)
	assert durability_check.status == 0, durability_check.output
	t.say('PACKAGE DURABILITY captured-files captured-directories alias-special-nul-refusal ordinary-retry PASS')
	// Organization restrictions are reviewed and atomically persisted without
	// editing trust, the account selection or the installed generation.
	policy_path := '/tmp/organization-policy.json'
	original_configuration := pkgcore.load_config('')!
	original_state := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	os.write_file(policy_path, json2.encode(pkgcore.PolicyDocument{ architecture: architecture,
		policy: pkgcore.Policy{ allowed: [application.id], reserve_bytes: 0 } }))!
	policy_review_text := package_success(['policy-review', policy_path])!
	mut policy_review := pkgcore.decode_policy_review(policy_review_text)!
	defer { policy_review.close() }
	assert policy_review.rows.len == 2 && policy_review.rows.all(it.diagnostic_before == '')
	assert policy_review.rows.all(it.diagnostic_after.contains(runtime.id + ': blocked by organization allowlist'))
	assert pkgcore.load_config('')! == original_configuration
	policy_text := os.read_file(policy_path)!
	for ambiguous in [policy_text.replace('"offline":false', '"offline":true,"offline":false'),
		policy_text.replace('"offline":false', '"offline":true,"off\\u006cine":false'),
		policy_text.replace('"policy":{', '"policy":{"allow_firmwar":true,'),
		policy_text.replace('"pins":[]', '"pins":[{"id":"' + application.id + '","id":"' + application.id + '","minimum":"","before":""}]')] {
		os.write_file(policy_path, ambiguous)!
		for operation in [['policy-review', policy_path], ['policy-apply', policy_review.fingerprint, policy_path]] {
			refused := run(['/usr/bin/vinix-package', ...operation], '', none, none)
			assert refused.status != 0 && refused.output.contains('document field'), refused.output
		}
		assert pkgcore.load_config('')! == original_configuration
		assert pkgcore.read_state('/var/lib/vinix-packages', architecture)! == original_state
	}
	os.write_file(policy_path, policy_text)!
	for incomplete in [policy_review_text.replace('"firmware":false,', ''),
		policy_review_text.replace('"proprietary":false,', '')] {
		if mut accepted := pkgcore.decode_policy_review(incomplete) {
			accepted.close()
			assert false, 'policy review omitted license/firmware disclosure'
		}
	}
	t.say('PACKAGE DOCUMENTS unknown-duplicate-escaped-keys explicit-policy-disclosure PASS')
	ordinary_policy := run(['/usr/bin/vinix-package', 'policy-apply', policy_review.fingerprint, policy_path], '', db, must_user(db, 'alex'))
	assert ordinary_policy.status != 0 && pkgcore.load_config('')! == original_configuration, ordinary_policy.output
	package_success(['policy-apply', policy_review.fingerprint, policy_path])!
	policy_denied_launch := run(['/usr/bin/vinix-package', 'run', application.id], '', none, none)
	assert policy_denied_launch.status != 0 && policy_denied_launch.output.contains('blocked by organization allowlist'), policy_denied_launch.output
	policy_reused := run(['/usr/bin/vinix-package', 'policy-apply', policy_review.fingerprint, policy_path], '', none, none)
	assert policy_reused.status != 0 && policy_reused.output.contains('review is stale'), policy_reused.output
	assert pkgcore.read_state('/var/lib/vinix-packages', architecture)! == original_state
	os.write_file(policy_path, json2.encode(pkgcore.PolicyDocument{ architecture: architecture, policy: original_configuration.policy }))!
	mut policy_restore := pkgcore.decode_policy_review(package_success(['policy-review', policy_path])!)!
	package_success(['policy-apply', policy_restore.fingerprint, policy_path])!
	policy_restore.close()
	assert pkgcore.load_config('')!.repositories == original_configuration.repositories
	assert pkgcore.load_config('')!.launch_user == original_configuration.launch_user
	assert package_success(['run', application.id])!.contains('PACKAGE LINUX')
	// Verification covers the complete runtime, including usr/lib dependencies.
	library := generation + '/apps/' + runtime.id + '/usr/lib/libfixture.so'
	original := os.read_bytes(library)!
	os.write_file(library, 'tampered\n')!
	bad_verification := run(['/usr/bin/vinix-package', '--json', 'verify'], '', none, none)
	assert bad_verification.status != 0 && bad_verification.output.contains('installed payload verification failed'), bad_verification.output
	changed := run(['/usr/bin/vinix-package', 'run', application.id], '', none, none)
	assert changed.status != 0 && changed.output.contains('installed application payload changed'), changed.output
	os.write_file_array(library, original)!
	package_success(['run', application.id])!
	// A signed publisher mistake reaches the loader's useful failure diagnostic.
	// No host-global copy can satisfy a missing library outside the grants.
	broken_recipe := pkgcore.RootRecipe{
		manifest: pkgcore.Package{ ...runtime, version: '1.1.0' }
		entries:  [
			pkgcore.RootEntry{ source: 'bin/vinix-linux-runner', path: 'bin/vinix-linux-runner' },
			pkgcore.RootEntry{ source: 'lib', path: 'lib' },
			pkgcore.RootEntry{ source: 'licenses', path: 'licenses' },
		]
	}
	os.write_file('/tmp/linux-recipe.json', json2.encode(broken_recipe))!
	package_success(['pack-root', '/tmp/linux-recipe.json', prepared, repository])!
	pkgcore.publish(repository, 'fixture', '/tmp/linux-signing-seed', 2, time.now().unix() + 3600)!
	latest_index := os.read_file(repository + '/index.json')!
	latest_signature := os.read_file(repository + '/index.sig')!
	package_success(['update'])!
	// The old lock deliberately retains the known working runtime after a new
	// signed runtime appears. A same-version application must not pull it in.
	mut locked_review := pkgprotocol.decode_review(package_success(['deployment-review', deployment_path])!)!
	assert locked_review.rows.all(it.version == '1.0.0' && it.action == 'keep')
	locked_review.close()
	// A catalog mirror would select the new (broken) runtime. A deployment
	// mirror must carry the exact older runtime pinned by the organization.
	locked_media := '/tmp/locked-media; $literal'
	mut locked_export := pkgprotocol.decode_deployment_mirror_review(package_success([
		'mirror-deployment-review', locked_media, deployment_path])!)!
	defer { locked_export.close() }
	assert locked_export.mirror.review.rows.all(it.version == '1.0.0' && it.action == 'export')
	assert !os.exists(locked_media)
	locked_progress := package_progress_events(package_success(['--progress', 'mirror-deployment-apply',
		locked_export.mirror.review.fingerprint, locked_media, deployment_path])!)!
	assert locked_progress.last().phase == 'complete' && locked_progress.all(it.phase != 'activate')
	assert read_text(locked_media + '/_deployment.json') == deployment_text
	locked_client := '/tmp/locked-offline-client'
	os.mkdir_all(locked_client + '/etc/vinix-packages')!
	os.write_file(locked_client + '/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{
		architecture: architecture, policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }))!
	package_success(['--root', locked_client, 'repo-enroll', 'fixture', 'file://' + locked_media + '/fixture', key])!
	package_success(['--root', locked_client, 'update'])!
	mut locked_install := pkgprotocol.decode_review(package_success(['--root', locked_client, 'deployment-review', locked_media + '/_deployment.json'])!)!
	defer { locked_install.close() }
	package_success(['--root', locked_client, 'deployment-apply', locked_install.fingerprint, locked_media + '/_deployment.json'])!
	assert pkgcore.read_state(pkgcore.state_directory(locked_client), architecture)!.packages.all(it.package.version == '1.0.0')
	package_success(['--root', locked_client, 'verify'])!
	t.say('PACKAGE LOCKED MIRROR exact-old-runtime bundled-lock offline-reproduction PASS')
	qualify_package_stored_state(locked_client, architecture, application.id, runtime.id)!
	t.say('PACKAGE STATE runtime-closure duplicate-fields canonical-generations collection-preflight restore PASS')
	t.say('PACKAGE COLLECTION obsolete=128 nofile=32 live-lease preserved-and-released verified-state PASS')
	updates := json2.decode[pkgcore.SoftwareView](package_success(['view'])!)!
	assert updates.update_error == '' && updates.rows.filter(it.updatable).map(it.id) == [runtime.id]
	assert updates.rows.any(it.id == runtime.id && it.kind == 'runtime' && it.version == '1.1.0'
		&& it.installed_version == '1.0.0' && it.update_action == 'update' && it.public_key == key)
	update_row := json2.decode[pkgcore.SoftwareRow](package_success(['--json', 'updates'])!)!
	assert update_row.id == runtime.id && update_row.updatable
	reviewed_package_operation('upgrade', [])!
	assert package_success(['--json', 'updates'])!.trim_space() == ''
	t.say('PACKAGE UPDATES runtime-only resolved-version complete-closure PASS')
	missing := run(['/usr/bin/vinix-package', 'run', application.id], '', none, none)
	assert missing.status == 127 && missing.output.contains('libfixture.so.1'), missing.output
	mut restore_lock := pkgprotocol.decode_review(package_success(['deployment-review', deployment_path])!)!
	assert restore_lock.rows.any(it.id == runtime.id && it.version == '1.0.0' && it.action == 'update')
	ordinary_deploy := run(['/usr/bin/vinix-package', 'deployment-apply', restore_lock.fingerprint, deployment_path], '', db, must_user(db, 'alex'))
	assert ordinary_deploy.status != 0, ordinary_deploy.output
	package_success(['deployment-apply', restore_lock.fingerprint, deployment_path])!
	restore_lock.close()
	assert pkgcore.read_state('/var/lib/vinix-packages', architecture)!.packages.all(it.package.version == '1.0.0')
	assert package_success(['run', application.id])!.contains('PACKAGE LINUX')
	// Rollback now restores the failed runtime; another rollback returns the
	// locked, complete generation. Both use the normal persistent history.
	reviewed_package_operation('rollback', [])!
	assert run(['/usr/bin/vinix-package', 'run', application.id], '', none, none).status == 127
	reviewed_package_operation('rollback', [])!
	assert package_success(['run', application.id])!.contains('PACKAGE LINUX')
	mut revocation := pkgprotocol.decode_repository_review(package_success(['repo-review', 'revoke', 'fixture'])!)!
	defer { revocation.close() }
	assert revocation.public_key == key && revocation.url == 'file://' + repository
	package_success(['repo-apply', revocation.fingerprint, 'revoke', 'fixture'])!
	revoked_launch := run(['/usr/bin/vinix-package', 'run', application.id], '', none, none)
	assert revoked_launch.status != 0, revoked_launch.output
	revoked_rollback := run(['/usr/bin/vinix-package', 'rollback'], '', none, none)
	assert revoked_rollback.status != 0, revoked_rollback.output
	reviewed_package_operation('remove', [application.id])!
	removed := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	assert removed.packages.len == 0
	assert os.is_file(data)
	package_success(['update'])!
	assert pkgcore.read_snapshots('/var/lib/vinix-packages')!.len == 0
	os.write_file(repository + '/index.json', first_index)!
	os.write_file(repository + '/index.sig', first_signature)!
	replay := run(['/usr/bin/vinix-package', 'repo-enroll', 'fixture', 'file://' + repository, key], '', none, none)
	assert replay.status != 0 && replay.output.contains('retained trust history'), replay.output
	assert pkgcore.load_config('')!.repositories.len == 0
	os.write_file(repository + '/index.json', latest_index)!
	os.write_file(repository + '/index.sig', latest_signature)!
	package_success(['repo-enroll', 'fixture', 'file://' + repository, key])!
	package_success(['update'])!
	assert pkgcore.read_state('/var/lib/vinix-packages', architecture)!.generation == removed.generation
	assert os.is_file(data)
	t.say('PACKAGE TRUST REVIEW read-only authenticated-metadata stale-confirmation reviewed-revocation PASS')
	t.say('PACKAGE CONFIGURATION lock-scoped-policy verified-json-status busy-launch PASS')
	t.say('PACKAGE ORGANIZATION reviewed-policy dependency-impact stale-refusal ordinary-user-denial atomic-restore PASS')
	t.say('PACKAGE DEPLOYMENT exact-metadata complete-runtime-closure offline-reproduction stale-refusal ordinary-user-denial rollback PASS')
	t.say('PACKAGE PROGRESS bounded-byte-counters verified-copy activation-completion offline-runtime-closure PASS')
	t.say('PACKAGE REPOSITORY authenticated-enrollment revocation retained-replay-floor re-enrollment PASS')
	t.say('PACKAGE LINUX IMPORT signed-source-aliases explicit-runtime tamper-refusal missing-library rollback clean-uninstall PASS')
}

fn scenario_packages_linux(mut t Test) {
	qualify_package_linux(mut t) or { t.check(false, err.msg()) }
}
