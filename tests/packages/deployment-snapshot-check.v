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
fn C.chown(&char, int, int) int

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
	return command_status(binary, root, args, 0)
}

fn command_status(binary string, root string, args []string, expected int) !string {
	mut p := os.new_process(binary); p.set_args(['--root', root, ...args]); p.set_redirect_stdio_merged(); p.run()
	text := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	if code != expected { return error('expected exit ${expected}, received ${code}: ' + text) }
	return text
}

fn audit_command(binary string, root string, path string, matches bool) !string {
	text := command_status(binary, root, ['--offline', '--json', 'deployment-audit', path], if matches { 0 } else { 3 })!
	mut report := pkgprotocol.decode_deployment_audit(text)!; defer { report.close() }
	assert report.matches == matches
	return text
}

fn ordinary_audit(binary string, root string, path string, expected string) ! {
	if os.geteuid() != 0 { return }
	child := C.fork(); if child < 0 { return error('cannot fork ordinary deployment auditor') }
	if child == 0 {
		assert C.setgroups(0, unsafe { nil }) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0
		assert audit_command(binary, root, path, true)! == expected
		C._exit(0)
	}
	mut status := 0
	assert C.waitpid(child, unsafe { &status }, 0) == child && status == 0
	println('DEPLOYMENT AUDIT ordinary UID 1000 reads exact root-owned comparison without administrator authorization PASS')
}

