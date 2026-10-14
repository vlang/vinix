// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import time
import tools.packages.signing as ed25519
import tools.packages.pkgprotocol

#include <sys/resource.h>
fn C.getrlimit(int, voidptr) int
fn C.setrlimit(int, voidptr) int
fn C.link(&char, &char) int
fn C.mkfifo(&char, u32) int
struct GenerationAdmissionLimit { current u64 maximum u64 }

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

struct GenerationFixture {
	root string
	directory string
	config Config
}

fn generation_fixture() !GenerationFixture {
	root := os.temp_dir() + '/vinix-generation-admission-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(root)!
	public_key, private_key := ed25519.generate_key()!
	repository := root + '/repository'
	os.mkdir_all(repository + '/objects')!
	config := Config{ architecture: 'aarch64', repositories: [Repository{
		id: 'fixture', url: 'file://' + repository, public_key: public_key.hex()
	}], policy: Policy{ reserve_bytes: 0, offline: true } }
	directory := root + '/state'
	for sequence in [u64(1), 2] {
		data := 'generation ' + sequence.str()
		p := Package{ id: 'app', version: sequence.str() + '.0.0', architecture: 'aarch64',
			name: 'Application', description: 'Generation admission fixture', license: 'MIT', kind: 'native',
			entrypoint: 'bin/app', files: [Payload{ path: 'bin/app', sha256: sha256.sum(data.bytes()).hex(), bytes: u64(data.len), executable: true }] }
		os.write_file(repository + '/objects/' + p.files[0].sha256, data)!
		text := canonical_index(Index{ repository: 'fixture', sequence: sequence,
			expires: time.now().unix() + 3600, packages: [p] })!
		os.write_file(repository + '/index.json', text)!
		os.write_file(repository + '/index.sig', ed25519.sign(private_key, text.bytes())!.hex())!
		refresh(config, directory)!
		if sequence == 1 { transact(config, directory, 'install', ['app'], TransactionOptions{})! }
	}
	return GenerationFixture{ root: root, directory: directory, config: config }
}

fn generation_damage_state(phase string) {
	if phase != 'staged' { return }
	os.write_file(os.getenv('VINIX_GENERATION_FIXTURE') + '/generations/.stage-2/state.json', '{}') or { panic(err) }
}

fn test_generation_admission_refuses_late_state_change() {
	f := generation_fixture()!
	defer { os.rmdir_all(f.root) or {} }
	os.setenv('VINIX_GENERATION_FIXTURE', f.directory, true)
	defer { os.unsetenv('VINIX_GENERATION_FIXTURE') }
	mut refused := false
	transact(f.config, f.directory, 'upgrade', [], TransactionOptions{ checkpoint: generation_damage_state }) or { refused = true }
	changed := os.readlink(f.directory + '/current')! != 'generations/1'
	println('GENERATION ADMISSION late-state refused=${refused} current_changed=${changed}')
	assert refused
	assert !changed
}

fn generation_mutate(phase string) {
	if phase != os.getenv('VINIX_GENERATION_PHASE') { return }
	root := os.getenv('VINIX_GENERATION_ROOT')
	if os.exists(root + '/mutated') { return }
	os.write_file(root + '/mutated', phase) or { panic(err) }
	stage := os.getenv('VINIX_GENERATION_TARGET')
	subject := os.getenv('VINIX_GENERATION_SUBJECT')
	kind := os.getenv('VINIX_GENERATION_KIND')
	path := if subject == '' { stage } else { stage + '/' + subject }
	match kind {
		'content' {
			mode := os.lstat(path) or { panic(err) }
			os.chmod(path, 0o600) or { panic(err) }
			os.write_file(path, 'changed bytes') or { panic(err) }
			os.chmod(path, int(mode.mode & 0o7777)) or { panic(err) }
		}
		'mode' { os.chmod(path, if os.is_dir(path) {
			if subject == '' && phase == 'prepared' { 0o755 } else { 0o700 }
		} else { 0o400 }) or { panic(err) } }
		'link' { assert C.link(path.str, (root + '/linked').str) == 0 }
		'extra' { os.write_file(path + '/unrequested', 'extra') or { panic(err) } }
		'extra-dir' { os.mkdir_all(path + '/unrequested/deeper') or { panic(err) } }
		else {
			os.rename(path, root + '/saved') or { panic(err) }
			match kind {
				'alias' { os.symlink(root + '/outside', path) or { panic(err) } }
				'dir-alias' { os.symlink(root + '/outside-dir', path) or { panic(err) } }
				'fifo' { assert C.mkfifo(path.str, 0o600) == 0 }
				'missing' {}
				else { panic('unknown generation mutation: ' + kind) }
			}
		}
	}
}

