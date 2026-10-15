// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

struct Client { root string binary string operation string deployment string }
struct Roots { format int = 1 architecture string packages []string }

fn repair_progress(event pkgprotocol.Progress) {
	if event.phase != 'resolve' { return }
	path := os.getenv('VINIX_REPAIR_RESTORE')
	if path == '' { return }
	os.unsetenv('VINIX_REPAIR_RESTORE')
	os.write_file(path, os.read_file(os.getenv('VINIX_REPAIR_SOURCE')) or { panic(err) }) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
}

fn (client Client) service() pkgcore.Service { return pkgcore.Service{ root: client.root, progress: repair_progress } }

fn (client Client) command(args []string) !string {
	mut process := os.new_process(client.binary)
	process.set_args(['--root', client.root, ...args]); process.set_redirect_stdio_merged(); process.run()
	text := process.stdout_slurp(); process.wait(); code := process.code; process.close()
	if code != 0 { return error(text) }
	return text
}

fn (client Client) state(verify bool) !pkgcore.State {
	if client.binary == '' {
		if verify { return client.service().verify() }
		return client.service().state()
	}
	return json2.decode[pkgcore.State](client.command(['--json', if verify { 'verify' } else { 'status' }])!)
}

fn (client Client) review() !pkgprotocol.Review {
	if client.binary == '' {
		if client.deployment != '' { return client.service().review_deployment(client.deployment) }
		return client.service().review(client.operation, if client.operation == 'install' { ['app'] } else { []string{} })
	}
	return pkgprotocol.decode_review(client.command(if client.deployment != '' { ['deployment-review', client.deployment] }
		else { ['review', client.operation, ...if client.operation == 'install' { ['app'] } else { []string{} }] })!)
}

fn (client Client) apply(review pkgprotocol.Review) !pkgcore.State {
	if client.binary == '' {
		if client.deployment != '' { return client.service().apply_deployment(client.deployment, review.fingerprint) }
		return client.service().transact(client.operation, review.names, pkgcore.TransactionOptions{ expected_review: review.fingerprint })
	}
	client.command(if client.deployment != '' { ['deployment-apply', review.fingerprint, client.deployment] }
		else { ['apply', review.fingerprint, client.operation, ...review.names] })!
	return client.state(false)
}

