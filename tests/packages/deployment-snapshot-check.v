// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol
import tools.packages.pkgadmin

#include <sys/wait.h>
#include <unistd.h>
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C.setgroups(usize, voidptr) int
fn C.setgid(u32) int
fn C.setuid(u32) int
fn C._exit(int)

fn ordinary_snapshot(binary string, root string, expected string) ! {
	if os.geteuid() != 0 { return }
	child := C.fork(); if child < 0 { return error('cannot fork ordinary snapshot reader') }
	if child == 0 {
		assert C.setgroups(0, unsafe { nil }) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0
		assert command(binary, root, ['deployment-snapshot'])! == expected
		C._exit(0)
	}
	mut status := 0
	assert C.waitpid(child, unsafe { &status }, 0) == child && status == 0
	println('DEPLOYMENT SNAPSHOT ordinary UID 1000 reads exact root-owned metadata without administrator authorization PASS')
}

fn command(binary string, root string, args []string) !string {
	mut p := os.new_process(binary); p.set_args(['--root', root, ...args]); p.set_redirect_stdio_merged(); p.run()
	text := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	if code != 0 { return error(text) }
	return text
}

fn version(work string, architecture string, value string) ! {
	for id in ['app', 'runtime', 'assets'] {
		os.mkdir_all(work + '/sources/' + id + '/bin')!
		os.write_file(work + '/sources/' + id + '/bin/runner', id + ' ' + value)!
		os.chmod(work + '/sources/' + id + '/bin/runner', 0o755)!
		p := pkgcore.Package{ id: id, name: id, version: if id == 'assets' { '1.0.0' } else { value },
			architecture: if id == 'assets' { 'all' } else { architecture }, license: 'MIT',
			kind: if id == 'assets' { 'data' } else if id == 'runtime' { 'runtime' } else { 'linux' },
			runtime: if id == 'app' { 'runtime' } else { '' }, entrypoint: if id == 'app' { 'bin/runner' } else { '' },
			dependencies: if id == 'app' { [pkgcore.Dependency{ id: 'runtime', minimum: value }] }
				else if id == 'runtime' { [pkgcore.Dependency{ id: 'assets' }] } else { []pkgcore.Dependency{} } }
		// Architecture-independent data remains identical across releases.
		if id == 'assets' { os.write_file(work + '/sources/' + id + '/bin/runner', 'shared data')! }
		os.write_file(work + '/manifest.json', json2.encode(p))!
		pkgcore.pack(work + '/manifest.json', work + '/sources/' + id, work + '/repository')!
	}
}

