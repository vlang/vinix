// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.signing as ed25519
import crypto.sha256
import json2
import os
import time

fn C.umask(u32) u32

fn fixture_dir(label string) string {
	path := os.temp_dir() + '/vinix-distribution-' + label + '-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(path) or { panic(err) }
	return path
}

fn fixture_package(id string, version string, architecture string) Package {
	data := '${id} ${version}'.bytes()
	return Package{
		id:           id
		version:      version
		architecture: architecture
		name:         id
		description:  'A fixture application'
		license:      'MIT'
		kind:         'native'
		entrypoint:   'bin/app'
		files:        [Payload{ path: 'bin/app', sha256: sha256.sum(data).hex(), bytes: u64(data.len), executable: true }]
	}
}

fn fixture_candidate(p Package) Installed {
	return Installed{ package: p, repository: 'fixture', public_key: '01'.repeat(32), sequence: 1 }
}

fn fixture_config(architecture string) Config {
	return Config{
		architecture: architecture
		repositories: [Repository{ id: 'fixture', url: 'https://example.invalid/packages', public_key: '01'.repeat(32) }]
		policy:       Policy{ reserve_bytes: 0 }
	}
}

fn write_fixture_index(repository string, packages []Package, private_key ed25519.PrivateKey, sequence u64) ! {
	os.mkdir_all(repository + '/objects')!
	for p in packages {
		for file in p.files {
			// Callers that test malformed hashes overwrite the object afterwards.
			os.write_file(repository + '/objects/' + file.sha256, '${p.id} ${p.version}')!
		}
	}
	text := canonical_index(Index{ repository: 'fixture', sequence: sequence, expires: time.now().unix() + 3600, packages: packages })!
	os.write_file(repository + '/index.json', text)!
	os.write_file(repository + '/index.sig', ed25519.sign(private_key, text.bytes())!.hex())!
}

fn test_metadata_validation_and_reproducibility() {
	p := fixture_package('editor', '1.2.10', 'aarch64')
	p.validate() or { panic(err) }
	assert compare_versions('1.2.10', '1.2.9') > 0
	assert compare_versions('1.10.0', '1.9.99') > 0
	for bad in ['01.2.3', '1.2', '1.2.3-beta', '1.-2.3', '1.2.3.4'] {
		if _ := version_parts(bad) {
			assert false, 'accepted invalid version ${bad}'
		}
	}
	for bad in ['../escape', '/absolute', 'a/../b', 'a//b', 'a\\b', 'a/./b', 'a\x00b'] {
		assert !relative_path(bad)
	}
	assert !identifier('Bad')
	assert !identifier('a;rm')
	if _ := (Package{ ...p, architecture: 'i386' }).validate() {
		assert false
	}
	if _ := (Package{ ...p, architecture: 'all' }).validate() {
		assert false
	}
	if _ := (Package{ ...p, files: [Payload{ ...p.files[0], path: '../bin/app' }] }).validate() {
		assert false
	}
	if _ := (Package{ ...p, files: [p.files[0], p.files[0]] }).validate() {
		assert false
	}
	if _ := (Package{ ...p, files: [p.files[0], Payload{ ...p.files[0], path: 'bin' }] }).validate() {
		assert false
	}
	if _ := (Package{ ...p, permissions: ['everything'] }).validate() {
		assert false
	}
	if _ := (Package{ ...p, kind: 'windows' }).validate() {
		assert false
	}
	q := fixture_package('browser', '2.0.0', 'x86_64')
	first := canonical_index(Index{
		repository: 'fixture'
		sequence:   1
		expires:    2000000000
		packages:   [
			p,
			q,
		]
	}) or { panic(err) }
	second := canonical_index(Index{
		repository: 'fixture'
		sequence:   1
		expires:    2000000000
		packages:   [
			q,
			p,
		]
	}) or { panic(err) }
	assert first == second
}

fn test_repository_signature_expiry_and_identity() {
	public_key, private_key := ed25519.generate_key() or { panic(err) }
	repository := Repository{ id: 'fixture', url: 'https://example.invalid', public_key: public_key.hex() }
	text := canonical_index(Index{ repository: 'fixture', sequence: 4, expires: 2000000000, packages: [fixture_package('app', '1.0.0', 'aarch64')] }) or { panic(err) }
	sig := ed25519.sign(private_key, text.bytes()) or { panic(err) }
	assert verify_index(repository, text, sig.hex(), 1900000000)!.sequence == 4
	if _ := verify_index(repository, text + ' ', sig.hex(), 1900000000) {
		assert false
	}
	if _ := verify_index(repository, text, sig.hex(), 2000000000) {
		assert false
	}
	if _ := verify_index(Repository{ ...repository, id: 'other' }, text, sig.hex(), 1900000000) {
		assert false
	}
	if _ := verify_index(repository, text, '00'.repeat(64), 1900000000) {
		assert false
	}
	if _ := verify_index(repository, text, 'not-hex', 1900000000) {
		assert false
	}
}

