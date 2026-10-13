// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import tools.packages.pkgprotocol

pub fn state_directory(root string) string {
	return root.trim_right('/') + '/var/lib/vinix-packages'
}

pub fn load_config(root string) !Config {
	path := root.trim_right('/') + '/etc/vinix-packages/config.json'
	if root == '' || root == '/' {
		for trusted in ['/etc/vinix-packages', path, state_directory(root)] {
			if !os.exists(trusted) { continue }
			info := os.lstat(trusted)!
			if os.is_link(trusted) || info.uid != 0 || info.mode & 0o022 != 0 {
				return error('package trust/state must be root-owned and not writable by other users: ${trusted}')
			}
		}
	}
	config := json2.decode[Config](read_metadata(path)!)!
	config.validate()!
	if root == '' || root == '/' {
		$if arm64 {
			if config.architecture != 'aarch64' { return error('package configuration targets another architecture') }
		}
		$if amd64 {
			if config.architecture != 'x86_64' { return error('package configuration targets another architecture') }
		}
	}
	return config
}

pub fn read_state(directory string, architecture string) !State {
	current := directory + '/current'
	if !os.is_link(current) {
		if os.exists(current) { return error('package activation pointer is not a symlink') }
		return State{ architecture: architecture }
	}
	target := os.readlink(current)!
	defer { unsafe { target.free() } }
	if !target.starts_with('generations/') || target.len <= 12 {
		return error('invalid package activation pointer')
	}
	generation := generation_number(unsafe { tos(target.str + 12, target.len - 12) })!
	return read_generation_state(directory, architecture, generation)
}

fn validate_state(state State, architecture string) ! {
	if state.format != 1 || state.architecture != architecture || state.generation == 0
		|| state.previous >= state.generation || state.packages.len > 4096 || state.requested.len > 4096
		|| state.requested.any(!identifier(it)) {
		return error('invalid persistent package state')
	}
	mut ids := map[string]int{}
	defer { unsafe { ids.free() } }
	for index, installed in state.packages {
		installed.package.validate()!
		if installed.package.id in ids || installed.package.architecture !in [
			architecture,
			'all',
		]
			|| !identifier(installed.repository) || !digest_valid(installed.public_key) || installed.sequence == 0 {
			return error('invalid installed package provenance')
		}
		ids[installed.package.id] = index
	}
	mut reached := map[string]bool{}
	mut pending := []string{cap: state.packages.len}
	unsafe { pending.flags |= .noslices }
	defer { unsafe { reached.free(); (&array(&pending)).free() } }
	for id in state.requested {
		if id !in ids { return error('persistent requested package is missing: ${id}') }
		if id in reached { return error('duplicate persistent requested package: ${id}') }
		reached[id] = true
		pending << id
	}
	for installed in state.packages {
		for dependency in installed.package.dependencies {
			if dependency.id !in ids || !dependency.accepts(state.packages[ids[dependency.id]].package) {
				return error('persistent dependency closure is inconsistent: ${dependency.id}')
			}
		}
		p := installed.package
		if p.runtime != '' {
			runtime := state.packages[ids[p.runtime]].package
			if runtime.kind != 'runtime' || !runtime.files.any(it.path == p.entrypoint && it.executable) {
				return error('${p.id}: persistent isolated runtime ${p.runtime} does not provide ${p.entrypoint}')
			}
		}
	}
	mut next := 0
	for next < pending.len {
		id := pending[next]
		next++
		for dependency in state.packages[ids[id]].package.dependencies {
			if dependency.id in reached { continue }
			reached[dependency.id] = true
			pending << dependency.id
		}
	}
	if reached.len != state.packages.len { return error('persistent package state contains packages outside the requested dependency closure') }
}

fn next_generation(directory string) !u64 {
	mut maximum := u64(0)
	for name in os.ls(directory + '/generations')! {
		if numeric_generation_name(name) {
			generation := generation_number(name)!
			if generation > maximum { maximum = generation }
		}
	}
	if maximum == ~u64(0) { return error('package generation counter exhausted') }
	return maximum + 1
}