fn check_case(work string, mode string, binary string, before bool) ! {
	root := work + '/root'
	os.mkdir_all(root + '/etc/vinix-packages')!
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	key := pkgcore.keygen(work + '/seed')!
	config := pkgcore.Config{ architecture: architecture, policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 },
		repositories: [pkgcore.Repository{ id: 'trusted', url: 'file://' + work + '/repository', public_key: key }] }
	configuration := root + '/etc/vinix-packages/config.json'
	os.write_file(configuration, json2.encode(config))!
	for id in ['app', 'runtime', 'assets'] {
		source := work + '/source-' + id
		os.mkdir_all(source + '/bin')!; os.write_file(source + '/bin/app', 'signed payload for ' + id)!
		os.chmod(source + '/bin/app', if id == 'assets' { 0o644 } else { 0o755 })!
		manifest := pkgcore.Package{ id: id, name: id, version: '1.0.0', license: 'MIT',
			architecture: if id == 'assets' { 'all' } else { architecture }, kind: if id == 'app' { 'native' } else if id == 'runtime' { 'runtime' } else { 'data' },
			entrypoint: if id == 'app' { 'bin/app' } else { '' }, permissions: if id == 'app' { ['files'] } else { []string{} },
			dependencies: if id == 'app' { [pkgcore.Dependency{ id: 'runtime' }, pkgcore.Dependency{ id: 'assets' }] } else { []pkgcore.Dependency{} } }
		os.write_file(work + '/manifest.json', json2.encode(manifest))!
		pkgcore.pack(work + '/manifest.json', source, work + '/repository')!
	}
	pkgcore.publish(work + '/repository', 'trusted', work + '/seed', 1, time.now().unix() + 3600)!
	setup := pkgcore.Service{ root: root }; setup.refresh()!
	initial := setup.transact('install', ['app'], pkgcore.TransactionOptions{})!
	if mode == 'repair' {
		// New signed versions are available, including their dependency closure.
		// Explicit repair must retain the installed manifests and sequence records.
		for installed in initial.packages {
			p := pkgcore.Package{ ...installed.package, version: '2.0.0' }
			os.write_file(work + '/manifest.json', json2.encode(p))!
			pkgcore.pack(work + '/manifest.json', work + '/source-' + p.id, work + '/repository')!
		}
		pkgcore.publish(work + '/repository', 'trusted', work + '/seed', 2, time.now().unix() + 3600)!
		setup.refresh()!
		assert setup.plan('upgrade', [])!.packages.all(it.package.version == '2.0.0')
		assert setup.plan('repair', [])!.packages == initial.packages
	}
	deployment := if mode.starts_with('deploy') { work + '/deployment.json' } else { '' }
	if deployment != '' {
		locked := setup.lock_deployment([])!
		text := if mode == 'deploy-roots' { json2.encode(Roots{ architecture: architecture, packages: ['app'] }) } else { json2.encode(locked) }
		os.write_file(deployment, text)!
	}
	client := Client{ root: root, binary: binary, operation: if deployment != '' { 'deploy' } else { mode }, deployment: deployment }
	store := pkgcore.state_directory(root)
	app := store + '/current/apps/app/bin/app'
	runtime := store + '/current/apps/runtime/bin/app'
	state := os.read_file(store + '/current/state.json')!
	catalog := os.read_file(store + '/catalog.json')!; history := os.read_file(store + '/trust-history.json')!
	mut healthy := client.review()!; defer { healthy.close() }
	assert healthy.disk_needed == 0 && healthy.rows.all(it.action == 'keep')
	os.rm(app)!; os.write_file(runtime, 'x'.repeat(os.read_file(runtime)!.len))!
	if before {
		assert client.apply(healthy)!.generation == initial.generation
		if _ := client.state(true) { assert false }
		println('PACKAGE REPAIR BEFORE unchanged install reports success while installed application/runtime payloads remain damaged')
		return
	}
	sentinel := store + '/generations/.stage-preserve'
	os.mkdir(sentinel)!; os.write_file(sentinel + '/keep', 'recovery data')!
	if _ := client.apply(healthy) { assert false } else { assert err.msg().contains('stale') }
	assert os.is_dir(sentinel) && os.read_file(store + '/current/state.json')! == state
	mut review := client.review()!; defer { review.close() }
	assert review.fingerprint != healthy.fingerprint && review.disk_needed > 4 * 1024 * 1024
	assert review.rows.filter(it.action == 'update').map(it.id) == ['app', 'runtime']
	assert review.rows.filter(it.id == 'assets')[0].action == 'keep'
	assert review.rows.all(it.version == '1.0.0' && it.installed_version == '1.0.0')
	mut decoded := pkgprotocol.decode_review(json2.encode(review))!; assert decoded == review; decoded.close()
	// A different repair set (or a restored healthy set) requires new approval.
	os.write_file(app, os.read_file(work + '/source-app/bin/app')!)!
	os.chmod(app, 0o755)!
	if _ := client.apply(review) { assert false } else { assert err.msg().contains('stale') }
	os.write_file(runtime, os.read_file(work + '/source-runtime/bin/app')!)!
	if _ := client.apply(review) { assert false } else { assert err.msg().contains('stale') }
	os.rm(app)!; os.write_file(runtime, 'broken runtime')!
	mut repeated := client.review()!; defer { repeated.close() }
	assert repeated.fingerprint == review.fingerprint && os.is_dir(sentinel)
	// Trust and policy still gate repair; installed bytes grant no new authority.
	for restricted in [pkgcore.Config{ ...config, repositories: [] }, pkgcore.Config{ ...config, policy: pkgcore.Policy{ ...config.policy, permissions: [] } }] {
		os.write_file(configuration, json2.encode(restricted))!
		if _ := client.apply(review) { assert false }
		assert os.read_file(store + '/current/state.json')! == state
	}
	os.write_file(configuration, json2.encode(config))!
	if binary == '' && mode == 'install' {
		os.setenv('VINIX_REPAIR_RESTORE', app, true); os.setenv('VINIX_REPAIR_SOURCE', work + '/source-app/bin/app', true)
		if _ := client.apply(review) { assert false } else { assert err.msg().contains('stale') }
		os.unsetenv('VINIX_REPAIR_RESTORE'); os.unsetenv('VINIX_REPAIR_SOURCE')
		assert os.is_dir(sentinel) && os.read_file(store + '/current/state.json')! == state
		os.rm(app)!
	}
	// A repair with no usable cache and a bad signed-source object must fail
	// without activating; valid cache bytes permit an offline retry afterwards.
	os.mkdir(work + '/saved-cache')!
	for installed in initial.packages {
		if installed.package.id == 'assets' { continue }
		for file in installed.package.files { os.rename(store + '/objects/' + file.sha256, work + '/saved-cache/' + file.sha256)! }
	}
	app_payload := initial.packages.filter(it.package.id == 'app')[0].package.files[0]
	os.write_file(work + '/repository/objects/' + app_payload.sha256, 'x'.repeat(int(app_payload.bytes)))!
	if _ := client.apply(review) { assert false } else { assert err.msg().contains('checksum') }
	assert os.read_file(store + '/current/state.json')! == state && client.state(false)!.generation == 1
	for name in os.ls(work + '/saved-cache')! { os.rename(work + '/saved-cache/' + name, store + '/objects/' + name)! }
	os.rename(work + '/repository/objects', work + '/hidden-objects')!
	os.mkdir(work + '/personal')!; os.write_file(work + '/personal/memo', 'personal bytes')!
	repaired := client.apply(review)!
	assert repaired.generation > initial.generation && repaired.previous == initial.generation
	assert repaired.packages == initial.packages && repaired.requested == initial.requested
	assert client.state(true)!.generation == repaired.generation
	assert os.is_file(store + '/current/share/applications/vinix-app.desktop') && !os.is_link(app)
	assert os.read_file(store + '/catalog.json')! == catalog && os.read_file(store + '/trust-history.json')! == history
	mut unchanged := client.review()!; defer { unchanged.close() }
	assert unchanged.rows.all(it.action == 'keep') && unchanged.disk_needed == 0
	assert client.apply(unchanged)!.generation == repaired.generation
	if mode == 'repair' {
		// A publisher withdrawal must fail explicitly, rather than substituting
		// the newer manifest or trusting the old installed state by itself.
		os.rename(work + '/hidden-objects', work + '/repository/objects')!
		os.write_file(work + '/repository/objects/' + app_payload.sha256, os.read_file(work + '/source-app/bin/app')!)!
		manifest := work + '/repository/manifests/app-' + architecture + '-1.0.0.json'
		os.rename(manifest, work + '/withdrawn.json')!
		pkgcore.publish(work + '/repository', 'trusted', work + '/seed', 3, time.now().unix() + 3600)!
		setup.refresh()!
		if _ := client.review() { assert false } else { assert err.msg().contains('installed manifest is unavailable') }
		assert client.state(true)!.generation == repaired.generation
		os.rename(work + '/withdrawn.json', manifest)!
		pkgcore.publish(work + '/repository', 'trusted', work + '/seed', 4, time.now().unix() + 3600)!
		setup.refresh()!
		if binary == '' {
			if _ := setup.review('repair', ['app']) { assert false } else { assert err.msg().contains('takes no package IDs') }
			assert setup.transact('repair', [], pkgcore.TransactionOptions{})!.generation == repaired.generation
		} else {
			if _ := client.command(['repair', 'app']) { assert false } else { assert err.msg().contains('takes no package IDs') }
			client.command(['--offline', '--progress', 'repair'])!
			assert client.state(true)!.generation == repaired.generation
		}
	}
	// The damaged previous generation is retained for inspection, but rollback
	// must not trust its broken bytes merely because repair succeeded.
	if binary == '' { if _ := setup.rollback('') { assert false } }
	else { if _ := client.command(['rollback']) { assert false } }
	assert client.state(true)!.generation == repaired.generation
	setup.transact('remove', ['app'], pkgcore.TransactionOptions{})!
	assert setup.state()!.packages.len == 0 && os.read_file(work + '/personal/memo')! == 'personal bytes'
	println('PACKAGE REPAIR ' + mode + ': same-version rewrite review, stale health refusal, trust/policy/source checks, offline activation, healthy no-op and damaged rollback refusal PASS')
}

fn check() ! {
	if os.args.len !in [2, 3] { return error('usage: repair-check NEW_WORK_DIRECTORY [--before|PACKAGE_CLI]') }
	work := os.abs_path(os.args[1]); before := os.args.len == 3 && os.args[2] == '--before'
	binary := if os.args.len == 3 && !before { os.real_path(os.args[2]) } else { '' }
	if os.exists(work) || os.is_link(work) { return error('repair qualification directory must be new') }
	os.mkdir(work)!
	for mode in if before { ['install'] } else { ['install', 'upgrade', 'deploy-roots', 'deploy-lock', 'repair'] } {
		check_case(work + '/' + mode, mode, binary, before)!
	}
	if !before { println('PACKAGE REPAIR signed install/upgrade/deployment/explicit repair, reviewed corruption recovery, exact installed versions despite available updates, publisher withdrawal refusal, preserved state/data and protocol compatibility PASS') }
}

fn main() { check() or { eprintln(err); exit(1) } }