fn test_resolver_backtracks_checks_cycles_and_architecture() {
	config := fixture_config('aarch64')
	mut candidates := []Installed{}
	a := Package{ ...fixture_package('a', '1.0.0', 'aarch64'), dependencies: [Dependency{ id: 'lib', before: '2.0.0' }] }
	b := Package{ ...fixture_package('b', '1.0.0', 'aarch64'), dependencies: [Dependency{ id: 'lib', minimum: '1.0.0' }] }
	for p in [a, b, fixture_package('lib', '1.0.0', 'aarch64'),
		fixture_package('lib', '2.0.0', 'aarch64'), fixture_package('lib', '9.0.0', 'x86_64')] {
		candidates << fixture_candidate(p)
	}
	plan := resolve(Catalog{ packages: candidates }, config, State{}, ['b', 'a'], true) or { panic(err) }
	assert plan.packages.len == 3
	assert plan.packages.filter(it.package.id == 'lib')[0].package.version == '1.0.0'
	conflict := Package{ ...b, dependencies: [Dependency{ id: 'lib', minimum: '2.0.0' }] }
	if _ := resolve(Catalog{
		packages: [fixture_candidate(a), fixture_candidate(conflict), ...candidates[2..]]
	}, config, State{}, ['a', 'b'], true) {
		assert false
	}
	cycle_a := Package{ ...a, dependencies: [Dependency{ id: 'b' }] }
	cycle_b := Package{ ...b, dependencies: [Dependency{ id: 'a' }] }
	assert resolve(Catalog{ packages: [fixture_candidate(cycle_a), fixture_candidate(cycle_b)] }, config, State{}, ['a'], true)!.packages.len == 2
	if _ := resolve(Catalog{ packages: [fixture_candidate(fixture_package('app', '1.0.0', 'x86_64'))] }, config, State{}, ['app'], true) {
		assert false
	}
	// Choosing the latest root itself can require backtracking.
	new_a := Package{ ...fixture_package('a', '2.0.0', 'aarch64'), dependencies: [Dependency{ id: 'missing' }] }
	assert resolve(Catalog{ packages: [fixture_candidate(new_a), ...candidates] }, config, State{}, ['a'], true)!.packages.filter(it.package.id == 'a')[0].package.version == '1.0.0'
	// Another enrolled publisher cannot adopt an already-installed identity.
	replacement := Installed{ ...fixture_candidate(fixture_package('a', '3.0.0', 'aarch64')), repository: 'replacement' }
	if _ := resolve(Catalog{ packages: [replacement] }, config,
		State{ packages: [fixture_candidate(a)] }, ['a'], true) {
		assert false, 'silently changed an installed package publisher'
	}
}