pub fn estimate_space(plan Plan, directory string) !u64 {
	mut needed := u64(4 * 1024 * 1024)
	mut cache := map[string]bool{}
	for installed in plan.packages {
		for file in installed.package.files {
			// A block per file plus payload, directory entries and metadata.
			cost := file.bytes + 8192
			if needed > ~u64(0) - cost { return error('package disk requirement overflow') }
			needed += cost
			if file.sha256 !in cache && !verified_file(directory + '/objects/' + file.sha256, file) {
				if needed > ~u64(0) - cost { return error('package cache requirement overflow') }
				needed += cost
				cache[file.sha256] = true
			}
		}
	}
	return needed
}

fn cached_payload(config Config, installed Installed, payload Payload, directory string) !string {
	return cached_payload_progress(config, installed, payload, directory, no_progress)
}

fn cached_payload_progress(config Config, installed Installed, payload Payload, directory string, report fn (pkgprotocol.Progress)) !string {
	path := directory + '/objects/' + payload.sha256
	if verified_file(path, payload) { return path }
	if os.exists(path) { os.rm(path)! }
	part := path + '.part'
	if os.is_link(part) { os.rm(part)! }
	if os.exists(part) && !ordinary_file(part) {
		return error('${installed.package.id}: partial download must be an ordinary regular file: ${part}')
	}
	// A complete invalid partial cannot use a range request at EOF. Retire it
	// before transport, including oversized data left by an interrupted child.
	if os.is_file(part) && (os.file_size(part) > payload.bytes
		|| (os.file_size(part) == payload.bytes && !verified_file(part, payload))) { os.rm(part)! }
	repositories := config.repositories.filter(it.id == installed.repository && it.public_key == installed.public_key)
	if repositories.len != 1 {
		return error('${installed.package.id}: repository was revoked or its key changed')
	}
	url := repositories[0].url.trim_right('/') + '/objects/' + payload.sha256
	resumed := os.is_file(part) && os.file_size(part) > 0 && os.file_size(part) < payload.bytes
	event := pkgprotocol.Progress{ phase: 'download', package: installed.package.id,
		repository: installed.repository, path: payload.path, total: payload.bytes }
	if !verified_file(part, payload) {
		println('Downloading ${installed.package.id}/${payload.path} (${payload.bytes} bytes)')
		fetch_progress(url, part, payload.bytes, true, config.policy.offline, event, report)!
	}
	report(pkgprotocol.Progress{ phase: 'verify', package: installed.package.id, repository: installed.repository, path: payload.path })
	if !verified_file(part, payload) && resumed {
		os.rm(part)!
		// Restart once with the same authenticated source/size. A failed fresh
		// transfer retains its new partial; a second integrity failure stops.
		println('Restarting ${installed.package.id}/${payload.path}: resumed payload failed verification')
		fetch_progress(url, part, payload.bytes, false, config.policy.offline, event, report)!
		report(pkgprotocol.Progress{ phase: 'verify', package: installed.package.id, repository: installed.repository, path: payload.path })
	}
	if !verified_file(part, payload) {
		os.rm(part)!
		return error('${installed.package.id}: payload checksum or size mismatch; partial data discarded, retry from the trusted repository')
	}
	os.chmod(part, 0o444)!
	sync_file(part)!
	os.rename(part, path)!
	sync_directory(directory + '/objects')!
	return path
}

fn desktop_entry(p Package) string {
	return '[Desktop Entry]\nType=Application\nName=' + p.name + '\nComment=' + p.description +
		'\nExec=/usr/bin/vinix-package run ' + p.id + ' %F\nTerminal=false\nMimeType=' + p.associations.join(';') +
		';\nX-Vinix-Package=' + p.id + '\nX-Vinix-Runtime=' + p.runtime + '\n'
}

fn flush_tree(path string) ! {
	os.chmod(path, 0o755)!
	for name in os.ls(path)! {
		child := path + '/' + name
		if os.is_dir(child) { flush_tree(child)! }
	}
	sync_directory(path)!
}

