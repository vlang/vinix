// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import time
import tools.packages.wineadapter

fn test_signed_repository_install_to_guarded_prefix_review() {
	work := os.real_path(os.temp_dir()) + '/wine-signed-review-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	repository := work + '/repository'
	root := work + '/installed'
	app_source := work + '/app-source'
	runtime_source := work + '/runtime-source'
	os.mkdir_all(app_source + '/bin')!
	os.mkdir_all(runtime_source + '/bin')!
	os.mkdir_all(runtime_source + '/root/usr/lib/wine/x86_64-windows')!
	os.write_file(app_source + '/bin/program.exe', 'fixture application, never executed')!
	os.chmod(app_source + '/bin/program.exe', 0o755)!
	os.write_file(runtime_source + '/bin/wine', 'fixture runtime, never executed')!
	os.chmod(runtime_source + '/bin/wine', 0o755)!
	os.write_file(runtime_source + '/root/usr/lib/wine/x86_64-windows/kernel32.dll', 'signed fixture builtin')!
	key := keygen(work + '/seed')!
	for p in [Package{id: 'app', name: 'Windows fixture', version: '1.0.0', architecture: 'aarch64', license: 'MIT',
		kind: 'windows', runtime: 'wine', entrypoint: 'bin/wine', arguments: ['bin/program.exe'],
		dependencies: [Dependency{id: 'wine', minimum: '1.0.0'}]},
		Package{id: 'wine', name: 'Runtime fixture', version: '1.0.0', architecture: 'aarch64', license: 'MIT',
		kind: 'runtime', entrypoint: 'bin/wine'}] {
		os.write_file(work + '/manifest.json', json2.encode(p))!
		pack(work + '/manifest.json', if p.id == 'app' { app_source } else { runtime_source }, repository)!
	}
	publish(repository, 'fixture', work + '/seed', 1, time.now().unix() + 3600)!
	os.mkdir_all(root + '/etc/vinix-packages')!
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(Config{architecture: 'aarch64',
		repositories: [Repository{id: 'fixture', url: 'file://' + repository, public_key: key}], policy: Policy{reserve_bytes: 0}}))!
	service := Service{root: root}
	mut catalog := service.refresh()!
	catalog.close()
	mut installed := service.transact('install', ['app'], TransactionOptions{})!
	defer { installed.close() }
	// Public Wine admission intentionally refuses alternate roots. This test
	// uses its private preparation/verification components on a signed install.
	mut prepared := service.prepare_launch('app')!
	defer { prepared.close() }
	assert prepared.lease >= 0 && prepared.state.generation == installed.generation
	verify_launch_payloads(prepared.config, prepared.directory, prepared.state, 'app')!
	index := wine_runtime_index(prepared.state, 'app')!
	mut admission := WineAdmission{generation: prepared.state.generation, runtime: prepared.state.packages[index].package, prepared: prepared}
	prepared = PreparedLaunch{}
	defer { admission.close() }
	data := work + '/data'
	os.mkdir(data)!; os.chmod(data, 0o700)!; os.chown(data, int(C.geteuid()), os.getegid())!
	number := admission.generation.str()
	builtins := admission.prepared.directory + '/generations/' + number + '/apps/wine/root/usr/lib/wine/x86_64-windows'
	mut prefix := wineadapter.prepare_prefix(data, builtins)!
	defer { prefix.close() }
	mut owner := WinePrefixReview{admission: admission, review: admission.capture_prefix(data)!, root: root.clone(), application: 'app'}
	admission = WineAdmission{}
	defer { owner.close() }
	assert owner.review.review.bindings.len == 1 && owner.review.review.bindings[0].operation == .keep
	owner.review.recheck()!
	initial_document := owner.document()!
	assert initial_document.runtime_id == 'wine'
	assert initial_document.runtime_version == '1.0.0'
	assert initial_document.generation == installed.generation
	owner.close(); owner.close()
	mut released := prefix.acquire_launch(data)!
	released.close()
	os.write_file(runtime_source + '/root/usr/lib/wine/x86_64-windows/kernel32.dll', 'signed upgraded builtin')!
	os.write_file(runtime_source + '/root/usr/lib/wine/x86_64-windows/new.dll', 'signed added builtin')!
	os.write_file(work + '/manifest.json', json2.encode(Package{id: 'wine', name: 'Runtime fixture', version: '2.0.0',
		architecture: 'aarch64', license: 'MIT', kind: 'runtime', entrypoint: 'bin/wine'}))!
	pack(work + '/manifest.json', runtime_source, repository)!
	publish(repository, 'fixture', work + '/seed', 2, time.now().unix() + 3600)!
	mut refreshed := service.refresh()!
	refreshed.close()
	mut upgraded := service.transact('upgrade', [], TransactionOptions{})!
	defer { upgraded.close() }
	assert upgraded.generation != installed.generation
	mut next := service.prepare_launch('app')!
	defer { next.close() }
	verify_launch_payloads(next.config, next.directory, next.state, 'app')!
	next_index := wine_runtime_index(next.state, 'app')!
	mut next_admission := WineAdmission{generation: next.state.generation, runtime: next.state.packages[next_index].package, prepared: next}
	next = PreparedLaunch{}
	defer { next_admission.close() }
	mut next_owner := WinePrefixReview{admission: next_admission, review: next_admission.capture_prefix(data)!, root: root.clone(), application: 'app'}
	next_admission = WineAdmission{}
	defer { next_owner.close() }
	assert next_owner.review.review.generation == upgraded.generation
	assert next_owner.review.review.prior_generation == installed.generation
	assert next_owner.review.review.bindings.len == 2
	assert next_owner.review.review.bindings[0].operation == .replace
	assert next_owner.review.review.bindings[1].operation == .create
	upgrade_document := next_owner.document()!
	assert upgrade_document.runtime_version == '2.0.0'
	assert upgrade_document.prior_generation == installed.generation
	// Existing format-1 consumers can continue decoding the structural fields.
	document_json := json2.encode(upgrade_document)
	defer { unsafe { document_json.free() } }
	mut legacy := json2.decode[wineadapter.BindingReview](document_json)!
	defer { legacy.close() }
	assert legacy.format == 1 && legacy.runtime_id == 'wine'
	assert legacy.generation == upgraded.generation && legacy.bindings.len == 2
	assert os.readlink(data + '/wine/drive_c/windows/system32/kernel32.dll')! == builtins + '/kernel32.dll'
	assert !os.exists(data + '/wine/drive_c/windows/system32/new.dll')
	next_owner.review.recheck()!
	next_owner.recheck()!
	mut retarget_refused := false
	next_owner.complete_additions() or { retarget_refused = err.msg().contains('all existing links') }
	assert retarget_refused
	assert !os.exists(data + '/wine/drive_c/windows/system32/new.dll')
	system := data + '/wine/drive_c/windows/system32'
	target := next_owner.admission.prepared.directory + '/generations/' + upgraded.generation.str() + '/apps/wine/root/usr/lib/wine/x86_64-windows'
	next_owner.migrate_bindings()!
	next_owner.migrate_bindings()!
	assert os.readlink(system + '/kernel32.dll')! == target + '/kernel32.dll'
	next_owner.complete_additions()!
	next_owner.complete_additions()!
	completed_document := next_owner.document()!
	assert completed_document.runtime_version == '2.0.0'
	assert completed_document.prior_generation == 0
	assert completed_document.bindings.all(it.operation == .keep)
	assert os.readlink(system + '/new.dll')! == target + '/new.dll'
	configuration_path := root + '/etc/vinix-packages/config.json'
	original_config := os.read_file(configuration_path)!
	os.write_file(configuration_path, json2.encode(Config{architecture: 'aarch64', policy: Policy{reserve_bytes: 0}}))!
	mut revoked := false
	next_owner.document() or { revoked = err.msg().contains('publisher key has been revoked') }
	assert revoked
	os.write_file(configuration_path, original_config)!
	next_owner.recheck()!
	state_path := next_owner.admission.prepared.directory + '/generations/' + upgraded.generation.str() + '/state.json'
	original_state := os.read_file(state_path)!
	os.write_file(state_path, '\n' + original_state + '\n')!
	next_owner.recheck()!
	changed_state := original_state.replace('"version":"2.0.0"', '"version":"2.0.1"')
	assert changed_state != original_state
	os.write_file(state_path, changed_state)!
	mut metadata_changed := false
	next_owner.document() or { metadata_changed = err.msg().contains('active generation metadata changed') }
	assert metadata_changed
	os.write_file(state_path, original_state)!
	next_owner.recheck()!
	os.write_file(configuration_path, json2.encode(Config{architecture: 'aarch64',
		repositories: [Repository{id: 'fixture', url: 'file://' + repository, public_key: key}],
		policy: Policy{allowed: ['other'], reserve_bytes: 0}}))!
	mut blocked := false
	next_owner.document() or { blocked = err.msg().contains('blocked by organization allowlist') }
	assert blocked
	os.write_file(configuration_path, original_config)!
	next_owner.recheck()!
	activation := acquire(next_owner.admission.prepared.directory)!
	activate(next_owner.admission.prepared.directory, installed.generation)!
	activation.release()
	mut changed := false
	next_owner.document() or { changed = err.msg().contains('active generation changed') }
	assert changed
	restore := acquire(next_owner.admission.prepared.directory)!
	activate(next_owner.admission.prepared.directory, upgraded.generation)!
	restore.release()
	next_owner.recheck()!
	next_owner.close()
	mut closed := false
	next_owner.document() or { closed = err.msg().contains('closed or lacks service admission') }
	assert closed
}

