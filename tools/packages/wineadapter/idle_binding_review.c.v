// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import crypto.sha256

fn binding_asset_digest(parent int, name string) !(string, u64) {
	fd := C.openat(parent, name.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC)
	if fd < 0 { return error('cannot read Wine binding review asset') }
	defer { C.close(fd) }
	mut before := C.stat{}
	if C.fstat(fd, unsafe { &before }) != 0 || u32(before.st_mode) & 0o170000 != 0o100000
		|| before.st_size < 1 || before.st_size > 64 * 1024 * 1024 {
		return error('Wine binding review asset must be ordinary and between 1 byte and 64 MiB')
	}
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	mut sum := []u8{len: sha256.size}
	defer { unsafe { hash.free(); free(hash); buffer.free(); sum.free() } }
	mut count := u64(0)
	for count < u64(before.st_size) {
		remaining := u64(before.st_size) - count
		limit := if remaining < u64(buffer.len) { int(remaining) } else { buffer.len }
		n := C.read(fd, buffer.data, uint(limit))
		if n <= 0 { return error('cannot finish Wine binding review asset') }
		hash.write(buffer[..int(n)])!
		count += u64(n)
	}
	mut sentinel := u8(0)
	mut after := C.stat{}
	if C.read(fd, &sentinel, 1) != 0 || C.fstat(fd, unsafe { &after }) != 0
		|| before.st_dev != after.st_dev || before.st_ino != after.st_ino || before.st_size != after.st_size
		|| before.st_mtime != after.st_mtime || before.st_ctime != after.st_ctime {
		return error('Wine binding review asset changed while reading')
	}
	hash.checksum_into(mut sum)
	return sum.hex(), count
}

// Single owner. Do not copy, concurrently use/close, or transfer the borrowed
// review. This excludes cooperating managed launches while live, not arbitrary
// same-account writers. Requires an existing prefix; capturing may create
// launch/server coordination files and directories, never builtin bindings.
pub struct IdleBindingReview {
pub mut:
	review BindingReview
mut:
	guard LaunchGuard
	server ServerDirectory
	data string
	builtins string
	store string
	system_fd int = -1
	assets_fd int = -1
	digests []string
	sizes []u64
}

pub fn (mut capture IdleBindingReview) close() {
	capture.review.close()
	capture.server.close()
	capture.guard.close()
	if capture.system_fd >= 0 { C.close(capture.system_fd) }
	if capture.assets_fd >= 0 { C.close(capture.assets_fd) }
	unsafe { for digest in capture.digests { digest.free() }; (&array(&capture.digests)).free() }
	unsafe { capture.sizes.free() }
	unsafe { capture.data.free(); capture.builtins.free(); capture.store.free() }
	capture = IdleBindingReview{}
}

pub fn capture_idle_binding_review(data string, builtins string, store string) !IdleBindingReview {
	data_fd := absolute_directory(data)!
	mut prefix := Prefix{path: data + '/wine', data: data_fd}
	defer { prefix.close() }
	directory(prefix.data, u32(C.geteuid()), true)!
	prefix.directory = review_child(prefix.data, 'wine')!
	info := directory(prefix.directory, u32(C.geteuid()), true)!
	prefix.device = u64(info.st_dev); prefix.inode = u64(info.st_ino)
	mut value := IdleBindingReview{data: data.clone(), builtins: builtins.clone(), store: store.clone()}
	// Receiver addresses are borrowed only within this call. Return the owner
	// by value without promoting its temporary shell to an unowned heap block.
	mut capture := unsafe { &value }
	mut accepted := false
	defer { if !accepted { capture.close() } }
	capture.guard = prefix.acquire_launch(data)!
	capture.server = capture.guard.prepare_server_directory(data)!
	system_path := data + '/wine/drive_c/windows/system32'
	defer { unsafe { system_path.free() } }
	capture.system_fd = absolute_directory(system_path)!
	capture.assets_fd = absolute_directory(builtins)!
	capture.review = review_prefix_bindings(data, builtins, store)!
	capture.digests = []string{cap: capture.review.bindings.len}
	capture.sizes = []u64{cap: capture.review.bindings.len}
	mut total := u64(0)
	for binding in capture.review.bindings {
		digest, size := binding_asset_digest(capture.assets_fd, binding.name)!
		total += size
		capture.digests << digest.clone()
		unsafe { digest.free() }
		capture.sizes << size
		if total > 1024 * 1024 * 1024 { return error('Wine binding review assets exceed 1 GiB') }
	}
	capture.recheck()!
	accepted = true
	return *capture
}

pub struct BuiltinExpectation {
pub:
	name string
	sha256 string
	bytes u64
}

