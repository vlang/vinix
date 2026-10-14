// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol
import tools.packages.signing

struct Roots { format int = 1 architecture string packages []string }

fn progress(event pkgprotocol.Progress) { println(pkgprotocol.progress_prefix + json2.encode(event)) }

// Isolate service calls in children: the qualification measures refusal ordering,
// not the lifetime of the service's decoded catalogs across repeated requests.
fn service_call(root string, action string, names []string) ! {
	service := pkgcore.Service{ root: root, progress: progress }
	match action {
		'retry' {
			assert names.len == 3
			mut review := service.review('install', [names[0]])!; defer { review.close() }
			result := service.transact('install', [names[0]], pkgcore.TransactionOptions{ expected_review: review.fingerprint })!
			store := pkgcore.state_directory(root)
			assert result.generation == 2 && result.previous == 1 && !os.exists(store + '/generations/.stage-sentinel')
			assert service.verify()!.packages.len == 2
			assert sha256.hexhash(os.read_file(store + '/catalog.json')!) == names[1]
			assert sha256.hexhash(os.read_file(store + '/trust-history.json')!) == names[2]
			println('STATE PREFLIGHT signed service/CLI reviews and transactions reject oversized metadata before cleanup/download/staging; active state, trust and recovery data survive; bounded retry PASS')
			return
		}
		'review' { mut review := service.review('install', names)!; review.close() }
		'install' { service.transact('install', names, pkgcore.TransactionOptions{})! }
		'deployment-review' { mut review := service.review_deployment(names[0])!; review.close() }
		'deploy' { service.deploy(names[0])! }
		else { return error('unknown fixture service action') }
	}
	println('ACCEPTED ' + action)
}

fn command(binary string, args []string) (int, string) {
	mut child := os.new_process(binary); child.set_args(args); child.set_redirect_stdio_merged(); child.run()
	text := child.stdout_slurp(); child.wait(); code := child.code; child.close(); return code, text
}

fn publish(repository pkgcore.Repository, path string, packages []pkgcore.Package, sequence u64, private signing.PrivateKey) ! {
	text := pkgcore.canonical_index(pkgcore.Index{ repository: repository.id, sequence: sequence,
		expires: time.now().unix() + 3600, packages: packages })!
	bytes := text.bytes(); signature := signing.sign(private, bytes)!; encoded := signature.hex()
	defer { unsafe { text.free(); bytes.free(); signature.free(); encoded.free() } }
	os.write_file(path + '/index.json', text)!
	os.write_file(path + '/index.sig', encoded)!
}

