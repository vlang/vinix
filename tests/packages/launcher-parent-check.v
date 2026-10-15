// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

fn command(binary string, root string, args []string) !string {
	mut child := os.new_process(binary)
	child.set_args(['--root', root, ...args]); child.set_redirect_stdio_merged(); child.run()
	text := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	if code != 0 { return error(text) }
	return text
}

fn review(binary string, root string) !pkgprotocol.Review {
	text := command(binary, root, ['review', 'repair'])!
	defer { unsafe { text.free() } }
	return pkgprotocol.decode_review(text)
}

fn check_case(work string, binary string, part string, alias bool) ! {
	root := work + '/root'; architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	os.mkdir_all(root + '/etc/vinix-packages')!
	key := pkgcore.keygen(work + '/seed')!
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ architecture: architecture,
		policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 },
		repositories: [pkgcore.Repository{ id: 'trusted', url: 'file://' + work + '/repository', public_key: key }] }))!
	os.mkdir_all(work + '/source/bin')!
	for id in ['app', 'utility', 'runtime', 'assets'] {
		os.write_file(work + '/source/bin/app', 'signed payload for ' + id)!
		os.chmod(work + '/source/bin/app', if id == 'assets' { 0o644 } else { 0o755 })!
		os.write_file(work + '/manifest.json', json2.encode(pkgcore.Package{ id: id, name: id, version: '1.0.0', license: 'MIT',
			architecture: if id == 'assets' { 'all' } else { architecture },
			kind: if id == 'assets' { 'data' } else if id == 'runtime' { 'runtime' } else { 'native' },
			entrypoint: if id in ['app', 'utility'] { 'bin/app' } else { '' }, associations: if id == 'app' { ['text/plain'] } else { []string{} },
			dependencies: if id in ['app', 'utility'] { [pkgcore.Dependency{ id: 'runtime' }, pkgcore.Dependency{ id: 'assets' }] } else { []pkgcore.Dependency{} } }))!
		pkgcore.pack(work + '/manifest.json', work + '/source', work + '/repository')!
	}
	pkgcore.publish(work + '/repository', 'trusted', work + '/seed', 1, time.now().unix() + 3600)!
	service := pkgcore.Service{ root: root }; service.refresh()!
	initial := service.transact('install', ['app', 'utility'], pkgcore.TransactionOptions{})!
	store := pkgcore.state_directory(root); generation := store + '/generations/1'; path := generation + '/' + part
	app_entry := os.read_file(generation + '/share/applications/vinix-app.desktop')!
	state := os.read_file(generation + '/state.json')!; catalog := os.read_file(store + '/catalog.json')!; history := os.read_file(store + '/trust-history.json')!
	mut healthy := review(binary, root)!; defer { healthy.close() }
	assert healthy.rows.all(it.action == 'keep') && healthy.disk_needed == 0
	if alias { os.rename(path, work + '/outside')!; os.symlink(work + '/outside', path)! }
	else { os.chmod(path, 0o777)! }
	mut refused := false
	command(binary, root, ['verify']) or { message := err.msg(); refused = message.contains('registration verification failed'); unsafe { message.free(); err.free() } }
	assert refused
	mut health := pkgprotocol.decode_health(command(binary, root, ['--json', 'health'])!)!; defer { health.close() }
	assert health.rows.filter(it.issue != '').map(it.id) == ['app', 'utility']
	assert health.rows.filter(it.issue != '').all(it.issue == 'registration')
	stage := store + '/generations/.stage-preserve'; os.mkdir(stage)!; os.write_file(stage + '/keep', 'recovery')!
	refused = false; command(binary, root, ['apply', healthy.fingerprint, 'repair']) or { refused = true; unsafe { err.free() } }; assert refused && os.exists(stage)
	mut damaged := review(binary, root)!; defer { damaged.close() }
	assert damaged.rows.filter(it.action == 'update').map(it.id) == ['app', 'utility'] && damaged.disk_needed > 4 * 1024 * 1024
	assert damaged.rows.all(it.version == it.installed_version)
	if alias { os.rm(path)!; os.rename(work + '/outside', path)! } else { os.chmod(path, 0o755)! }
	refused = false; command(binary, root, ['apply', damaged.fingerprint, 'repair']) or { refused = true; unsafe { err.free() } }; assert refused && os.exists(stage)
	if alias { os.rename(path, work + '/outside')!; os.symlink(work + '/outside', path)! } else { os.chmod(path, 0o777)! }
	os.rename(work + '/repository/objects', work + '/unreachable-objects')!
	personal := root + '/home/user/.local/share/vinix-apps/app'; os.mkdir_all(personal)!; os.write_file(personal + '/memo', 'personal data')!
	command(binary, root, ['apply', damaged.fingerprint, 'repair'])!
	repaired := service.verify()!
	assert repaired.generation == 2 && repaired.previous == 1 && repaired.packages == initial.packages && repaired.requested == initial.requested
	assert os.read_file(store + '/generations/1/state.json')! == state
	assert os.read_file(store + '/current/share/applications/vinix-app.desktop')! == app_entry
	assert !os.is_link(store + '/current/share') && !os.is_link(store + '/current/share/applications')
	assert os.lstat(store + '/current/share')!.mode & 0o7777 == 0o755 && os.lstat(store + '/current/share/applications')!.mode & 0o7777 == 0o755
	assert os.read_file(store + '/catalog.json')! == catalog && os.read_file(store + '/trust-history.json')! == history
	if alias {
		outside_entry := work + '/outside/' + if part == 'share' { 'applications/' } else { '' } + 'vinix-app.desktop'
		assert os.read_file(outside_entry)! == app_entry && os.lstat(work + '/outside')!.mode & 0o7777 == 0o755
	}
	mut clean := service.health()!; assert clean.rows.all(it.issue == ''); clean.close()
	command(binary, root, ['remove', 'app', 'utility'])!
	assert service.state()!.packages.len == 0 && os.ls(store + '/current/share/applications')!.len == 0
	assert os.read_file(personal + '/memo')! == 'personal data'
	println('LAUNCHER CLI ' + part + if alias { ' alias' } else { ' mode' } + ': Verify/health, exact repair set, stale approvals, offline repair, preserved outside/state/history/data and uninstall PASS')
}

fn check() ! {
	if os.args.len != 3 || os.exists(os.args[1]) { return error('usage: launcher-parent-check NEW_WORK PACKAGE_CLI') }
	for alias in [true, false] { for part in ['share', 'share/applications'] {
		check_case(os.args[1] + '/' + part.replace('/', '-') + if alias { '-alias' } else { '-mode' }, os.args[2], part, alias)!
	} }
	println('LAUNCHER CLI four signed shared-parent repairs preserve app/runtime/data manifests and provenance, cache recovery, retained generations and clean uninstall PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
