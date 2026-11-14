// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import tools.packages.wineadapter

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
	// Real decoded state and flock lease; publisher/payload admission is
	// deliberately outside this bounded ownership/collection-lock test.
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
	owner.close(); owner.close()
	assert C.flock(collection.lease, C.LOCK_EX | C.LOCK_NB) == 0
	check_collection_lease(collection)!
	assert C.flock(collection.lease, C.LOCK_UN) == 0
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