fn generation_report(event pkgprotocol.Progress) {
	path := os.getenv('VINIX_GENERATION_EVENTS')
	if path == '' { return }
	mut file := os.open_append(path) or { panic(err) }
	file.writeln(json2.encode(event)) or { panic(err) }
	file.close()
	if event.phase == 'activate' { generation_mutate('activate') }
}

fn generation_case(f GenerationFixture, phase string, subject string, kind string) ! {
	generation := next_generation(f.directory)!
	number := generation.str()
	target := f.directory + '/generations/' + if phase in ['published', 'activate'] { number } else { '.stage-' + number }
	for key, value in {'VINIX_GENERATION_PHASE': phase, 'VINIX_GENERATION_SUBJECT': subject,
		'VINIX_GENERATION_KIND': kind, 'VINIX_GENERATION_TARGET': target} { os.setenv(key, value, true) }
	os.write_file(f.root + '/events', '')!
	mut message := ''
	transact(f.config, f.directory, 'upgrade', [], TransactionOptions{
		checkpoint: generation_mutate, progress: generation_report }) or { message = err.msg() }
	assert message != '', phase + '/' + subject + '/' + kind
	assert os.exists(f.root + '/mutated')
	assert os.readlink(f.directory + '/current')! == 'generations/1'
	assert read_state(f.directory, f.config.architecture)!.generation == 1
	assert !os.exists(f.directory + '/generations/.stage-' + number)
	assert os.exists(f.directory + '/generations/' + number) == (phase in ['published', 'activate'])
	if phase in ['published', 'activate'] { assert message.contains('retained for inspection at ' + target) && message.contains('retry builds a new generation') }
	for line in os.read_file(f.root + '/events')!.split_into_lines() { assert pkgprotocol.decode_progress(line)!.phase != 'complete' }
	assert os.read_file(f.root + '/outside')! == 'preserved'
	assert os.lstat(f.root + '/outside')!.mode & 0o777 == 0o600
	assert os.read_file(f.root + '/outside-dir/keep')! == 'preserved'
	assert os.lstat(f.root + '/outside-dir')!.mode & 0o777 == 0o700
	for name in ['mutated', 'linked', 'saved'] {
		path := f.root + '/' + name
		if os.is_dir(path) { os.rmdir_all(path)! } else if os.exists(path) { os.rm(path)! }
	}
}

fn test_generation_complete_admission_preserves_activation_and_retries_offline() {
	f := generation_fixture()!
	defer { os.rmdir_all(f.root) or {} }
	os.write_file(f.root + '/outside', 'preserved')!; os.chmod(f.root + '/outside', 0o600)!
	os.mkdir(f.root + '/outside-dir')!; os.chmod(f.root + '/outside-dir', 0o700)!
	os.write_file(f.root + '/outside-dir/keep', 'preserved')!
	os.setenv('VINIX_GENERATION_ROOT', f.root, true)
	os.setenv('VINIX_GENERATION_EVENTS', f.root + '/events', true)
	defer { for key in ['VINIX_GENERATION_ROOT', 'VINIX_GENERATION_EVENTS', 'VINIX_GENERATION_PHASE',
		'VINIX_GENERATION_TARGET', 'VINIX_GENERATION_SUBJECT', 'VINIX_GENERATION_KIND'] { os.unsetenv(key) } }
	old_text := os.read_file(f.directory + '/generations/1/state.json')!
	catalog := os.read_file(f.directory + '/catalog.json')!
	history := os.read_file(f.directory + '/trust-history.json')!
	mut cases := 0
	for phase in ['prepared', 'staged', 'published'] {
		for subject in ['state.json', 'apps/app/bin/app', 'share/applications/vinix-app.desktop', 'lease'] {
			for kind in ['content', 'missing', 'alias', 'fifo', 'link', 'mode'] {
				generation_case(f, phase, subject, kind)!; cases++
			}
		}
		for subject, kind in {'': 'extra', 'apps/app': 'extra-dir', 'apps': 'dir-alias', 'share/applications': 'missing'} {
			generation_case(f, phase, subject, kind)!; cases++
		}
		generation_case(f, phase, '', 'mode')!; cases++
		if phase != 'prepared' { generation_case(f, phase, 'apps/app/bin', 'mode')!; cases++ }
		assert os.read_file(f.directory + '/generations/1/state.json')! == old_text
		assert os.read_file(f.directory + '/catalog.json')! == catalog
		assert os.read_file(f.directory + '/trust-history.json')! == history
	}
	generation_case(f, 'activate', 'apps/app/bin/app', 'content')!; cases++
	assert cases == 90
	// All authenticated downloads survived refusal; no repository is needed.
	os.rmdir_all(f.root + '/repository')!
	os.unsetenv('VINIX_GENERATION_EVENTS')
	retry := transact(f.config, f.directory, 'upgrade', [], TransactionOptions{})!
	assert retry.previous == 1 && retry.packages[0].package.version == '2.0.0'
	assert rollback(f.config, f.directory)!.generation == 1
	println('GENERATION ADMISSION 90 prepared/staged/published/activate refusals preserve current state, history and outside data; no completion, clean unpublished stages, retained published failures and offline retry PASS')
}

