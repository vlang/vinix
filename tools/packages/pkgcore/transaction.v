// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import strings
import tools.packages.pkgprotocol

pub fn state_directory(root string) string {
	return rooted_package_path(root, '/var/lib/vinix-packages')
}

// Borrow the trimmed prefix only while constructing the independent path.
fn rooted_package_path(root string, suffix string) string {
	mut end := root.len
	for end > 0 && root[end - 1] == `/` { end-- }
	return unsafe { tos(root.str, end) } + suffix
}

pub fn load_config(root string) !Config {
	path := rooted_package_path(root, '/etc/vinix-packages/config.json')
	defer { unsafe { path.free() } }
	if root == '' || root == '/' {
		directory := state_directory(root)
		defer { unsafe { directory.free() } }
		for trusted in ['/etc/vinix-packages', path, directory]! {
			mut info := C.stat{}
			if C.lstat(trusted.str, unsafe { &info }) != 0 {
				if C.errno == C.ENOENT { continue }
				return error('cannot inspect package trust/state ownership')
			}
			if u32(info.st_mode) & 0o170000 == 0o120000 || info.st_uid != 0 || info.st_mode & 0o022 != 0 {
				return error('package trust/state must be root-owned and not writable by other users: ${trusted}')
			}
		}
	}
	text := read_metadata(path)!
	defer { unsafe { text.free() } }
	config := decode_configuration(text) or {
		message := err.msg()
		defer { unsafe { message.free(); err.free() } }
		return error('invalid package configuration: ' + message)
	}
	if root == '' || root == '/' {
		$if arm64 {
			if config.architecture != 'aarch64' { close_decoded_configuration(config); return error('package configuration targets another architecture') }
		}
		$if amd64 {
			if config.architecture != 'x86_64' { close_decoded_configuration(config); return error('package configuration targets another architecture') }
		}
	}
	return config
}

pub fn read_state(directory string, architecture string) !State {
	current := directory + '/current'
	defer { unsafe { current.free() } }
	mut info := C.stat{}
	if C.lstat(current.str, unsafe { &info }) != 0 {
		if C.errno == C.ENOENT { return State{ architecture: architecture } }
		return error('cannot inspect package activation pointer')
	}
	if u32(info.st_mode) & 0o170000 != 0o120000 { return error('package activation pointer is not a symlink') }
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
	// The traversal queue borrows IDs from the state; retire only its buffer.
	mut pending := []string{cap: state.packages.len}
	unsafe { pending.flags |= .noslices }
	defer { unsafe { reached.free(); (&array(&pending)).free() } }
	for id in state.requested {
		if id !in ids { return error('persistent requested package is missing: ${id}') }
		if id in reached { return error('duplicate persistent requested package: ${id}') }
		reached[id] = true
		pointer := unsafe { &id }
		unsafe { pending.push_many(pointer, 1) }
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
			next_id := dependency.id
			pointer := unsafe { &next_id }
			unsafe { pending.push_many(pointer, 1) }
		}
	}
	if reached.len != state.packages.len { return error('persistent package state contains packages outside the requested dependency closure') }
}

fn next_generation(directory string) !u64 {
	path := directory + '/generations'
	defer { unsafe { path.free() } }
	names := os.ls(path)!
	defer { unsafe { for name in names { name.free() }; (&array(&names)).free() } }
	mut maximum := u64(0)
	for name in names {
		if numeric_generation_name(name) {
			generation := generation_number(name)!
			if generation > maximum { maximum = generation }
		}
	}
	if maximum == ~u64(0) { return error('package generation counter exhausted') }
	return maximum + 1
}

pub fn estimate_space(plan Plan, directory string) !u64 {
	return estimate_space_from(plan, directory, '')
}

fn estimate_transaction_space(plan Plan, directory string, current State, operation string) !u64 {
	if operation !in ['remove', 'rollback'] || current.generation == 0 { return estimate_space(plan, directory) }
	number := if operation == 'rollback' { current.previous.str() } else { current.generation.str() }
	retained := directory + '/generations/' + number + '/apps'
	defer { unsafe { number.free(); retained.free() } }
	return estimate_space_from(plan, directory, retained)
}