fn activate(directory string, generation u64) ! {
	temporary := directory + '/activate.new'
	if os.is_link(temporary) || os.exists(temporary) { os.rm(temporary)! }
	os.symlink('generations/' + generation.str(), temporary)!
	replace_path(temporary, directory + '/current')!
	// A failure here means activation occurred but durability is uncertain.
	// Never delete the newly activated generation on this error.
	sync_directory(directory) or { return error('package set activated, but its directory flush failed; check storage and inspect status: ${err}') }
}

pub struct TransactionOptions {
pub:
	// A reviewed operation must still resolve to these exact inputs under the lock.
	expected_review string
	// Used by the crash fixture. Production CLI never accepts this flag.
	stop_before_activation bool
	// In-process qualification hook; no CLI option/environment enables it.
	checkpoint fn (string) = transaction_no_checkpoint
	progress fn (pkgprotocol.Progress) = no_progress
}

fn transaction_no_checkpoint(_ string) {}

pub fn transact(config Config, directory string, operation string, names []string, options TransactionOptions) !State {
	config.validate()!
	guard := acquire(directory)!
	defer { guard.release() }
	return transact_locked(config, directory, operation, names, options)
}

fn transact_locked(config Config, directory string, operation string, names []string, options TransactionOptions) !State {
	current := read_state(directory, config.architecture)!
	plan := operation_plan(config, directory, current, operation, names)!
	if options.expected_review != '' {
		check_review(options.expected_review, review_fingerprint(config, operation, names, current, plan, 0))!
	}
	options.progress(pkgprotocol.Progress{ phase: 'resolve' })
	return activate_plan_locked(config, directory, current, plan, operation, options)
}

// Callers validate the complete plan and any review identity under the writer
// lock before reaching this shared transactional activation boundary.
fn activate_plan_locked(config Config, directory string, current State, plan Plan, operation string, options TransactionOptions) !State {
	if current.requested == plan.requested && current.packages == plan.packages {
		options.progress(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 })
		return current
	}
	// Parse all generation identities before retiring any abandoned work.
	generation := next_generation(directory)!
	// Retire abandoned work only after a supplied review has been accepted.
	for name in os.ls(directory + '/generations')! {
		if name.starts_with('.stage-') { os.rmdir_all(directory + '/generations/' + name)! }
	}
	disk_check(free_bytes(directory)!, estimate_space(plan, directory)!, config.policy.reserve_bytes)!
	stage := directory + '/generations/.stage-' + generation.str()
	owned_directory(stage, 0o700)!
	os.mkdir_all(stage + '/apps')!
	os.mkdir_all(stage + '/share/applications')!
	os.write_file(stage + '/lease', '')!
	os.chmod(stage + '/lease', 0o444)!
	sync_file(stage + '/lease')!
	mut completed := false
	defer {
		if !completed { os.rmdir_all(stage) or {} }
	}
	mut done := 0
	options.progress(pkgprotocol.Progress{ phase: 'stage', total: u64(plan.packages.len) })
	for installed in plan.packages {
		p := installed.package
		println('Installing ${p.name} ${p.version} (${done + 1}/${plan.packages.len}) from ${installed.repository}')
		for file in p.files {
			retained := directory + '/generations/' + current.generation.str() + '/apps/' + p.id + '/' + file.path
			source := if operation == 'remove' && verified_file(retained, file) {
				retained
			} else {
				cached_payload_progress(config, installed, file, directory, options.progress)!
			}
			target := stage + '/apps/' + p.id + '/' + file.path
			os.mkdir_all(os.dir(target))!
			copy_file_progress(source, target, 0, file.bytes,
				pkgprotocol.Progress{ phase: 'copy', package: p.id, repository: installed.repository,
					path: file.path, total: file.bytes }, options.progress)!
			options.progress(pkgprotocol.Progress{ phase: 'verify', package: p.id, repository: installed.repository, path: file.path })
			if !verified_file(target, file) { return error('${p.id}: staged payload verification failed: ${file.path}') }
			os.chmod(target, if file.executable { 0o755 } else { 0o644 })!
			sync_file(target)!
		}
		if p.kind !in ['data', 'runtime'] {
			entry := stage + '/share/applications/vinix-' + p.id + '.desktop'
			os.write_file(entry, desktop_entry(p))!
			sync_file(entry)!
		}
		done++
		options.progress(pkgprotocol.Progress{ phase: 'stage', package: p.id, current: u64(done), total: u64(plan.packages.len) })
	}
	state := State{
		generation:   generation
		previous:     current.generation
		architecture: config.architecture
		requested:    plan.requested
		packages:     plan.packages
	}
	encoded := json2.encode(state)
	if encoded.len > max_metadata { return error('installed state exceeds metadata limit') }
	os.write_file(stage + '/state.json', encoded)!
	os.chmod(stage + '/state.json', 0o644)!
	sync_file(stage + '/state.json')!
	flush_tree(stage)!
	options.checkpoint('staged')
	if options.stop_before_activation {
		// Preserve the unfinished stage as a process killed here would.
		completed = true
		return error('fixture interrupted before activation')
	}
	os.rename(stage, directory + '/generations/' + generation.str())!
	completed = true
	sync_directory(directory + '/generations')!
	options.checkpoint('published')
	options.progress(pkgprotocol.Progress{ phase: 'activate' })
	activate(directory, generation)!
	options.checkpoint('activated')
	println('Activated package generation ${generation}')
	options.progress(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 })
	return state
}