fn test_policy_runtime_and_literal_launch_arguments() {
	config := fixture_config('x86_64')
	app := fixture_package('app', '1.0.0', 'x86_64')
	if _ := check_policy(Package{ ...app, proprietary: true, license: 'Vendor-EULA' }, config.policy) {
		assert false
	}
	check_policy(Package{ ...app, proprietary: true, license: 'Vendor-EULA' }, Policy{ licenses: ['Vendor-EULA'] }) or { panic(err) }
	if _ := check_policy(Package{ ...app, firmware: true }, config.policy) {
		assert false
	}
	if _ := check_policy(app, Policy{ allowed: ['other'] }) {
		assert false
	}
	if _ := check_policy(Package{ ...app, permissions: ['network'] }, Policy{ permissions: [] }) {
		assert false
	}
	if _ := check_policy(app, Policy{ pins: [Dependency{ id: 'app', before: '1.0.0' }] }) {
		assert false
	}
	runtime := Package{ ...fixture_package('wine', '1.0.0', 'x86_64'), kind: 'runtime' }
	windows := Package{
		...app
		kind:         'windows'
		runtime:      'wine'
		dependencies: [Dependency{ id: 'wine' }]
		arguments:    [
			'@APP@/program.exe',
			'literal;$(do-not-run)',
		]
	}
	plan := resolve(Catalog{ packages: [fixture_candidate(runtime), fixture_candidate(windows)] }, config, State{}, ['app'], true) or { panic(err) }
	state := State{ generation: 1, architecture: 'x86_64', requested: plan.requested, packages: plan.packages }
	launch := launch_plan(config, '/var/lib/vinix-packages', state, 'app', '/home/user/data', 1000, 1000, []) or { panic(err) }
	assert launch.program == '/usr/bin/vinix-sandbox'
	promises := launch.arguments[launch.arguments.index('--promises') + 1].split(' ')
	assert 'flock' in promises && 'inet' !in promises && 'proc' !in promises
	assert 'tty' !in promises && 'TERM=linux' !in launch.arguments
	terminal := terminal_launch_plan(config, '/var/lib/vinix-packages', state, 'app', '/home/user/data', 1000, 1000, [])!
	assert 'tty' in terminal.arguments[terminal.arguments.index('--promises') + 1].split(' ')
	assert 'TERM=linux' in terminal.arguments
	assert terminal.arguments.filter(it == '/home/user' || it == '/dev' || it == '/dev/pts').len == 0
	assert '/home/user/data' in launch.arguments && '/home/user' !in launch.arguments
	assert launch.arguments.last() == 'literal;$(do-not-run)'
	assert '/var/lib/vinix-packages/generations/1/apps/wine/bin/app' in launch.arguments
	assert 'LD_LIBRARY_PATH=/var/lib/vinix-packages/generations/1/apps/app/lib:/var/lib/vinix-packages/generations/1/apps/app/usr/lib:/var/lib/vinix-packages/generations/1/apps/wine/lib:/var/lib/vinix-packages/generations/1/apps/wine/usr/lib' in launch.arguments
	if _ := launch_plan(config, '/var/lib/vinix-packages', state, 'app', '/home/user/data', 0, 0, []) {
		assert false
	}
	bad := Package{ ...windows, entrypoint: 'bin/missing' }
	if _ := resolve(Catalog{ packages: [fixture_candidate(runtime), fixture_candidate(bad)] }, config, State{}, ['app'], true) {
		assert false
	}
}

fn test_transaction_lifecycle_recovery_and_offline_cache() {
	work := fixture_dir('lifecycle')
	defer { os.rmdir_all(work) or {} }
	public_key, private_key := ed25519.generate_key() or { panic(err) }
	repository := work + '/repo'
	directory := work + '/state'
	config := Config{ architecture: 'aarch64', repositories: [Repository{ id: 'fixture', url: 'file://' + repository, public_key: public_key.hex() }], policy: Policy{ reserve_bytes: 0, offline: true } }
	v1 := fixture_package('app', '1.0.0', 'aarch64')
	v2 := fixture_package('app', '2.0.0', 'aarch64')
	write_fixture_index(repository, [v1], private_key, 1) or { panic(err) }
	refresh(config, directory) or { panic(err) }
	os.mkdir_all(directory + '/objects') or { panic(err) }
	// Resume a partial object copied from a local/offline repository.
	os.write_file(directory + '/objects/' + v1.files[0].sha256 + '.part', 'app ') or { panic(err) }
	first := transact(config, directory, 'install', ['app'], TransactionOptions{}) or { panic(err) }
	assert first.generation == 1
	assert read_state(directory, 'aarch64')!.packages[0].package.version == '1.0.0'
	assert os.is_file(directory + '/current/share/applications/vinix-app.desktop')
	assert verified_file(directory + '/objects/' + v1.files[0].sha256, v1.files[0])
	write_fixture_index(repository, [v1, v2], private_key, 2) or { panic(err) }
	refresh(config, directory) or { panic(err) }
	if _ := transact(config, directory, 'upgrade', [], TransactionOptions{ stop_before_activation: true }) {
		assert false
	}
	assert read_state(directory, 'aarch64')!.generation == 1
	assert os.is_dir(directory + '/generations/.stage-2')
	second := transact(config, directory, 'upgrade', [], TransactionOptions{}) or { panic(err) }
	assert second.generation == 2
	assert second.previous == 1
	assert !os.exists(directory + '/generations/.stage-2')
	assert second.packages[0].package.version == '2.0.0'
	// Actual persistent state is usable after creating another controller.
	assert json2.decode[State](read_metadata(directory + '/current/state.json')!)!.generation == 2
	assert rollback(config, directory)!.generation == 1
	assert read_state(directory, 'aarch64')!.packages[0].package.version == '1.0.0'
	// Cache permits operation with the repository payload absent.
	os.rm(repository + '/objects/' + v2.files[0].sha256) or { panic(err) }
	assert transact(config, directory, 'upgrade', [], TransactionOptions{})!.packages[0].package.version == '2.0.0'
	removed := transact(config, directory, 'remove', ['app'], TransactionOptions{}) or { panic(err) }
	assert removed.packages.len == 0
	assert !os.exists(directory + '/current/share/applications/vinix-app.desktop')
	assert rollback(config, directory)!.packages[0].package.id == 'app'
	collect(config, directory) or { panic(err) }
	assert os.is_dir(directory + '/generations/' + read_state(directory, 'aarch64')!.generation.str())
}