fn ordinary_save(binary string, root string, directory string, expected string) ! {
	if os.geteuid() != 0 { return }
	os.mkdir(directory, mode: 0o700)!; assert C.chown(directory.str, 1000, 1000) == 0
	child := C.fork(); if child < 0 { return error('cannot fork ordinary snapshot saver') }
	if child == 0 {
		assert C.setgroups(0, unsafe { nil }) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0
		os.chdir(directory)!
		mut saved := pkgprotocol.decode_deployment_saved(command(binary, root, ['--json', 'deployment-snapshot-save', 'saved.json'])!)!; defer { saved.close() }
		assert saved.destination == 'saved.json' && saved.generation == 1 && saved.roots == 1 && saved.packages == 3
		assert os.read_file('saved.json')! == expected
		assert command_status(binary, root, ['deployment-snapshot-save', 'saved.json'], 1)!.contains('already exists')
		assert os.read_file('saved.json')! == expected && os.ls('.')! == ['saved.json']
		C._exit(0)
	}
	mut status := 0; assert C.waitpid(child, unsafe { &status }, 0) == child && status == 0
	println('DEPLOYMENT SAVE ordinary UID 1000 saves exact root-owned installed metadata into an owned relative destination without administrator authorization PASS')
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
	path := work + '/snapshot é; $literal.json'
	mut saved := pkgprotocol.decode_deployment_saved(command(binary, root, ['--json', 'deployment-snapshot-save', path])!)!; defer { saved.close() }
	assert saved.generation == 1 && saved.roots == 1 && saved.packages == 3 && saved.destination == path
	assert os.read_file(path)! == first
	ordinary_save(binary, root, work + '/ordinary-export', first)!
	assert command_status(binary, root, ['deployment-snapshot-save', path], 1)!.contains('already exists')
	assert os.read_file(path)! == first
	audit := audit_command(binary, root, path, true)!
	ordinary_audit(binary, root, path, audit)!
	newer_path := work + '/newer-lock.json'; os.write_file(newer_path, json2.encode(catalog))!
	mut drift := pkgprotocol.decode_deployment_audit(audit_command(binary, root, newer_path, false)!)!; defer { drift.close() }
	assert drift.rows.filter(it.status == 'changed').map(it.id) == ['app', 'assets', 'runtime']
	assert drift.rows.filter(it.id == 'app')[0].differences == ['metadata_sha256', 'sequence', 'version']
	assert drift.rows.filter(it.id == 'assets')[0].differences == ['sequence']
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
	assert audit_command(binary, root, path, true)! == audit
	command(binary, root, ['--offline', 'deployment-snapshot-save', work + '/revoked.json'])!
	assert os.read_file(work + '/revoked.json')! == first
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
	mut absent := pkgprotocol.decode_deployment_audit(audit_command(binary, consumer, path, false)!)!; defer { absent.close() }
	assert absent.generation == 0 && absent.rows.len == 3 && absent.rows.all(it.status == 'missing')
	assert !os.exists(consumer + '/var')
	command(binary, consumer, ['update'])!
	mut review := pkgprotocol.decode_review(command(binary, consumer, ['deployment-review', path])!)!; defer { review.close() }
	assert review.rows.all(it.version == '1.0.0') && review.rows.len == 3
	command(binary, consumer, ['deployment-apply', review.fingerprint, path])!
	installed := pkgcore.Service{ root: consumer }.verify()!
	assert installed.packages.all(it.package.version == '1.0.0' && it.sequence == 3 && it.public_key == key)
	assert installed.requested == state.requested && installed.packages.len == state.packages.len
	assert command(binary, consumer, ['deployment-snapshot'])!.contains('"minimum_sequence":3')
	mut restored := pkgprotocol.decode_deployment_audit(audit_command(binary, consumer, path, true)!)!; defer { restored.close() }
	assert restored.matches && restored.rows.len == 3 && restored.rows.all(it.status == 'match')
	// An exact subset is not the desired complete organization application set.
	command(binary, consumer, ['remove', 'app'])!
	mut removed := pkgprotocol.decode_deployment_audit(audit_command(binary, consumer, path, false)!)!; defer { removed.close() }
	assert removed.rows.all(it.status == 'missing')
	refused = false; pkgadmin.validate_arguments(['deployment-snapshot']) or { refused = true }; assert refused
	assert !pkgadmin.administrative(['deployment-snapshot'])
	refused = false; pkgadmin.validate_arguments(['deployment-audit', path]) or { refused = true }; assert refused
	assert !pkgadmin.administrative(['deployment-audit', path])
	refused = false; pkgadmin.validate_arguments(['deployment-snapshot-save', path]) or { refused = true }; assert refused
	assert !pkgadmin.administrative(['deployment-snapshot-save', path])
	assert command_status(binary, root, ['deployment-snapshot-save'], 1)!.contains('requires a new destination')
	assert command_status(binary, root, ['--progress', 'deployment-snapshot-save', path], 1)!.contains('--progress supports')
	assert command_status(binary, root, ['deployment-snapshot-save', work + '/missing-root.json', 'missing'], 1)!.contains('is not installed')
	assert !os.exists(work + '/missing-root.json')
	assert command(binary, root, ['deployment-audit', path])!.contains('Metadata comparison only;')
	assert command_status(binary, root, ['deployment-audit'], 1)!.contains('requires one exact deployment lock')
	assert command_status(binary, root, ['--progress', 'deployment-audit', path], 1)!.contains('--progress supports')
	bad_path := work + '/roots-only.json'
	os.write_file(bad_path, '{"format":1,"architecture":"' + architecture + '","packages":["app"]}')!
	assert command_status(binary, root, ['--json', 'deployment-audit', bad_path], 1)!.contains('requires an exact format-2 lock')
	println('DEPLOYMENT SAVE CLI new-file durable export, exact receipt and withdrawn/offline/revoked metadata, existing-file preservation and authenticated reproduction PASS')
	println('DEPLOYMENT AUDIT CLI exact offline metadata and sequence-floor matches, missing/changed drift exit 3, no fresh-state initialization and authenticated reproduction PASS')
	println('DEPLOYMENT SNAPSHOT CLI preserves withdrawn installed app/runtime/all-data pins offline with revoked policy, refuses missing roots and unauthenticated apply, and reproduces exact versions from newly authenticated media PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