pub fn rollback(config Config, directory string) !State {
	return rollback_reviewed(config, directory, '')
}

fn rollback_target(config Config, directory string, current State) !State {
	if current.previous == 0 { return error('no previous package generation is available') }
	old := read_generation_state(directory, config.architecture, current.previous)!
	for installed in old.packages {
		check_policy(installed.package, config.policy)!
		if !config.repositories.any(it.id == installed.repository && it.public_key == installed.public_key) {
			return error('${installed.package.id}: rollback repository key is no longer trusted')
		}
		for file in installed.package.files {
			if !verified_file(directory + '/generations/' + old.generation.str() + '/apps/' + installed.package.id + '/' + file.path, file) {
				return error('${installed.package.id}: rollback payload verification failed')
			}
		}
	}
	return old
}

pub fn rollback_reviewed(config Config, directory string, expected string) !State {
	config.validate()!
	guard := acquire(directory)!
	defer { guard.release() }
	return rollback_locked(config, directory, expected)
}

fn rollback_locked(config Config, directory string, expected string) !State {
	return rollback_progress(config, directory, expected, no_progress)
}

fn rollback_progress(config Config, directory string, expected string, report fn (pkgprotocol.Progress)) !State {
	current := read_state(directory, config.architecture)!
	old := rollback_target(config, directory, current)!
	if expected != '' {
		check_review(expected, review_fingerprint(config, 'rollback', [], current,
			Plan{ requested: old.requested, packages: old.packages }, old.generation))!
	}
	report(pkgprotocol.Progress{ phase: 'activate' })
	activate(directory, old.generation)!
	println('Rolled back to generation ${old.generation}; application data was retained')
	report(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 })
	return old
}

pub fn collect(config Config, directory string) ! {
	guard := acquire(directory)!
	defer { guard.release() }
	collect_locked(config, directory)!
}

fn collect_locked(config Config, directory string) ! {
	current := read_state(directory, config.architecture)!
	defer { if current.generation != 0 { close_decoded_state(current) } }
	previous := if current.previous == 0 { State{} }
		else { read_generation_state(directory, config.architecture, current.previous)! }
	defer { if previous.generation != 0 { close_decoded_state(previous) } }
	// Retain content needed by both the active and rollback generation.
	mut keep := map[string]bool{}
	defer { unsafe { keep.free() } }
	for state in [current, previous]! {
		for installed in state.packages {
			for file in installed.package.files { keep[file.sha256] = true }
		}
	}
	targets := collection_targets(directory, current)!
	defer { close_collection_targets(targets) }
	for target in targets { remove_collection_target(target)! }
	for name in os.ls(directory + '/objects')! {
		if digest_valid(name) && name !in keep { os.rm(directory + '/objects/' + name)! }
		if name.ends_with('.part') && digest_valid(name.all_before_last('.part')) {
			os.rm(directory + '/objects/' + name)!
		}
	}
	sync_directory(directory + '/generations')!
	sync_directory(directory + '/objects')!
}
