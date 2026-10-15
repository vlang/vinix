// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

struct Client { root string binary string operation string deployment string }
struct Roots { format int = 1 architecture string packages []string }

fn C.umask(u32) u32
fn C.mkfifo(&char, u32) int

fn health_progress(event pkgprotocol.Progress) {
	if event.phase != 'resolve' { return }
	path := os.getenv('VINIX_HEALTH_RESTORE')
	if path == '' { return }
	os.unsetenv('VINIX_HEALTH_RESTORE')
	os.chmod(path, 0o755) or { panic(err) }
}

fn (client Client) service() pkgcore.Service { return pkgcore.Service{ root: client.root, progress: health_progress } }

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

fn with_umask(client Client, review pkgprotocol.Review) !pkgcore.State {
	previous := C.umask(0o077); defer { C.umask(previous) }
	return client.apply(review)
}


fn restore(base string, entry_bytes string, outside string) ! {
	work := os.dir(outside)
	for pair in [[base + "/apps/app/bin", work + "/saved-bin"], [base + "/apps/app", work + "/saved-app"]] {
		if !os.exists(pair[1]) { continue }
		os.rm(pair[0])!; os.rename(pair[1], pair[0])!
	}
	if os.exists(work + "/saved-file") {
		os.rm(base + "/apps/app/bin/app")!; os.rename(work + "/saved-file", base + "/apps/app/bin/app")!
	}
	for path in [base + "/apps/app/extra", base + "/apps/runtime/lib", base + "/apps/assets/extra"] {
		if os.is_dir(path) { os.rmdir_all(path)! } else if os.exists(path) || os.is_link(path) { os.rm(path)! }
	}
	for id in ["app", "runtime", "assets"] { os.chmod(base + "/apps/" + id + "/bin", 0o755)! }
}

fn damage(base string, kind string, outside string, entry_bytes string) ! {
	work := os.dir(outside)
	match kind {
		"extra-app" { os.write_file(base + "/apps/app/extra", "undeclared code")! }
		"extra-runtime" { os.mkdir(base + "/apps/runtime/lib")!; os.write_file(base + "/apps/runtime/lib/extra.so", "undeclared library")! }
		"extra-assets" { assert C.mkfifo((base + "/apps/assets/extra").str, 0o600) == 0 }
		"empty-directory" { os.mkdir(base + "/apps/app/extra")! }
		"app-directory" { os.chmod(base + "/apps/app/bin", 0o700)! }
		"nested-alias" { os.rename(base + "/apps/app/bin", work + "/saved-bin")!; os.symlink(work + "/saved-bin", base + "/apps/app/bin")! }
		"package-alias" { os.rename(base + "/apps/app", work + "/saved-app")!; os.symlink(work + "/saved-app", base + "/apps/app")! }
		"payload-hardlink" { os.rename(base + "/apps/app/bin/app", work + "/saved-file")!; os.link(work + "/saved-file", base + "/apps/app/bin/app")! }
		else { return error("unknown installed namespace case") }
	}
}

