// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

#include <sys/file.h>
#include <fcntl.h>
fn C.flock(int, int) int

fn command(binary string, root string, args []string) !string {
	mut child := os.new_process(binary)
	child.set_args(['--root', root, ...args]); child.set_redirect_stdio_merged(); child.run()
	text := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	if code != 0 { return error(text) }
	return text
}

fn check() ! {
	if os.args.len != 3 { return error('usage: rollback-check NEW_WORK PACKAGE_CLI') }
	work := os.args[1]; binary := os.args[2]
	if os.exists(work) { return error('rollback fixture requires a new workspace') }
	root := work + '/root'
	os.mkdir_all(root + '/etc/vinix-packages')!
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	key := pkgcore.keygen(work + '/seed')!
	configuration := pkgcore.Config{ architecture: architecture, policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 },
		repositories: [pkgcore.Repository{ id: 'trusted', url: 'file://' + work + '/repository', public_key: key }] }
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(configuration))!
	service := pkgcore.Service{ root: root }
	os.mkdir_all(work + '/runtime/bin')!; os.write_file(work + '/runtime/bin/runner', 'isolated runtime')!
	os.chmod(work + '/runtime/bin/runner', 0o755)!
	os.mkdir_all(work + '/assets/share')!; os.write_file(work + '/assets/share/data', 'architecture-independent data')!
	for p in [pkgcore.Package{ id: 'runtime', name: 'Runtime', version: '1.0.0', architecture: architecture, kind: 'runtime', license: 'MIT' },
		pkgcore.Package{ id: 'assets', name: 'Assets', version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT' }] {
		os.write_file(work + '/manifest.json', json2.encode(p))!
		pkgcore.pack(work + '/manifest.json', work + '/' + p.id, work + '/repository')!
	}
	for version in 1 .. 5 {
		os.mkdir_all(work + '/source/bin')!
		os.write_file(work + '/source/bin/app', 'signed application version ' + version.str())!
		os.chmod(work + '/source/bin/app', 0o755)!
		os.write_file(work + '/manifest.json', json2.encode(pkgcore.Package{ id: 'app', name: 'Application', license: 'MIT',
			version: version.str() + '.0.0', architecture: architecture, kind: 'native', entrypoint: 'bin/app',
			dependencies: [pkgcore.Dependency{ id: 'runtime' }, pkgcore.Dependency{ id: 'assets' }] }))!
		pkgcore.pack(work + '/manifest.json', work + '/source', work + '/repository')!
		pkgcore.publish(work + '/repository', 'trusted', work + '/seed', u64(version), time.now().unix() + 3600)!
		command(binary, root, ['update'])!
		command(binary, root, if version == 1 { ['install', 'app'] } else { ['upgrade'] })!
	}
	directory := pkgcore.state_directory(root)
	before := service.state()!
	old := pkgcore.read_state(directory, architecture)!
	assert old.generation == 4 && old.previous == 3
	mut cleanup := pkgprotocol.decode_cleanup_review(command(binary, root, ['cleanup-review'])!)!; defer { cleanup.close() }
	assert cleanup.generations == [u64(1), 2]
	command(binary, root, ['cleanup-apply', cleanup.fingerprint])!
	assert !os.exists(directory + '/generations/2')
	retained_text := os.read_file(directory + '/generations/3/state.json')!
	retained := json2.decode[pkgcore.State](retained_text)!
	lease := C.open((directory + '/generations/3/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	if lease < 0 || C.flock(lease, C.LOCK_SH) != 0 { return error('cannot lease rollback source') }
	defer { C.close(lease) }
	for name in os.ls(directory + '/objects')! { os.rm(directory + '/objects/' + name)! }
	os.rmdir_all(work + '/repository')!
	personal := root + '/home/user/.local/share/vinix-apps/app'
	os.mkdir_all(personal)!; os.write_file(personal + '/note', 'retained personal data')!
	catalog := os.read_file(directory + '/catalog.json')!
	history := os.read_file(directory + '/trust-history.json')!
	mut review := pkgprotocol.decode_review(command(binary, root, ['review', 'rollback'])!)!; defer { review.close() }
	assert review.target_generation == 3 && review.generation == 4 && review.requested == ['app']
	assert review.rows.len == 3 && review.rows.filter(it.action == 'update').map(it.id) == ['app']
	assert review.disk_needed > 4 * 1024 * 1024
	output := command(binary, root, ['--progress', 'apply', review.fingerprint, 'rollback'])!
	mut phases := []string{}
	for line in output.split_into_lines() {
		if !line.starts_with(pkgprotocol.progress_prefix) { continue }
		event := pkgprotocol.decode_progress(line[pkgprotocol.progress_prefix.len..])!
		phases << event.phase
	}
	assert phases[0] == 'resolve' && phases.last() == 'complete' && phases.filter(it == 'activate').len == 1
	assert 'copy' in phases && 'download' !in phases
	restored := service.verify()!
	assert restored.generation == 5 && restored.previous == 4
	assert restored.requested == retained.requested && restored.packages == retained.packages
	assert os.read_file(directory + '/generations/3/state.json')! == retained_text
	os.mkdir(directory + '/generations/.stage-sentinel')!
	os.write_file(directory + '/generations/.stage-sentinel/keep', 'interrupted recovery')!
	if _ := command(binary, root, ['apply', review.fingerprint, 'rollback']) { assert false, 'reused approval accepted' }
	assert service.state()! == restored && os.exists(directory + '/generations/.stage-sentinel/keep')
	mut busy := pkgprotocol.decode_cleanup_review(command(binary, root, ['cleanup-review'])!)!; defer { busy.close() }
	assert busy.generation == 5 && busy.previous == 4 && busy.generations.len == 0
	assert C.flock(lease, C.LOCK_UN) == 0
	mut released := pkgprotocol.decode_cleanup_review(command(binary, root, ['cleanup-review'])!)!; defer { released.close() }
	assert released.generations == [u64(3)]
	command(binary, root, ['cleanup-apply', released.fingerprint])!
	command(binary, root, ['rollback'])!
	undone := service.verify()!
	assert undone.generation == 6 && undone.previous == 5 && undone.packages == before.packages
	command(binary, root, ['gc'])!
	assert os.ls(directory + '/generations')!.sorted() == ['5', '6']
	assert os.ls(directory + '/objects')!.len == 0 && service.verify()! == undone
	assert os.read_file(directory + '/catalog.json')! == catalog && os.read_file(directory + '/trust-history.json')! == history
	assert os.read_file(personal + '/note')! == 'retained personal data'
	command(binary, root, ['remove', 'app'])!
	assert service.state()!.packages.len == 0 && !os.exists(directory + '/current/share/applications/vinix-app.desktop')
	command(binary, root, ['rollback'])!
	assert service.verify()!.packages == before.packages && os.exists(directory + '/current/share/applications/vinix-app.desktop')
	assert os.read_file(personal + '/note')! == 'retained personal data'
	println('ROLLBACK CLI signed app/runtime/all-data closure, reviewed progress, offline source copies, stale approval, leases, cleanup, undo, uninstall and personal data PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