fn check() ! {
	if os.args.len > 1 && os.args[1] == '--service' { return service_call(os.args[2], os.args[3], os.args[4..]) }
	if os.args.len !in [2, 3] { return error('usage: state-preflight-check NEW_WORK [CLI | --before]') }
	before := os.args.len == 3 && os.args[2] == '--before'
	binary := if os.args.len == 3 && !before { os.real_path(os.args[2]) } else { '' }
	work := os.abs_path(os.args[1]); if os.exists(work) || os.is_link(work) { return error('qualification directory must be new') }
	root := work + '/root'; os.mkdir_all(root + '/etc/vinix-packages')!; os.mkdir_all(work + '/repository/objects')!
	arch := $if arm64 { 'aarch64' } $else { 'x86_64' }
	private := signing.new_key_from_seed([]u8{len: 32, init: 7}) // Explicit public test key; never a release publisher.
	repository := pkgcore.Repository{ id: 'trusted' + 'r'.repeat(121), public_key: private.public_key().hex(), url: 'file://' + work + '/repository' }
	config := pkgcore.Config{ architecture: arch, repositories: [repository], policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }
	os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
	seed_payload := pkgcore.Payload{ path: 'asset', bytes: 4, sha256: sha256.hexhash('seed') }
	seed := pkgcore.Package{ id: 'seed', name: 'Seed', version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT', files: [seed_payload] }
	os.write_file(work + '/repository/objects/' + seed_payload.sha256, 'seed')!
	publish(repository, work + '/repository', [seed], 1, private)!
	service := pkgcore.Service{ root: root }; service.refresh()!
	initial := service.transact('install', ['seed'], pkgcore.TransactionOptions{})!
	assert initial.generation == 1
	store := pkgcore.state_directory(root)
	mut packages := [seed]; mut names := []string{}
	payload := pkgcore.Payload{ path: 'asset', bytes: 7, sha256: sha256.hexhash('payload') }
	os.write_file(work + '/repository/objects/' + payload.sha256, 'payload')!
	for index in 0 .. 32 {
		id := 'item-' + index.str(); names << id
		packages << pkgcore.Package{ id: id, name: id, version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT',
			arguments: []string{len: 64, init: 'x'.repeat(4080)}, files: [payload] }
	}
	// Calibrate a valid cache just below its limit. The persistent state adds a
	// publisher identity per package, so its resolved encoding crosses that limit.
	base := pkgcore.canonical_index(pkgcore.Index{ repository: repository.id, sequence: 2, expires: time.now().unix() + 3600, packages: packages })!
	mut cache_bytes := []u8{cap: base.len + 16384}; unsafe { cache_bytes.flags |= .noslices }
	json2.encode_append([pkgcore.Snapshot{ repository: repository, text: base, signature: 'a'.repeat(128) }], mut cache_bytes)
	size := cache_bytes.len; unsafe { cache_bytes.free(); base.free() }
	padding := (pkgcore.max_metadata - 256 - size) / 32
	assert padding > 0 && padding <= 4096
	for index in 1 .. packages.len { packages[index] = pkgcore.Package{ ...packages[index], description: 'd'.repeat(padding) } }
	publish(repository, work + '/repository', packages, 2, private)!
	service.refresh()!
	catalog := os.read_file(store + '/catalog.json')!; history := os.read_file(store + '/trust-history.json')!
	state := os.read_file(store + '/current/state.json')!; pointer := os.readlink(store + '/current')!
	assert catalog.len < pkgcore.max_metadata
	mut roots := ['seed', ...names]; roots.sort()
	installed := packages.map(pkgcore.Installed{ package: it, repository: repository.id, public_key: repository.public_key, sequence: 2 })
	oversized := json2.encode(pkgcore.State{ generation: 2, previous: 1, architecture: arch, requested: roots, packages: installed })
	assert oversized.len > pkgcore.max_metadata
	println('STATE PREFLIGHT valid signed cache ${catalog.len} bytes; resolved installed state ${oversized.len} bytes')
	unsafe { oversized.free() }
	deployment := work + '/deployment.json'; os.write_file(deployment, json2.encode(Roots{ architecture: arch, packages: ['seed', ...names] }))!
	sentinel := store + '/generations/.stage-sentinel'; os.mkdir(sentinel)!; os.write_file(sentinel + '/keep', 'interrupted work')!
	for action in ['review', 'install', 'deployment-review', 'deploy'] {
		args := if action in ['review', 'install'] { names } else { [deployment] }
		code, output := if binary == '' { command(os.executable(), ['--service', root, action, ...args]) }
			else { command(binary, ['--root', root, ...if action in ['install', 'deploy'] { ['--progress'] } else { []string{} },
				...if action == 'review' { ['review', 'install'] } else { [action] }, ...args]) }
		os.write_file(work + '/' + action + '.txt', output)!
		if before && action == 'review' { assert code == 0; continue }
		assert code != 0 && output.contains('installed state exceeds metadata limit'), output
		assert os.read_file(store + '/current/state.json')! == state && os.readlink(store + '/current')! == pointer
		assert os.read_file(store + '/catalog.json')! == catalog && os.read_file(store + '/trust-history.json')! == history
		if before {
			assert action == 'install' && !os.exists(sentinel) && os.is_file(store + '/objects/' + payload.sha256)
			assert output.contains('Installing')
			println('STATE PREFLIGHT BEFORE review accepts oversized state; apply retires recovery work and fills cache before rejecting metadata')
			return
		}
		assert os.read_file(sentinel + '/keep')! == 'interrupted work'
		assert !os.exists(store + '/objects/' + payload.sha256) && !os.exists(store + '/objects/' + payload.sha256 + '.part')
		for phase in ['stage', 'download', 'copy', 'activate', 'complete'] { assert !output.contains('"phase":"' + phase + '"') }
		assert !output.contains('Installing') && os.ls(store + '/generations')!.sorted() == ['.stage-sentinel', '1']
	}
	// Release the large setup/inspection heap before the independent bounded
	// retry, as separate CLI requests do. This does not test catalog heap lifetime.
	println('STATE PREFLIGHT all four oversized review/apply refusals preserve state, cache and recovery work PASS')
	flush_stdout()
	os.execvp(os.executable(), ['--service', root, 'retry', names[0], sha256.hexhash(catalog), sha256.hexhash(history)])!
}

fn main() { check() or { eprintln(err); exit(1) } }