fn test_failure_preserves_activation_and_repository_sequence_floor() {
	work := fixture_dir('failure')
	defer { os.rmdir_all(work) or {} }
	public_key, private_key := ed25519.generate_key() or { panic(err) }
	repository := work + '/repo'
	directory := work + '/state'
	config := Config{ architecture: 'x86_64', repositories: [Repository{ id: 'fixture', url: 'file://' + repository, public_key: public_key.hex() }], policy: Policy{ reserve_bytes: 0 } }
	v1 := fixture_package('app', '1.0.0', 'x86_64')
	v2 := fixture_package('app', '2.0.0', 'x86_64')
	write_fixture_index(repository, [v1], private_key, 10) or { panic(err) }
	refresh(config, directory) or { panic(err) }
	transact(config, directory, 'install', ['app'], TransactionOptions{}) or { panic(err) }
	write_fixture_index(repository, [v1, v2], private_key, 11) or { panic(err) }
	refresh(config, directory) or { panic(err) }
	os.write_file(repository + '/objects/' + v2.files[0].sha256, 'corruption') or { panic(err) }
	if _ := transact(config, directory, 'upgrade', [], TransactionOptions{}) {
		assert false
	}
	assert read_state(directory, 'x86_64')!.generation == 1
	assert !os.exists(directory + '/objects/' + v2.files[0].sha256 + '.part')
	write_fixture_index(repository, [v1], private_key, 9) or { panic(err) }
	if _ := refresh(config, directory) {
		assert false
	}
	assert load_catalog(config, directory)!.packages.len == 2
	if _ := read_state(directory, 'aarch64') {
		assert false
	}
	if _ := disk_check(100, 80, 21) {
		assert false
	}
	disk_check(100, 80, 20) or { panic(err) }
	if _ := disk_check(~u64(0), ~u64(0), 1) {
		assert false
	}
	guard := acquire(directory) or { panic(err) }
	if another := acquire(directory) {
		another.release()
		assert false
	}
	guard.release()
	again := acquire(directory) or { panic(err) }
	again.release()
}

fn test_pack_and_signed_publish_use_real_payload_bytes() {
	work := fixture_dir('publisher')
	defer { os.rmdir_all(work) or {} }
	source := work + '/source'
	os.mkdir_all(source + '/bin') or { panic(err) }
	os.write_file(source + '/bin/app', 'actual executable bytes') or { panic(err) }
	os.chmod(source + '/bin/app', 0o755) or { panic(err) }
	template := fixture_package('app', '1.0.0', 'x86_64')
	os.write_file(work + '/manifest.json', json2.encode(template)) or { panic(err) }
	p := pack(work + '/manifest.json', source, work + '/repository') or { panic(err) }
	assert p.files[0].sha256 == sha256.sum('actual executable bytes'.bytes()).hex()
	assert p.files[0].executable
	key := keygen(work + '/seed') or { panic(err) }
	publish(work + '/repository', 'fixture', work + '/seed', 1, time.now().unix() + 3600) or { panic(err) }
	index := verify_index(Repository{ id: 'fixture', public_key: key }, read_metadata(work + '/repository/index.json')!, read_metadata(work + '/repository/index.sig')!, time.now().unix()) or { panic(err) }
	assert index.packages.len == 1
	assert index.packages[0] == p
	os.symlink('bin/app', source + '/link') or { panic(err) }
	if _ := pack(work + '/manifest.json', source, work + '/repository') {
		assert false
	}
}

fn test_state_directories_do_not_depend_on_umask() {
	previous := C.umask(0)
	defer { C.umask(previous) }
	work := fixture_dir('ownership')
	defer { os.rmdir_all(work) or {} }
	directory := work + '/state'
	guard := acquire(directory) or { panic(err) }
	guard.release()
	for path in [directory, directory + '/objects', directory + '/generations'] {
		assert os.lstat(path)!.mode & 0o777 == 0o755
	}
	os.chmod(directory + '/objects', 0o777) or { panic(err) }
	if other := acquire(directory) {
		other.release()
		assert false, 'accepted a writable payload cache'
	}
	os.chmod(directory + '/objects', 0o755) or { panic(err) }
	os.rmdir(directory + '/objects') or { panic(err) }
	os.mkdir(work + '/outside') or { panic(err) }
	os.symlink(work + '/outside', directory + '/objects') or { panic(err) }
	if other := acquire(directory) {
		other.release()
		assert false, 'accepted a linked payload cache'
	}
	assert os.ls(work + '/outside')!.len == 0
}