fn wine_review_collect(store string) ! {
	writer := acquire(store)!
	defer { writer.release() }
	collect_locked(Config{architecture: 'aarch64'}, store)!
}

fn test_persisted_generation_lease_survives_combined_prefix_review() {
	root := os.real_path(os.temp_dir()) + '/wine-review-lease-' + os.getpid().str()
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	store := root + '/store'
	generation := store + '/generations/2'
	builtins := generation + '/apps/wine/root/usr/lib/wine/x86_64-windows'
	data := root + '/data'
	os.mkdir_all(builtins)!; os.mkdir(data)!
	os.chmod(data, 0o700)!; os.chown(data, int(C.geteuid()), os.getegid())!
	os.write_file(builtins + '/kernel32.dll', 'new')!
	os.write_file(generation + '/lease', '')!
	key := 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
	runtime := Package{id: 'wine', name: 'Wine fixture', version: '1.0.0', architecture: 'aarch64', license: 'MIT',
		kind: 'runtime', entrypoint: 'bin/wine', files: [Payload{path: 'bin/wine', sha256: sha256.hexhash('runner'), bytes: 6, executable: true},
		Payload{path: 'root/usr/lib/wine/x86_64-windows/kernel32.dll', sha256: sha256.hexhash('new'), bytes: 3}]}
	app := Package{id: 'app', name: 'Windows fixture', version: '1.0.0', architecture: 'aarch64', license: 'MIT', kind: 'windows',
		runtime: 'wine', entrypoint: 'bin/wine', arguments: ['bin/program.exe'], dependencies: [Dependency{id: 'wine', minimum: '1.0.0'}],
		files: [Payload{path: 'bin/program.exe', sha256: sha256.hexhash('app'), bytes: 3, executable: true}]}
	fixture := State{generation: 2, architecture: 'aarch64', requested: ['app'], packages: [
		Installed{package: app, repository: 'fixture', public_key: key, sequence: 1},
		Installed{package: runtime, repository: 'fixture', public_key: key, sequence: 1}]}
	os.write_file(generation + '/state.json', json2.encode(fixture))!
	os.symlink('generations/2', store + '/current')!
	writer := acquire(store)!
	writer.release()
	mut prefix := wineadapter.prepare_prefix(data, builtins)!
	defer { prefix.close() }
	reader := acquire_reader(store)!
	state, lease := generation_lease(store, 'aarch64', 'app')!
	reader.release()
	index := wine_runtime_index(state, 'app')!
	// Exercise launch verification against the declared on-disk closure.
	// Provenance is fixture metadata, not a signed repository installation.
	os.mkdir_all(generation + '/apps/wine/bin')!
	os.write_file(generation + '/apps/wine/bin/wine', 'runner')!
	os.chmod(generation + '/apps/wine/bin/wine', 0o755)!
	os.mkdir_all(generation + '/apps/app/bin')!
	os.write_file(generation + '/apps/app/bin/program.exe', 'app')!
	os.chmod(generation + '/apps/app/bin/program.exe', 0o755)!
	os.mkdir_all(generation + '/share/applications')!
	os.write_file(generation + '/share/applications/vinix-app.desktop', desktop_entry(app))!
	os.chmod(generation + '/share/applications/vinix-app.desktop', 0o644)!
	config := Config{architecture: 'aarch64', repositories: [Repository{id: 'fixture', public_key: key, url: 'file:///fixture'}]}
	verify_launch_payloads(config, store, state, 'app')!
	mut revoked := false
	verify_launch_payloads(Config{architecture: 'aarch64'}, store, state, 'app') or {
		revoked = err.msg().contains('publisher key has been revoked')
	}
	assert revoked
	os.write_file(generation + '/apps/wine/extra.dll', 'undeclared')!
	mut extra := false
	verify_launch_payloads(config, store, state, 'app') or { extra = err.msg().contains('namespace verification failed') }
	assert extra
	os.rm(generation + '/apps/wine/extra.dll')!
	os.write_file(generation + '/share/applications/vinix-app.desktop', 'changed registration')!
	mut registration := false
	verify_launch_payloads(config, store, state, 'app') or { registration = err.msg().contains('registration verification failed') }
	assert registration
	os.write_file(generation + '/share/applications/vinix-app.desktop', desktop_entry(app))!
	os.write_file(builtins + '/kernel32.dll', 'BAD')!
	mut tampered := false
	verify_launch_payloads(config, store, state, 'app') or {
		tampered = err.msg().contains('payload changed')
	}
	assert tampered
	os.write_file(builtins + '/kernel32.dll', 'new')!
	verify_launch_payloads(config, store, state, 'app')!
	mut admission := WineAdmission{generation: state.generation, runtime: state.packages[index].package,
		prepared: PreparedLaunch{directory: store.clone(), state: state, lease: lease}}
	mut owner := WinePrefixReview{admission: admission, review: admission.capture_prefix(data)!}
	admission = WineAdmission{}
	defer { owner.close() }
	collection := open_collection_generation(generation)!
	defer { close_collection_lease(collection) }
	assert C.flock(collection.lease, C.LOCK_EX | C.LOCK_NB) != 0
	owner.review.recheck()!
	assert C.flock(collection.lease, C.LOCK_EX | C.LOCK_NB) != 0
	// Move activation beyond the retained generation. Generation 2 is now
	// obsolete and has no rollback protection; only the review lease saves it.
	os.mkdir_all(store + '/objects')!
	os.mkdir(store + '/generations/3')!
	os.write_file(store + '/generations/3/lease', '')!
	os.write_file(store + '/generations/3/state.json', json2.encode(State{...fixture, generation: 3}))!
	activation := acquire(store)!
	activate(store, 3)!
	activation.release()
	for _ in 0 .. 3 {
		wine_review_collect(store)!
		assert os.read_file(builtins + '/kernel32.dll')! == 'new'
		assert os.readlink(store + '/current')! == 'generations/3'
		owner.review.recheck()!
	}
	owner.close(); owner.close()
	assert C.flock(collection.lease, C.LOCK_EX | C.LOCK_NB) == 0
	check_collection_lease(collection)!
	assert C.flock(collection.lease, C.LOCK_UN) == 0
	wine_review_collect(store)!
	assert !os.exists(generation)
	assert os.exists(store + '/generations/3/state.json')
	assert os.readlink(store + '/current')! == 'generations/3'
	// Collection does not rewrite private prefix links. Migration remains a
	// separate operation even after obsolete runtime storage is retired.
	assert os.readlink(data + '/wine/drive_c/windows/system32/kernel32.dll')! == builtins + '/kernel32.dll'
	mut released := prefix.acquire_launch(data)!
	released.close()
}