fn generation_publication_race(phase string) {
	if phase == 'staged' { os.mkdir(os.getenv('VINIX_GENERATION_FIXTURE') + '/generations/2') or { panic(err) } }
}

fn test_generation_publication_preserves_a_raced_empty_destination() {
	f := generation_fixture()!; defer { os.rmdir_all(f.root) or {} }
	os.setenv('VINIX_GENERATION_FIXTURE', f.directory, true)
	defer { os.unsetenv('VINIX_GENERATION_FIXTURE') }
	mut message := ''
	transact(f.config, f.directory, 'upgrade', [], TransactionOptions{ checkpoint: generation_publication_race }) or { message = err.msg() }
	assert message.contains('without replacing')
	assert os.ls(f.directory + '/generations/2')!.len == 0
	assert !os.exists(f.directory + '/generations/.stage-2')
	assert read_state(f.directory, 'aarch64')!.generation == 1
	assert transact(f.config, f.directory, 'upgrade', [], TransactionOptions{})!.generation == 3
	println('GENERATION ADMISSION exclusive publication preserves raced destination and retries at a fresh identity PASS')
}

fn test_generation_rollback_admission_binds_captured_metadata_and_checks_after_progress() {
	f := generation_fixture()!; defer { os.rmdir_all(f.root) or {} }
	transact(f.config, f.directory, 'upgrade', [], TransactionOptions{})!
	// Previously accepted whitespace remains readable; compare captured bytes
	// after the progress callback rather than imposing a new serialization.
	path := f.directory + '/generations/1/state.json'
	text := os.read_file(path)! + '\n '
	os.write_file(path, text)!
	os.setenv('VINIX_GENERATION_ROOT', f.root, true)
	os.setenv('VINIX_GENERATION_EVENTS', f.root + '/events', true)
	defer { for key in ['VINIX_GENERATION_ROOT', 'VINIX_GENERATION_EVENTS', 'VINIX_GENERATION_PHASE',
		'VINIX_GENERATION_TARGET', 'VINIX_GENERATION_SUBJECT', 'VINIX_GENERATION_KIND'] { os.unsetenv(key) } }
	for subject, kind in {'state.json': 'content', 'lease': 'content', 'apps/app/bin/app': 'mode', '': 'extra'} {
		for key, value in {'VINIX_GENERATION_PHASE': 'activate', 'VINIX_GENERATION_TARGET': f.directory + '/generations/1',
			'VINIX_GENERATION_SUBJECT': subject, 'VINIX_GENERATION_KIND': kind} { os.setenv(key, value, true) }
		os.write_file(f.root + '/events', '')!
		mut refused := false
		rollback_progress(f.config, f.directory, '', generation_report) or { refused = true }
		assert refused && os.readlink(f.directory + '/current')! == 'generations/2'
		for line in os.read_file(f.root + '/events')!.split_into_lines() { assert pkgprotocol.decode_progress(line)!.phase != 'complete' }
		os.rm(f.root + '/mutated')!
		match subject {
			'state.json' { os.write_file(path, text)! }
			'lease' { os.chmod(f.directory + '/generations/1/lease', 0o600)!; os.write_file(f.directory + '/generations/1/lease', '')!; os.chmod(f.directory + '/generations/1/lease', 0o444)! }
			'apps/app/bin/app' { os.chmod(f.directory + '/generations/1/apps/app/bin/app', 0o755)! }
			else { os.rm(f.directory + '/generations/1/unrequested')! }
		}
	}
	os.unsetenv('VINIX_GENERATION_EVENTS')
	assert rollback(f.config, f.directory)!.generation == 1
	assert os.read_file(path)! == text
	println('GENERATION ADMISSION rollback refuses four late changes without switching current; captured whitespace-compatible metadata retries PASS')
}