fn check() ! {
	if os.args.len != 3 { return error('usage: deployment-snapshot-check NEW_WORK PACKAGE_CLI') }
	work := os.args[1]; binary := os.args[2]
	if os.exists(work) { return error('snapshot qualification requires a new workspace') }
	root := work + '/root'; os.mkdir_all(root + '/etc/vinix-packages')!
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	key := pkgcore.keygen(work + '/seed')!
	config := pkgcore.Config{ architecture: architecture, policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 },
		repositories: [pkgcore.Repository{ id: 'trusted', url: 'file://' + work + '/repository', public_key: key }] }
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
	version(work, architecture, '1.0.0')!
	pkgcore.publish(work + '/repository', 'trusted', work + '/seed', 1, time.now().unix() + 3600)!
	command(binary, root, ['update'])!; command(binary, root, ['install', 'app'])!
	service := pkgcore.Service{ root: root }
	state := service.state()!
	first := command(binary, root, ['deployment-snapshot'])!
	mut snapshot := json2.decode[pkgcore.DeploymentLock](first)!; defer { snapshot.close() }
	assert snapshot.packages == ['app'] && snapshot.locked.map(it.id) == ['app', 'assets', 'runtime']
	for item in snapshot.locked { assert item.minimum_sequence == 1 && item.version == '1.0.0' && item.public_key == key }
	mut old_manifests := []string{}
	for id in ['app', 'runtime'] { old_manifests << os.read_file(work + '/repository/manifests/' + id + '-' + architecture + '-1.0.0.json')! }
	version(work, architecture, '2.0.0')!
	for id in ['app', 'runtime'] { os.rm(work + '/repository/manifests/' + id + '-' + architecture + '-1.0.0.json')! }
	pkgcore.publish(work + '/repository', 'trusted', work + '/seed', 2, time.now().unix() + 3600)!
	command(binary, root, ['update'])!
	mut catalog := json2.decode[pkgcore.DeploymentLock](command(binary, root, ['deployment-lock'])!)!; defer { catalog.close() }
	assert catalog.locked.filter(it.id != 'assets').all(it.version == '2.0.0')
	assert command(binary, root, ['deployment-snapshot'])! == first
	assert command(binary, root, ['--offline', 'deployment-snapshot'])! == first
	ordinary_snapshot(binary, root, first)!
	path := work + '/snapshot.json'; os.write_file(path, first)!
	mut refused := false
	command(binary, root, ['deployment-review', path]) or { refused = err.msg().contains('absent from the authenticated catalog') }
	assert refused && service.state()! == state
	directory := pkgcore.state_directory(root)
	config_text := os.read_file(root + '/etc/vinix-packages/config.json')!
	catalog_text := os.read_file(directory + '/catalog.json')!
	history_text := os.read_file(directory + '/trust-history.json')!
	for file in ['catalog.json', 'trust-history.json'] { os.write_file(directory + '/' + file, 'unavailable metadata')! }
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ ...config, repositories: [],
		policy: pkgcore.Policy{ offline: true, allowed: ['unrelated'], permissions: [], reserve_bytes: 0 } }))!
	assert command(binary, root, ['deployment-snapshot'])! == first
	for file in ['catalog.json', 'trust-history.json'] { assert os.read_file(directory + '/' + file)! == 'unavailable metadata' }
	os.write_file(root + '/etc/vinix-packages/config.json', config_text)!
	os.write_file(directory + '/catalog.json', catalog_text)!; os.write_file(directory + '/trust-history.json', history_text)!
	for names in [['missing'], ['app', 'app'], ['../app']] {
		refused = false; command(binary, root, ['deployment-snapshot', ...names]) or { refused = true }; assert refused
	}
	assert service.state()! == state
	// Restore the archived manifests in a newly signed catalog. Snapshot metadata
	// alone cannot supply trust or payloads to a new machine.
	for index, id in ['app', 'runtime'] { os.write_file(work + '/repository/manifests/' + id + '-' + architecture + '-1.0.0.json', old_manifests[index])! }
	pkgcore.publish_release(work + '/repository', 'trusted', work + '/seed', 3, time.now().unix() + 3600, work + '/approved-media')!
	consumer := work + '/consumer'; os.mkdir_all(consumer + '/etc/vinix-packages')!
	os.write_file(consumer + '/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ ...config,
		repositories: [pkgcore.Repository{ ...config.repositories[0], url: 'file://' + work + '/approved-media' }] }))!
	command(binary, consumer, ['update'])!
	mut review := pkgprotocol.decode_review(command(binary, consumer, ['deployment-review', path])!)!; defer { review.close() }
	assert review.rows.all(it.version == '1.0.0') && review.rows.len == 3
	command(binary, consumer, ['deployment-apply', review.fingerprint, path])!
	installed := pkgcore.Service{ root: consumer }.verify()!
	assert installed.packages.all(it.package.version == '1.0.0' && it.sequence == 3 && it.public_key == key)
	assert installed.requested == state.requested && installed.packages.len == state.packages.len
	assert command(binary, consumer, ['deployment-snapshot'])!.contains('"minimum_sequence":3')
	refused = false; pkgadmin.validate_arguments(['deployment-snapshot']) or { refused = true }; assert refused
	assert !pkgadmin.administrative(['deployment-snapshot'])
	println('DEPLOYMENT SNAPSHOT CLI preserves withdrawn installed app/runtime/all-data pins offline with revoked policy, refuses missing roots and unauthenticated apply, and reproduces exact versions from newly authenticated media PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
