// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

fn health_progress(event pkgprotocol.Progress) {
	if event.phase != 'verify' || event.package == '' { return }
	root := os.getenv('VINIX_HEALTH_ROOT')
	defer { unsafe { root.free() } }
	if root == '' { return }
	if _ := (pkgcore.Service{ root: root }).transact('remove', ['app'], pkgcore.TransactionOptions{}) { panic('health did not hold its reader lock') }
	else { message := err.msg(); assert message.contains('transaction'); unsafe { message.free(); err.free() } }
	os.write_file(os.getenv('VINIX_HEALTH_LOCKED'), 'writer refused') or { panic(err) }
}

struct Client { root string binary string }

fn (client Client) command(args []string) !string {
	mut child := os.new_process(client.binary)
	child.set_args(['--root', client.root, ...args]); child.set_redirect_stdio_merged(); child.run()
	text := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	if code != 0 { return error(text) }
	return text
}

fn (client Client) report() !pkgprotocol.HealthReport {
	if client.binary == '' { return (pkgcore.Service{ root: client.root, progress: health_progress }).health() }
	return pkgprotocol.decode_health(client.command(['--json', 'health'])!)
}

fn check() ! {
	if os.args.len !in [2, 3] { return error('usage: health-report-check NEW_WORK [PACKAGE_CLI]') }
	work := os.abs_path(os.args[1]); if os.exists(work) || os.is_link(work) { return error('health qualification directory must be new') }
	root := work + '/root'; os.mkdir_all(root + '/etc/vinix-packages')!
	arch := $if arm64 { 'aarch64' } $else { 'x86_64' }
	key := pkgcore.keygen(work + '/seed')!
	config := pkgcore.Config{ architecture: arch, policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 },
		repositories: [pkgcore.Repository{ id: 'trusted', url: 'file://' + work + '/repository', public_key: key }] }
	configuration := root + '/etc/vinix-packages/config.json'; os.write_file(configuration, json2.encode(config))!
	client := Client{ root: root, binary: if os.args.len == 3 { os.real_path(os.args[2]) } else { '' } }
	store := pkgcore.state_directory(root)
	mut empty := client.report()!; assert empty.generation == 0 && empty.rows.len == 0 && !os.exists(store); empty.close()
	for id in ['app', 'runtime', 'assets', 'utility'] {
		source := work + '/source-' + id
		os.mkdir_all(source + '/bin')!; os.write_file(source + '/bin/app', 'signed payload for ' + id)!
		os.chmod(source + '/bin/app', if id == 'assets' { 0o644 } else { 0o755 })!
		p := pkgcore.Package{ id: id, name: 'Package é🚀 ' + id, version: '1.0.0', architecture: if id == 'assets' { 'all' } else { arch },
			kind: if id == 'runtime' { 'runtime' } else if id == 'assets' { 'data' } else { 'native' }, license: 'MIT',
			entrypoint: if id in ['app', 'utility']! { 'bin/app' } else { '' }, permissions: ['files'],
			dependencies: if id == 'app' { [pkgcore.Dependency{ id: 'runtime' }, pkgcore.Dependency{ id: 'assets' }] } else { []pkgcore.Dependency{} } }
		os.write_file(work + '/manifest.json', json2.encode(p))!
		pkgcore.pack(work + '/manifest.json', source, work + '/repository')!
	}
	pkgcore.publish(work + '/repository', 'trusted', work + '/seed', 1, time.now().unix() + 3600)!
	service := pkgcore.Service{ root: root }; service.refresh()!
	initial := service.transact('install', ['app', 'utility'], pkgcore.TransactionOptions{})!
	mut clean := client.report()!; assert clean.generation == initial.generation && clean.rows.len == 4 && clean.rows.all(it.issue == ''); clean.close()
	app := store + '/current/apps/app/bin/app'
	os.write_file(app, 'x'.repeat(os.read_file(app)!.len))!
	os.write_file(store + '/current/apps/runtime/unexpected', 'undeclared')!
	os.chmod(store + '/current/apps/assets/bin/app', 0o600)!
	os.rm(store + '/current/share/applications/vinix-utility.desktop')!
	sentinel := store + '/generations/.stage-health-preserve'; os.mkdir(sentinel)!; os.write_file(sentinel + '/keep', 'recovery data')!
	os.mkdir(work + '/personal')!; os.write_file(work + '/personal/memo', 'personal data')!
	state := os.read_file(store + '/current/state.json')!
	catalog := os.read_file(store + '/catalog.json')!; history := os.read_file(store + '/trust-history.json')!
	os.setenv('VINIX_HEALTH_ROOT', root, true); os.setenv('VINIX_HEALTH_LOCKED', work + '/locked', true)
	defer { os.unsetenv('VINIX_HEALTH_ROOT'); os.unsetenv('VINIX_HEALTH_LOCKED') }
	mut damaged := client.report()!; defer { damaged.close() }
	assert damaged.rows.map(it.id) == ['app', 'assets', 'runtime', 'utility']
	assert damaged.rows.map(it.issue) == ['payload', 'namespace', 'namespace', 'registration']
	assert damaged.rows.all(it.repository == 'trusted' && it.public_key == key && it.name.starts_with('Package é🚀'))
	if client.binary == '' { assert os.read_file(work + '/locked')! == 'writer refused' }
	os.unsetenv('VINIX_HEALTH_ROOT')
	if _ := service.verify() { assert false } else { assert err.msg().contains('app: installed payload') }
	if client.binary != '' {
		text := client.command(['health'])!; assert text.contains('4; with issues: 4') && text.contains('utility 1.0.0: registration')
		if _ := client.command(['health', 'app']) { assert false } else { assert err.msg().contains('takes no package IDs') }
		if _ := client.command(['--progress', 'health']) { assert false } else { assert err.msg().contains('--progress supports') }
	}
	// Integrity observations remain available with revoked publishers, restrictive
	// policy, corrupt cached metadata and unavailable upstream repositories.
	os.write_file(configuration, json2.encode(pkgcore.Config{ ...config, repositories: [], policy: pkgcore.Policy{ ...config.policy, permissions: [] } }))!
	os.write_file(store + '/catalog.json', 'unavailable catalog')!; os.write_file(store + '/trust-history.json', 'unavailable history')!
	os.rename(work + '/repository', work + '/hidden-repository')!
	mut independent := client.report()!; assert independent == damaged; independent.close()
	assert os.read_file(store + '/current/state.json')! == state && os.read_file(sentinel + '/keep')! == 'recovery data'
	assert os.read_file(store + '/catalog.json')! == 'unavailable catalog' && os.read_file(store + '/trust-history.json')! == 'unavailable history'
	os.write_file(store + '/current/state.json', 'broken state')!
	if _ := client.report() { assert false }
	os.write_file(store + '/current/state.json', state)!
	os.write_file(configuration, json2.encode(config))!; os.write_file(store + '/catalog.json', catalog)!; os.write_file(store + '/trust-history.json', history)!
	// A report is not approval. A fresh authenticated repair review and the normal
	// disk/cache/activation checks restore all packages without an upstream read.
	mut review := service.review('repair', [])!; defer { review.close() }
	assert review.rows.all(it.action == 'update')
	repaired := service.transact('repair', [], pkgcore.TransactionOptions{ expected_review: review.fingerprint })!
	assert repaired.generation > initial.generation && repaired.packages == initial.packages && repaired.requested == initial.requested
	mut after := client.report()!; defer { after.close() }
	assert after.generation == repaired.generation && after.rows.all(it.issue == '')
	assert damaged.generation == initial.generation && damaged.rows.all(it.issue != '')
	assert os.read_file(work + '/personal/memo')! == 'personal data'
	service.transact('remove', ['app', 'utility'], pkgcore.TransactionOptions{})!
	mut removed := client.report()!; defer { removed.close() }
	assert removed.generation > repaired.generation && removed.rows.len == 0
	println('HEALTH REPORT signed service/CLI, all simultaneous app/runtime/data/launcher issues, read-only locking and retained state, trust/catalog independence, malformed state refusal, fresh offline repair and clean uninstall PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