fn check_case(work string, kind string, binary string, before bool) ! {
	root := work + '/root'; os.mkdir_all(root + '/etc/vinix-packages')!
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	key := pkgcore.keygen(work + '/seed')!
	config := pkgcore.Config{ architecture: architecture, policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 },
		repositories: [pkgcore.Repository{ id: 'trusted', url: 'file://' + work + '/repository', public_key: key }] }
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
	for id in ['app', 'runtime', 'assets'] {
		source := work + '/source-' + id; os.mkdir_all(source + '/bin')!
		os.write_file(source + '/bin/app', 'signed payload for ' + id)!; os.chmod(source + '/bin/app', if id == 'assets' { 0o644 } else { 0o755 })!
		p := pkgcore.Package{ id: id, name: 'Editor é', description: 'Read and write text', version: '1.0.0', license: 'MIT',
			architecture: if id == 'assets' { 'all' } else { architecture }, kind: if id == 'app' { 'native' } else if id == 'runtime' { 'runtime' } else { 'data' },
			entrypoint: if id == 'app' { 'bin/app' } else { '' }, permissions: if id == 'app' { ['files'] } else { []string{} },
			associations: if id == 'app' { ['text/plain', 'text/markdown'] } else { []string{} },
			dependencies: if id == 'app' { [pkgcore.Dependency{ id: 'runtime' }, pkgcore.Dependency{ id: 'assets' }] } else { []pkgcore.Dependency{} } }
		os.write_file(work + '/manifest.json', json2.encode(p))!; pkgcore.pack(work + '/manifest.json', source, work + '/repository')!
	}
	pkgcore.publish(work + '/repository', 'trusted', work + '/seed', 1, time.now().unix() + 3600)!
	setup := pkgcore.Service{ root: root }; setup.refresh()!
	mask := C.umask(if before { 0o022 } else { 0o077 })
	initial := setup.transact('install', ['app'], pkgcore.TransactionOptions{}) or { C.umask(mask); return err }
	C.umask(mask)
	assert setup.verify()!.generation == 1
	operation := if kind in ['extra-runtime', 'nested-alias'] { 'upgrade' } else if kind in ['extra-assets', 'payload-hardlink'] { 'deploy' } else { 'install' }
	deployment := if operation == 'deploy' { work + '/deployment.json' } else { '' }
	if deployment != '' {
		locked := setup.lock_deployment([])!
		text := if kind == 'extra-assets' { json2.encode(Roots{ architecture: architecture, packages: ['app'] }) } else { json2.encode(locked) }
		os.write_file(deployment, text)!
	}
	client := Client{ root: root, binary: binary, operation: operation, deployment: deployment }
	store := pkgcore.state_directory(root); base := store + '/generations/1'
	entry := base + '/share/applications/vinix-app.desktop'; entry_bytes := os.read_file(entry)!
	outside := work + '/outside'; os.write_file(outside, entry_bytes)!; os.chmod(outside, 0o640)!
	state := os.read_file(store + '/current/state.json')!; catalog := os.read_file(store + '/catalog.json')!; history := os.read_file(store + '/trust-history.json')!
	mut healthy := client.review()!; defer { healthy.close() }
	assert healthy.disk_needed == 0 && healthy.rows.all(it.action == 'keep')
	damage(base, kind, outside, entry_bytes)!
	for installed in initial.packages { for file in installed.package.files { assert pkgcore.verified_file(base + '/apps/' + installed.package.id + '/' + file.path, file) } }
	if before {
		assert client.state(true)!.generation == 1 && client.apply(healthy)!.generation == 1
		mut ignored := client.review()!; defer { ignored.close() }
		assert ignored.disk_needed == 0 && ignored.rows.all(it.action == 'keep')
		println('INSTALLED NAMESPACE BEFORE ' + kind + ': Verify and unchanged install report healthy success with damaged installation')
		return
	}
	if _ := client.state(true) { assert false } else { assert err.msg().contains('verification failed') }
	sentinel := store + '/generations/.stage-preserve'; os.mkdir(sentinel)!; os.write_file(sentinel + '/keep', 'recovery data')!
	if _ := client.apply(healthy) { assert false } else { assert err.msg().contains('stale') }
	assert os.is_dir(sentinel) && os.read_file(store + '/current/state.json')! == state
	mut review := client.review()!; defer { review.close() }
	affected := if kind == 'extra-runtime' { 'runtime' } else if kind == 'extra-assets' { 'assets' } else { 'app' }
	assert review.rows.filter(it.action == 'update').map(it.id) == [affected] && review.disk_needed > 4 * 1024 * 1024
	assert review.rows.all(it.version == '1.0.0' && it.installed_version == '1.0.0')
	mut decoded := pkgprotocol.decode_review(json2.encode(review))!; assert decoded == review; decoded.close()
	restore(base, entry_bytes, outside)!
	if _ := client.apply(review) { assert false } else { assert err.msg().contains('stale') }
	damage(base, kind, outside, entry_bytes)!
	if binary == '' && kind == 'app-mode' {
		os.setenv('VINIX_HEALTH_RESTORE', base + '/apps/app/bin/app', true)
		if _ := client.apply(review) { assert false } else { assert err.msg().contains('stale') }
		os.unsetenv('VINIX_HEALTH_RESTORE'); assert os.is_dir(sentinel)
		damage(base, kind, outside, entry_bytes)!
	}
	os.rename(work + '/repository/objects', work + '/hidden-objects')!
	personal := root + '/home/user/.local/share/vinix-apps/app'; os.mkdir_all(personal)!; os.write_file(personal + '/memo', 'private notes')!
	repaired := with_umask(client, review)!
	assert repaired.generation == 2 && repaired.previous == 1 && repaired.packages == initial.packages && repaired.requested == initial.requested
	assert client.state(true)!.generation == 2
	assert os.read_file(store + '/current/share/applications/vinix-app.desktop')! == entry_bytes
	assert !os.is_link(store + '/current/share/applications/vinix-app.desktop') && os.lstat(store + '/current/share/applications/vinix-app.desktop')!.mode & 0o7777 == 0o644
	for installed in repaired.packages { for file in installed.package.files {
		assert os.lstat(store + '/current/apps/' + installed.package.id + '/' + file.path)!.mode & 0o7777 == if file.executable { u32(0o755) } else { u32(0o644) }
	} }
	assert os.read_file(outside)! == entry_bytes && os.lstat(outside)!.mode & 0o7777 == 0o640
	assert os.read_file(store + '/catalog.json')! == catalog && os.read_file(store + '/trust-history.json')! == history
	mut unchanged := client.review()!; defer { unchanged.close() }
	assert unchanged.rows.all(it.action == 'keep') && unchanged.disk_needed == 0 && client.apply(unchanged)!.generation == 2
	if _ := client.apply(review) { assert false } else { assert err.msg().contains('stale') }
	if binary == '' { if _ := setup.rollback('') { assert false } else { assert err.msg().contains('verification failed') || err.msg().contains('generation') } }
	else { if _ := client.command(['rollback']) { assert false } else { assert err.msg().contains('verification failed') || err.msg().contains('generation') } }
	assert client.state(false)!.generation == 2
	restore(base, entry_bytes, outside)!
	if binary == '' { assert setup.rollback('')!.generation == 1 } else { client.command(['rollback'])!; assert client.state(false)!.generation == 1 }
	assert client.state(true)!.generation == 1
	setup.transact('remove', ['app'], pkgcore.TransactionOptions{})!
	assert setup.state()!.packages.len == 0 && !os.exists(store + '/current/share/applications/vinix-app.desktop')
	assert os.read_file(personal + '/memo')! == 'private notes'
	println('INSTALLED NAMESPACE ' + kind + ': reviewed offline namespace repair, stale approvals, preserved outside/data/history, rollback refusal/restoration and uninstall PASS')
}

fn check() ! {
	if os.args.len !in [2, 3] { return error('usage: installed-namespace-check NEW_WORK_DIRECTORY [--before|PACKAGE_CLI]') }
	work := os.abs_path(os.args[1]); before := os.args.len == 3 && os.args[2] == '--before'
	binary := if os.args.len == 3 && !before { os.real_path(os.args[2]) } else { '' }
	if os.exists(work) || os.is_link(work) { return error('installed-namespace qualification directory must be new') }
	os.mkdir(work)!
	for kind in if before { ['extra-app', 'nested-alias'] } else { ['extra-app', 'extra-runtime', 'extra-assets', 'empty-directory', 'app-directory', 'nested-alias', 'package-alias', 'payload-hardlink'] } {
		check_case(work + '/' + kind, kind, binary, before)!
	}
	if !before { println('INSTALLED NAMESPACE eight signed app/runtime/data namespace repairs, unchanged payload hashes, stale approvals, offline cache, rollback and uninstall PASS') }
}

fn main() { check() or { eprintln(err); exit(1) } }
