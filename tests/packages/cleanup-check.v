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
	if os.args.len != 3 { return error('usage: cleanup-check NEW_WORK PACKAGE_CLI') }
	work := os.args[1]; binary := os.args[2]
	if os.exists(work) { return error('cleanup fixture requires a new workspace') }
	root := work + '/root'
	os.mkdir_all(root + '/etc/vinix-packages')!
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	key := pkgcore.keygen(work + '/seed')!
	configuration := pkgcore.Config{ architecture: architecture, policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 },
		repositories: [pkgcore.Repository{ id: 'trusted', url: 'file://' + work + '/repository', public_key: key }] }
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(configuration))!
	service := pkgcore.Service{ root: root }
	for version in 1 .. 5 {
		os.mkdir_all(work + '/source/bin')!
		os.write_file(work + '/source/bin/app', 'signed application version ' + version.str())!
		os.chmod(work + '/source/bin/app', 0o755)!
		os.write_file(work + '/manifest.json', json2.encode(pkgcore.Package{ id: 'app', name: 'Application', license: 'MIT',
			version: version.str() + '.0.0', architecture: architecture, kind: 'native', entrypoint: 'bin/app' }))!
		pkgcore.pack(work + '/manifest.json', work + '/source', work + '/repository')!
		pkgcore.publish(work + '/repository', 'trusted', work + '/seed', u64(version), time.now().unix() + 3600)!
		service.refresh()!
		state := service.transact(if version == 1 { 'install' } else { 'upgrade' }, if version == 1 { ['app'] } else { []string{} }, pkgcore.TransactionOptions{})!
		assert state.generation == u64(version) && state.packages[0].package.version == version.str() + '.0.0'
	}
	directory := pkgcore.state_directory(root)
	os.mkdir(directory + '/generations/.stage-retained')!
	os.write_file(directory + '/generations/.stage-retained/payload', 'interrupted recovery')!
	os.write_file(directory + '/objects/' + 'f'.repeat(64) + '.part', 'interrupted download')!
	os.mkdir_all(root + '/home/user/.local/share/vinix-apps/app')!
	os.write_file(root + '/home/user/.local/share/vinix-apps/app/data', 'personal data')!
	state_bytes := os.read_file(directory + '/current/state.json')!
	objects := os.ls(directory + '/objects')!.sorted()
	lease := C.open((directory + '/generations/2/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	if lease < 0 || C.flock(lease, C.LOCK_SH) != 0 { return error('cannot lease obsolete generation') }
	defer { C.close(lease) }
	mut review := pkgprotocol.decode_cleanup_review(command(binary, root, ['cleanup-review'])!)!
	defer { review.close() }
	assert review.generations == [u64(1)] && review.generation == 4 && review.previous == 3 && review.architecture == architecture
	assert os.exists(directory + '/generations/1/apps/app/bin/app')
	assert C.flock(lease, C.LOCK_UN) == 0
	mut stale := false
	command(binary, root, ['cleanup-apply', review.fingerprint]) or {
		message := err.msg(); stale = message.contains('stale'); unsafe { message.free(); err.free() }
	}
	assert stale && os.exists(directory + '/generations/1/apps/app/bin/app')
	mut fresh := pkgprotocol.decode_cleanup_review(command(binary, root, ['cleanup-review'])!)!; defer { fresh.close() }
	assert fresh.generations == [u64(1), 2]
	// No repository access or publisher authentication is needed for removal.
	os.write_file(directory + '/catalog.json', 'corrupt catalog')!
	os.write_file(directory + '/trust-history.json', 'unavailable trust')!
	command(binary, root, ['cleanup-apply', fresh.fingerprint])!
	assert !os.exists(directory + '/generations/1') && !os.exists(directory + '/generations/2')
	assert os.exists(directory + '/generations/3/apps/app/bin/app') && os.exists(directory + '/generations/4/apps/app/bin/app')
	assert os.read_file(directory + '/current/state.json')! == state_bytes && os.readlink(directory + '/current')! == 'generations/4'
	assert os.ls(directory + '/objects')!.sorted() == objects
	assert os.read_file(directory + '/generations/.stage-retained/payload')! == 'interrupted recovery'
	assert os.read_file(root + '/home/user/.local/share/vinix-apps/app/data')! == 'personal data'
	assert service.verify()!.generation == 4
	mut empty := pkgprotocol.decode_cleanup_review(command(binary, root, ['cleanup-review'])!)!; defer { empty.close() }
	assert empty.generations.len == 0
	command(binary, root, ['cleanup-apply', empty.fingerprint])!
	for args in [['cleanup-review', 'extra'], ['cleanup-apply'], ['cleanup-apply', 'invalid'], ['cleanup-apply', fresh.fingerprint, 'extra']] {
		mut refused := false; command(binary, root, args) or { refused = true; unsafe { err.free() } }; assert refused
	}
	println('CLEANUP CLI signed install/three upgrades, leased-generation review, stale refusal, offline apply, current/rollback/cache/stage/data retention and empty retry PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