fn test_manifest_prefix_review_bridge_and_failure_cleanup() {
	root := os.real_path(os.temp_dir()) + '/wine-manifest-review-' + os.getpid().str()
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	store := root + '/store'
	old := store + '/generations/1/apps/wine/root/usr/lib/wine/x86_64-windows'
	new := store + '/generations/2/apps/wine/root/usr/lib/wine/x86_64-windows'
	data := root + '/data'
	os.mkdir_all(old)!; os.mkdir_all(new)!; os.mkdir(data)!
	os.chmod(data, 0o700)!; os.chown(data, int(C.geteuid()), os.getegid())!
	os.write_file(old + '/kernel32.dll', 'old')!; os.write_file(new + '/kernel32.dll', 'new')!
	mut prefix := wineadapter.prepare_prefix(data, old)!
	defer { prefix.close() }
	// Synthetic admission isolates bridge behavior; it is not evidence that a
	// successful signed installed-state admission has been exercised.
	fd := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	assert fd >= 0
	mut admission := WineAdmission{generation: 2, runtime: Package{id: 'wine', kind: 'runtime', files: [Payload{
		path: 'root/usr/lib/wine/x86_64-windows/kernel32.dll', sha256: sha256.hexhash('new'), bytes: 3}]},
		prepared: PreparedLaunch{directory: store.clone(), lease: fd}}
	defer { admission.close() }
	mut review := admission.capture_prefix(data)!
	assert review.review.prior_generation == 1
	review.recheck()!
	review.close()
	os.write_file(new + '/kernel32.dll', 'BAD')!
	if mut invalid := admission.capture_prefix(data) {
		invalid.close(); assert false, 'manifest digest mismatch accepted'
	} else { assert err.msg().contains('digest or size differs') }
	mut guard := prefix.acquire_launch(data)!
	guard.close()
	assert os.readlink(data + '/wine/drive_c/windows/system32/kernel32.dll')! == old + '/kernel32.dll'
	os.write_file(new + '/kernel32.dll', 'new')!
	mut owner := WinePrefixReview{admission: admission, review: admission.capture_prefix(data)!}
	admission = WineAdmission{}
	owner.close(); owner.close()
	assert C.fcntl(fd, C.F_GETFD) < 0
	mut released := prefix.acquire_launch(data)!
	released.close()
}

fn test_builtin_manifest_inventory_refuses_nested_and_empty_inputs() {
	for runtime in [Package{}, Package{files: [Payload{path: 'root/usr/lib/wine/x86_64-windows/subdir/a.dll'}]}] {
		if mut expected := wine_builtin_expectations(runtime) {
			free_wine_expectations(mut expected); assert false, 'invalid manifest inventory accepted'
		}
	}
	if mut owner := (Service{root: '/tmp/alternate'}).wine_prefix_review('app', '/tmp/private') {
		owner.close(); assert false, 'alternate root accepted'
	}
	mut empty := WinePrefixReview{}
	empty.close(); empty.close()
}
