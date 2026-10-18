// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tools.packages.signing
import tools.packages.pkgprotocol

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn refresh_request_cycles() int {
	$if refresh_request_baseline ? { return 2 }
	return 64
}

fn retire_refresh_reply(mut catalog Catalog) {
	$if refresh_request_baseline ? { close_authenticated_catalog(catalog) }
	$if !refresh_request_baseline ? { catalog.close(); catalog.close(); assert catalog.packages.len == 0 }
}

fn refresh_request_signed(repository Repository, arch string, id string, sequence u64, expires i64, fault string) !(string, string) {
	private := signing.new_key_from_seed([]u8{len: 32, init: 7})
	p := Package{id: id, version: '1.0.0', architecture: arch, name: 'Editor é🚀', description: 'long description '.repeat(64),
		homepage: 'https://example.invalid/app', license: 'MIT', kind: 'native', entrypoint: 'bin/app', window_protocol: 2,
		arguments: ['--literal', 'argument é🚀 with spaces'], permissions: ['files', 'display'], associations: ['text/plain'],
		dependencies: [Dependency{id: 'assets', minimum: '1.0.0', before: '3.0.0'}],
		files: [Payload{path: 'bin/app', sha256: 'a'.repeat(64), bytes: 4294967296, executable: true}]}
	valid := canonical_index(Index{repository: repository.id, sequence: sequence, expires: expires, packages: [p]})!
	text := match fault {
		'syntax' { valid[..valid.len - 8] }
		'schema' { valid.replace('"entrypoint":"bin/app",', '') }
		else { valid }
	}
	signature := if fault == 'signature' { '00'.repeat(64) } else { signing.sign(private, text.bytes())!.hex() }
	return text, signature
}

fn refresh_request_call(service Service, config Config, directory string, explicit bool) !Catalog {
	if explicit { return refresh(config, directory) }
	return service.refresh()
}

fn refresh_request_scope(arch string, explicit bool, mode string) ! {
	label := arch + (if explicit { ' explicit ' } else { ' service ' }) + mode
	selection := os.getenv('VINIX_REFRESH_CASE')
	defer { unsafe { selection.free(); label.free() } }
	if selection != '' && selection != label { return }
	work := os.temp_dir() + '/vinix-refresh-request-' + os.getpid().str()
	defer { os.rmdir_all(work) or {} }
	root := work + '/root'; path := root + '/etc/vinix-packages/config.json'; directory := state_directory(root)
	os.mkdir_all(root + '/etc/vinix-packages')!
	private := signing.new_key_from_seed([]u8{len: 32, init: 7}); key := private.public_key().hex()
	first := Repository{id: 'first', url: 'file://' + work + '/first', public_key: key}
	second := Repository{id: 'second', url: if mode == 'offline' { 'https://example.invalid/second' } else { 'file://' + work + '/second' }, public_key: key}
	config := Config{architecture: arch, repositories: if mode == 'empty' { []Repository{} } else { [first, second] },
		policy: Policy{offline: mode == 'offline', reserve_bytes: 0}}
	for name in ['first', 'second']! { os.mkdir_all(work + '/' + name)! }
	expires := time.now().unix() + 86400
	one, sig_one := refresh_request_signed(first, arch, 'app', 7, expires, '')!
	two, sig_two := refresh_request_signed(second, arch, 'other', 7, expires, '')!
	cache := json2.encode([Snapshot{repository: first, text: one, signature: sig_one}, Snapshot{repository: second, text: two, signature: sig_two}])
	history := json2.encode(TrustHistory{repositories: [RepositoryFloor{id: first.id, public_key: key, sequence: 7, index_sha256: index_digest(one)},
		RepositoryFloor{id: second.id, public_key: key, sequence: if mode == 'floor' { 8 } else { 7 },
			index_sha256: if mode == 'equivocation' { '0'.repeat(64) } else { index_digest(two) }}]})
	bad_two, bad_sig := refresh_request_signed(second, arch, if mode == 'ambiguous' { 'app' } else { 'other' }, if mode == 'ambiguous' { u64(8) } else { 7 },
		if mode == 'expired' { time.now().unix() - 60 } else { expires }, mode)!
	for name, text in {'first/index.json': one, 'first/index.sig': sig_one, 'second/index.json': bad_two, 'second/index.sig': bad_sig} {
		os.write_file(work + '/' + name, text)!
	}
	if mode == 'missing-index' { os.rm(work + '/second/index.json')! }
	if mode == 'missing-signature' { os.rm(work + '/second/index.sig')! }
	save_configuration(path, config)!
	initial_guard := acquire(directory)!; initial_guard.release()
	service := Service{root: if mode == 'invalid-root' { 'relative' } else { root }, offline: mode == 'offline'}
	configuration := os.read_file(path)!
	mut total := u64(0)
	for pass in 0 .. 2 {
		loops := if pass == 0 { 8 } else { refresh_request_cycles() }
		for _ in 0 .. loops {
			os.write_file(directory + '/catalog.json', if mode == 'bad-cache' { '{broken cache' } else { cache })!
			os.write_file(directory + '/trust-history.json', if mode == 'bad-history' { '{broken history' } else { history })!
			if mode == 'fresh' { os.rm(directory + '/catalog.json')!; os.rm(directory + '/trust-history.json')! }
			if mode == 'migrate' { os.rm(directory + '/trust-history.json')! }
			before_cache := if mode == 'fresh' { '' } else { os.read_file(directory + '/catalog.json')! }
			before_history := if mode in ['fresh', 'migrate']! { '' } else { os.read_file(directory + '/trust-history.json')! }
			mut guard := Lock{fd: -1}
			if mode == 'busy' { guard = acquire(directory)! }
			if mode in ['busy', 'bad-config']! { os.write_file(path, '{broken configuration')! }
			$if track_heap ? { C.vinix_heap_begin() }
			mut refused := false
			mut result := refresh_request_call(service, config, directory, explicit) or {
				refused = true; message := err.msg()
				expected := match mode {
					'signature' { 'signature verification failed' } 'syntax' { 'unterminated' } 'schema' { 'missing required' }
					'expired' { 'expired' } 'floor', 'equivocation' { 'rollback or sequence equivocation' }
					'ambiguous' { 'ambiguous package' } 'missing-index', 'missing-signature' { 'offline repository file unavailable' }
					'offline' { 'offline mode' } 'busy' { 'another package transaction' }
					'bad-config' { 'invalid package configuration' } 'invalid-root' { 'absolute directory' }
					else { 'metadata' }
				}
				assert message.contains(expected), label + ': ' + message
				unsafe { message.free(); err.free() }
				Catalog{}
			}
			if !refused {
				assert result.packages.len == if mode == 'empty' { 0 } else { 2 }, label
				if result.packages.len != 0 {
					p := result.packages[0]
					assert p.repository == 'first' && p.public_key == key && p.sequence == 7
					assert p.package.arguments[1] == 'argument é🚀 with spaces' && p.package.files[0].bytes == 4294967296
				}
				retire_refresh_reply(mut result)
			}
			mut kept := u64(0); $if track_heap ? { kept = C.vinix_heap_end() }
			if pass == 1 { total += kept }
			if guard.fd >= 0 { guard.release() }
			assert refused == (mode !in ['fresh', 'cached', 'migrate', 'empty']!), label
			if refused {
				assert os.read_file(directory + '/catalog.json')! == before_cache
				assert os.read_file(directory + '/trust-history.json')! == before_history
			}
			assert !os.exists(directory + '/refresh')
			save_configuration(path, config)!
			unsafe { before_cache.free(); before_history.free() }
		}
	}
	assert os.read_file(path)! == configuration
	println('REFRESH REQUEST ' + label + ' retained ' + total.str() + ' tracked bytes')
	$if !refresh_request_baseline ? { assert total == 0, label }
}