// Compare borrowed expectations, without retaining them or establishing their
// provenance. Caller must authenticate the source inventory and retain the
// selected generation lease. Success is not migration authorization.
pub fn (capture &IdleBindingReview) require_builtin_inventory(runtime string, generation u64, expected []BuiltinExpectation) ! {
	capture.recheck()!
	if runtime != capture.review.runtime_id || generation != capture.review.generation {
		return error('Wine expected builtin runtime or generation differs')
	}
	if expected.len != capture.review.bindings.len || capture.sizes.len != expected.len {
		return error('Wine expected builtin inventory length differs')
	}
	mut seen := map[string]bool{}
	defer { unsafe { seen.free() } }
	for entry in expected {
		if entry.name in seen { return error('Wine expected builtin inventory repeats a name') }
		seen[entry.name] = true
		mut found := false
		for index, binding in capture.review.bindings {
			if binding.name != entry.name { continue }
			found = true
			if entry.sha256 != capture.digests[index] || entry.bytes != capture.sizes[index] {
				return error('Wine expected builtin digest or size differs')
			}
		}
		if !found { return error('Wine expected builtin name differs') }
	}
}

fn binding_directory_unchanged(held int, path string, private bool) ! {
	current := absolute_directory(path)!
	defer { C.close(current) }
	a := directory(held, u32(C.geteuid()), private)!
	b := directory(current, u32(C.geteuid()), private)!
	if a.st_dev != b.st_dev || a.st_ino != b.st_ino {
		return error('Wine binding review captured directory identity changed')
	}
}

fn (capture &IdleBindingReview) recheck_namespace() ! {
	capture.server.require_idle(&capture.guard, capture.data)!
	system_path := capture.data + '/wine/drive_c/windows/system32'
	defer { unsafe { system_path.free() } }
	binding_directory_unchanged(capture.system_fd, system_path, true)!
	binding_directory_unchanged(capture.assets_fd, capture.builtins, false)!
}

fn (capture &IdleBindingReview) recheck_structure() ! {
	capture.recheck_namespace()!
	mut current := review_prefix_bindings(capture.data, capture.builtins, capture.store)!
	defer { current.close() }
	if current.generation != capture.review.generation || current.prior_generation != capture.review.prior_generation
		|| current.runtime_id != capture.review.runtime_id || current.bindings != capture.review.bindings {
		return error('Wine binding review changed while captured')
	}
	if capture.digests.len != current.bindings.len || capture.sizes.len != current.bindings.len {
		return error('Wine binding review digest inventory differs')
	}
}

// Full structural/payload checks bracket migration. Within its single-owner
// write loop, recheck the held namespace, exact old link and authenticated
// target before each rename. Unrelated changes refuse at the final full check;
// partial progress is recoverable. Cooperating writers must honor the guard.
fn (capture &IdleBindingReview) recheck_migration_binding(index int) ! {
	capture.recheck_namespace()!
	binding := capture.review.bindings[index]
	mut buffer := [4097]u8{}
	length := C.readlinkat(capture.system_fd, binding.name.str, &char(&buffer[0]), 4096)
	if length < 1 || length >= 4096
		|| unsafe { tos(&buffer[0], int(length)) } != binding.observed { return error('Wine binding review changed while captured') }
	mut info := C.stat{}
	if C.vinix_wine_directory_fstatat(capture.assets_fd, binding.name.str,
		unsafe { &info }, C.AT_SYMLINK_NOFOLLOW) != 0 || u32(info.st_mode) & 0o170000 == 0o120000 {
		return error('Wine binding review asset is linked or unavailable')
	}
	if u32(info.st_mode) & 0o170000 != 0o100000 { return error('Wine binding review asset is not ordinary') }
	digest, size := binding_asset_digest(capture.assets_fd, binding.name)!
	defer { unsafe { digest.free() } }
	if digest != capture.digests[index] || size != capture.sizes[index] {
		return error('Wine binding review asset bytes changed')
	}
	capture.recheck_namespace()!
}

// Re-run structural inspection between idle/namespace checks, retaining the
// guard. This does not authenticate runtime bytes or freeze concurrent writes.
// Migration application still needs authenticated inputs, fresh checks at use,
// atomic binding changes and an interruption recovery policy.
pub fn (capture &IdleBindingReview) recheck() ! {
	capture.recheck_structure()!
	mut total := u64(0)
	for index, binding in capture.review.bindings {
		digest, size := binding_asset_digest(capture.assets_fd, binding.name)!
		defer { unsafe { digest.free() } }
		total += size
		if total > 1024 * 1024 * 1024 { return error('Wine binding review assets exceed 1 GiB') }
		if digest != capture.digests[index] || size != capture.sizes[index] { return error('Wine binding review asset bytes changed') }
	}
	capture.recheck_namespace()!
}
