// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol
import tools.packages.signing

fn progress(event pkgprotocol.Progress) { println(pkgprotocol.progress_prefix + json2.encode(event)) }

fn command(binary string, args []string) (int, string) {
	mut child := os.new_process(binary); child.set_args(args); child.set_redirect_stdio_merged(); child.run()
	text := child.stdout_slurp(); child.wait(); code := child.code; child.close(); return code, text
}

// Typed encoding avoids making the qualification setup depend on the generic
// publisher encoder's separate lifetime. All metadata declarations are present.
fn publish(repository pkgcore.Repository, path string, packages []pkgcore.Package, sequence u64, private signing.PrivateKey) ! {
	mut buffer := []u8{cap: 2048}; unsafe { buffer.flags |= .noslices }
	defer { unsafe { buffer.free() } }
	json2.encode_append(pkgcore.Index{ repository: repository.id, sequence: sequence,
		expires: time.now().unix() + 3600, packages: packages }, mut buffer)
	buffer << u8(`\n`)
	assert buffer.len < pkgcore.max_metadata
	signature := signing.sign(private, buffer)!; encoded := signature.hex()
	defer { unsafe { signature.free(); encoded.free() } }
	os.write_file_array(path + '/index.json', buffer)!
	os.write_file(path + '/index.sig', encoded)!
}

fn bulky_packages(prefix string) []pkgcore.Package {
	mut packages := []pkgcore.Package{}
	for i in 0 .. 18 {
		packages << pkgcore.Package{ id: prefix + '-' + i.str(), version: '1.0.0', architecture: 'all',
			kind: 'data', name: 'Metadata fixture', license: 'MIT', arguments: []string{len: 64, init: 'a'.repeat(3700)},
			files: [pkgcore.Payload{ path: 'asset', sha256: 'a'.repeat(64) }] }
	}
	return packages
}

fn check() ! {
	if os.args.len > 1 && os.args[1] == '--service' {
		service := pkgcore.Service{ root: os.args[2], progress: progress }
		catalog := service.refresh()!
		assert catalog.packages.len == 1 && catalog.packages[0].package.id == 'seed'
		assert catalog.packages[0].package.files[0].path == 'asset'
		assert service.verify()!.generation == 1
		println('CACHE PREFLIGHT bounded retry returns intact manifest and verifies active generation PASS')
		return
	}
	if os.args.len !in [2, 3] { return error('usage: cache-preflight-check NEW_WORK [CLI]') }
	work := os.abs_path(os.args[1]); if os.exists(work) || os.is_link(work) { return error('qualification directory must be new') }
	binary := if os.args.len == 3 { os.real_path(os.args[2]) } else { '' }
	root := work + '/root'; os.mkdir_all(root + '/etc/vinix-packages')!
	for name in ['first', 'second'] { os.mkdir_all(work + '/' + name + '/objects')! }
	arch := $if arm64 { 'aarch64' } $else { 'x86_64' }
	private := signing.new_key_from_seed([]u8{len: 32, init: 7}) // Public fixture key, never a release publisher.
	first := pkgcore.Repository{ id: 'first', url: 'file://' + work + '/first', public_key: private.public_key().hex() }
	second := pkgcore.Repository{ ...first, id: 'second', url: 'file://' + work + '/second' }
	later := pkgcore.Repository{ ...first, id: 'later', url: 'file://' + work + '/unreachable' }
	config := pkgcore.Config{ architecture: arch, repositories: [first, second], policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }
	configuration := root + '/etc/vinix-packages/config.json'
	os.write_file(configuration, json2.encode(config))!
	seed := pkgcore.Package{ id: 'seed', version: '1.0.0', architecture: 'all', kind: 'data', name: 'Seed', license: 'MIT',
		files: [pkgcore.Payload{ path: 'asset', bytes: 4, sha256: sha256.hexhash('seed') }] }
	os.write_file(work + '/first/objects/' + seed.files[0].sha256, 'seed')!
	publish(first, work + '/first', [seed], 1, private)!
	publish(second, work + '/second', [], 1, private)!
	service := pkgcore.Service{ root: root }
	service.refresh()!; service.transact('install', ['seed'], pkgcore.TransactionOptions{})!
	store := pkgcore.state_directory(root)
	cache := os.read_file(store + '/catalog.json')!; history := os.read_file(store + '/trust-history.json')!
	state := os.read_file(store + '/current/state.json')!; pointer := os.readlink(store + '/current')!
	sentinel := store + '/generations/.stage-sentinel'; os.mkdir(sentinel)!; os.write_file(sentinel + '/keep', 'interrupted work')!
	partial := store + '/objects/' + 'b'.repeat(64) + '.part'; os.write_file(partial, 'partial payload')!
	publish(first, work + '/first', bulky_packages('first-app'), 2, private)!
	publish(second, work + '/second', bulky_packages('second-app'), 2, private)!
	first_signature := os.read_file(work + '/first/index.sig')!
	os.write_file(configuration, json2.encode(pkgcore.Config{ ...config, repositories: [first, second, later] }))!
	for fault in ['signature', 'cache'] {
		os.write_file(work + '/first/index.sig', if fault == 'signature' { '00'.repeat(64) } else { first_signature })!
		code, output := if binary == '' { command(os.executable(), ['--service', root]) }
			else { command(binary, ['--root', root, '--offline', '--progress', 'update']) }
		os.write_file(work + '/' + fault + '.txt', output)!
		assert code != 0 && output.contains(if fault == 'signature' { 'signature verification failed' } else { 'combined repository metadata exceeds cache limit' }), output
		assert !output.contains('Updating trusted repository later') && !output.contains('"repository":"later"'), output
		assert !output.contains('"phase":"complete"') && !os.exists(store + '/refresh')
		assert os.read_file(store + '/catalog.json')! == cache && os.read_file(store + '/trust-history.json')! == history
		assert os.read_file(store + '/current/state.json')! == state && os.readlink(store + '/current')! == pointer
		assert os.read_file(sentinel + '/keep')! == 'interrupted work' && os.read_file(partial)! == 'partial payload'
		assert os.read_file(store + '/current/apps/seed/asset')! == 'seed'
	}
	println('CACHE PREFLIGHT authenticated prefix overflow stops before later repository fetch; signature precedence, active cache/history/generation and recovery data preserved PASS')
	publish(first, work + '/first', [seed], 2, private)!
	publish(second, work + '/second', [], 2, private)!
	os.write_file(configuration, json2.encode(config))!
	code, output := if binary == '' { command(os.executable(), ['--service', root]) }
		else { command(binary, ['--root', root, '--offline', '--progress', 'update']) }
	os.write_file(work + '/retry.txt', output)!
	assert code == 0 && output.contains('"phase":"complete"'), output
	assert !os.exists(store + '/refresh') && os.read_file(store + '/current/state.json')! == state
	assert os.read_file(sentinel + '/keep')! == 'interrupted work' && os.read_file(partial)! == 'partial payload'
	assert os.read_file(store + '/trust-history.json')!.contains('"sequence":2')
	assert service.verify()!.generation == 1
	println('CACHE PREFLIGHT signed service/CLI refresh rejects oversized cache before later acquisition/publication and accepts a bounded retry PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