// Removal copies verified active files before consulting the object cache.
// Rollback copies the admitted previous generation without consulting the cache.
fn estimate_space_from(plan Plan, directory string, retained string) !u64 {
	mut needed := u64(4 * 1024 * 1024)
	mut cache := map[string]bool{}
	defer { unsafe { cache.free() } }
	for installed in plan.packages {
		for file in installed.package.files {
			// A block per file plus payload, directory entries and metadata.
			if file.bytes > ~u64(0) - 8192 { return error('package disk requirement overflow') }
			cost := file.bytes + 8192
			if needed > ~u64(0) - cost { return error('package disk requirement overflow') }
			needed += cost
			if retained != '' {
				path := retained + '/' + installed.package.id + '/' + file.path
				valid := verified_file(path, file)
				unsafe { path.free() }
				if valid { continue }
			}
			if file.sha256 in cache { continue }
			path := directory + '/objects/' + file.sha256
			valid := verified_file(path, file)
			unsafe { path.free() }
			if !valid {
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
	mut accepted := false
	defer { if !accepted { unsafe { path.free() } } }
	if verified_file(path, payload) { accepted = true; return path }
	if os.exists(path) { os.rm(path)! }
	part := path + '.part'
	defer { unsafe { part.free() } }
	mut info := C.stat{}
	if C.lstat(part.str, unsafe { &info }) == 0 {
		if info.st_mode & 0o170000 == 0o120000 { os.rm(part)! }
		else { validate_download_partial(part)! }
	} else if C.errno != C.ENOENT { return error('cannot inspect partial package payload') }
	// A complete invalid partial cannot use a range request at EOF. Retire it
	// before transport, including oversized data left by an interrupted child.
	if info.st_mode & 0o170000 == 0o100000 && (u64(info.st_size) > payload.bytes
		|| (u64(info.st_size) == payload.bytes && !verified_file(part, payload))) { os.rm(part)! }
	repositories := config.repositories.filter(it.id == installed.repository && it.public_key == installed.public_key)
	defer { unsafe { (&array(&repositories)).free() } }
	if repositories.len != 1 {
		return error('${installed.package.id}: repository was revoked or its key changed')
	}
	prefix := repositories[0].url.trim_right('/')
	url := prefix + '/objects/' + payload.sha256
	defer { unsafe { prefix.free(); url.free() } }
	mut resumed := false
	event := pkgprotocol.Progress{ phase: 'download', package: installed.package.id,
		repository: installed.repository, path: payload.path, total: payload.bytes }
	if !verified_file(part, payload) {
		number := payload.bytes.str()
		message := 'Downloading ${installed.package.id}/${payload.path} (${number} bytes)'
		defer { unsafe { number.free(); message.free() } }
		println(message)
		resumed = fetch_progress(url, part, payload.bytes, true, config.policy.offline, event, report)!
	}
	report(pkgprotocol.Progress{ phase: 'verify', package: installed.package.id, repository: installed.repository, path: payload.path })
	if !verified_file(part, payload) && resumed {
		os.rm(part)!
		// Restart once with the same authenticated source/size. A failed fresh
		// transfer retains its new partial; a second integrity failure stops.
		message := 'Restarting ${installed.package.id}/${payload.path}: resumed payload failed verification'
		defer { unsafe { message.free() } }
		println(message)
		fetch_progress(url, part, payload.bytes, false, config.policy.offline, event, report)!
		report(pkgprotocol.Progress{ phase: 'verify', package: installed.package.id, repository: installed.repository, path: payload.path })
	}
	if !verified_file(part, payload) {
		os.rm(part)!
		return error('${installed.package.id}: payload checksum or size mismatch; partial data discarded, retry from the trusted repository')
	}
	promote_cached_payload(directory, payload)!
	accepted = true
	return path
}

// XDG string values interpret backslash escapes; encode boundary spaces as \s.
// Encode directly into the existing builder; the signed metadata stays intact.
fn desktop_entry_value(mut text strings.Builder, value string) {
	mut first := 0
	for first < value.len && value[first] == ` ` { first++ }
	mut end := value.len
	for end > first && value[end - 1] == ` ` { end-- }
	for index, byte in value {
		if byte == `\\` { text.write_string('\\\\') }
		else if byte == ` ` && (index < first || index >= end) { text.write_string('\\s') }
		else { text.write_u8(byte) }
	}
}

fn desktop_entry(p Package) string {
	mut capacity := 256 + 2 * p.name.len + 2 * p.description.len + 2 * p.id.len + p.runtime.len + p.associations.len
	for mime in p.associations { capacity += mime.len }
	mut text := &strings.Builder(strings.new_builder(capacity))
	// Builder is an array alias: retire both its buffer and owned descriptor.
	defer { unsafe { text.free(); free(voidptr(text)) } }
	text.write_string('[Desktop Entry]\nType=Application\nName='); desktop_entry_value(mut text, p.name)
	text.write_string('\nComment='); desktop_entry_value(mut text, p.description)
	text.write_string('\nExec=/usr/bin/vinix-package run '); text.write_string(p.id)
	text.write_string(' %F\nTerminal=false\nMimeType=')
	for i, mime in p.associations { if i > 0 { text.write_u8(`;`) }; text.write_string(mime) }
	text.write_string(';\nX-Vinix-Package='); text.write_string(p.id)
	text.write_string('\nX-Vinix-Runtime='); text.write_string(p.runtime); text.write_u8(`\n`)
	return text.str()
}

// Reuse the owned descriptor enumerator without the prepared-root payload
// limit. os.ls allocates a result buffer before opening, leaking it on refusal
// in manual-free programs. The caller owns every returned name and the buffer.
fn publisher_flush_names(path string) ![]string {
	fd := C.open(path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
	if fd < 0 { return error('cannot enumerate package directory: ' + path) }
	defer { C.close(fd) }
	return import_names_limit(fd, 0x7fffffff)
}

fn flush_tree(path string) ! {
	os.chmod(path, 0o755)!
	names := publisher_flush_names(path)!
	defer { unsafe { names.free() } }
	for name in names {
		child := path + '/' + name
		defer { unsafe { child.free() } }
		mut info := C.stat{}
		// Preserve stat's directory-following behavior without an allocated
		// os.Stat output record or an unretired error for a missing child.
		if C.fstatat(C.AT_FDCWD, child.str, unsafe { &info }, 0) == 0 && info.st_mode & 0o170000 == 0o040000 { flush_tree(child)! }
	}
	sync_directory(path)!
}

fn activate(directory string, generation u64) ! {
	temporary := directory + '/activate.new'
	current := directory + '/current'
	number := generation.str()
	target := 'generations/' + number
	defer { unsafe { temporary.free(); current.free(); number.free(); target.free() } }
	mut info := C.stat{}
	if C.lstat(temporary.str, unsafe { &info }) == 0 { os.rm(temporary)! }
	else if C.errno != C.ENOENT { return error('cannot inspect temporary package activation pointer') }
	os.symlink(target, temporary)!
	replace_path(temporary, current)!
	// A failure here means activation occurred but durability is uncertain.
	// Never delete the newly activated generation on this error.
	sync_directory(directory) or {
		message := err.msg()
		diagnostic := 'package set activated, but its directory flush failed; check storage and inspect status: ' + message
		unsafe { message.free(); err.free() }
		return error(diagnostic)
	}
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
	defer { if current.generation != 0 { close_decoded_state(current) } }
	mut prepared := prepare_operation_plan(config, directory, current, operation, names)!
	defer { prepared.close() }
	plan := prepared.plan
	repairs := transaction_repairs(directory, current, plan, operation)
	defer { close_transaction_repairs(repairs) }
	if options.expected_review != '' {
		fingerprint := review_fingerprint(config, operation, names, current, plan, 0, repairs)
		defer { unsafe { fingerprint.free() } }
		check_review(options.expected_review, fingerprint)!
	}
	options.progress(pkgprotocol.Progress{ phase: 'resolve' })
	state := activate_repair_plan_locked(config, directory, current, plan, operation, repairs, options)!
	return owned_transaction_state(state)
}

// Callers validate the complete plan and any review identity under the writer
// lock before reaching this shared transactional activation boundary.
fn activate_plan_locked(config Config, directory string, current State, plan Plan, operation string, options TransactionOptions) !State {
	repairs := transaction_repairs(directory, current, plan, operation)
	defer { close_transaction_repairs(repairs) }
	return activate_repair_plan_locked(config, directory, current, plan, operation, repairs, options)
}

fn activate_repair_plan_locked(config Config, directory string, current State, plan Plan, operation string, repairs []string, options TransactionOptions) !State {
	return activate_repair_plan_from_locked(config, directory, current, plan, operation, repairs, RollbackSource{}, options)
}

// A rollback source is borrowed for the duration of a transaction. Its exact
// metadata and complete tree are checked before staging and after callbacks at
// the activation boundary. Never rewrite a retained immutable generation.
struct RollbackSource {
	state State
	text string
}

fn verify_rollback_source(directory string, source RollbackSource) ! {
	number := source.state.generation.str()
	root := directory + '/generations/' + number
	defer { unsafe { number.free(); root.free() } }
	verify_generation_tree(root, source.state, source.text, true)!
}

fn verify_transaction_activation(directory string, published string, state State, encoded string, source RollbackSource) ! {
	if source.state.generation != 0 { verify_rollback_source(directory, source)! }
	verify_generation_tree(published, state, encoded, true)!
}

fn activate_repair_plan_from_locked(config Config, directory string, current State, plan Plan, operation string, repairs []string, source_generation RollbackSource, options TransactionOptions) !State {
	observed := transaction_repairs(directory, current, plan, operation)
	defer { close_transaction_repairs(observed) }
	if observed != repairs { return error('package review is stale: installed payload repair set changed; review again') }
	if operation != 'rollback' && current.requested == plan.requested && current.packages == plan.packages && repairs.len == 0 {
		options.progress(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 })
		return current
	}
	// Parse all generation identities before retiring any abandoned work.
	generation := next_generation(directory)!
	state := State{
		generation: generation
		previous: current.generation
		architecture: config.architecture
		requested: plan.requested
		packages: plan.packages
	}
	encoded := encode_generation_state(state)!
	defer { unsafe { encoded.free() } }
	// Check space before retiring abandoned work, and only after review admission.
	disk_check(free_bytes(directory)!, estimate_transaction_space(plan, directory, current, operation)!, config.policy.reserve_bytes)!
	recover_generation_stages(directory)!
	number := generation.str()
	stage_name := '.stage-' + number
	stage := directory + '/generations/' + stage_name
	defer { unsafe { number.free(); stage_name.free(); stage.free() } }
	owned_directory(stage, 0o700)!
	parent := recovery_parent(directory)!
	defer { C.close(parent) }
	stage_target := capture_stage(parent, stage_name)!
	defer { unsafe { stage_target.name.free() } }
	mut completed := false
	defer {
		if !completed {
			retire_stage(parent, stage_target) or {
				message := err.msg()
				diagnostic := 'Unpublished package stage retained for inspection at ${stage}: ${message}'
				eprintln(diagnostic)
				unsafe { diagnostic.free(); message.free(); err.free() }
			}
		}
	}
	apps := stage + '/apps'
	applications := stage + '/share/applications'
	lease := stage + '/lease'
	metadata := stage + '/state.json'
	defer { unsafe { apps.free(); applications.free(); lease.free(); metadata.free() } }
	make_package_directories(apps, 0o777)!
	make_package_directories(applications, 0o777)!
	os.write_file(lease, '')!
	os.chmod(lease, 0o444)!
	sync_file(lease)!
	mut done := 0
	count := plan.packages.len.str()
	defer { unsafe { count.free() } }
	options.progress(pkgprotocol.Progress{ phase: 'stage', total: u64(plan.packages.len) })
	for installed in plan.packages {
		p := installed.package
		position := (done + 1).str()
		message := 'Installing ${p.name} ${p.version} (${position}/${count}) from ${installed.repository}'
		defer { unsafe { position.free(); message.free() } }
		println(message)
		for file in p.files {
			retained_number := if operation == 'rollback' { source_generation.state.generation.str() } else { current.generation.str() }
			retained := directory + '/generations/' + retained_number + '/apps/' + p.id + '/' + file.path
			defer { unsafe { retained_number.free(); retained.free() } }
			mut acquired := false
			source := if operation == 'rollback' {
				if !verified_installed_file(retained, file) { return error('${p.id}: rollback source changed; review rollback again') }
				retained
			} else if operation == 'remove' && verified_file(retained, file) {
				retained
			} else {
				acquired = true
				cached_payload_progress(config, installed, file, directory, options.progress)!
			}
			defer { if acquired { unsafe { source.free() } } }
			target := stage + '/apps/' + p.id + '/' + file.path
			target_parent := os.dir(target)
			defer { unsafe { target.free(); target_parent.free() } }
			make_package_directories(target_parent, 0o777)!
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
			text := desktop_entry(p)
			defer { unsafe { entry.free(); text.free() } }
			os.write_file(entry, text)!
			os.chmod(entry, 0o644)!
			sync_file(entry)!
		}
		done++
		options.progress(pkgprotocol.Progress{ phase: 'stage', package: p.id, current: u64(done), total: u64(plan.packages.len) })
	}
	os.write_file(metadata, encoded)!
	os.chmod(metadata, 0o644)!
	sync_file(metadata)!
	options.checkpoint('prepared')
	verify_generation_tree(stage, state, encoded, false)!
	flush_tree(stage)!
	options.checkpoint('staged')
	verify_generation_tree(stage, state, encoded, true)!
	if options.stop_before_activation {
		// Preserve the unfinished stage as a process killed here would.
		completed = true
		return error('fixture interrupted before activation')
	}
	published := directory + '/generations/' + number
	defer { unsafe { published.free() } }
	publish_new_directory(stage, published, 'package generation')!
	completed = true
	generations := directory + '/generations'
	defer { unsafe { generations.free() } }
	sync_directory(generations)!
	options.checkpoint('published')
	options.progress(pkgprotocol.Progress{ phase: 'activate' })
	verify_transaction_activation(directory, published, state, encoded, source_generation) or {
		message := err.msg()
		diagnostic := 'package generation was not activated; retained for inspection at ${published}: ${message}; retry builds a new generation'
		unsafe { message.free(); err.free() }
		return error(diagnostic)
	}
	activate(directory, generation)!
	options.checkpoint('activated')
	message := 'Activated package generation ' + number
	defer { unsafe { message.free() } }
	println(message)
	options.progress(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 })
	return state
}

pub fn rollback(config Config, directory string) !State {
	return rollback_reviewed(config, directory, '')
}

fn rollback_target(config Config, directory string, current State) !State {
	if current.previous == 0 { return error('no previous package generation is available') }
	old := read_generation_state(directory, config.architecture, current.previous)!
	mut accepted := false
	defer { if !accepted { close_decoded_state(old) } }
	number := old.generation.str()
	root := directory + '/generations/' + number
	defer { unsafe { number.free(); root.free() } }
	require_publisher_keys(old.packages)!
	for installed in old.packages {
		check_policy(installed.package, config.policy)!
		if !config.repositories.any(it.id == installed.repository && it.public_key == installed.public_key) {
			return error('${installed.package.id}: rollback repository key is no longer trusted')
		}
		for file in installed.package.files {
			path := '${root}/apps/${installed.package.id}/${file.path}'
			valid := verified_installed_file(path, file)
			unsafe { path.free() }
			if !valid {
				return error('${installed.package.id}: rollback payload verification failed')
			}
		}
		if !verified_registration(root, installed.package) {
			return error('${installed.package.id}: rollback application registration verification failed')
		}
	}
	accepted = true
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
	return rollback_transaction_locked(config, directory, TransactionOptions{ expected_review: expected, progress: report })
}

fn rollback_transaction_locked(config Config, directory string, options TransactionOptions) !State {
	current := read_state(directory, config.architecture)!
	defer { if current.generation != 0 { close_decoded_state(current) } }
	old := rollback_target(config, directory, current)!
	defer { close_decoded_state(old) }
	plan := Plan{ requested: old.requested, packages: old.packages }
	if options.expected_review != '' {
		fingerprint := review_fingerprint(config, 'rollback', [], current, plan, old.generation, [])
		defer { unsafe { fingerprint.free() } }
		check_review(options.expected_review, fingerprint)!
	}
	number := old.generation.str()
	root := directory + '/generations/' + number
	metadata := root + '/state.json'
	defer { unsafe { number.free(); root.free(); metadata.free() } }
	text := read_metadata(metadata)!
	defer { unsafe { text.free() } }
	captured := decode_persistent_state(text, config.architecture)!
	defer { close_decoded_state(captured) }
	if captured != old { return error('rollback generation metadata changed; inspect the retained generation and review again') }
	source := RollbackSource{ state: old, text: text }
	verify_rollback_source(directory, source)!
	options.progress(pkgprotocol.Progress{ phase: 'resolve' })
	state := activate_repair_plan_from_locked(config, directory, current, plan, 'rollback', [], source, options)!
	activated_number := state.generation.str()
	message := 'Restored packages from generation ${number} in generation ${activated_number}; application data was retained'
	defer { unsafe { activated_number.free(); message.free() } }
	println(message)
	return owned_transaction_state(state)
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
	recover_generation_stages(directory)!
	for target in targets { remove_collection_target(target)! }
	objects := directory + '/objects'
	defer { unsafe { objects.free() } }
	names := publisher_flush_names(objects)!
	defer { unsafe { names.free() } }
	for name in names {
		mut partial := false
		if name.len == 69 && name.ends_with('.part') {
			digest := name[..64]
			partial = digest_valid(digest)
			unsafe { digest.free() }
		}
		if (digest_valid(name) && name !in keep) || partial {
			path := objects + '/' + name
			defer { unsafe { path.free() } }
			// os.rm's wrapped diagnostic retains an intermediate concatenation
			// under manualfree. Keep its remove(3) semantics and POSIX code while
			// giving every temporary string an explicit lifetime.
			if C.remove(path.str) != 0 {
				code := C.errno
				prefix := 'Failed to remove "${path}": '
				message := prefix + os.posix_get_error_msg(code)
				defer { unsafe { prefix.free() } }
				// The returned error owns message; its caller retires it.
				return error_with_code(message, code)
			}
		}
	}
	generations := directory + '/generations'
	defer { unsafe { generations.free() } }
	sync_directory(generations)!
	sync_directory(objects)!
}