fn test_generation_admission_streams_deep_trees_under_a_descriptor_limit() {
	f := generation_fixture()!; defer { os.rmdir_all(f.root) or {} }
	root := f.directory + '/generations/1'
	original := read_state(f.directory, 'aarch64')!
	deep := 'apps/app/' + 'nested/'.repeat(64) + 'app'
	os.mkdir_all(os.dir(root + '/' + deep))!
	os.rename(root + '/apps/app/bin/app', root + '/' + deep)!
	os.rmdir(root + '/apps/app/bin')!
	p := original.packages[0].package
	state := State{ ...original, packages: [Installed{ ...original.packages[0], package: Package{ ...p,
		entrypoint: deep[9..], files: [Payload{ ...p.files[0], path: deep[9..] }] } }] }
	text := encode_generation_state(state)!
	os.write_file(root + '/state.json', text)!
	// Registration does not include the entrypoint; only the stable launcher ID.
	mut limit := GenerationAdmissionLimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, voidptr(&limit)) == 0
	reduced := GenerationAdmissionLimit{ current: 32, maximum: limit.maximum }
	assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&reduced)) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, voidptr(&limit)) == 0 }
	for _ in 0 .. 128 { verify_generation_tree(root, state, text, true)! }
	os.write_file(root + '/' + os.dir(deep) + '/unexpected', 'extra')!
	for _ in 0 .. 128 {
		mut refused := false
		verify_generation_tree(root, state, text, true) or {
			message := err.msg(); refused = message.contains('unexpected generation entry')
			unsafe { message.free(); err.free() }
		}
		assert refused
	}
	os.rm(root + '/' + os.dir(deep) + '/unexpected')!
	verify_generation_tree(root, state, text, true)!
	println('GENERATION ADMISSION 128 valid and refused scans of 64-level trees retire descriptors under a 32-descriptor limit PASS')
}

fn test_generation_admission_releases_checker_scratch() {
	$if track_heap ? {
		f := generation_fixture()!; defer { os.rmdir_all(f.root) or {} }
		root := f.directory + '/generations/1'
		state := read_state(f.directory, 'aarch64')!
		text := os.read_file(root + '/state.json')!
		for kind in ['valid', 'namespace', 'metadata', 'payload', 'registration', 'lease'] {
			path := match kind {
				'namespace' { root + '/extra' }
				'metadata' { root + '/state.json' }
				'payload' { root + '/apps/app/bin/app' }
				'registration' { root + '/share/applications/vinix-app.desktop' }
				else { root + '/lease' }
			}
			saved := if kind in ['valid', 'namespace'] { '' } else { os.read_file(path)! }
			mode := if kind == 'payload' { 0o755 } else if kind in ['lease', 'valid'] { 0o444 } else { 0o644 }
			if kind != 'valid' { os.chmod(path, 0o600) or {}; os.write_file(path, 'changed')!; os.chmod(path, mode)! }
			C.vinix_heap_begin()
			for _ in 0 .. 128 {
				mut refused := false
				verify_generation_tree(root, state, text, true) or {
					message := err.msg(); refused = true
					unsafe { message.free(); err.free() }
				}
				assert refused == (kind != 'valid')
			}
			bytes := C.vinix_heap_end(); count := C.vinix_heap_count()
			assert bytes == 0 && count == 0, kind + ': checker scratch retained'
			if kind == 'namespace' { os.rm(path)! }
			else if kind != 'valid' { os.chmod(path, 0o600)!; os.write_file(path, saved)!; os.chmod(path, mode)! }
		}
		println('GENERATION ADMISSION checker scratch zero retained allocations across 128 valid and five refused-path loops PASS')
	}
}