fn test_complete_refresh_requests_retire_replies_and_success_refusal_scratch() {
	for arch in ['aarch64', 'x86_64']! {
		for explicit in [false, true]! {
			for mode in ['fresh', 'cached', 'migrate', 'empty', 'bad-cache', 'bad-history', 'signature', 'syntax', 'schema',
				'expired', 'floor', 'equivocation', 'ambiguous', 'missing-index', 'missing-signature', 'offline', 'busy']! {
				refresh_request_scope(arch, explicit, mode)!
			}
		}
		for mode in ['bad-config', 'invalid-root']! { refresh_request_scope(arch, false, mode)! }
	}
	$if !refresh_request_baseline ? {
		selection := os.getenv('VINIX_REFRESH_CASE')
		defer { unsafe { selection.free() } }
		if selection == '' { println('REFRESH REQUEST 72 service and explicit cases preserve signed metadata, lock order and owned replies across 64 measured calls PASS') }
		else { println('REFRESH REQUEST selected case PASS') }
	}
}

fn test_refresh_replies_outlive_configuration_and_other_replies() {
	$if !refresh_request_baseline ? {
		work := os.temp_dir() + '/vinix-refresh-lifetime-' + os.getpid().str()
		defer { os.rmdir_all(work) or {} }
		root := work + '/root'; os.mkdir_all(root + '/etc/vinix-packages')!; os.mkdir_all(work + '/repository')!
		private := signing.new_key_from_seed([]u8{len: 32, init: 7}); key := private.public_key().hex()
		repository := Repository{id: 'publisher', url: 'file://' + work + '/repository', public_key: key}
		text, signature := refresh_request_signed(repository, 'aarch64', 'app', 7, time.now().unix() + 86400, '')!
		os.write_file(work + '/repository/index.json', text)!; os.write_file(work + '/repository/index.sig', signature)!
		save_configuration(root + '/etc/vinix-packages/config.json', Config{architecture: 'aarch64', repositories: [repository]})!
		service := Service{root: root}; directory := state_directory(root)
		owned_config := load_config(root)!
		mut first := refresh(owned_config, directory)!; mut second := service.refresh()!
		assert first.packages[0].repository.str != owned_config.repositories[0].id.str
		assert first.packages[0].public_key.str != owned_config.repositories[0].public_key.str
		expected := json2.encode(first); close_decoded_configuration(owned_config)
		first.close(); first.close()
		actual := json2.encode(second); assert actual == expected
		assert second.packages[0].package.dependencies[0].before == '3.0.0' && second.packages[0].package.window_protocol == 2
		second.close(); second.close(); unsafe { expected.free(); actual.free() }
		println('REFRESH REQUEST independently owned publisher identities and nested manifests survive configuration and sibling reply retirement PASS')
	}
}

fn refresh_request_publication_fault(event pkgprotocol.Progress) {
	if event.phase != 'verify' { return }
	directory := os.getenv('VINIX_REFRESH_FAULT_DIRECTORY')
	mode := os.getenv('VINIX_REFRESH_FAULT_MODE')
	path := directory + '/' + mode + '.json'
	defer { unsafe { directory.free(); mode.free(); path.free() } }
	assert C.remove(path.str) == 0 && C.mkdir(path.str, 0o755) == 0
}

fn test_refresh_workspace_retirement_and_publication_failures() {
	$if !refresh_request_baseline ? {
		work := os.temp_dir() + '/vinix-refresh-workspace-' + os.getpid().str()
		defer { os.rmdir_all(work) or {} }
		root := work + '/root'; directory := state_directory(root)
		os.mkdir_all(root + '/etc/vinix-packages')!; os.mkdir_all(work + '/repository')!
		private := signing.new_key_from_seed([]u8{len: 32, init: 7}); key := private.public_key().hex()
		repository := Repository{id: 'publisher', url: 'file://' + work + '/repository', public_key: key}
		config := Config{architecture: 'aarch64', repositories: [repository]}
		text, signature := refresh_request_signed(repository, 'aarch64', 'app', 7, time.now().unix() + 86400, '')!
		os.write_file(work + '/repository/index.json', text)!; os.write_file(work + '/repository/index.sig', signature)!
		save_configuration(root + '/etc/vinix-packages/config.json', config)!
		service := Service{root: root}; mut initial := service.refresh()!; initial.close()
		cache := os.read_file(directory + '/catalog.json')!; history := os.read_file(directory + '/trust-history.json')!
		workspace := directory + '/refresh'
		os.mkdir_all(workspace + '/nested/deep')!; os.write_file(workspace + '/nested/deep/interrupted', 'partial')!
		mut recovered := service.refresh()!; recovered.close(); assert !os.exists(workspace)
		os.mkdir_all(work + '/foreign')!; os.write_file(work + '/foreign/keep', 'foreign data')!
		for mode in ['alias', 'writable']! {
			if mode == 'alias' { os.symlink(work + '/foreign', workspace)! }
			else { os.mkdir(workspace)!; os.chmod(workspace, 0o777)!; os.write_file(workspace + '/keep', 'retained')! }
			mut refused := false
			service.refresh() or {
				message := err.msg(); refused = message.contains('unsafe refresh workspace')
				unsafe { message.free(); err.free() }
			}
			assert refused && os.read_file(work + '/foreign/keep')! == 'foreign data'
			assert os.read_file(directory + '/catalog.json')! == cache && os.read_file(directory + '/trust-history.json')! == history
			if mode == 'alias' { os.rm(workspace)! } else { os.rmdir_all(workspace)! }
		}
		println('REFRESH WORKSPACE captured stale nested work retires; aliases and writable work preserve metadata and foreign files PASS')
		os.setenv('VINIX_REFRESH_FAULT_DIRECTORY', directory, true)
		defer { os.unsetenv('VINIX_REFRESH_FAULT_DIRECTORY'); os.unsetenv('VINIX_REFRESH_FAULT_MODE') }
		for mode in ['trust-history', 'catalog']! {
			os.setenv('VINIX_REFRESH_FAULT_MODE', mode, true)
			failing := Service{root: root, progress: refresh_request_publication_fault}
			mut total := u64(0)
			for pass in 0 .. 2 {
				for _ in 0 .. 64 {
					os.write_file(directory + '/catalog.json', cache)!; os.write_file(directory + '/trust-history.json', history)!
					$if track_heap ? { C.vinix_heap_begin() }
					mut refused := false
					failing.refresh() or {
						refused = true; message := err.msg(); assert message.contains('cannot atomically replace package metadata')
						unsafe { message.free(); err.free() }
					}
					mut kept := u64(0); $if track_heap ? { kept = C.vinix_heap_end() }
					if pass == 1 { total += kept }
					assert refused && !os.exists(workspace)
					assert os.read_file(directory + '/' + (if mode == 'catalog' { 'trust-history' } else { 'catalog' }) + '.json')! == if mode == 'catalog' { history } else { cache }
					os.rmdir(directory + '/' + mode + '.json')!
				}
			}
			assert total == 0
			println('REFRESH PUBLICATION ' + mode + ' 64 refused calls retained ' + total.str() + ' tracked bytes PASS')
		}
	}
}
